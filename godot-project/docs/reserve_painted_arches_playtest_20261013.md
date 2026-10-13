# Reserve painted-arch integration — October 13, 2026

**Source authority:** Approved Muse environmental PNGs in the Reaper's Reaper Drive, no repaint or AI reinterpretation applied.

**Art provenance and exact files**
- `res://assets/environment/reserve_crumbling_arch_v1.png` from Drive `env-crumbling-arch-v1.png` (ID: `11_5k0I7NOkg8Wtfbd16N69N6mByimAXr`; original 512×512, 223,064 bytes).
- `res://assets/environment/reserve_stone_archway_v1.png` from Drive `env-archway-stone-v1.png` (ID: `1RScfFPAjq7WkL7t6UJlAWRF27bKS96WZ`; original 512×512, 362,049 bytes).

Both are stored as **real PNG Git blobs** so Godot imports their transparency with or without Git LFS. The original master bytes were not altered.

## What is different in the game

The flat stone ring at each garden landmark is replaced by an old painted crumbling arch. The boxy rectangular exit gateways are replaced by distinctive hand-painted stone archways with ivy and warm lanterns. The east gate is reflected horizontally to vary the composition. This affects gd1, gd2 and gd3 through their shared `garden_world.gd` script.

Painted roots and arch-foot pixels meet the *existing* world-space position, calculated from each PNG's nontransparent bounding box rather than from the middle of the square 512px canvas. The ruined arch displays at about 195 world pixels tall; gateway arches at about 205 pixels tall. Each is a non-colliding `Sprite2D` sorted by ground Y so the player can pass through and stand at the same world locations.

**All established story objects, refuge entry, creature spawn sites, garden world bounds, walkway corridors, tree colliders and exit transition triggers remain exactly where they were.** No new quests, story, economy, capture logic or input are added. If the image is unavailable or `use_painted_landmarks=false`, the old procedural geometry remains as a fallback.

## QA for Android or Godot 4.3

1. Use a debug build from the merged feature commit; older APKs have none of this artwork. The title screen's TEST RESERVE shortcut is the fastest way to inspect gd1.
2. Confirm the x≈300, y≈100 central landmark is now a broken, overgrown stone arch rather than a simple ring, without hiding interactable lore labels.
3. Walk west/east toward the room boundaries: painted archways should mark the existing exit transitions, with no new solid walls, blocked inputs or change to where the next room loads.
4. Walk to gd2 and gd3; confirm the same two art types and varying room placements.
5. Check that painted arch feet rest on the terrain, that characters draw naturally near them, and that lanterns are readable at dusk.
6. Check performance on Android and look for repeated dark/blue portals that seem too intrusive. Asset intensity/target size are presentation parameters, not gameplay.
7. If a regression is seen, toggle `PlayableGarden.use_painted_landmarks` off in the scene inspector to restore the previous drawn shapes.

## Automated checks

```sh
godot --headless --path godot-project --import --quit
godot --headless --path godot-project --script res://scripts/garden_painted_arches_test.gd
godot --headless --path godot-project --script res://scripts/garden_world_test.gd
godot --headless --path godot-project --script res://scripts/garden_painted_landmarks_test.gd
```

The test covers actual PNG headers and dimensions (not LFS pointer text), silhouette bounding box, zero-padding correction, Y-depth ordering, approved room scene script defaults, unchanged original exits and paths, and togglable procedural fallback. Merging requires GitHub CI and Godot 4.3 feature tests to be green.

This is an approved-art integration step, not final aesthetic signoff; Ivy/player should validate actual game-scale views before treating these as finished.
