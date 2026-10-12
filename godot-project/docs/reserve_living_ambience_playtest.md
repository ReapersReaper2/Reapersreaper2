# Reserve living ambience — first visual QA

**Branch:** `chatgpt/reserve-living-ambience-20261012`  
**PR:** https://github.com/ReapersReaper2/Reapersreaper2/pull/23  
**Target:** Godot 4.3, including the Android debug build. `develop` is not modified by this branch.

## Gameplay difference

Previously all five residents bobbed in place, making them appear like motionless decorations. They now have four deterministic, sprite-only presentation behaviors:

| Resident | Visual behavior | Expected read |
| --- | --- | --- |
| Dragonthorn | PROWL | Confident, slow, short-radius steps (no chase/attack) |
| Gloomcap | ROOTED | Subtle breathing and soft settling, no travel |
| Spinehopper | HOP | Distinct, intermittent upward hops separated by ground rests |
| Bellmaw | ROOTED | Heavy, deliberate breathing without wandering |
| Wispwillow | DRIFT | Slow hovering and lateral drifting without an obvious short loop |

Every resident gets a soft contact shadow. The shadow follows short ground-level movements but stays **on the floor** when the sprite bobs or hops. Creatures give a small recoil/lean when noticing Mollosar and a flash when interacted with.

No collision or artificial captures were added; the existing `reserve_creature.gd`, `reserve_guide.gd`, and LFS-independent approved PNG art remain authoritative. Motion stays inside a **40 px** offset from the placed sprite root; the temporary authored placements are unchanged. No lore, dialogue, or balance values are introduced.

## QA instructions for Ivy / Tucker

1. Open `godot-project/project.godot` with Godot 4.3 and run `room_gd1.tscn` directly via **F6**, or export a **debug APK** and use the **TEST RESERVE [DEV]** title action.
2. Stand where both a moving resident and nearby ground are visible. Confirm motion is noticeable at the phone's size and that shadows stay fixed beneath airborne sprites.
3. Approach each resident. The awareness prompt must track the moving image; only **one** nearest resident may claim USE/E at any time. Leave its ring to confirm the prompt vanishes.
4. Observe a creature, then verify the existing observation count increments **once only**; check the gold soul-thread ripple, the creature's subtle response, and returning prompt text **USE** on touchscreen builds.
5. Walk around five residents for several minutes. None may escape its authored clearing, obstruct a path, cause automatic capture, or start a new chase/combat action.
6. Walk to a different garden room and back. Motion is local and deterministic; creature observations remain in the existing save fields.

## Automated tests

```sh
godot --headless --path godot-project --import --quit
godot --headless --path godot-project --script res://scripts/reserve_creature_motion_test.gd
godot --headless --path godot-project --script res://scripts/reserve_loop_test.gd
```

The first command imports resources; the new motion test checks seeded determinism, trajectory continuity, movement/lift/tilt caps, species-specific motion amplitude, shadow grounding while hopping, and retained awareness/interaction. GitHub Actions executes this test alongside the existing full feature suite.

**Important:** Procedural motion is a transitional gameplay polish, not a replacement for Muse's approved animated overworld sprite sheets. Source animations should ultimately drive gestures and ground contacts. This change is limited to the Reserve and does not write capture or bonding decisions.

**Merge gate:** review Godot CI status on PR #23 and test on Android. Do not merge a failed/pending draft PR.
