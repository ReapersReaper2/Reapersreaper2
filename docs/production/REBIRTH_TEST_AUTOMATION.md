# Project Rebirth test automation

Candidate only. No merge or art acceptance is implied.

## Audit (2026-10-27)

The prior Windows run [40516564711](https://github.com/ReapersReaper2/Reapersreaper2/actions/runs/40516564711) stopped during the version check despite printing `4.3.stable.official.77dcf97d8`. It invoked the GUI executable and relied on PowerShell's `$LASTEXITCODE`. No suites or artifacts ran. The workflow also checked only three suites, did not fail on engine errors, and lacked individual process timeouts. The local PowerShell runner discovered the suite roster but did not import resources or enforce the engine version.

## Repeatable baseline

`project-rebirth-windows.yml` uses a disposable GitHub Windows 2022 runner with LFS, Python 3.12 and the official Godot 4.3 console executable. It runs on `candidate/rebirth-**` pushes and can be dispatched manually once GitHub exposes it. The same standard-library Python runner is used locally:

```powershell
python tools/testing/run_godot_tests.py --godot 'C:\Tools\Godot_v4.3-stable_win64_console.exe' --output 'C:\ReapersReaper\TestResults\baseline-001'
python tools/testing/run_godot_tests.py --godot 'C:\Tools\Godot_v4.3-stable_win64_console.exe' --output 'C:\ReapersReaper\TestResults\capture-001' --capture
```

Output directories must be new. The existing `Run-BaselineTests.ps1` is a wrapper with optional `-Capture` and `-TimeoutSeconds` switches. Requires Python 3.10 or newer. Run from a complete Git LFS checkout. There is no engine upgrade or asset recovery/substitution step.

Version, import and tests use explicit process handles, redirected stdout/stderr, and bounded waits. Import has a 600-second limit; each test defaults to 120 seconds. All `scripts/*_test.gd` scripts are discovered in stable order (117 at the audited baseline). Script/engine errors fail even on exit zero. Tests continue after individual failures and preserve intermediate results. Startup/import failure prevents running against an invalid project. Application-data environment variables point at a fresh evidence-specific directory so test saves do not use the operator's normal saves.

Reports include exact commit, worktree status, Godot version, commands, per-test durations, timeouts, raw logs, CSV results, test roster and SHA-256 evidence hashes. Artifacts are named by commit and attempt, retained 14 days, and uploaded even on failure. Download durable evidence before GitHub expiry.

## Actual graphical capture

A separate minimal project probes the graphical renderer without game code. Unsupported graphics is explicitly reported as `UNSUPPORTED_GRAPHICS`, never as a successful gameplay capture. Once the probe succeeds, game startup/capture failures are failures, not skipped hardware checks.

The opt-in `rebirth_gameplay_capture.gd` starts the actual title scene, sends New Game input, checks entry into `room_p1`, sends movement and sword input, and checks displacement and active attack state. It captures 27 actual viewport PNGs: title, bridge idle, bridge walk, and 24 attack samples. It waits for `RenderingServer.frame_post_draw` before reading each image. The JSON input trace records frame indices, attack states, positions, scene, fixed seed, display driver and adapter. Normal gameplay never loads this harness. No portrait compositing, replacement art or production gameplay changes are included.

This is source-checkout evidence of a bounded opening scenario. It is not packed Android proof, a full playthrough, timing/performance measurement, hardware input validation, or artistic acceptance. Fixed inputs/seed help repeatability but particles and platform rendering can vary. The attack samples must be visually reviewed; a complete capture does not prove the approved art loader was selected. Existing DQ-005 candidates remain separate.

## Runner verification

`python -m unittest discover -s tools/testing -p 'test_*.py' -v` checks clean exits, nonzero failures, stdout and stderr errors with exit zero, explicit failure markers, and timeouts. CI executes these checks before the game suite.

## Executed Windows evidence

[Run 40519063374](https://github.com/ReapersReaper2/Reapersreaper2/actions/runs/40519063374), commit `3368043b26e2a6d5a3bd94eb3f816db3f802d4bb`:

- Official Godot 4.3 version and resource import passed.
- All 117 scripts completed: **72 clean, 45 failed the strict diagnostic gate**. Every script returned exit code zero; no script timed out. These are script counts, not assertion counts.
- The 45 include both real diagnostics (invalid polygons, duplicate connections, scene-tree lifecycle errors, leaks) and deliberate negative-path tests (corrupt saves, unsupported form 99, invalid step-driver inputs). They must not be described as 45 distinct gameplay bugs. No blanket error suppression or unreviewed allowlist was added.
- Windows graphics probe passed using ANGLE / Microsoft Basic Render Driver / Direct3D11.
- Actual title → New Game → bridge capture completed: **27 PNGs**, zero movement/attack/capture assertions failed. The job correctly remains red for **12 engine errors**, including 11 invalid-polygon errors and a title-input callback calling `set_input_as_handled` after the title leaves the tree. The missing external story-package file is a separate `dialogue_test` diagnostic. This is diagnostic capture success, not a clean game result.
- Windows bridge/walking screenshot inspected; local software-rendered bridge and attack screenshots also inspected. No art approval or phone rendering claim.
- Downloaded Windows artifact verified: all **358 baseline** and **43 capture** recorded hashes matched. The follow-up runner also hashes `results.csv` (the first version generated CSV after sealing) and explicitly records `captured_frames` and `capture_completed` independently of diagnostic status.
- Artifact: `rebirth-windows-3368043b26e2a6d5a3bd94eb3f816db3f802d4bb-1`, available from the run page until 2026-11-10. Artifacts contain stdout/stderr and the full test roster, not only this summary.

Next bounded work: classify intentional error cases with per-test exact expectations; repair the title-input scene-transition callback, bridge polygon generation and story-package path; then address scene-tree lifecycle/resource cleanup diagnostics. Keep those gameplay/test-fixture repairs separate from this infrastructure PR. Existing packed-art/DQ-005 work remains unmerged.
