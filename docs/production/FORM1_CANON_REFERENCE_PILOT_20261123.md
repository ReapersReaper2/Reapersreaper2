# Mollosar Form 1 — canon reference and slash_side-r pilot assessment

Date: 2026-11-23. Follow-up to draft PR #83 and Issue #82. **No changes authorized to production sprites.**

## Canon appearance
The operator supplied a new primary visual reference in chat (uploaded file `canon-form1(2).png`, not registered as a repository asset). Treat this as a visual anchor for **future candidate artwork only** unless and until the owner explicitly approves a new asset replacing the existing source of record.

Visible details: long windblown deep green hair, blue eyes, youthful clean-shaven face; silver armor with gold trim and black chainmail; white tabard bearing a black cross; brown belts and gold hanging cross; tattered white-and-black cloak; steel longsword with gold cruciform guard.

## What was attempted
Two independent six-pose candidate illustrations were generated and adapted locally into separate `2304×384`, six `384×384`-cell, binary-alpha nonproduction PNGs. The second candidate has 315,335 opaque pixels, 569,401 transparent pixels, zero semitransparent pixels, with cell painted coverage [22.4%, 38.3%, 38.6%, 40.1%, 38.1%, 36.4%]. Source files remain local conversation artifacts, not repository production assets.

**Both are REJECTED for integration.** Original renders came with white backgrounds; cleanup and recropping met some mechanical requirements but introduced/preserved incomplete sword and cloak shapes. In candidate v2, the sword continues beyond the right edge of zero-based frame 2 and appears as an isolated sliver in frame 3; partial cloth fragments appear near cell edges in several frames. Six equal cells cannot be assumed simply by dividing a composited group image into sixths. Visual consistency and clean isolation are gating failures even when dimensions and alpha pass.

## Next candidate acceptance gate
1. Generate each full pose independently against the operator's canon reference, with enough empty margin to contain the entire sword and cloak. Never slice overlapping composited figures.
2. Keep the actor's relative size and feet at pivot (192,376); exact attack-frame shape 384×384, six cells, 12fps, alpha 0/255.
3. Compare the actual six source PNGs side by side for sword continuity, facial likeness, tabard/cross, armor detail and pose differences. No detached body parts or segments.
4. Run `python tools/art/validate_form1_candidate.py <candidate.png> --action slash` and visual QA. A technical pass is **not** art approval.
5. Deliver original-vs-candidate contact sheet; owner must approve before changing any APPROVED manifest or artwork.

No production sprite, Godot runtime, branch `develop`, or APK was modified by this assessment.
