# Project Rebirth — Recovery Register and First Sprint

This is an **initial triage register**, not a verified complete inventory. Every entry must be reconciled against actual source files and CI runs. No source documents or assets were moved.

## Known anchors
- Source repo: https://github.com/ReapersReaper2/Reapersreaper2 ; default `develop`; Godot project at `godot-project/`; CI at `.github/workflows/ci.yml`.
- Archived Drive source folder: https://drive.google.com/drive/folders/1_UtxKuVQzxJddcCd2yErUG0vsNK1Rb8V
- Existing replacement Drive reference library: https://drive.google.com/drive/folders/1VJoBQEhoMBC0i4TOraMUFCid9XaGaKGP
- Form 1 canon folder: https://drive.google.com/drive/folders/1Bop3tbQDJN9EYTzxpb9GA0txwINLLWQ7
- Team file folder: https://drive.google.com/drive/folders/1zNywgwb7zDDzU-hW-qWRLh7POiaiXo7O
- Existing recovery/source documents discovered: `CANON-EXTRACTION.md`, `RXR-LOCAL-ARCHIVE-MANIFEST.md`, full Game 1 storyboard, `01 - Story Bible (ChatGPT survey Oct 2026).md`. **Not yet reconciled for contradictions.**

## Open PRs requiring disposition
- #73 Form 1 packed/resource-loading/continuity playtest candidate; evidence pending at discovery.
- #72 attack facing and walk-clock fixes; source-run tests reported, not packed device proof.
- #70 diagnostic on-device trace; explicitly DO NOT MERGE.
- #69 P3 shore fallback; candidate.
- #68/#67 packed Form 1 diagnosis; older competing candidates.
- #65 combat stage-1 documentation; reconcile against REV 3 and later DQ-003 candidate work.
- #54 combined QA preview; never treat as independently approved integration.
Other open PRs, issues, and branches require full enumeration before closing or merging anything.

## Sprint 0 — auditable deliverables
1. **Baseline report:** checkout develop with LFS and pinned Git SHA, import Godot 4.3, run headless test suite, export packed desktop build; log all warnings and failing scripts.
2. **Visual baseline:** launch real title and opening bridge via desktop graphical runner, capture image/video, record asset rendering source; no simulated screenshot replacements.
3. **Animation baseline:** inspect actual approved manifest and 20 attacks, all walk directions; reconcile owner-accepted canonical art; capture six real rendered frames at frame-index boundaries.
4. **Combat baseline:** enumerate DQ-003 commits/branches, replay REV 3 checks through real encounter scenes, not fixtures.
5. **Asset recovery:** produce a non-destructive Drive manifest of sources with original links, classification, duplicate hashes, missing originals, and owner-approval questions.
6. **Muse intake:** convert live tasks into individual GitHub issues with fixed acceptance criteria; freeze open-ended parallel art batches until references and review gates are clear.
7. **Workstation proof:** pick local or cloud interactive desktop runner, document reproducible setup, demonstrate a real Godot screenshot + one automated scene interaction.
8. **Decision gate:** owner approves selected Form 1 anchor and ranked scope before production merges.

## Workspace proposal
```
source-of-truth:
  GitHub:
    godot-project/      actual playable game and imported-approved manifests
    docs/production/    plans, QA policy, recovery register
    .github/workflows/  reproducible tests/builds
    issues/PRs          task ownership and acceptance history
  Google Drive:
    00_INBOX_TO_TRIAGE/ incoming unverified assets (create later)
    01_CANON_APPROVED/  owner-approved originals (create later)
    02_STORY_WORLD/     storyboard, lore, script drafts (create later)
    03_SOURCE_ART/      layered originals + reference assets (create later)
    04_REVIEWS/         candidate submissions and comparisons (create later)
    90_ARCHIVE_READONLY/ preserved old structures (create later)
```
Do not create, rename, or move these Drive folders until source and permissions inventory is complete; existing folders may be reused instead of duplicated.

## Evidence record template
```
Task:
Git SHA / branch:
Godot version:
Source art/manifest:
Test environment:
Command/input trace:
Expected result:
Observed result:
Screenshot/video/log links:
Automated checks passed/failed:
Packed build proof:
Remaining risks:
Creative approval:
```

## Non-goals of this planning commit
No migration, game code change, asset editing, release, merge, CI claim, or Muse-bot execution has occurred.
