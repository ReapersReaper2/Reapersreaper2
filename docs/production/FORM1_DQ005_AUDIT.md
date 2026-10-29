# Form 1 / DQ-005 audit — 2026-10-28

Audit completed before changing runtime code or artwork. Base: PR #80,
`38839dc2bcc9c0a892740cb6deeec90322a91d24`, stacked on PR #79.
Develop remains `94a4b9ca886a51970707544713fed0418e771682`.

## Finding: the reported phone fallback is not yet a diagnosed loader failure

The [DQ-005 queue](https://drive.google.com/file/d/1l8x1l-r8NbKCJPYW3HFm9hZTFN_wPxOp/view)
records the operator's split-sword symptom, but also the prior diagnosis:
20/20 clips loaded against the shipped tree on packed Godot 4.3 debug/release
and 4.5.1 release. The manifest and compiled textures were present in the APK.
The empty-clip explanation was an inference from appearance, not a device trace.

Reproduced here before changes: official Godot 4.3 `77dcf97d8`, Windows-preset
PCK exported from #80 and launched from an empty directory on Linux:
`form1_animation_runtime_test.gd` PASS 937 checks. Raw PNGs are replaced by
imported textures; CriticalSpriteLoader already tries ResourceLoader before
bundled fallback. The JSON manifest is explicitly included by every preset.
Do not claim that introducing a duplicate .tres manifest fixes a proven bug.

Historical evidence inspected beyond workflow badges:
- [#67 Android emulator run](https://github.com/ReapersReaper2/Reapersreaper2/actions/runs/39314639166): job 118273923488 logs manifest raw_exists=true, 20 CompressedTexture2D loads, real bridge painted=true, unique_frames=6, clips=20.
- [#68 packed probe](https://github.com/ReapersReaper2/Reapersreaper2/actions/runs/39703693531): job 119578598307 loads all imported textures without raw PNGs and actor_clips=20.
- [#70 real entry](https://github.com/ReapersReaper2/Reapersreaper2/actions/runs/40050279627): job 120741202975 reaches approved=true, fallback=false, six frames; source-run Linux evidence.
- [#73 playtest](https://github.com/ReapersReaper2/Reapersreaper2/actions/runs/40093175731): job 120869870482 proves Linux packed real-entry clips=20 and approved=true, then exports an APK. This is not an Android device execution. Its log includes the bridge polygon errors fixed in #80. Green historical badges are not strict error-free evidence.

## Candidate reconciliation

| Candidate | Audited head | Disposition |
| --- | --- | --- |
| #67 chatgpt/dq005-form1-packed-diagnostics | 9094f2d | Per-gate logging, Android probe; evidence contradicts a universal packed rejection. Retain unmerged. |
| #68 fix/form1-packed-attack-loader-20261021 | 6f35a2c | Diagnostic-only loader/probe; isolated packed test passes. Android smoke workflow fails. Retain unmerged. |
| #70 chatgpt/dq005-selfcontained-trace | faefcc1 | Persistent trace, duplicate JSON-in-.tres manifest, Android export/share trials. Do not wholesale import unrelated plugin/workflows or assume .tres is root-cause repair. |
| #71 chatgpt/dq005-share-plugin-trial | 520c561 | Closed duplicate of share trial ported to #70; no merge, no animation fix. |
| #72 chatgpt/form1-animation-continuity | ba9c21d | Small phase-facing and frame-zero stop fixes plus six regressions. Reproduce then port narrowly with attribution. |
| #73 chatgpt/form1-playtest | 46cb91b | Combines #70/#72 and actual-displacement gait-rate change. Packed Linux evidence + APK export, not phone proof. No need to replace entire player movement logic for the confirmed defects. |
| fix/dq005-form1-packed-runtime | d5e1aa9 | Per-gate log, standalone packed and Android startup probes; diagnosis only. |
| fix/dq005-packed-form1-runtime | 3b1b0b0 | Alternate logging/pack/Android probe; diagnosis only. |
| test/dq005-packed-bridge-scene | b1ba44f | Extends preceding branch with real bridge display/source trace; no corrective loader behavior. |
| chatgpt/form1-attack-art-qa-handoff-20261013 | 6b390d9 | Non-production registration/intake manifest and asset QA; no approved replacement art. |
| chatgpt/form1-approved-attack-20261014 | 40a8c7f | Historical branch behind develop; do not restore superseded artwork. |
| #56 approved-form1-attack-pipeline | ed217a9 | Already merged gate/sampler foundation. |
| #64 form1-attack-integration | edc0373 | Already merged; older integration prose describes [192,360] and older artwork, superseded by #66. |
| #66 feature/form1-approved-attacks-20261018 | 8bab4c5 | Already merged current 20 strips / 128 frames, pivot [192,376]. Preserve all bytes. |
| #28/#31/#32/#46 | e0fb830 / 1477279 / 707c084 / 8beb704 | Merged procedural/body-pose/painted-blade/charge history; fallback remains intentional for unavailable art. |

All repository branches were enumerated; matching Form 1 and DQ005 branches
and their changed-file sets were inspected. PR #69 is a separate shore-art
fallback and DQ-003 is a separate combat redesign; neither belongs in this fix.
Existing candidates remain untouched and unmerged.

## Why the appearance changes

1. The active four six-frame canon_walk strips (introduced by f1226dc) and
   the twenty October-18 attack strips are separate authored image sets.
   Visual inspection shows differing face/body proportions, armor rendering,
   palette, sword placement and framing even within the cross-tabard lineage.
   Recovery contains visible detached/clipped material at cell edges. The
   source art QA explicitly records accepted upper-edge flecks/clipping.
2. The legacy four-frame green-cloak walking set and two-frame idle are retained
   as fallback. If the entire canon set cannot load, runtime intentionally
   selects that older lineage. No file name alone confers new art approval.
3. _try_approved_attack re-latches facing whenever action index changes, so
   charge/strike/recovery can select different directional sheets mid-sequence.
   This is a runtime continuity defect, separate from artwork differences.
4. A stop during walk frame zero leaves _walk_t nonzero, shortening the first
   frame after restarting. This is a reproducible animation-clock defect.
5. The existing runtime test reports PASS when both manifest and clips are
   absent. That is unsuitable as a packed delivery gate: it can validate the
   very fallback the delivery needs to rule out.

No PNG, alpha, pivot, palette, source manifest or import settings will be
changed by this candidate. Canon/identity unification needs an explicit art
selection and reviewed matching frames, not automatic replacement or shader
recoloring. Phone-specific DQ-005 closure still requires a trace from the
symptomatic exact build/device; desktop PCK evidence must be labeled as such.
