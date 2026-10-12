# Bellhollow Bridge prologue rescue — playtest checklist

**Work branch:** `chatgpt/prologue-visual-rescue-20261011`
**Engine:** Godot 4.3
**Scene:** `res://scenes/room_p1.tscn`

## Try the opening first
1. Switch to the work branch in GitHub Desktop (or `git switch chatgpt/prologue-visual-rescue-20261011`). Open `godot-project/project.godot` in Godot 4.3.
2. Press F6 on `scenes/room_p1.tscn` for the bridge, or launch the game normally to go through the title screen.
3. Confirm **Form 1 Mollosar is an animated character with a sword** and **Mira and the wounded soldier display painted figures**, not the purple rectangle / colored polygons seen in the October 11 recordings.
4. Test movement along the paved bridge, against both parapets, and near the shrine. You should not be able to walk into the void beyond the railings.
5. Talk to Mira and the soldier. The dialogue should display their face portraits rather than only letters.
6. Trigger the invader waves and swing the sword. Confirm hits, knockback, and wave progression still work.
7. On an Android touchscreen, hold the circular joystick and press SWORD with a second finger; press TALK with another finger. Watch for sticky movement after releasing the joystick.

## If the art is still missing
- Check the Godot Output panel. `[ART] Loaded playable image fallback: ...` means the bundled, LFS-independent PNG copy loaded correctly.
- `res://assets/critical_sprites/` contains fallback encoded artwork for **Form 1** walking/idle sprites and the opening NPCs. These were verified against their original PNG bytes.
- **Other forms** still rely on normal Git LFS hydration. Run `git lfs pull` for the wider game.

## Headless regression checks
From the repository root:
```bash
godot --headless --path godot-project --script res://scripts/prologue_visual_test.gd
godot --headless --path godot-project --script res://scripts/mobile_touch_test.gd
```
These scripts are checked in but **have not been executed in this assistant environment**. Report any parse errors and the test label.

## Known limitations
- The bridge has an authored stone collision/deck overlay, but the skyline remains a painted backdrop. This is a targeted prologue recovery, not a final full-world art rebuild.
- Painted NPCs use a static master pose; more animation requires separate game-sized sheets.
- Godot import/runtime and Android touch need a device playtest before merging this branch to `develop`.
