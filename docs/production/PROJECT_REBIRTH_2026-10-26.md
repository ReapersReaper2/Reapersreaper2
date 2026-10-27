# Reaper's Reaper — Project Rebirth (2026-10-26)

**Status:** Proposed production policy; candidate branch only. No gameplay or canon rewrite. Owner approval governs promotion to develop.

## Mission
Ship a coherent dark-fantasy 2D action RPG by prioritizing reproducible, visually verified player experiences over asset counts or unfinished parallel features.

## Authority and sources of truth
1. **Creative owner:** final decision on story, character design, feel, art canon and releases.
2. **GitHub:** authoritative code, technical specifications, actionable issues, candidate PRs, CI evidence, and approved in-game asset manifests.
3. **Replacement Drive:** archival and working source art, high-resolution creative references, recovery sources, long-form story material. Drive contents are not automatically approved canon.
4. **Runtime:** a feature is accepted only with recorded evidence from the actual Godot scene and (where relevant) a packed Android build.
5. **Muse specialists:** contributors, not independent authorities. Their output requires traceable review and explicit acceptance.

## Recovery rules
- **No deletion, bulk moves, renames, or overwrite** of legacy Drive or GitHub assets during initial inventory.
- Track each recovered source by original URL/path, source date, checksum when materialized, owner, license when relevant, classification, and approval status.
- Classes: APPROVED / CANDIDATE / ARCHIVE / CONFLICT / MISSING. Unknown = CANDIDATE, never APPROVED.
- Preserve both historical Form 1 visual lineages until owner resolves the canonical anchor. Do not infer approval from file names.
- Keep legacy drafts and PRs visible until each is individually reconciled.

## Initial production scope
**P0: infrastructure and recovery:** inventory branches/PRs, Drive art/story sources, current build baseline, CI workflows, and blocked assets.
**P1: player feel:** one approved Form 1 reference; true six-frame walk and attack consistency; exact alpha/pivot/clip QA; real engine render and packed-build proof; correct mobile input.
**P2: real-time duel:** finish DQ-003 fighter duel, validate real existing field enemy, damage, victory, defeat, 2-second interruptible flee, forced teardown, on-device controls.
**P3: world slice:** opening bridge -> Reaper's Reprieve -> Grimley's garden, dialogue, one quest, companion encounter, save/load, polished audio/UI.
**P4: 15–30 minute complete vertical slice**, release candidate only after end-to-end physical-device playtest.

## Visual workstation requirements
A persistent machine (local or cloud) with Godot 4.3 editor, GUI/desktop capture, input automation, project checkout + LFS, Android SDK/build tools, reproducible setup script, and artifact storage.
- Test runner should launch exact scenes with deterministic seed and test fixtures; inject movement/attack/interact; capture frame sequences, screenshots, videos, logs, and Godot version/commit.
- Golden screenshots and animation metrics are reviewed, **not treated as substitutes for human visual acceptance**.
- Test reports include scene, commit, OS/device, input trace, rendering source, expected/actual, and links to raw evidence.
- Use CI for headless contract/unit checks; GUI runner for pixel/pose inspection; Android emulator for smoke checks; physical phone for final input/render validation.
- Do not claim to visually inspect footage until a computer-access environment actually exposes frames/screenshots.

## Change control
- `develop` remains integration; `main` remains releasable. Candidate branches target develop; no direct changes to develop by this reset.
- PR acceptance requires scope, linked issue, screenshots or footage for visual changes, test output, packed proof where necessary, risks, and rollback path.
- No candidate becomes approved because its tests *exist*: test execution evidence must pass.
- Existing DQ-003 and DQ-005 branches/PRs remain unmerged until audit, independent validation, and explicit owner approval.

## Muse bot reboot
Stop parallel unbounded orders. Each assignment is a GitHub issue: task ID; single owner; exact input links; immutable reference versions; allowed files; deliverables; objective acceptance gates; due/checkpoint; reviewer.
- States: BACKLOG -> READY -> IN PROGRESS -> REVIEW -> ACCEPTED or REJECTED/BLOCKED.
- A bot cannot approve its own output or change canon.
- Work is accepted per artifact, not per batch. Failed QA halts dependent batches.
- If a bot misses evidence/checkpoints, reassign task without making architectural changes.
- Start with 3 functions rather than a sprawling team: engineering integration, art/animation production, independent QA. Story/canon decisions remain owner-gated.

## First reconciliation queue
- DQ-005: PR #70 tracing, #72 animation clock/facing, #73 combined playtest; verify overlap and packed Android proof before selecting approach.
- DQ-003: real-time battle slice implementation/CI four-outcome verification (independent of asset recovery).
- Recovered Drive folders: historical archive, team files, Reference Library / Canon - Mollosar Form 1; inspect source images and provenance before migrating.
- Resolve discrepancy between older sprite visual references and 2026-10-24 knight anchor explicitly.

## Definition of done
Working scene at pinned commit; tests executed; screenshots/video inspected; correct sprite provenance; no unapproved fallbacks; keyboard/gamepad/touch when applicable; regression tests pass; reproducible artifact and rollback; creative owner accepts.
