# Reserve interaction and dusk clock — playable QA handoff (2026-10-12)

**Branch:** `chatgpt/reserve-clock-interactions-20261012`, based on `chatgpt/prologue-visual-rescue-20261011`. No changes to `develop`. Godot 4.3 project folder: `godot-project/`.

## Scope of this implementation

- Three contiguous garden scenes (`gd1`, `gd2`, `gd3`) now have a small clock readout and progressively tinted day/dawn/dusk/night presentation.
- The clock starts at 09:00 for saves with no prior Reserve time, runs a **placeholder 12 real minutes per game day**, and persists a separate `state["reserve_time_minutes"]` numeric value when the player is in these rooms. This is an optional save key compatible with v3 saves; it is not yet a global underworld time simulation.
- The `ReserveClock` emits `phase_changed(phase)` and `dusk_started(day_number)`. Future Lullmother bonding decisions should listen to dusk. **No bonding or captures have been implemented**, and the scene does not call battle/capture APIs as a shortcut.
- Each of the five residents in `gd1` gets a proximity ring. The `ReserveGuide` picks **only the nearest nearby resident** and shows its E / INTERACT prompt. Touch INTERACT uses the existing action. On interaction, the creature animates a brief reaction, is added to `GameState.seen_creatures`, and its unique ID enters `state["reserve_observed"]` (also optional/backward-compatible). This records observation, *never capture*.
- A small Reserve HUD shows `Observe residents · 0/5`, increasing to 5/5 as residents are examined. This is neutral UI text, not final Muse dialogue.
- Critical artwork is present for `dragonthorn`, `gloomcap`, `spinehopper`, `bellmaw`, `wispwillow` as `res://assets/critical_sprites/<id>.png.b64`. Exact PNG file sizes and SHA-256 were compared against Git LFS pointers and **all five matched**. The asset loader prefers original PNGs when valid, otherwise decodes the .b64 backup. The old `Texture2D` external scene declarations were removed to prevent bad LFS pointers from breaking the `gd1` scene.
- Dragonthorn, Gloomcap, and Spinehopper originals have opaque white paper backgrounds. A temporary lightweight canvas shader keys the paper out in-game without rewriting the approved originals. Sizes were reduced from battle-illustration scale to game-scale presentation. Muse should ultimately deliver clean 3/4-view transparent overworld sprites for these five.

## Quick playtest

1. Check out the **feature branch** above and open `godot-project/project.godot` in Godot **4.3**.
2. Open `res://scenes/room_gd1.tscn`, press **F6** to run current scene. Confirm upper-left objective and upper-right Reserve clock.
3. Approach Gloomcap at (-350, 180) or Dragonthorn at (-750, -140) from the main path. Only the closest visible creature should say E / INTERACT, even when two awareness rings overlap.
4. Press **E**, or the phone's **INTERACT** button. The creature should react visually, the counter increment once, and the same creature should never inflate the counter on repeated presses.
5. Walk away: prompt must disappear. Repeat for all five residents. Open another scene `gd2`/ `gd3` and return; clock and observation state should persist in the GameState payload.
6. For quick dusk tests, select the `ReserveClock` node and set exported `starting_hour = 16.5` in the scene **on a fresh save** and `cycle_seconds = 60` (test-only). Dusk should begin near 17:00 and the world should gradually darken. A prior save with `reserve_time_minutes` overrides starting_hour.

## Headless tests (not yet executed by ChatGPT)

From repository root:

```bash
godot --headless --path godot-project --import --quit
godot --headless --path godot-project --script res://scripts/reserve_loop_test.gd
godot --headless --path godot-project --script res://scripts/prologue_visual_smoke_test.gd
godot --headless --path godot-project --script res://scripts/garden_world_test.gd
```

A GitHub Actions workflow (`.github/workflows/godot-feature-tests.yml`) was added for feature branches and PRs, using Godot 4.3. Check the Actions tab for actual results; the presence of tests does **not** mean they have passed.

## Follow-up for Muse / Tucker / Ivy

- **Muse art:** Replace temporary battle-art projections with five transparent game-scale 3/4 top-down overworld sprites (one approved PNG each). Remove white-paper matte shader once all three opaque masters are replaced.
- **Muse design:** Confirm a gameplay day length and exact phase boundaries; 12 minutes per day and 17:00 dusk are placeholders used to expose the clock API.
- **Muse systems:** Provide final Lullmother planting/fruit/dusk decision specifications; no instant capture and do not add romance meters.
- **Tucker:** Review on a separate feature branch; do not merge `develop` until Godot import/tests and APK export pass.
- **Ivy:** Test overlaid residents, UI on Android, time tint, exit transitions, initial observation and save/reload.

Future implementation: a Lullmother planting/offer/walk-away state machine, consumption of actual fruit inventory, and dusk-time creature choice. No current implementation claims to offer those features.
