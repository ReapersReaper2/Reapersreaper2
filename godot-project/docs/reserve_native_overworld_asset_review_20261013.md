# Reserve native creature artwork — player-visible integration (2026-10-13)

**Source:** Muse production Drive. Replaces five battle-art cutouts in the playable garden with five **actual 384×384 true-transparent native overworld sprites**. No asset was generated anew; no old art has been overwritten.

## Provenance and review labels

| Creature | Delivered Drive file | ID | Size | Status |
| --- | --- | --- | --- | --- |
| Dragonthorn | CANDIDATE-dragonthorn_overworld.png | 1a7blCE5j1o_Qz4j4ePKc_yzdUledcyna | 146856 | **Candidate:** Marrow delivery QA-verified, pending director visual acceptance |
| Gloomcap | CANDIDATE-gloomcap_overworld.png | 1xm8aXZoNl6ZTmmnsxTwmuJX9yy2pQ3d6 | 72111 | **Candidate:** QA-verified, pending director visual acceptance |
| Spinehopper | CANDIDATE-spinehopper_overworld.png | 1QgK0ufh4oJx4ywpqUyQFF0nElo6jUclz | 44931 | **Candidate:** QA-verified, pending director visual acceptance |
| Bellmaw | bellmaw_overworld.png | 1DuxOL4A17sjs3jZH38bLpGSSQA8cr5wX | 137645 | Delivered without CANDIDATE prefix |
| Wispwillow | wispwillow_overworld.png | 1lKZN4DNZMccRoyDknSH0OHr7GRSIk22B | 182909 | Delivered without CANDIDATE prefix |

All images were visually inspected, delivered 384×384 RGBA with true alpha, corner transparency, one whole subject and consistent visual baseline y≈352. Marrow's `DELIVERY-20261012-reserve-overworld-006.md` documents its input species-sheet and battle-art references. No model, colors or markings were changed by engineering. Committed PNGs match the original uploaded **byte sizes**.

## How it works

- Native files are installed at `res://assets/creatures/<species>_overworld.png`, exactly matching the current `reserve_creature.gd` optional native artwork convention. The game will automatically use these at the existing per-species screen heights already declared in `room_gd1.tscn`.
- The native PNGs have built-in transparency, so the previous white-paper matting shader is disabled when a native texture loads.
- If the PNG is absent/corrupt or team art rejects it, the existing `res://assets/creatures/<species>.png` original painting stays available. `prefer_overworld_art = false` on any creature in the scene reverts just that creature without affecting saves.
- Neither the Reserve clock, observation counter, voluntary bonding system, encounter table, creature animations, collisions, or interaction mechanics are modified.
- Android, Web and Desktop export presets already include `assets/creatures/*_overworld.png` as non-resource files; the fallback loader opens the native PNG via `FileAccess` to bypass LFS/import cache issues.

## QA

1. Install the new debug APK built after this branch is merged, then press **TEST RESERVE [DEV]**.
2. Look at all five residents (use the compass). You should see complete painterly silhouettes with **no rectangular backgrounds** behind them. Compare Dragonthorn/Gloomcap/Spinehopper carefully because their art is explicitly still a CANDIDATE.
3. All five should appear at sensible relative heights (~146–179 game pixels), grounded on their existing shadow positions, with the original hop/prowl/drift animations.
4. Approach a creature, observe it via USE, and confirm the prompt follows the moving sprite. The journal counter should increment only once per species. Walk away and test random grass encounters.
5. Test hover-light and dusk lighting. Wispwillow's own light is painted in the sprite; the environment's clock remains the source of day/night transitions.
6. To compare any **candidate** with original battle art, temporarily set that resident's `prefer_overworld_art=false` in `room_gd1.tscn` and run F6 again.
7. Check both Android input transparency and device performance (these images total under 600 KB in PNG source).

```sh
godot --headless --path godot-project --import --quit
godot --headless --path godot-project --script res://scripts/reserve_native_overworld_test.gd
godot --headless --path godot-project --script res://scripts/reserve_loop_test.gd
```

**Approval gate:** automated CI confirms that the candidate art renders correctly and follows engine scale contracts, not that Tucker/Muse have signed off aesthetics. The three candidates must remain labeled in this handoff until explicitly accepted; their technical usability does not silently change their editorial status.
