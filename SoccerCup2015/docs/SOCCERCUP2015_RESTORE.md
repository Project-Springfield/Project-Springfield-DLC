# Tap Ball / Soccer Cup (June 2015) — How We Made It Work

A case study of restoring the **June 2015 Tap Ball** event (the Soccer Cup tie-in)
end-to-end on the private server, purely from DLC. Like the Superheroes write-up it
doubles as a **playbook**: Tap Ball is the first restored event with a native C++
**minigame** (the match engine is a state machine inside `libscorpio`, not script), so
most of its failures were engine era-gaps that only show up when 2015 data runs on a
4.69 client — and most were root-caused live with Frida + IDA rather than by guessing.

Gamescript prefix: `june2015_*` (the event registers as `June2015_*` packages);
component folders `4_15_June2015_*` and `4_15_SoccerCup2015_*`. Always-on restore
mode. Every hand-fix below is marked in-file with a `DLC restore:` comment.

---

## 1. Event shape — the window is gameplayconfig-gated

Unlike Superheroes, Tap Ball's window does **not** live in `dates.xml` literals: every
date is a `June2015_GameConfig:Dates:*` **gameplayconfig sub-key** (the smoke output for
this event legitimately shows `dates: (none)`). Opening the DLC dates alone does
nothing — the **server** must publish those sub-keys opened (start → far past, end →
far future) or the event reads as expired no matter what the DLC says.

The DLC side still gets the standard restore layer: the `June2015_*` SpecialEvent
registrations un-deprecated in `specialeventlist.xml`, the running-event marker set, the
event store authored (`storemenu_temp_soccercup2015.xml` + include in `storemenu.xml`),
`_LTD` art packs re-indexed for **all** device tiers, buildings made buyable, freeplay
jobs un-gated, and the event-specific date files opened.

## 2. Match HUD localization crash → the bundled textpool pack

**Symptom:** SIGSEGV (`strlen(NULL)` in `HUDHandler::getTextForMenu`) the moment the
match HUD builds — the round counter (`UI_June2015_RoundText`) is the first to die.

**Root cause:** retired events get their `UI_<event>_*` strings pruned from later
textpools. The 4.69 client resolves every `UI_June2015_*` localise key to NULL; the
strings exist in no modern pool and the `.so` has no fallback text.

**Fix:** recover the event's `ui_june2015_*` group from the **earliest** base-tree
textpool that still carries it (recently-ended events linger a few releases before
pruning) and re-ship exactly those entries as a minimal `textpools-en` pack — the
**197 strings** in `textpools/textpools-en-r1781189778-RESTORE.zip`, indexed with
`Language="en"`. Without this pack the event is unplayable.

## 3. Star-rating widget crash (4.68+ engine regression)

**Symptom:** SIGSEGV `GetAttribute(NULL, "animNeutral")` while the match HUD builds the
per-player star-rating widgets.

**Root cause:** on 4.68+ `RatingSystem::Clear()` frees **and nulls** the rating config,
then `onMenuComponentCreated` re-reads it via `RegisterMenuSprite`. The 4.15 engine's
`Clear` only reset the sprite vector — this is an engine regression that only bites
restored events. Engine bug, not data.

**Fix (DLC-only):** remove the rating config from every menu that builds the widget —
`ratingConfig` in the match config (`june2015_homerballconfig.xml`), `ratingFormula` /
`ratingConfigPath` in the career screen (`june2015_careerscreenconfig.xml`) and the hub
friend list (`june2015_hubfriendlistconfig.xml`), and the `ratingSystem` AttributeSets in
the result popups. Cost: in-match star-rating widgets don't render (team-management
ratings are unaffected; `<NormalStarRating>` is kept).

## 4. Match-end result freeze — the big one (RE-confirmed live)

**Symptom:** the match plays its 4 rounds fine, then "Round 5" appears and the game
freezes on the pitch — no results popup, no exit. ("Round 5" is not a real round: it is
the round counter ticking as the match parks at terminal state 18.)

**Root cause:** the match is a native state machine. At match end (`OnDone`, state 17)
the engine runs `wonMatchScript`/`lostMatchScript`/`tiedMatchScript` (= `MatchGameWin`
/`Lose`/`Tie`) via `RunMatchResultScript`. On 4.69 those wrapper scripts run **zero
actions** at teardown — verified live with a global-variable-setter hook: not one of
`MatchGameWin`'s `setVariable`s fires. It is not a single halting action; the whole
script body is suppressed because the HUD is tearing down. The `*GameMessage` popup
scripts, which carry `ignoreHUD="true"`, **do** run at teardown. (Tried and rejected:
stripping the server/social actions, owner injection, adding `ignoreHUD` to
`MatchGameWin` — it still never runs.)

**Fix (`june2015_homerballconfig.xml` + `june2015_scripts.xml`):**

1. Point the result scripts straight at the popup scripts that do run:
   `wonMatchScript = June2015_Scripts:WinGameMessage` (and Lose/Tie equivalents).
2. Move the reward/counter grants **into** the `*GameMessage` scripts, placed *before*
   the `genericMessage` popup (safe ordering: worst case is no popup, never a stuck
   one): `activeGamesWon++`, `HomerballWins`, `HBTicketStubs`, `DailyWinComplete`, the
   loss/tie play-count equivalents — so a win grants event currency and advances the
   win-count quests again.
3. Remove the `ratingSystem` star widget from the three popups (same §3 regression — it
   stalls the popup build).
4. Keep the away-match result emit, but **conditional** on `AwayGameStarted`:
   `saveFriendAction` into the opponent's `PassiveMatches` buffer + the `PlayedOpponent`
   peer notification + `BallsOfGlory04` completion — multiplayer still records, while
   the single-player path skips the server-only actions cleanly
   (`SaveActiveMatch`/`CheckPeerMatchmakingExhaustion`/`ResetReadyPlayersBadge` removed
   from the wrappers).
5. Clear `AwayGameStarted` on exit so a stuck away flag isn't persisted into the save.

Confirmed live: match unfreezes, the results popup shows, Collect exits to town, and
rewards/quest progression flow.

## 5. Play didn't start the friend match

**Symptom:** challenge a specific friend, travel to their pitch, press **Play** → you're
dumped on the opponent's pitch with no match running.

**Root cause:** the Play button (`HomerballConfig:PlayButtonScript` →
`LaunchMatchmaking`) always ended in `findMatch` — *random* matchmaking — even when a
specific opponent had already been chosen and `visitPeer`'d
(`FriendMatch → ChallengeFriend → visitPeer`).

**Fix (`june2015_scripts.xml`, `StartMultiplayerMatch`):** route on land. In your **own**
town → `findMatch` (random matchmaking, as before). Standing in a **peer's** town →
`BeginHomerballMatch` → `gotoState State_TapBallMatch`: play the town you're standing
in. Single-player routes through `BeginHomerballSinglePlayer` when
`HomerballSinglePlayerMode` is set, and single-player is kept **always available** in
the hub (`june2015_hubfriendlistconfig.xml` — EA hid it once `BallsOfGlory04` started).

## 6. Opponent's pitch un-tappable

**Symptom:** on the opponent's pitch, "Tap the field to challenge" did nothing.

**Root cause:** the `CanPlayHomerBall` requirement (`june2015_requirements.xml`) gated on
`friendvariable CanPlayHomerball`/`Homerball`. A matchmaking opponent is a town
**snapshot** whose shared variables are never synced as friendvariables, so the gate
always failed.

**Fix:** drop the friendvariable checks — matchmaking already returned a valid opponent —
and gate on the local player's readiness only (`CanPlayHomerball`, `Homerball`, pending
match cap).

## 7. Emulator leaderboard crash (MEmu / Houdini)

**Symptom:** on MEmu only, the app closes when visiting a friend's town during the
event. Real ARM devices are unaffected.

**Root cause:** challenging a friend sets `OpenLeaderboard`, and entering their town
auto-opens `WorldState_Leaderboard` (`June2015_LeaderboardMenuConfig`); that
leaderboard's GL render path null-derefs under MEmu's Houdini ARM→x86 translation.

**Fix (`june2015_gameconfig.xml` + `june2015_specialevents.xml`):**
`LeaderboardPopup` 1 → 0 (no auto-popup), and the manual friend-map leaderboard button
gated on the same config key (`June2015_GameConfig:Enable:LeaderboardPopup`) so tapping
it can't enter the crashing state either. Flip the key back to 1 to re-enable on real
hardware.

## 8. Data fixes: macros + cooldown

- **Macro literalization:** the working copy replaces EA macro references the modern
  client no longer resolves (`__June2015_GameConfig:Match:maxSwitches__` etc.) with
  their literal values (`maxSwitches=2`, `maxPowerUpRating=11`, `ratingPerPowerUp=4`).
- **Athlete cooldown = `4h`** — the original energy/donut-recharge economy, present in
  **two** places that must agree: the 17 per-athlete `cooldown` attributes in
  `june2015_homerballconfig.xml` and the `<Cooldown>` table in `june2015_gameconfig.xml`
  (the master source the homerballconfig mirrors). For rapid back-to-back match
  *testing* set both to `1s` — and revert both before release. (NB: an early "round 5
  freeze" was misdiagnosed as a cooldown problem; the real cause was §4.)

## 9. What the server must provide

The DLC above makes the event and the single-player match fully playable. Multiplayer
(async PvP) additionally needs the server to implement the Tap Ball matchmaking
protocol — `docs/tsto_homerball_matchmaking_protocol.md` documents the endpoints as
RE'd from the client (`mh` views, `currentClientSessionId` → `DeviceToken` auth, the
match-result write-back into `PassiveMatches`). Two gotchas:

- The **match-result write-back must accept non-friends**: matchmaking opponents are
  usually not on the friend list, and a friends-only guard 403s the result post — the
  visible symptom is Career Stats never filling.
- The `June2015_GameConfig:Dates:*` gameplayconfig sub-keys must be published opened
  (§1), or the event reads as expired.

## 10. Deploy checklist

1. Serve the `Main/gamescripts/` files (part of the DLC payload).
2. Serve + index the `textpools/` pack (`Language="en"`). **Not optional** (§2).
3. Publish the opened `June2015_GameConfig:Dates:*` sub-keys from the server (§1).
4. Clear the client DLC cache (`files/dlcindexcodesave` + `files/DOWNLOADCACHE`) and
   fully relaunch — an in-game reload does not re-fetch DLC.
5. Test on a fresh save: one-shot intro quests won't re-fire once consumed.

---

*Diagnosis toolchain: IDA (stripped `libscorpio.arm64-v8a.so`, string-xref anchoring) +
Frida on a rooted arm64 device for live state-machine and script-dispatch hooks. The
match state machine, `RunMatchResultScript`, and the script-suppression behaviour in §4
were all confirmed against the running 4.69 client, not inferred from data.*
