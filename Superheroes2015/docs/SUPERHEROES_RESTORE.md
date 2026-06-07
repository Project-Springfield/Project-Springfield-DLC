# Superheroes (2015) — How We Made It Work

A case study of restoring the 2015 **Superheroes** event end-to-end on the
private server, purely from DLC. It doubles as a **playbook**: every problem here
is a *class* of problem you'll likely hit restoring any pre-2017 (legacy-format)
event, with the diagnosis method that found it.

Codenames: `Superheroes` + `MarvinMonroe` + `SuperheroesBossFight`. Always-on
restore mode. Everything below ships in the `dlc_events` overlay — the base DLC
tree (`E:\SIMPSONS\dlc`) is never touched.

> Short version of the fixes also lives in the event's **Notes** tab
> (`project.py → BUILTIN_NOTES["Superheroes"]`). This doc is the long form +
> methodology.

---

## Starting state

A retired legacy event is dead on multiple independent layers. The tool's
standard auto-fixes (undeprecate, trigger_event, store, art_reindex,
intro_at_start, prize_track, freeplay_jobs, + the always-on date open) got the
event *running* — splash, HUD theme, intro, quests starting. Then the
event-specific problems surfaced one at a time as we played through it.

---

## 1. SuperiorSquadHQ wasn't buildable ("Build Superior Squad HQ" un-pressable)

**Symptom.** The quest "Build Superior Squad HQ" had no buy target — the building
never appeared in the store, so the objective couldn't be actioned.

**Root cause — two stacked gates:**
1. Event buildings are `<Unique value="true">` → store-hidden (they were meant to
   be granted by the original first-run, which a restore can't re-fire).
2. The SpecialEvent's `<Buildings override="true">` block hid SuperiorSquadHQ
   behind `<VisibilityRequirements><Requirement type="quest started"
   quest="TheDeathOfAHero03"/></VisibilityRequirements>` — a **building-level**
   filter the store XML can't override. A restore gates quests via the event
   variable, not real progression, so "quest started" never evaluated true.

**How we confirmed it.** EA's own re-run event, **SuperheroesReturn** (2016),
sells SuperiorSquadHQ from the store with a plain `building owned not=true` gate
and its SpecialEvent `<Buildings>` block has **no** quest-started gate (just a
BuildTime override). EA hit the same problem and dropped the gate — so we do too.

**Fix.**
- `_make_event_buildings_buyable` strips `<Unique value="true">` (always-on).
- `_ungate_building_visibility` strips quest-based `<VisibilityRequirements>` from
  the SpecialEvent `<Buildings>` block (always-on).

**The gotcha that cost hours.** The first rebuilds *did nothing* even though the
transform reported success. `ensure_project` loads the `events/<Event>/xmls/`
working copy into `file_overrides`, and those are applied **last** (so user edits
win) — silently re-applying the un-fixed snapshot over the transform. Fix: the
SpecialEvent + buildings transforms now **source FROM** and **write BACK TO** the
matching `file_overrides` entry when one exists. Any new always-on transform on an
event file must do the same.

---

## 2. Cutscene crash (SIGSEGV right after a video)

**Symptom.** Hard crash at the end of the `TheDeathOfAHero04` "quest failed"
video cutscene.

**Diagnosis method (reused for every crash below):**
1. `adb logcat -d | grep 'F DEBUG'` → native backtrace. Signature:
   `SIGSEGV null deref` in `atoi`/`StrToI` ← libscorpio ← `onDrawFrame`.
2. Pull the tombstone (`/data/tombstones`, `su -c cat`). The **`memory near x23`**
   section ([anon:scudo:secondary]) contained the *exact XML being parsed*:
   `<Action type="createobject" name="RadioactiveManDead" ... onThisObject="true"/>`.
   Stack memory naming the culprit is the single most useful artifact — always
   check it before editing.
3. Resolve the libscorpio offsets in the scarlett IDA db (4_69 arm64, base 0x0 so
   offsets map directly) to confirm the crashing function/attribute.

**Root cause.** `createobject ... onThisObject="true"` spawns at the position of
"this object"; on the restore that anchor resolves to a null position →
`atoi(null)`. The spawn is cosmetic (a dead Radioactive Man on the wrecked house).

**Red herring.** `RadioactiveManDead` also had a one-char avatar casing typo
(`avatar="RadioActiveMan"` vs canonical `RadioactiveMan`). We fixed it first; it
did **not** stop the crash. Lesson: confirm the crash site from the tombstone
before assuming a nearby oddity is the cause.

**Fix.** Removed the cosmetic `createobject` line in `DestroyBrownHouse` (kept the
`Destroyed_BrownHouse` skin so the house still looks wrecked). Generalized as the
opt-in `neutralize_spawns` transform for other events.

---

## 3. Prize track opened the wrong (Monorail) track; event currencies missing

**Symptom.** Tapping the trophy opened the permanent **Monorail** prize track, not
the Superheroes one; CarbonRods/PieBombs/FreezeRays never appeared in the HUD.
"Unlock Arbitrarium" routed to the prize track (correct — the first prize *is* the
Arbitrarium 10-pack at 400 CarbonRods), but the track was inactive.

**Root cause.** Always-on mode sends every non-"end" date to the far past,
including the act boundaries `SuperheroesPartOne..PartFour`. The **last** boundary
(`PartFour`) doubles as the prize track's `time end=` cutoff for the event
currencies and prize lists. With it in the past, `time end PartFour` was false →
the whole prize track + currencies switched off, and the trophy fell back to the
only active track (Monorail).

**Fix.** `date_rewrite.force_last_phase_future` keeps the highest-numbered act
boundary (`PartFour`) in the far future, leaving earlier ones past. The prize
track is active and progresses by **quest** (Clownface → DrColossus), not
calendar. General fix (any multi-act always-on restore).

**Pipeline gotcha.** `dates.xml` is rewritten in **two** places — `build_restore`
*and* `emit_event_overlay` (emit re-runs `alwayson_xml` on dates.xml
independently). The fix had to be called in both, or the served pack kept
`PartFour=2000`.

---

## 4. Lieutenant tap crash (strlen(null))

**Symptom.** Tapping the Lieutenant (the orange miniboss criminal) hard-crashed.

**Diagnosis.** `strlen(null)` in libscorpio. The tombstone memory was empty (a
null string has nothing nearby), so we resolved the crashing function in IDA:
`strlen(sub_E624B0(node, "timerEndTime"))`. The renderer `sub_C256D8` draws a
type-34 **ProgressDisplay**, and the modern 4.69 client queries its `timerEndTime`
attribute **unconditionally**.

**Root cause.** The Lieutenant's `progressDisplayConfig`
(`MinibossHealthDisplay`) is health-only in the 2015 data (hearts + `title` +
`formula`) — **no `timerEndTime`**. The modern client read a null string. (THOH2015's
boss display *has* `timerEndTime`, confirming the modern requirement.) Same family
as the spawn crash: **legacy config missing a modern-client-required attribute**.

**Fix.** Added `<Attribute name="timerEndTime" value="SuperheroesPartOne"/>` to
`MinibossHealthDisplay` — a *past* date, so the timer resolves valid-but-elapsed
(hidden; the Lieutenant is a health boss, not a timed task) and never hits null.
Hearts still show.

---

## 5. Friend criminals never spawned

**Symptom.** Visiting a neighbor's town spawned no tappable criminals.

**Root cause.** The `user="remote"` `LandVisited` handlers gate
`SpawnFirst/Second/ThirdFriendCriminals` on **friend level 5/10/15**. Two fresh
accounts sit below level 5, so the first tier never fired.

**Fix.** Lowered the three tiers to friend level **1/5/10** so criminals spawn
from friend level 1. (The handlers also require the visitor to have started
`ANewHeroRises02`; left intact.)

---

## 6. Issue 4 (the boss fight) never unlocked

**Symptom.** The prize track's Issue 4 tab stayed locked no matter how much currency
was collected.

**Root cause — a side effect of fix #3.** Issue 4 is the Radioactive Man Statue
**boss fight** (`SuperheroesBossFight` content): build the statue, defeat it over 5
levels (send heroes + tap felons) for Rad Mobile (@2 defeats), Kane Manor (@3),
Radioactive Man (@5). Its entry quest **"Remembering a Hero"** (internal `Tribute`,
objective = build `ConstructionSite`) and the boss-fight SpecialEvent (4320) were
hard-gated on `time start="SuperheroesPartFour"`. Fix #3 deliberately keeps
PartFour in the far future (to keep Issue 3's FreezeRays collectable) — which
simultaneously meant Issue 4 could never start. The two acts are mutually exclusive
on that one date boundary.

**Fix.** Replaced the three `time start="SuperheroesPartFour"` gates (in
`superheroesbossfight_quests.xml` + `superheroesbossfight_specialevents.xml`) with
the event variable, so Issue 4 opens by **quest progression** (level 6 + Death of a
Hero Pt 4) while Issue 3 stays alive — both coexist instead of being date-exclusive.
The Issue-4 tab itself is driven by the boss-fight's own PrizeList (menuConfig
`PrizeTrackFinal`), which goes live once `SuperheroesBossFight` (4320) activates
(after "Remembering a Hero" / Tribute completes).

**Note on diagnosis.** The main pack's `superheroes_specialevents.xml` PrizeList
id=3 is a blank `JOB_BlankReq` placeholder — easy to mistake for "Issue 4 was never
made" (I did). The real Issue 4 prizes live in the **boss-fight** files; cross-
referencing a community walkthrough (tstoaddicts) corrected that and named the
mechanic.

**Second block — couldn't send heroes to the statue.** Even with the boss fight
"started", "Send Heroes to Attack The Statue 0/5" wouldn't let you assign anyone, and
the statue just looped its idle `RememberingAHero` job. Cause: the `FightFinalBoss_*`
jobs require `<Requirement type="variable" variable="SuperheroesBossFight_Event"/>`,
which only the boss-fight SpecialEvent (4320) set — and 4320 wasn't reliably
instantiating on the restore, so the var stayed false and no hero job was offered. Fix:
force `<Variable name="SuperheroesBossFight_Event" value="true"/>` on the **main** event
(4272). Mechanic gotcha that wasted time: you attack the statue by **tapping the hero
characters** (in costume) and assigning the "Fight Final Boss" task — tapping the statue
only plays a sound, and its looping idle job is a red herring. Confirmed working.

## 7. Retired-event art packs gutted (re-point to the full-art revision)

> NOTE: this was found while chasing the "2 white circles" boss panel, and was at
> first *mistaken* for its cause. It is a **real, separate** fix (some served art
> packs really were stripped), but it did **not** fix the panel — see §8 for the
> actual root cause. Keep this fix; it recovers genuinely-gutted art.

**Symptom (what sent us here).** The boss panel rendered with **two white circles**.
Every XML asset reference checked out as "served," and the in-world statue drew fine
through the fight — so we suspected stripped menu art.

**Root cause — takedown *gutted* the main art packs, not just dropped _LTD ones.**
When EA retires an event it doesn't only remove the `_LTD` packs (which `art_reindex`
re-adds). It also **republishes the MAIN game/menu art packs at a later revision with
the art stripped out**, and the cumulative index points at that gutted revision while
the full-art original sits unreferenced in the served tree:

| Pack | Served (indexed) revision | Full-art revision on disk |
|------|---------------------------|---------------------------|
| `BossFightGame-100/50/25` | `r272024` — **0 art files** (xml only) | `r179376` — 80 |
| `BossFightMenu-{retina,ipad,ipad3,iphone}` | `r406729` — **8 art** | `r179376` — 23 |
| `SuperheroesGame-*` / `SuperheroesMenu-*` | `r406729` — reduced | `r168003` / `r167336` — full |

The S20 had the *game* art cached from an earlier session, so the statue still drew
through the fight — but the post-battle **menu** pack it was served (`r406729`) holds
only 8 of 23 images, and the victory popup references images that were stripped →
white. EA's takedown gutted the packs progressively (`179376 → 272024 → 406729`).

**How we confirmed it.** Decoded every `BossFight*` pack revision on disk and counted
`.rgb`/`.bsv3` members, then diffed against which revision the **served** cumulative
index (base *and* overlay) actually references. The served index pointed at the
stripped revisions every time.

**Fix.** Extended `art_reindex` with `_repoint_richest_art_packs`: for every
`<Package>` belonging to the event's component folders, find the sibling revision on
disk with the **most** art files and, if it holds strictly more than the indexed one,
rewrite that entry's `FileName` + `IndexFileCRC` + sizes to it. Retire only ever
*strips* art, so the original launch revision is a superset — re-pointing recovers the
full event art with no regression. On Superheroes this re-points 25 packs (boss-fight
game 0→80, boss-fight menu 8→23, plus the main Superheroes/MarvinMonroe/Takedown
menus that were silently gutted too).

**Lesson / generalization.** "All assets are served" can be a lie told by the *base
files existing on disk* — what matters is the **revision the cumulative index points
at**. For any retired event, audit indexed-vs-richest revision per art pack, not just
file presence. `_LTD` re-add alone is insufficient when the takedown gutted the main
packs.

**Sub-component menu art (now automated).** A related gotcha: art that lives ONLY in a
sub-component's `_LTD` menu pack (the boss-fight comic prize panels in
`BossFightMenu_LTD`) isn't in the atlas the active event loads (`SuperheroesMenu_LTD`),
so it renders white once the (real) quest-lot panel works (§8). `restore.py
_merge_event_menu_art` (in `emit_event_overlay`, gated `art_reindex`) folds each sibling
component's `*Menu_LTD` art the primary pack lacks INTO the primary pack (overlay copy,
all tiers) and repoints the index — and `emit_prod` carries those merged packs into the
raw Stage-Prod output, so Build and raw both serve the same art with no manual step.

## 8. Boss "Monumental Battle" quest-lot panel rendered empty + trapped the player (the REAL "2 white circles")

**Symptom.** After the 5th `FightFinalBoss` hero send, the boss progress panel
("Monumental Battle") opened with **two grey/white placeholder circles** instead of
the three comic prize covers — and **trapped** the player (back-out flashed/stuck).
The fight worked otherwise (send heroes, tap criminals, prizes via the trophy track).

**The long dead end.** ~30 deploys chased the *panel data*: re-pointing gutted art
(§7), relocating the configs into a loaded package, merging the comic art into the
active atlas, rewriting the prize-group `componentType` to `firstPrize`/`smallArrow`,
unique QuestLot ids, moving QuestLists to a dedicated lean event, and authoring
`_questlotquests`/`_questlotscripts` companion files. **Every one failed.**

**How it was actually cracked — on-device RE.** Decompiled `GameState_InspectQuestLot`
in libscorpio (scarlett IDA): it resolves the target lot from the SpecialEvent's
`QuestLists` field (`event+368`), then builds one prize cell per lot item. Hooked its
init on the S20 with Frida (`frida.get_device("RZ8R31Q08NF")`, `base+0x96C68C`) and
read `*(event+368)` live: the SpecialEvent was **found, but its `QuestLists` was
NULL** — so there were zero lots to render. The failure was *upstream of the panel
entirely*: the `<QuestLists>` block never attaches to the live event.

**Root cause — a missed `time start=<lastphase>` gate in `specialeventlist.xml`.**
The boss `<SpecialEvent id="4320"/"4321">` *registration* in `specialeventlist.xml`
carried `<Requirement type="time" start="SuperheroesPartFour"/>`. The always-on
restore's `force_last_phase_future` pins `PartFour` to the far future (to keep
Issue-3's currency window open, §3), so that requirement is **permanently false**.
The event then **instantiates only partially** — per-event variables still fire
(jobs/criminals work, which is why everything *looked* active) but
registration-gated features never come on, so the `<QuestLists>` never parse/attach
→ empty, trapping panel. This is the **same `time start=PartFour` gate** removed for
the Issue-4 fix (§6) from the quests/specialevents files — it also lives in
`specialeventlist.xml`, and was simply missed there.

**Fix.** `_ungate_lastphase_registration` (restore.py): when always-on, strip the
`time start=<lastphase>` Requirement from the event's `<SpecialEvent>` registration
blocks in `specialeventlist.xml` (scoped by `package=` codename), paired with
`force_last_phase_future`. The event fully activates, QuestLists attach, the panel
renders (verified: `+368` non-null, comic panels draw). The `componentType` rewrite
(§7-adjacent) + the art re-point/merge are kept so the cells render with the correct
comic art once the lots exist.

**Lesson / generalization.** The `time start=<lastphase>` gate that `force_last_phase_future`
turns false lives in **four** places: the event's quests, specialevents, gameconfig
dates, **and the `specialeventlist.xml` registration**. Ungate ALL of them, or
registration-gated activation (quest-lot QuestLists, and likely other features) silently
fails while the event still *looks* active. When a restored panel is empty, trace the
runtime data source (here `event+368`) before touching the panel's own art/config —
an empty container points upstream to event *activation*, not panel *data*.

## 9. "Final Episode" prize track locked ("unlock in 24855d") — and the forcing trap

**Symptom.** Once you reach the boss fight, the **Final Episode** prize track (Rad Mobile
@2 RadioactiveGirders / Kane Manor @3 / Radioactive Man @5) showed every prize **locked**
with "Slow down! ...unlock in 24855d" + a `*TEMP` placeholder, plus stale Issue 1–4 tabs.
Real EA shows it as a single active track with "0/2" currency progress.

**Root cause — the `PartFour` gate again, this time in the prize-track menuConfig.**
`Superheroes_MenuConfig:PrizeTrackFinal` is keyed `startDate="SuperheroesPartFour"` plus a
`<Requirement type="time" start="SuperheroesPartFour"/>`. `force_last_phase_future` (§3)
pins `PartFour` to the far future, so the track's window never opens → "coming soon,"
and the 24855-day countdown is just that far-future date. (The "ends in 24855d" footer
is `endDate=SuperheroesEnd`, also far-future — cosmetic; the event never actually ends
in always-on.) This is the SAME gate family as §6/§8, now in the prize-track config — the
gate lives in **five** places total: quests, specialevents, gameconfig dates,
`specialeventlist.xml` registration, and prize-track menuConfig.

**The trap (important).** The naive fix — just open the window (`startDate` → first phase)
— *works for the final save but force-yanks every mid-event save into the Final track.*
The prize-track hub keys off the **menuConfig date window**, not the PrizeList's
requirements, so opening Final's window globally makes Issue-1/2 saves jump to Final. (And
a forcing build is doubly nasty: the client **writes final-boss state into the save**, so
those test saves stay corrupted even after you revert the DLC — always retest the gate on
a *clean* save, not one that saw the bad build.) Do **NOT** generalize this as a blanket
"open the final window" transform.

**Fix (per-event, quest-gated).** Two coordinated edits, in the event working copy:
- `superheroes_menuconfig.xml` → `PrizeTrackFinal`: `startDate` → first phase
  (`SuperheroesPartOne`, far-past = window open) and change the unlock
  `<Requirement type="time" start="SuperheroesPartFour"/>` → `<Requirement type="quest started"
  quest="Tribute"/>` (the boss-fight entry quest).
- `superheroesbossfight_specialevents.xml` → the Final `<PrizeList ... PrizeTrackFinal>`:
  gate its `<Requirements>` on `quest started "Tribute"` (so the track only activates at the
  boss fight, not for early saves).

Result: Final shows with live currency progress (Rad Mobile → Kane Manor → Radioactive Man)
only once the boss fight is reached; Issues 1–3 keep progressing normally. Kept as a
**per-event working-copy edit** (not a `restore.py` transform) precisely because a generic
always-open version re-introduces the forcing — see the NOTE next to `_ungate_lastphase_registration`
in `restore.py`. (The §6/§8 `specialeventlist` registration ungate IS generalized and safe.)

## Methodology recap (for the next event)

- **Crash class to expect:** legacy event data that only breaks on the modern
  client — a null read (`atoi(null)` / `strlen(null)`) in `onDrawFrame`, usually
  triggered by a specific tap or a cutscene.
- **Always check the tombstone stack memory first** (`memory near x*`) — it often
  contains the exact XML/attribute being parsed.
- **If stack memory is empty**, resolve the libscorpio offsets in the scarlett IDA
  db (4_69 arm64, base 0x0) and decompile the crashing function to find the
  attribute it's reading.
- **Cross-check EA's own re-run** of the event (e.g. SuperheroesReturn) — EA often
  already fixed the same legacy problem; mirror their change.
- **Per-event data fixes** go in the event's `xmls/` working copy (they flow
  through Build + Stage Prod via `file_overrides`); **general** fixes become
  transforms in `restore.py`.

## Devices & deploying

- Built into the overlay; deploy = set `Server.DLCEventsDirectory`, restart the
  server, then **clear the client DLC cache** (`files/dlcindexcodesave` +
  `files/DOWNLOADCACHE`) and **fully relaunch**. An in-game reload does NOT
  re-fetch DLC — this masked several fixes mid-session until the cache was cleared.
- Tested on a Samsung S20 (tier 100) + MuMu. Black menu backgrounds on one
  emulator (MEmu) turned out to be that emulator's GPU/texture handling — the art
  is re-indexed for every device tier (`100/50/25` + retina/ipad/iphone) and
  confirmed present on disk — not a content bug.

## Result

Superheroes 2015 is fully playable: buyable HQ + event buildings, the quest chain,
cutscenes, the Superheroes prize track (progresses by quest), the Lieutenant
miniboss, and friend-visit criminals — all from DLC, base tree untouched, and the
same content whether built as a packed overlay or staged as loose PS-DLC files.
