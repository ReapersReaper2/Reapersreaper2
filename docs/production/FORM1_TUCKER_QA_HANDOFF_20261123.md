# Issue #82 — Tucker QA handoff and correction instructions (2026-11-23)

**Status:** candidate-only inspection. Do not edit any approved production sprite, PNG, manifest, or runtime file. No merge to `develop` without Gage's approval.

## Path fix verified

The read-only inspection tool currently uses `manifest.parents[3]` (the `godot-project` root). This was fixed earlier on this branch and confirmed in the successful November 23 GitHub Actions run [45242566381](https://github.com/ReapersReaper2/Reapersreaper2/actions/runs/45242566381). Its nine tests passed; the `slash_side-r` inspection completed successfully with six binary-alpha frames and two edge-touch candidates (zero-based frames 0 and 4). **Do not reapply `parents[2]`.**

## Art QA observations requiring correction proposals

Tucker's independently reproduced inspection flags:
- Frames **0 and 4**: raised sword reaches or exits the top of the 384px cell. The correction must redraw/reframe the sword within its own frame, **without** globally shrinking Mollosar, changing the pivot, or displacing his feet.
- Frames **1, 4, 5**: small detached flecks; compare actual PNG pixels against the approved sword, cloak and motion reference before deciding whether each fleck is unintended. Do not remove legitimate cloak tatters or sword effects without visual evidence.
- Frame **3**: prior issue report identified an apparently detached horizontal blade; visually compare against the full approved strip before assigning a final correction.
- Tucker reports the outfit is visually consistent across the six original `slash_side-r` frames; **do not** recolor armor or change costumes on speculation.

## Next safe work

1. CI now runs the same **read-only** tool on every one of the **20 attack clips** (128 total frames) and preserves six-frame `slash_side-r` evidence in the same artifact.
2. Review all contact sheets and diagnostics (edge touch / disconnected islands are candidates, not confirmed defects). Give exact frame indices in report.
3. For slash_side-r, produce a **separate review-only candidate** using Gage's latest reference image; never overwrite the old strip. Check full sword containment, clothing continuity, binary alpha, `2304×384` strip, `384×384` cells and foot pivot near `(192,376)`.
4. Get Gage's explicit approval for any production art replacement. No downstream merges or phone-build claims from static visual QA alone.

Note: Previous separately generated visual pilot images have not passed visual QA and were not committed as replacements.
