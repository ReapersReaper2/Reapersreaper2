# Reserve observation wayfinding — QA handoff

**Feature branch:** `chatgpt/reserve-wayfinding-20261012` (based directly on `develop`).  
**Scope:** Player-facing guidance and its tests; not a narrative quest system.

## The problem

The current Reserve HUD instructs the player to observe five residents, but gives no directional clue in a garden nearly 2,600 pixels wide. Players can wander without knowing where to find creatures, and the existing objective counter doesn't distinguish seen from unseen destinations.

## What's implemented

`reserve_guide.gd` now uses resident nodes already loaded by the scene to choose the **nearest unobserved** species. A small gold compass arrow below the existing Reserve objective points toward the actual world position, with a neutral proximity label (NEARBY / AHEAD / FARTHER) and the creature's name. After interaction, the existing `reserve_observed` save ledger makes the guide select a different resident; it does not create new quest flags, grant rewards, or alter bonding.

- Ties break by species identifier, and targets switch only when the alternative is meaningfully closer, preventing arrow flicker as creatures sway.
- Only living nodes exposing the canonical `reserve_creature.gd` interaction contract qualify.
- The arrow uses Godot canvas drawing and doesn't need fonts, icons, art downloads or additional LFS assets.
- It never intercepts touches, issues movement commands, consumes fruit, or triggers capture.
- After all residents are observed, the arrow and hint go away, while the existing 5/5 objective remains visible.

**Files:** `scripts/reserve_compass_arrow.gd`, `scripts/reserve_guide.gd`, `scripts/reserve_wayfinding_test.gd`, and Godot feature CI.

## Android/editor QA

1. Run `room_gd1.tscn` in Godot 4.3 (F6) or use **TEST RESERVE [DEV]** in the debug APK.
2. Verify the small compass appears below the existing top-left Reserve objective; the top-right clock, pause/menu, and touchscreen joystick/USE remain accessible.
3. Begin near the center: follow the arrow to the indicated resident and verify it turns smoothly as you move around the creature.
4. Press **USE/E**, check one observation increments the count and the compass selects another unseen resident; observing the same creature repeatedly must not increment count.
5. When two residents are similarly distant, the arrow should not rapidly swap between them.
6. When all five have been observed, the guidance arrow and label should disappear without changing regular exploration/room transitions.
7. Resume a save with some species already seen: no already-observed creature should become an objective.
8. Test font availability for the label and that the compass appears inside the viewport on narrow phones.

## Automated verification

```sh
godot --headless --path godot-project --import --quit
godot --headless --path godot-project --script res://scripts/reserve_wayfinding_test.gd
godot --headless --path godot-project --script res://scripts/reserve_loop_test.gd
```

The first test checks deterministic target selection, save-ledger exclusion, distance classifications, compass direction, mobile touch pass-through, and a live ReserveGuide fixture. Existing scene and interaction tests remain part of CI.

**Merge gate:** Godot 4.3 feature CI, repository-wide CI, and Ivy/Tucker Android visual review. No changes to `develop` without review.

**Future art:** Compass lines/colors are a functional placeholder; approved Muse UI artwork can replace the small directional marker without changing discovery logic.
