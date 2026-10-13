# Death's Garden — approved cutout foot grounding (2026-10-13)

**Branch:** `chatgpt/reserve-alpha-foot-grounding-20261013`  
**Baseline:** `develop` at commit `365d00fb`; the 5 approved transparent 384×384 creature PNGs were already merged before this pass.

## Visual problem

The native overworld PNGs contain generous transparent framing: painted feet usually end around source row 353, but their Sprite2D scene pivot sat in the middle at row 192. As a result, a creature's visual feet landed dozens of world pixels **below** its interaction sensor and its contact shadow. The art also scaled using the full square canvas, not the actual visible animal height, making different creatures visually smaller than intended and letting some prompts overlap the subject.

## Code correction

In `scripts/reserve_creature.gd`:
- `overworld_layout()` reads `Texture2D.get_image().get_used_rect()` to find the actual painted alpha bounds. This is done at startup, not each frame.
- Scales native art to its existing per-species `overworld_display_height` using the **visible** alpha height.
- Uses the `Sprite2D.offset` property to put the **visible bottom edge** at the creature's original authored world position. It does **not** change the underlying Node2D placement, observation guide, combat, collisions, save positions or species IDs.
- Anchors ground shadows at this same position, sizes them using actual visible art width and positions the USE/E prompt above the visible silhouette.
- Preserves the legacy painting/fallback path untouched if `prefer_overworld_art=false` or a PNG is unavailable.

The existing approved art bytes are **not** edited, re-encoded or overwritten. No lore, bonding/capture mechanics, encounter probabilities or day/night logic was added.

## Validation and phone QA

Run `godot --headless --path godot-project --script res://scripts/reserve_native_overworld_test.gd`. The five-species test now verifies measured alpha height, foot pivot, contact shadow, prompt clearance and preserved art fallback. Existing `reserve_loop_test.gd` and `reserve_creature_motion_test.gd` must also pass.

On a new **debug APK**, enter the Reserve and compare Dragonthorn, Gloomcap, Spinehopper, Bellmaw, Wispwillow: each should visually meet the floor/hover point beneath its shadow, with no mysterious gap. Hopping Spinehopper should lift from and return to that point. USE should appear above the animal, not over its head. Walk behind and around the residents; they should stay near their preexisting placed locations and share the same navigation/observation response.

Check especially that Bellmaw and Wispwillow don't look excessively tall next to Mollosar; their visible-body target is still the art director's existing `overworld_display_height`, but changing an old canvas-relative size to an alpha-relative size may alter the visual proportions slightly. Actual Android visual approval remains essential.
