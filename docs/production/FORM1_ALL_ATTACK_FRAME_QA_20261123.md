# All approved Form 1 attack clips — non-destructive batch QA (2026-11-23)

GitHub Actions [run 45248456488](https://github.com/ReapersReaper2/Reapersreaper2/actions/runs/45248456488) on commit `262b772e01629abf633489d067a19f752491e18f` completed the extended tool run. **9/9 tests passed**; read-only inspection of **20 clips / 128 frames** completed and artifact `form1-approved-art-review-all` (ID `14854278989`, 28.2 MB) uploaded. **All 128 frame alpha channels are binary** (0 or 255). The **18 edge-touch signals below are candidates, not 18 confirmed art defects**. All indices are zero-based.

## Exact edge-touch candidates

| Clip | Frame indices |
| --- | --- |
| heavy_back | 0 |
| heavy_front | 2, 3 |
| heavy_side-l | 1, 3 |
| heavy_side-r | 0 |
| recover_back | 0 |
| recover_front | 0, 1 |
| recover_side-l | 0 |
| recover_side-r | 0 |
| rslash_back | 5 |
| rslash_side-l | 0 |
| rslash_side-r | 0 |
| slash_back | 0 |
| slash_side-l | 1 |
| slash_side-r | 0, 4 |

Other clips have no *exact-cell-edge touch* signals, which does not mean they pass visual QA. Multiple 4-connected islands frequently correspond to legitimate separate costume/weapon details; they are a triage hint and must not be deleted automatically.

## Source-contact-sheet visual review

The slash_side-r contact sheet visibly shows: frame 0 blade extends beyond the top edge; frame 1 right-hand sword/cloth shape reaches toward the neighboring cell; frame 2 horizontal sword-shaped material with separate small fleck to lower right; frame 3 a separate horizontal segment to left of actor while sword points upward; frame 4 a blade-shaped isolated object at top-left and boundary-clipped raised sword; frame 5 an isolated small gold fragment high to left. Frame 4 also has visible partial leg/boot-like artifacts at the far left boundary. **These are visual repair targets**, not a license to retouch the approved strip.

The heavy_front contact sheet shows its overhead sword visibly reaching the upper cell edge in frames 2 and 3; animation still needs human review for other continuity defects. This note does **not** claim visual sign-off for the remaining clips.

## Safely proposed corrections (pilot first)

1. Reframe or redraw sword geometry **only in a distinct nonproduction candidate**, containing complete blade and guard within each 384px cell without shrinking the approved actor or changing foot anchor `(192,376)`.
2. Assess high left/right small-island and fragment regions using original pixels and the operator-supplied canon reference. Distinguish intentional tattered cloak from stray sword/limb components.
3. Review the 6-frame candidate against original `slash_side-r` side-by-side at 100% pixel resolution and 12fps playback; validate 2304×384, RGBA binary alpha, six 384px frames, and sword/costume continuity.
4. Seek Gage's explicit sign-off before touching an APPROVED file, changing manifest authority, or merging. All current generated replacement pilots remain rejected for contamination/clipping.

No approved PNG or manifest was modified by this inspection. No game runtime or Android validation implied.
