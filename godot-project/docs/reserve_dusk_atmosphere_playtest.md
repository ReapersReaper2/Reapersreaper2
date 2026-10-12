# Reserve dusk atmosphere — visual QA and integration

**Branch**: `chatgpt/reserve-dusk-atmosphere-20261012`  
**Target**: Godot 4.3 / Android debug build. Based on `develop` at commit `39a9474`; no mainline change.

## What changed

Death's Garden has a lightweight environmental presentation layer in `gd1`, `gd2`, and `gd3`. As the existing Reserve clock progresses toward dusk, small warm lantern sources brighten shrine/trail/refuge landmarks while floating firefly-like motes become more visible. Daytime keeps lanterns and motes subdued, dusk increases their warmth, and dawn fades them back.

This pass does **not** introduce collision, change navigation, override approved artwork, alter encounter/offer state, grant rewards, or modify save data. Its only dependency is `ReserveClock.get_time_of_day()`. The actual time/day system stays authoritative in `reserve_clock.gd`. No new lore or story beats.

**Files**:
- `scripts/garden_dusk_ambience.gd`: reusable Node2D for inexpensive deterministic mote and lantern rendering; at most six `PointLight2D` nodes, drawing throttled to 20 Hz.
- `scenes/room_gd1.tscn`, `room_gd2.tscn`, `room_gd3.tscn`: world bounds, existing landmark positions, distinct seeds and moderate mote counts.
- `scripts/garden_dusk_ambience_test.gd`: checks clock-phase brightness, deterministic/local mote movement, light count, no collision, and proper daytime/dusk/night energy change.
- `.github/workflows/godot-feature-tests.yml`: test invocation.

## Playtest steps for Tucker and Ivy

1. In Godot 4.3, open `room_gd1.tscn`, F6 to play the current scene. Check that motes do not overwhelm Mollosar or the resident sprites, and that warm visual accents lead toward the refuge, shrine, and existing gate landmarks.
2. To inspect dusk quickly on a **fresh save**, set `ReserveClock.starting_hour` to `16.5` and `cycle_seconds` to `60`, then run the scene. Existing saves override starting_hour.
3. Confirm the flame light and mote visibility increase gradually from daylight into dusk; at night, the scene should remain readable, with warm accents against cool shadows.
4. Stand near a creature and its interaction prompt. Motes and light must not capture touches, trigger combat, interfere with collision, or alter the observed count. Confirm the pause/menu and HUD remain legible on a phone.
5. Move between `gd1`, `gd2`, `gd3`, and the refuge. The interior remains warmly lit without outdoor motes; leaving and returning preserves the same Reserve time.
6. Watch Android performance for stutters. 20-Hz drawing, bounded mote counts, and a six-lantern maximum are intended to keep cost predictable.

**Headless check** (from repository root):

```bash
godot --headless --path godot-project --import --quit
godot --headless --path godot-project --script res://scripts/garden_dusk_ambience_test.gd
```

## Scope boundaries

These lanterns are temporary drawn effects, **not** permanent replacements for Muse's painted props or a final environment tileset. The Muse team can reuse their placements and replace the small lantern glyphs or firefly primitives with approved sprites. No gameplay mechanics rely on these effects.

**Merge gate**: GitHub Actions Godot feature tests plus manual visual inspection, especially Android. Do not merge a pending or failed draft PR.
