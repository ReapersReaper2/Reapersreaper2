# Mollosar Form 1 animation integration — October 14, 2026

The approved Wave 1 set now supplies whole-character windup, slash, reverse
slash, heavy and recovery in all four directions. The character and sword
share one Sprite2D; approved attacks bypass the old blade extraction shaders.

Source approval: https://drive.google.com/file/d/1F7Z7QnIBCzHKqxR0jpYlaFwmtvwFNsDs/view
The manifest records each original Drive file ID and the exact PNG SHA-256.
All 20 PNGs retain their original bytes, 384px cells, RGBA transparency and
artist pivot [192,360]. Nominal source FPS is metadata; existing combat state
durations, damage windows, hitstop and movement lock still own gameplay.

Recovery now occupies ScytheRig's separate RECOVER state, so its six frames
receive the existing full recovery time. Strike art remains visible throughout
the strike state. Returning to walking resets its clock and restores normal
sprite scale. The front idle master is scaled at render time to match its
walking figure height and foot baseline. No artwork is resampled or edited.

The loader also accepts actual JSON numeric arrays: Godot parses JSON numbers
as floats, so the previous integer-array comparison rejected valid files.
Every export preset explicitly includes the dynamic JSON manifest. Feature CI
checks the production assets and runs the same test from an exported PCK.
Android CI requires the real animation test before exporting an APK.

Verification performed with official Godot 4.3:

- All 20 exact source PNGs: dimension, RGBA and all 128 frame alpha checks.
- Runtime test: 937 checks on actual Player/ScytheRig and approved textures.
- The same 937 checks passed from an exported PCK in an empty directory,
  proving the JSON and imported textures resolve without source PNG access.
- Focused sampler, legacy fallback, charge, sprite grounding, walk/idle,
  prologue pose and canon/combat tests passed.
- Full local suite: 116/116 test scripts passed with zero SCRIPT ERRORs,
  using isolated per-test user-data directories.
- Actual Godot OpenGL render inspected across all four directions and idle,
  walk, slash, heavy and recovery: baseline and idle scale are consistent;
  strikes render complete character frames without the blade mask.

Physical Android playtesting remains required. Art approval carries a
non-blocking upper smear-edge clipping flag in heavy front/left; the original
approved files are preserved. Full CI and Android artifact status should be
read at the exact integration commit rather than inferred from these checks.
The approved attack set uses darker greens than the existing walk artwork;
character palette continuity still needs an art pass. Runtime correctness does
not establish final artistic quality or physical-device playability.
