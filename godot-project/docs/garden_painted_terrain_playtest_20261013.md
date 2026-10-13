# Death's Garden — Painted Terrain Integration (2026-10-13)

**Branch:** `chatgpt/painted-garden-ground-20261013`  
**Muse-source art imported as native binary PNGs:**
- `res://assets/environment/garden_grass_a_v2.png` — Drive `tile-grass-a-v2.png`, ID `1NUXZC0ToPf0w44UBgJ7YduIqlTcQPS6c`, original 512×512 PNG, 520,961 bytes.
- `res://assets/environment/garden_dirtpath_v2.png` — Drive `tile-dirtpath-v2.png`, ID `1NDBP4WeJUA4tTysf7HK_feefXHGGN_s2`, original 512×512 PNG, 517,198 bytes.

## Visual change

All three already-authored Death's Garden rooms instantiate `garden_world.gd`. Previously it drew 64-pixel flat green and brown rectangles to indicate trees versus paths. The same gameplay regions now display hand-painted grass and a real dirt/stone trail. A small `garden_ground_paint.gdshader` uses an 8-world-pixel mask sampled from the **existing** `_walkway()` geometry and gently blends the two textures across a narrow, approximately 40px transition.

The route mask is calculated once when the room loads. On phone, the floor uses one ColorRect and two repeating imported PNG textures. Both source images are committed **unchanged**; the scene does no cloud fetch or PNG baking on a player's phone. The ground stays behind tree canopies, trunks, rocks and characters.

The existing gardens' landmarks, creature placements, compass, clock, path connections, exits and collisions are untouched. This is a **presentation-only** replacement of the colored floor. The old flat colors are available via `PlayableGarden.use_painted_ground = false` as an immediate rollback.

## Playtest / acceptance

1. In Godot 4.3, run `scenes/room_gd1.tscn` (F6), or use the Android debug title screen's **TEST RESERVE [DEV]** shortcut on the new APK.
2. Walk east and west from spawn. The dirt path should be textured and softly merge into painted grass rather than ending at square grid boundaries. Existing obstacles still block where they used to.
3. Go toward the refuge at x≈−500; its existing clear passage to the main trail must remain usable, as must the shrine and the exits to gd2/gd3.
4. Look at the floor during daytime and dusk. CanvasModulate should continue tinting the whole world while lanterns and characters remain readable.
5. On phone, check whether the 512px tile repetition is noticeable. A custom transition atlas or a third grass variant can be added once the full environment's art direction is approved. Do not treat this pass as final terrain production.
6. Temporarily set `PlayableGarden.use_painted_ground=false` in the scene inspector; confirm the previous procedural rendering appears with exactly the same collisions and paths.

## Automated checks

```bash
godot --headless --path godot-project --import --quit
godot --headless --path godot-project --script res://scripts/garden_painted_ground_test.gd
godot --headless --path godot-project --script res://scripts/garden_world_test.gd
```

The new test checks that the two real PNGs match Drive bytes, imports the shader, validates texture scale and input handling in gd1/gd2/gd3, checks soft trail mask and landmark clearings, and verifies procedural fallback. It is added to the Godot 4.3 feature CI workflow.

**Next art priority:** replace procedurally circular garden tree canopies and angular gate props with approved top-down tree/trunk and portal sprites. Preserve authored tree collision radius and y-based depth when doing so.
