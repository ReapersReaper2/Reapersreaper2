# Reserve gameplay → Muse / Tucker integration handoff (2026-10-12)

**Feature branch:** `chatgpt/reserve-clock-interactions-20261012`  
**Master branch:** `develop` (do not merge without Godot 4.3/Android QA)  
**Source authority:** Tucker's `PROJECT-EXPORT-20261011.md`, Grimley's `CAPTURE-PLANT-Grimley.md` and `LULLMOTHER-INTEGRATION.md` in the project's Drive. This note does **not** create canon.

## Implemented by ChatGPT — ready for review, not approved

- Four garden-related scenes have a clock (gd1, gd2, gd3, and refuge interior). The scene emits `dusk_started(day)`, now correctly handling fast-forward over multiple days; no bonding outcome is wired to that signal.
- Five named residents use canonical `reserve_creature.gd` with separate awareness sensors; nearest resident gets one interact prompt; observation raises an understated golden soul-thread ripple. Observations persist separately from owned/bonded creatures. Existing `creatures.json` drives non-spoiler species name, region and temperament labels.
- LFS-independent sprite loader handles both `<stem>.b64` and `<stem>.png.b64`. Critical backup images are committed under `assets/critical_sprites/`; no text-only LFS pointers should appear as characters in an APK if the export includes them.
- Random grass encounter steps reset while a visible resident is in observation range, avoiding interrupted voluntary interaction. No instant bonding/roster entry.
- Debug-only `TEST RESERVE [DEV]` title action enters gd1 directly without writing a save slot, speeding phone QA. The regular story still begins in the prologue.

## One concrete request for Muse art production

Please supply **five distinct production-ready overworld PNGs** for:
`dragonthorn`, `gloomcap`, `spinehopper`, `bellmaw`, `wispwillow`.

Preferred integration paths:
`godot-project/assets/creatures/<species>_overworld.png`, one **transparent RGBA** 384×384 single-subject composition each, grounded at a consistent bottom-center foot/hover baseline. Use the existing approved illustrations and character sheets in Drive as strict silhouette, face and palette references, with the same 3/4 top-down camera. No paper textures, rectangular borders, labels, scenery, watermarks, or painted backgrounds. Animals should still be readable at roughly 100–160 screen pixels tall. Supply original master/source separately if possible.

**Why:** Three current battle illustrations carry opaque white-paint matte; runtime shader removal is a short-term visual workaround and can cut away white highlights. Using battle compositions as walking sprites makes the Reserve look like a collage.

## Technical decisions blocked by the Muse director

Before ChatGPT wires the Lullmother into the player inventory and dusk signal, Tucker/Jenn need to settle these **design questions** already raised by Grimley; do not improvise final mechanics:

1. **Plant naming/state ownership:** confirm Lullmother vs old Bloom terminology, cutting provenance ownership, nursery bed slots, and separate mantle state (never a breeding part).
2. **Creature agency:** confirm how a wild creature's pre-attunement approach and voluntary stay are represented, and whether a separate un-influenced signal is required. Rejection must never punish or harm the creature.
3. **Soul-thread economics:** confirm whether planting tithe and sigil are the same cost, and where thread balance lives.
4. **Re-offer rule:** differentiate a neutral first visit from hard refusal, define cooldown and per-individual visit tracking so a rejection cannot be overridden through repeated attempts.
5. **Offering resource contract:** define ripe, family-matched fruit validation, exact spend point, and source from either feeding/concoction or corpse-fruit economy. These fruit classes are separate and must not be conflated.
6. **Nursery implementation:** assign nursery beds/growth/harvest, compost recovery, seed-heart/territory trace, and whether plant-out frees a nursery bed.
7. **Dusk pacing:** approve actual game-day duration and dawn/day/dusk/night boundaries. The current 720 real seconds/day and 17:00 dusk are *placeholders*, not canon.

Do not implement coercive catch rates, instant capture, direct damage to creature on rejection, game-facing use of the word 'consent', or romance meters.

## Verification needed from Tucker / Ivy

- Godot 4.3 import and `godot --headless --path godot-project --script res://scripts/reserve_loop_test.gd`.
- Android debug export must include `assets/critical_sprites/*.b64` in **Resources → non-resource include filters**; there is no tracked Android export preset to enforce this yet.
- Tap the title-screen dev shortcut on a phone, inspect 5 creatures and prompts, trigger interaction twice (counter must remain one), walk away, go inside the refuge and back, run clock across dusk.
- Validate player/creature/canopy depth ordering and actual pixel sizes on Android. Send screenshot and first error line with scene path.

**Status:** Code is committed for QA. Neither the Android APK nor a Godot 4.3 headless run has been executed in this workspace.
