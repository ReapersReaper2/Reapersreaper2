# Death's Garden — Hand-painted Tree Integration (2026-10-13)

**Branch:** `chatgpt/painted-garden-trees-20261013`  
**Muse source cutouts imported unchanged as native Git PNGs:**

| Game asset path | Drive source | Original bytes |
| --- | --- | ---: |
| `assets/environment/garden_tree_oak_v2.png` | `tree-twisted-oak-v2.png` / `1yiP3cP4J15GVO14a9WfyU_uE6gMvaGIq` | 347,410 |
| `assets/environment/garden_tree_willow_v2.png` | `tree-willow-v2.png` / `1q4BCNYzqU-qKYV4q9E9P451kEXkvP8Yn` | 398,019 |
| `assets/environment/garden_tree_dead_v2.png` | `tree-deadtree-v2.png` / `1yfm6Lht_w_DW_VIfJvrsTVK7tYHxRFVr` | 237,892 |

All three original 512×512 PNGs remain intact. No black or white painted rectangles should accompany their alpha cutouts.

## What changed

Previously Death's Garden used geometric circles and straight lines for every tree. Now `garden_tree.gd` places a painted twisted oak, spirit willow or deadwood silhouette at the SAME authored tree node positions. Each is resized to 154–176 world pixels, grounded at the original trunk base, and keeps the same world-y depth sorting. A modest ground shadow still sits beneath the roots.

Importantly, **tree collision and procedural spawn locations are unchanged**. The exact original CircleShape2D radius of 24px, the (0,18) collider offset, collision layer and mask are preserved. `garden_world.gd` selects variants deterministically from the existing cell coordinates and room seed, without consuming extra RNG values; therefore creature placement, path corridors, save semantics and access to shrines/refuge/exits remain intact.

The original geometric tree rendering remains usable via `GardenTree.use_painted_art=false` for debug comparison/rollback.

## Android and Godot QA

1. Play `room_gd1.tscn`, then `room_gd2.tscn` and `room_gd3.tscn`. Look for three distinct painted trees against the new grass/path textures—no black boxes behind the cutouts.
2. Walk behind an oak and in front of a willow. The sprites should correctly occlude Mollosar according to y position, without popping or hiding the player permanently.
3. Walk beside several roots. Tree colliders should block at the same ground-foot position as before, not at the full canopy width.
4. Check that the shrine, refuge entrance, garden perimeter, living creatures and east/west exits remain reachable.
5. Inspect a dense cluster on Android; the 512px art is rescaled to approximately 160px with linear filtering, so silhouettes should read without pixellation.
6. Compare against the fallback by setting `GardenTree.use_painted_art=false` on a selected tree in the editor. No route geometry or collision should move.

## Automated test

```bash
godot --headless --path godot-project --import --quit
godot --headless --path godot-project --script res://scripts/garden_painted_trees_test.gd
godot --headless --path godot-project --script res://scripts/garden_world_test.gd
godot --headless --path godot-project --script res://scripts/garden_painted_ground_test.gd
```

The focused test checks original source byte sizes, transparent alpha corners, imported 512px size, visual root anchoring, original 24px collision geometry/layers, Y depth and deterministic variation; then generates a garden and confirms every solid tree still avoids paths and none are added/removed. Included in Godot 4.3 feature CI.

**Next:** remove or artistically upgrade geometric garden arches, gate posts and cottage shapes using suitable Muse props. The character/bonding mechanics are outside this art pass.
