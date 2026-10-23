# Phone visual QA — 2026-10-22 (user APK recording)
Evidence: user video `1000019282.mp4`, ~138.8s 2340x1080.

| Time | Finding | Status |
| --- | --- | --- |
| 0:00–0:35 | Form 1 animation pose/scale continuity inconsistent on device | Recorded; compare actual 20 source strips, visual QA pending |
| 0:45–1:15 | Bridge invaders remain hand-drawn placeholders | Confirmed in `scripts/invader.gd`; candidate character art unapproved, not promoted |
| 1:50+ | P3 black-sand shore is flat gray | LFS pointer `p3_black_sand_shore_1280x720.png` has no bundled .b64; temporary in-engine dark fallback added on this candidate branch |
| 1:57+ | Form 2 hood/scythe fallback visible, not canon sprite | Source walk art LFS pointers, missing essential-bundle originals; pending asset restore |
| 2:12+ | Battle uses blue and green CreatureDot placeholders | `battle.gd` intentional fallback; creature PNGs absent/LFS placeholders |
| Throughout | Immersion/UI: mobile overlays, inconsistent scenery, legacy turn-based creature battle | Separate gameplay/UI lane; do not change combat model in visual patch |

Scope: render shore without gray failure; no changes to story, approved art, save, enemy AI, combat clock, or realtime battle system.
This is NOT visual phone acceptance. P3 fallback is an intentionally temporary representation until approved painted shore art is available in the packed APK.
