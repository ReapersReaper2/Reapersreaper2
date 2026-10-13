# Form 1 — approved painted longsword swing integration

**2026-10-13 · Source art reviewed in Google Drive before implementation**

Source references:
- [Muse: Form 1 Mortal Mollosar, Asset Sheet 14](https://drive.google.com/file/d/1Lz2uYBeYmaS6zkpCfNNdeC5w69l3KT9c/view)
- [Muse: Mortal Armor, Asset Sheet 02](https://drive.google.com/file/d/1JEKr9XaAMCgVGV9LDPlz-1_NwetbP3-c/view)
- [Form 1 four-direction 384px source strips](https://drive.google.com/drive/folders/1v25De7hlRZ2YY2dHntWl679WweEK4Az3)
- [Captain Spaulding's animation pipeline](https://drive.google.com/file/d/14H3KIIt-kJmC8gNFirGhc5uoecXNZOqo/view)
- [Ivy's sprite QA report](https://drive.google.com/file/d/1Qhf-Wka8LRzzIR5IzMkY8Z1cZ5ZYiLk6/view)

## Root cause found in the actual approved art

The walk frames already depict the LONGSWORD in Mollosar's **right hand**. Before this pass, `scythe_visual.gd` added another synthetic 90px weapon on attack, so the player visibly held two swords. Worse, two separate functions animated the body on the same update tick, sometimes fighting each other's position/rotation.

## What this branch changes

- `form1_resting_blade.gdshader`: during a swing only, temporarily removes the painted resting blade from the original Form 1 sprite and inpaints its pixel corridor with nearby painted cloth/armor. No persistent modification to approved source PNGs. No missing-art fallback data.
- `form1_swing_blade.gdshader`: samples the **same exact sword pixels from the approved walk frame** and rotates the blade about its original gold crossguard. Its animation angle comes directly from the existing combat timeline (not a second timer). Gold hilt and right-hand pose stay on the body. Directions down, up, left, right use hand-marked source pivots.
- `mollosar_sprites.gd`: one masked base sprite plus one reprojected sword layer, kept at the identical body pose and image region. No added weapon geometry, no new damage or hitbox. Both materials are reused; zero allocations in the per-frame attack update. Resting and switching forms immediately restore the unchanged source art.
- `scythe_visual.gd`: when Form 1's approved sword rig exists, skip the old procedural double-sword overlay. Headless/no-art fallback remains intact.
- `mollosar_sprites.gd::tick`: removed the older competing body-rotation transform. The already-tested grounded pose in `set_mortal_sword_pose` is now the single authority for sprite movement.
- `form1_painted_blade_test.gd`: validates 4-way anchors, both combo directions, texture/atlas alignment, no duplicate rig geometry, effect cleanup and pixel source provenance. All integrated with Godot 4.3 CI.

**Canon lock:** mortal Form 1 uses a weathered steel field longsword with gold crossguard, in his RIGHT hand. He does not receive the double-headed scythe before death.

## Phone acceptance — new merged APK only

1. NEW GAME → Bellhollow. Confirm only one painted sword at idle, and only one sword during attack (no extra thin silver stick spinning through his torso).
2. Attack repeatedly facing each direction. Check down/left/right/up, two-hit chain, and returning to neutral after the second strike.
3. Verify the blade looks like the original *painted* steel, with no large purple pie wedge. Check its guard stays near his right hand as his body leans.
4. Watch for obvious cloth holes, sword ghosts or double exposure in the lower half: this is the highest-risk visual area because the master walk sheets are flattened.
5. Confirm attack hitstop, enemy damage, invader wave completion and touch controls remain unchanged.
6. Repeat on Android with an actual 16:9 and extra-wide display; the sword should be legible without overpowering the character.

## Remaining Muse deliverable (approved production attack animation)

The animation team's stated humanoid standard is rigged windup/recovery with **2–3 painted smear impact frames**. An actual separated Form 1 character rig, its individually painted RIGHT-hand sword mesh, and matching 4-direction attack accents are still needed for completely clean silhouettes. This code is a production-oriented interim pass that uses the existing art; it is not falsely presented as final 3D rigging or a signed-off sprite atlas. When approved attack strips arrive, the runtime should prioritize them over this fallback.

**Scope & merge gate:** no story/dialogue/save changes. Godot CI and Android export must pass, followed by a human visual check.
