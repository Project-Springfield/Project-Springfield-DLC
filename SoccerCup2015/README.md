# Tap Ball / Soccer Cup (June 2015) — Event Restore

Restores the retired **June 2015 Tap Ball** event (the Soccer Cup tie-in; gamescript
prefix `june2015_*`, component folders `SoccerCup2015` / `June2015`) so it runs playable
end-to-end again — the Tap Ball minigame vs. the CPU **and** away matches on a friend's
pitch, with quests, match rewards, prize tracks, currency, and the event store.

## What's in this bundle

| Path | Contents |
|------|----------|
| `../Main/gamescripts/` | The restored gamescripts (the functional restore — see the file list below). |
| `textpools/` | A rebuilt `textpools-en` pack carrying the event's 197 pruned `UI_June2015_*` localization strings. **Required** — without it the match HUD crashes the client (`strlen(NULL)`). |
| `art/` | The themed **title-splash** packs (`core-splashes-{small,medium,large}` + the `res-core` layout), served under the `SoccerCup2015` component. Built at priority 9000 so they override the APK's stock title splash via DLC. Cosmetic but part of the verified build. |
| `docs/SOCCERCUP2015_RESTORE.md` | Full restore write-up: every bug hit, the root causes (several traced live in the engine), and exactly what was changed. **Read this first.** |
| `docs/tsto_homerball_matchmaking_protocol.md` | The Tap Ball matchmaking / async-PvP wire protocol the server side needs (RE'd from the client). |

> **The `art/` here is the title splash only.** Unlike the Superheroes bundle (which
> shipped generated merged atlas packs), Tap Ball's menu/game art needs nothing
> generated: every pack it uses (`June2015Menu_LTD-*`, `SoccerCup2015Menu-*`,
> `June2015Game-*`, …) is a **stock base-tree file** that EA merely dropped from the
> DLC index on retire. The restore re-adds their index entries; the server just has to
> keep serving the base packs (overlay-first, base-fallback resolution).

## Gamescript changes (in `Main/gamescripts/`)

The restore touches the `june2015_*` and `soccercup2015_*` gamescripts plus the shared
registration/store/date files (`specialeventlist.xml`, `storemenu.xml`, `dates.xml`).
Every hand-fix is marked in-file with a `DLC restore:` comment. Key fixes:

- **Match-end result freeze fixed** — on 4.69 the engine suppresses the entire
  won/lost/tied result script at match teardown, so matches parked forever on the pitch
  ("Round 5"). The result scripts now point at the popup scripts that *do* run, and the
  reward/counter grants were moved into them — a win shows the results popup, grants
  event currency, and advances the win-count quests.
- **Match HUD crashes fixed** — the pruned localization strings re-shipped (see
  `textpools/`), and the star-rating widgets removed from the match/career/result UIs
  (a 4.68+ engine regression frees the rating config and then re-reads it → SIGSEGV).
- **Play actually starts the match** — Play used to re-run *random* matchmaking even
  after you'd challenged a specific friend and travelled to their pitch. It now plays
  the town you're standing in, and the opponent's pitch is tappable (the old gate
  required friend-variable sync that matchmaking opponents never have).
- **Emulator crash worked around** — the event leaderboard auto-popup null-derefs under
  MEmu's ARM translation; it's disabled via config and the manual button gated on the
  same key.
- **Standard restore layer** — SpecialEvents un-deprecated, store section authored,
  `_LTD` art re-indexed for all device tiers, buildings buyable, freeplay jobs un-gated,
  4h athlete cooldown (the original economy) confirmed.

See `docs/SOCCERCUP2015_RESTORE.md` for the complete, sectioned account.

## Deploying

1. The gamescripts in `Main/gamescripts/` are served as part of the DLC payload.
2. Serve the `textpools/` pack and index it (`Language="en"`) — the event HUD reads
   `UI_June2015_*` keys that no modern textpool carries; missing = instant crash when a
   match starts.
2b. (Optional, cosmetic) Serve the `art/` splash packs under the `SoccerCup2015`
   component and index them (tiers 25/50/100 + `res-core` for all) — they theme the
   title screen; their per-file priority (9000) is what overrides the APK splash.
3. The event window is **gameplayconfig-gated** (no literal `dates.xml` window): the
   server must publish the `June2015_GameConfig:Dates:*` sub-keys opened (start → far
   past, end → far future) or the event reads as expired regardless of the DLC.
4. Async PvP (Career Stats / match-result write-back) needs the matchmaking endpoints in
   `docs/tsto_homerball_matchmaking_protocol.md`; note the match-result write-back must
   accept matchmaking opponents that are **not** friends.
5. On the client, clear the cached DLC index and relaunch.

> The gamescripts alone make the event load; the `textpools/` pack is what keeps the
> match HUD from crashing the moment a Tap Ball match begins.
