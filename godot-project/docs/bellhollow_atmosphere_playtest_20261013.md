# Bellhollow Bridge — battlefield atmosphere playtest (2026-10-13)

**Branch:** `chatgpt/bellhollow-smoke-footsteps-20261013`  
**Baseline:** Godot 4.3 `develop` at `308dd162` (includes PR #32 painted Form 1 sword and previous irregular flagstone bridge).  
**Purpose:** connect the painted burning-city panorama with the stone surface and make grounded movement feel less like two cutouts sliding over a static image.

## Implemented

- `scripts/prologue_bridge_atmosphere.gd` adds 12 gentle drifting smoke groups along the distant parapet and 36 tiny ash/cinder motes. Motion is deterministic; it doesn't regenerate randomized positions each frame.
- When Mollosar travels about 76 game pixels on foot, two very faint ash wisps appear beside his feet and fade in under 0.72 seconds. Stopping leaves no footprints, and teleports/cutscenes never spray a row of particles.
- The effect is rendered **after** the approved irregular stone renderer but at z=-1, **behind the real NPC and protagonist artwork** (z=0). It uses no sprite textures, new LFS dependencies, collision shapes, input handlers or save fields.
- Drawing is capped at **15 fps** and counts are bounded for Android. Performance can be tuned in the scene export values (`smoke_count`, `ash_count`, `step_distance`).
- Only `room_p1.tscn` is altered. Existing bridge rails, story triggers, actual player and Mira, soldier, invader waves and camera are left unchanged.

## Verification

```sh
godot --headless --path godot-project --import --quit
godot --headless --path godot-project --script res://scripts/prologue_bridge_atmosphere_test.gd
godot --headless --path godot-project --script res://scripts/prologue_pose_bridge_test.gd
godot --headless --path godot-project --script res://scripts/prologue_canon_combat_test.gd
```

The new regression test checks smoke and ash determinism, safe motion ranges, fade curves, scene render order, unmodified mortality and battle triggers, walking footstep emission, teleport safety and cleanup. It is included in GitHub's feature CI.

## Android visual QA (Ivy / player)

1. Install the Android debug APK made **after merging this branch**; older screenshot builds may still show the original geometric bridge.
2. Begin the normal prologue bridge. Confirm the panorama remains visible, real characters are unobscured, mobile joystick and buttons stay on top, and the irregular stone renderer is visible beneath them.
3. Observe slow drifting haze near the distant edge and sporadic embers on the bridge; no exaggerated glowing fantasy magic or thick opaque gray fog.
4. Walk around Mira. Look at Mollosar's feet: a small ash disturbance should accompany movement and disappear quickly when still. Verify the new ashes follow his **position**, not a teleport or camera cut.
5. Confirm the touch UI is still responsive, the sword strikes work, and the bridge tutorial/exit proceeds without new obstacles.
6. Note whether the smoke feels too conspicuous or too subtle in actual gameplay. It can be made weaker by decreasing the `SMOKE` alpha, or disabled per-scene by setting counts to zero.

**Status discipline:** automated tests passing doesn't prove the mobile atmosphere is artistically approved. This is a code-based interim layer until Muse delivers final painted bridge props and environment-specific effects. No game-facing story/canon has been added.
