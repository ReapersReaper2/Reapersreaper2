# Death's Garden — painted trees and refuge cottage

**Branch:** `chatgpt/painted-garden-trees-refuge-20261013`  
**Reference authority:** Muse production Drive; the source PNGs were imported as real RGBA Git blobs without cropping, painterly restyling or changing canon.

| Asset | Original Muse filename | Repository path |
|---|---|---|
| Twisted oak | `tree-twisted-oak-v2.png` | `assets/environment/garden_tree_twisted_oak_v2.png` |
| Enchanted willow | `tree-willow-v2.png` | `assets/environment/garden_tree_willow_v2.png` |
| Dead tree | `tree-deadtree-v2.png` | `assets/environment/garden_tree_dead_v2.png` |
| Bone-white tree | `tree-bonewhite-v1.png` | `assets/environment/garden_tree_bonewhite_v1.png` |
| Refuge cottage | `building-cottage-v2.png` | `assets/environment/garden_refuge_cottage_v2.png` |

All paths above are relative to `godot-project/`. Tree images are transparent 512×512. The cottage is transparent 512×341. Their exact Git blob bytes are verified by the regression suite so LFS pointers cannot silently sneak back in.

## What changed

The procedural trees previously consisted of colored circles/rectangles, contrasting sharply with the newly painted grass and dirt. The existing `GardenWorld` still places exactly the same solid tree nodes/colliders, but each tree now receives one of four transparent Muse-painted silhouettes. Tree types are selected by a deterministic function of **authored world position and existing scene seed**, not by consuming additional generation RNG calls, so trees and route clearings do not move.

Trees are sized by their visible alpha bounding boxes and grounded at the original **local y=18px** trunk-collision baseline. The same body radius (24px), z-depth sorting, and escape routes are retained. The old geometric tree remains available with `use_painted_tree=false`.

The refuge cottage also now uses Muse's painted thatched stone building instead of rectangular facades; its visible doorstep lands near **local y=64px**, matching the unchanged entrance trigger. Existing cottage side/rear collision walls and the interior scene remain untouched. `use_painted_facade=false` retains the original fallback.

## Test instructions

```bash
godot --headless --path godot-project --import --quit
godot --headless --path godot-project --script res://scripts/garden_painted_landmarks_test.gd
godot --headless --path godot-project --script res://scripts/garden_world_test.gd
godot --headless --path godot-project --script res://scripts/garden_painted_ground_test.gd
```

## Android / live review

1. Open the latest debug APK after merge and use **TEST RESERVE [DEV]** on the title screen.
2. Walk through Death's Garden: oak, willow, deadwood and occasional bone-white trees should visibly blend into the hand-painted ground. The canopy may cover Mollosar when he walks behind a trunk; he should appear in front when below it.
3. Walk against the base of a tree: the same old trunk collider must stop Mollosar, and the art's roots should sit on the ground rather than float above it.
4. Approach the painted cottage at x=-500 and enter via the existing southern door at y=118. Confirm no new invisible obstruction and no entry-loop on return.
5. Check on Android that closely planted tree canopies don't make routes visually confusing, and report screenshots for size/spacing tuning.

**Scope:** visual replacement only. No new dialogues, bonding, inventory, save changes, or new biome lore. The art remains subject to Muse's final visual sign-off.
