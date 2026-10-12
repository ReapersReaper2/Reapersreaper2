# Android playtest fix — missing joystick and Mira scale (October 12, 2026)

**Observed from player's actual prologue bridge screenshot:** the landscape debug APK displays no joystick/action buttons, while Mira is visibly larger than Mollosar. The atmospheric painting loads correctly.

## Code changes

- `scripts/touch_controls.gd`: native Android and iOS builds always instantiate and show `MobileHUD`, even if `DisplayServer.is_touchscreen_available()` reports false. A touch-capable desktop/web viewport still shows controls. A headless/desktop QA override exists via the player's `TouchControls.force_touch_controls` export or the project setting `reaper/force_touch_controls=true`. Ordinary keyboard desktop remains uncluttered.
- `scenes/player.tscn`: touch CanvasLayer is set to **layer 8**, above the world drawing and below the pause menu (layer 10). Its overlay anchors and offsets fill the entire logical viewport.
- `scripts/npc.gd`: Mira gets a specific **108 world-pixel master-art height** rather than the shared 145 px; Mollosar's mortal sprite was visibly much shorter on the screenshot. Mira's sprite feet and name/prompt remain vertically aligned with the new height. Other NPCs retain their prior 145 px height. Future hand-approved art can use the optional `art_display_height` export.
- `scripts/art_test.gd`: verifies individual NPC scale, ground alignment, name-label clearance, and optional scaling override.
- `scripts/mobile_touch_visibility_test.gd`: verifies the failed touchscreen-detection scenario, player-scene wiring, layer order, full viewport geometry, finger control zones, and duplicate-instantiation guard.

## Android QA checklist

1. Install the **new APK built from this PR after merge**. An older installed APK will not change automatically.
2. Open a fresh/continued prologue. Verify a visible large joystick at **bottom-left**, **USE / SWORD** buttons at bottom-right, and **MENU** above the buttons. The buttons must appear without requiring a first touch.
3. Move Mollosar with a left thumb; while still moving, press SWORD or USE with a right thumb. Check the joystick releases cleanly on finger lift and menu opens on tap.
4. Walk toward Mira on Bellhollow Bridge. She should now be roughly Mollosar's apparent height, not a looming giant. Her feet should remain on the bridge and her MIRA label should clear her head.
5. Trigger her dialogue with USE. Verify the touch overlay stays visible in ordinary exploration and doesn't block the dialogue panel.
6. Verify the story's existing enemies and bridge triggers still work, and the pause/save dialog appears above the mobile HUD.
7. Check the scene on a wider-than-16:9 phone: controls should live inside the game canvas; black pillarboxes outside are expected with the current keep-aspect setting.

**Automated verification:** project-wide headless GDScript CI and Godot 4.3 feature workflow, plus manual Android visual QA before considering final art proportion. No new lore, dialogue, data schema, economy, or combat changes.
