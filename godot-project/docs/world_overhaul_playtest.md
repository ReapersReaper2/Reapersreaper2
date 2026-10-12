# World overhaul playtest — Garden route (Godot 4.3)

**Branch:** `chatgpt/world-overhaul-20261011` (includes the scythe/mobile visual branch; `develop` is unchanged).

## Open immediately in Godot

1. Check out the branch and run `git lfs pull` if your checkout uses Git LFS.
2. Open `godot-project/project.godot` with Godot **4.3**.
3. In the FileSystem dock open `res://scenes/room_gd1.tscn`, then **F6 (Run Current Scene)**. The game normally starts at the prologue, so F6 is the quickest way to inspect the changed area.
4. Walk left from the center spawn to the refuge building at roughly **(-500, 45)** and approach its open doorway at **(-500, 118)**. The building must have solid side walls but a passable doorway.
5. Inside: inspect the ledger on the western writing desk using **E**. Walk south through the opening to return to the garden (outside spawn **(-500, 265)**, clear of the entry trigger).
6. Follow the main path east to `gd2`, then `gd3`; visit the shrines and story objects. The trees should block at their trunks, and the crowns should layer in front of/behind the player depending on Y position.
7. Check the new wooden road signs, NPC/canopy depth and existing creature sprites. Form 1 should show a sword, not a scythe. Later forms follow the equipped reaper weapon.

## Headless route and save-room test

From the **repository root**:

```bash
godot --headless --path godot-project --script res://scripts/garden_world_test.gd
```

This checks primary paths, feature connections, safe doorway spawn offsets, and Continue's destination mapping. A Godot import/playtest is still needed for actual collision/visual validation.

## Known first-pass limitations

- Scenery is code-drawn, modular and collision-aware, **not yet** an approved painted `TileMapLayer` tileset.
- The three revised rooms are `gd1`, `gd2`, and `gd3`. Other world rooms still have their original presentation.
- Scythe/longsword/tail artwork is currently a fallback drawn from vectors; future sprite-based weapon art should replace it.
- Test a real Android device for touch controls; desktop visibility is intentionally disabled.
- Do not merge to `develop` until Godot import, travel transitions, dialogue, combat and save/load have been playtested.

Please report the exact scene, player position if possible, error text, and a screenshot for any blockage.
