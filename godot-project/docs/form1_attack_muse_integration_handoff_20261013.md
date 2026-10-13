# Form 1 sword animation QA handoff — 2026-10-13

**NO NEW ATTACK ART APPROVED.** Muse BOT-006 Marrow is the sole assigned artist; BOT-002/BOT-007 verify, Tucker integrates, Ivy checks Android. Engineering must not duplicate this assignment.

Approved 1536x384 RGBA walk strips (four 384px cells) were inspected: down/up/left/right. Alpha ends at y=372–373. Guide-only planted-foot pivot: (192,372), tolerance ±7px. Source right-hand guard anchors in current sprite shader: down (138,229), up (291,197), left (144,220), right (199,228). The artist must record per-frame moving sword/hand pivots.

Expected 20 Muse candidates: 5 motions (slash, return, windup, heavy, recover) x 4 directions, 6–8 transparent 384px cells each. Match approved mortal green hair/cloak, grey/gold armor and ONE steel longsword in RIGHT hand. No second sword, purple arcs, fake alpha, scenery or body drift. Impact smears: 2–3 subtle painted accents. Source parts, pivots and hierarchy required.

PR #46 remains unmerged: first slash 350ms, return 300ms, charge 500ms, heavy 660ms, recover 280ms. Sample art from ScytheRig normalized progress. Heavy starts from final windup pose.

After director approval only: godot-project/sprites/mollosar/form1_attack_{motion}_{direction}_spec384.png plus per-frame pivot metadata. Avoid double-rendering the fallback shader sword.

Run the Pillow checker at godot-project/tools/asset_qa/form1_attack_qc.py; full reference contact sheet and RGBA guides are in the separate downloadable QA ZIP.

Bellhollow's approved painted floor is already in develop. Muse-painted rail occluders and then approved invader figures remain pending. No merge without Tucker/Gage approval.
