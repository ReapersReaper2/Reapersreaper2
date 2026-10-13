# Bellhollow painted-stone integration — October 13, 2026

**Branch:** `chatgpt/bellhollow-painted-stone-deck-20261013`  
**Source of art:** Muse-approved `tile-stonepath-v2.png`, Google Drive file ID `1LOoO5GiavG1Gm5h0stMNugSZhymJKoZg`; imported intact as `res://assets/environment/bellhollow_stonepath_source.png` (512×512, 533,007 bytes).

## Change

The current prologue bridge already has an approved burning-city skyline and detailed character art, but a generated slab surface still feels noticeably disconnected from them. This pass uses an **actual approved hand-painted paving texture** on the playable bridge. The source is undamaged and checked into GitHub as a **real binary PNG**, not an LFS pointer or runtime download.

`prologue_bridge_world.gd` now makes a temporary in-memory copy and adjusts its brightness/contrast/saturation to suit the mortal Bellhollow palette: smoky charcoal, weathered rock, fading ember reflections. The file in `assets/environment/` remains identical to the approved source. The bridge is tiled horizontally; non-interactive soot and the old damaged parapet/rubble/weathering remain layered over the new painted floor. The existing `flagstones_for()` procedural geometry is kept as an explicit toggleable **fallback**, `use_painted_stone=false`.

No collision, character art, sword combat, animation, story dialogue, title, encounter balance, objective HUD, or save field was modified. The original rails, tutorial trigger and invader spawner are retained.

## Phone / Godot QA

1. Run `room_p1.tscn` with F6 or install a **new Android debug APK** built from this commit after merge.
2. Compare the paving to the skyline and characters: you should see irregular hand-painted cobbles instead of largely flat drawn stones. It should be dark charcoal with subtle warm stone seams, not saturated blue/cyan Reserve path art.
3. Confirm no hard repeated vertical bands become distracting when scrolling horizontally. Source art contains an internally repeating pattern; shader-free native tile drawing is deliberate for Android performance.
4. Confirm wall caps, parapet edges, bridge rails and rubble remain visible, and smoke/embers from the previous pass render above the floor but behind Mollosar and Mira.
5. Press joystick/SWORD/USE, talk to Mira, trigger the bridge tutorial and proceed through enemy waves. Nothing in gameplay should change.
6. Temporarily set `WalkableBridge.use_painted_stone=false` in the scene inspector to verify the original polygon stone fallback still renders.
7. If the world feels too dark or warm on your phone, adjust **runtime** parameters in `_prepare_painted_stone()` / `_draw_painted_deck()`, not the approved master image.

## Verification

```sh
godot --headless --path godot-project --import --quit
godot --headless --path godot-project --script res://scripts/bellhollow_painted_deck_test.gd
godot --headless --path godot-project --script res://scripts/prologue_pose_bridge_test.gd
godot --headless --path godot-project --script res://scripts/prologue_bridge_atmosphere_test.gd
```

GitHub CI exercises this test alongside the existing feature suite. The focused check verifies a real binary 512×512 artwork asset, pixel-value reduction in saturation/brightness, Godot texture repeating, fallback geometry, room triggers and collision continuity.

**Art boundary:** This is a production integration of approved painted paving, not a claim that the final Bellhollow-specific tileset is completed. A bespoke Muse bridge floor could eventually replace it with no change to the room's mechanics.
