# Form 1 slash_side-r — six-frame visual QA (2026-11-23)

Scope: **inspection only** under Issue #82. Original approved PNG and manifest unchanged. Source sha256: `c3c64a360b1869ac80b73048c806895effc277bfba5f76196189efed00a996b7`. 384×384 cells, six frames, zero-based indices.

## Verified evidence

- [GitHub Actions success: run 45240940545](https://github.com/ReapersReaper2/Reapersreaper2/actions/runs/45240940545) on candidate branch, commit `597ffb624bbe62f78be1f455fa86e5dc07327b8c`.
- All **4 unit tests passed**. The review generator completed for **all 6 original frames**.
- Run artifact `form1-slash-side-r-review` (artifact ID **14849854634**) contains six individually cropped, unmodified frames, checkerboard contact sheet, CSV, and a readme. Download via the linked Actions run.
- **2/6** frames have painted alpha at cell boundary (0 and 4); every frame has binary alpha. This automated test checks *only* exact boundary contact. It cannot reliably diagnose anatomical mistakes or all disconnected pixels.

## Human-observed frame defects/candidates

| Frame (zero-based) | Observation from generated contact sheet | Confidence |
|---|---|---|
| 0 | Raised sword extends beyond top cell boundary; blade cropped; detached-looking material at far right of cloak | High for crop |
| 1 | Sword and garment extend into right boundary; visually clipped although alpha does not reach the extreme pixel | High for visual discontinuity |
| 2 | Horizontal sword-like segment runs from left edge behind actor; detached fragment near right cloak | High for unnatural fragment |
| 3 | An extra horizontal blade-like segment protrudes left through the actor while raised sword is also visible; reported detached sword at Issue #82 confirmed visually | High |
| 4 | Isolated diagonal sword segment above/left of raised sword; missing blade continuity at cell top; stray fragment along lower-left edge | High |
| 5 | Detached miniature hilt/blade fragment near upper-left of actor; stray bottom-left pixels | High |

Important: overlapping opaque components can still be artistic effects, and 4-connected component counts cannot determine whether a sword is anatomically plausible. All six frames require an art review before canon replacement.

## Proposed safe repair sequence

1. Preserve the original `form1_slash_side-r.png`, its hash, existing 20-strip manifest, and loading behavior.
2. Derive a separate, nonproduction **candidate** six-frame strip with fixed sword continuity and consistent costume using the accepted character reference; do not crop/reassemble approved production frames destructively.
3. Validate exact `2304×384`, six `384×384` cells, binary alpha, foot pivot `(192, 376)`, 12 fps metadata; test the sword is visible and coherent in every frame and no neighboring-cell contamination occurs.
4. Present original and candidate contact sheets side by side for explicit art approval before changing production sprites.
5. Only after approval, integrate on a separate candidate branch and repeat Godot packed-resource/phone testing; do not merge without authorization.

No visual correction is included in PR #83.
