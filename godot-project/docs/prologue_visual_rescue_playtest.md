# Bellhollow Bridge visual rescue — first Android playtest

Branch: `chatgpt/prologue-visual-rescue-20261011` (based on the earlier garden overhaul).
Godot version: 4.3.

## What to inspect

Open `res://scenes/room_p1.tscn` and use F6 / Run Current Scene. This is the scene seen in the October 11 screen recordings.

- **Mollosar:** Actual four-direction Form 1 walking animations and the two-frame idle down strip, not a purple rectangle. Form 1's in-sprite longsword should not be duplicated at rest.
- **Mira and wounded soldier:** Real 1024×1536 illustrated NPC masters replacing the peach / red circles.
- **Dialogue:** Character portraits for Mollosar, Mira, and Soldier replace the initial-letter boxes; dialogue takes up less of the screen.
- **Bridge:** Characters walk on an actual stone deck with a clear parapet and solid edge collisions. Both the skyline painting and the floor should be visible.
- **Combat:** Enemies look like armored marauders rather than red spheres; they still take hits.
- **Phone buttons:** Rounded joystick and gold-rimmed action buttons. Form 1 action is labeled SWORD (input action is still `scythe_swing` for backward compatibility).

## Why this branch contains .b64 files

The original `res://sprites/mollosar/`, `res://assets/npc/`, and Bellhollow background PNG files are Git LFS-managed. A GitHub ZIP or misconfigured checkout can contain only the LFS pointer text, which explains why an APK can show placeholder polygon characters. The exact matching original image files were fetched from the project Drive and bundled as fallback base64 text under `res://assets/critical_sprites/`. `critical_sprite_loader.gd` prefers the original PNG when it exists, otherwise decodes the bundled PNG. Export presets include `assets/critical_sprites/*.b64` in the non-resource include filter.

If you generate a **new Android export preset**, make sure its **Resources > Filters to export non-resource files** also contains `assets/critical_sprites/*.b64`. Without it, the mobile export may omit the fallback files.

## Run tests

```bash
godot --headless --path godot-project --script res://scripts/prologue_visual_test.gd
godot --headless --path godot-project --script res://scripts/mollosar_sprites_test.gd
```

These are test scripts, not results. This branch has NOT yet been verified in a Godot runtime on the connected machine. Check Godot's Debugger > Errors if something goes missing.

## Still in progress

The bridge artwork behind the road is still a painted skyline; the new bridge floor is code-drawn. Wider world exploration and hand-painted modular terrain remain separate ongoing work. Existing NPCs outside the bundled opening scene may still require the Git LFS art checkout.

## Muse director brief — new progress (2026-10-11)

The priorities below come from Tucker's `PROJECT-EXPORT-20261011.md` in Drive:

- **Critical art recovery:** all seven needed Form 1 + prologue NPC fallback files have been confirmed present. Their Git object SHAs match the exact base64 encoding of the approved Drive PNG bytes, including Mira and the wounded soldier. Note: GitHub's contents API does not return inline content for files larger than 1 MB; an empty fetch response for those files does NOT mean the committed blobs are empty.
- **Animation pacing:** 6fps directional walking, 1.25fps idle. Sprite grounding is computed from per-sheet opaque-pixel extents; no hardcoded -22px correction.
- **Opening UI:** existing title screen now displays controls, and `room_p1.gd` shows a contextual objective that changes from crossing the bridge to the combat tutorial and onward route.
- **Reserve living read:** `reserve_creature.gd` adds subtle breath, sway, bobbing, a proximity sensor and `E / INTERACT` prompt. Interaction emits `interacted` and gives a visual response. It does **not** yet grant captures, write fiction, or bypass the Lullmother decision-at-dusk rules.
- **Test coverage:** a new smoke test asserts that all seven critical graphics decode, the title screen is the entry scene, and walk/idle FPS are configured as directed.

Run:

```bash
godot --headless --path godot-project --script res://scripts/prologue_visual_smoke_test.gd
```

For Reserve checks, open `res://scenes/room_gd1.tscn` directly and approach each creature. Confirm a prompt appears before pressing interact, that the sprite notices you, and that no immediate capture occurs. Check Android multi-touch separately.

**Coordination:** All changes remain on an isolated ChatGPT branch, not `develop`. Tucker manages mainline integration; Ivy handles actual Godot/phone playtesting. The Muse team continues to own final story/dialogue and painted tileset art.
