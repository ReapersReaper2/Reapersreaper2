# Prologue repair — footage-driven integration notes (2026-10-13)

**Source:** 3:09 Android playtest recording provided by the player. **Canon:** Mollosar meets Luna for the first time **after** his mortal death. The approved Bellhollow collapse and Black Sand dialogue are unchanged.

## Fixed in this branch

1. **Chronology:** `room_p1.tscn` contains no Luna. `room.gd` adds a safety rule hiding Luna in mortal P1/P2 even if an instance is mistakenly added in the future. The Black Sand Shore P3 instance and approved intro are preserved. The existing P2 cutscene sets `prologue_complete` before loading P3.
2. **Premature underworld systems:** the Soul Vault / REST / TRAVEL shrine was removed from the *mortal* bridge. P3 and later shrine systems remain intact. This also removes the floating gray shrine prop covering the painted bridge.
3. **Movement/dialogue:** player input and motion are blocked while a visible dialogue or shrine menu is active. The player's velocity is set to zero immediately; footsteps/odometer cannot accrue. NPCs check that no other dialogue or shrine menu owns USE, including across deferred interactions. `dialogue_box.gd` refuses to overwrite an active conversation.
4. **Mortal sword:** disabled the giant magenta/purple debug wedge in `scythe.gd`. Replaced the huge triangular sword drawing with a short weathered-steel blade at an achievable hand/shoulder offset, animated with anticipation → fast 0.19–0.67 sweep → follow-through and a narrow fading steel glint. Two-hit combos reverse strike direction. Combat timings, damage, invader waves, and collision logic are unchanged.
5. **Correct tutorials:** phone objectives use JOYSTICK / TAP SWORD; desktop uses WASD / SPACE = SWORD. The mortal tutorial displays the appropriate action hint without changing Muse's lines, and the title primer no longer suggests a scythe before death. Dialogue's advance hint now accommodates mobile USE/SWORD.
6. **Regression tests:** `prologue_canon_combat_test.gd` asserts mortal chronology, P2 flags preceding arrival, proper sprite/UI scene nodes, sword pose/trail curves, and actual input suppression by dialogue and shrine panels. The full `playthrough_test.gd` no longer expects Luna on the bridge or fast travel into a shrine that does not exist there; it uses the existing post-death P3 shrine instead.

## Android QA on the new APK (not an older build)

- Start a **NEW GAME** for the chronology test; Continue may reload flags/room state from the old APK.
- Bellhollow: Mollosar appears with no purple Luna companion. Mira and the soldier remain. The gray Lantern Shrine, REST/TRAVEL, and Soul Vault are absent during mortal life.
- Walk up to Mira and press USE: Mollosar must stop while the text is visible, dialogue text must not be stolen by the soldier or a story trigger, and walking resumes only after the conversation is dismissed.
- Reach the tutorial trigger and press the right-side SWORD button. The attack should be a **short steel sweep**, with a brief subtle glint, **no purple sector**, not a giant static scythe. Try a second press in the combo window to see the reverse sweep. Confirm hit/hitstop works and the invader waves still end.
- Continue **east** after all waves. Watch the actual tower-collapse cutscene and verify death/completion happens before entering Black Sand Shore.
- The Black Sand Shore is the **first** place Luna should appear. Her introduction should play once; afterward Form 2 unlocks. This story/cutscene transition is a critical phone acceptance criterion.
- Visit a shrine *after death* and open REST/TRAVEL/SOUL VAULT. The player must not move under the open menu. Closing it restores movement.

## Art still required from Muse

**A proper Form 1 sword attack animation** needs approved transparent hand-painted frames, matching the existing Mollosar character sheet and four-direction sprite scale. The new procedural blade/animation is a tactical visual improvement, not final hand-drawn attack art. Request 6–8 distinct frames per direction (anticipation, fast strike, impact, follow-through, recover), consistent feet/pivot and palette. Then the code should prefer approved action frames and retire the overlay. Do not generate new character identity or rewrite any dialogue.

Likewise the Bellhollow bridge's rigid polygon deck/railings and invasion dummy sprites still need integrated painted overworld assets. Do not mistake a passing headless Godot test for visual approval.

**Verification:** Run Godot 4.3 feature suite, core CI, and build a new Android APK from the merged commit. Do not merge failed checks.
