# Superheroes (2015) — Event Restore

Restores the retired **2015 Superheroes** event (codenames `MarvinMonroe`, `Superheroes`,
`SuperheroesBossFight`) so it runs playable end-to-end again — Issue 1–4 plus the final
boss fight, with quests, prize tracks, currency, and buyable event buildings.

## What's in this bundle

| Path | Contents |
|------|----------|
| `../Main/gamescripts/` | The restored gamescripts (the functional restore — see the file list below). |
| `art/` | Merged `SuperheroesMenu_LTD` art packs (all device tiers) with the boss-fight comic prize panels folded back into the loaded atlas. |
| `docs/SUPERHEROES_RESTORE.md` | Full restore write-up: every bug hit, the root causes, and exactly what was changed. **Read this first.** |
| `docs/RESTORE_FORMULA.md` | The general event-restore method. |

## Gamescript changes (in `Main/gamescripts/`)

The restore touches the `marvinmonroe_*`, `superheroes_*`, and `superheroesbossfight_*`
gamescripts, plus the shared registration/store/date files (`specialeventlist.xml`,
`storemenu.xml`, `dates.xml`). Key fixes:

- **Event registration un-gated** — the `SpecialEvent` registrations in `specialeventlist.xml`
  no longer carry the `time start=SuperheroesPartFour` requirement that left the boss event
  only partially active (which is why the "Monumental Battle" quest-lot panel was empty).
- **Final prize track** — `superheroes_menuconfig.xml` + `superheroesbossfight_specialevents.xml`
  restored so the "Final Episode" track unlocks on quest progress instead of a dead timer.
- **Always-on window** — event dates opened so it never deprecates again.
- **Store + buyable buildings, freeplay jobs, intro retimed, art re-indexed.**

See `docs/SUPERHEROES_RESTORE.md` for the complete, sectioned account.

## Deploying

1. The gamescripts in `Main/gamescripts/` are served as part of the DLC payload.
2. The `art/` packs replace the gutted menu atlas — repoint the index at these revisions
   (or copy them into the served art tree) so the boss comic panels render instead of white.
3. On the client, clear the cached DLC index and relaunch.

> The gamescripts alone make the event functional; the `art/` packs are what make the
> boss-fight prize panels show real art rather than blank tiles.
