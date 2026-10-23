# DQ-003 Stage 2 — slices 1–2 candidate (PARTIAL)
Base: develop @ 94a4b9ca886a51970707544713fed0418e771682 (verified 2026-10-22).
Authority: Director B, Grimley BOT-002; REV 3 §14 and director confirmations as supplied.
Status: **PARTIAL, NOT MERGEABLE**. Wrath BOT-003 slice-1 contract review + director authorization required before any merge. Slices 3–4 not implemented.

## Contract ledger / unresolved integration seams
- **Fighter bridge:** Mollosar vigor maps to fighter HP one-for-one; start default 3/3. Persisting encounter damage to GameState/player vigor remains to implement.
- **Creature bridge:** fighter-only prototype requires an explicit hostile fighter identity/side/role and authored vigor/might/guard/speed block. Creature BattleUnit derivation stays intact for creatures, but is not used as a fake fighter.
- **Damage:** CombatDamage.dealt is now the one arithmetic path used by BattleUnit.take_damage and fighter-only prototype. Existing modifiers and 0.6 guard mitigation stay the same. No WILT value was changed or frozen.
- **Companions:** taken-out returns with 1 HP after battle; no same-battle re-entry. XP lead share goes to fielded companion. Press/Guard/Focus stances. NO friendly fire. These are required contract behaviors **not implemented** in fighter-only slice.
- **Death:** actor_killed must be explicit opt-in; default actors nonkillable; companions never killed. The prototype emits fight_ended only; it never emits actor_killed. Opt-in kill reporting needs integration later.
- **Enemy-owned companions:** noncapturable. No capture logic added or changed; §10 Q-a and Q-b still need director decisions.
- **Combat and legacy:** existing BattleManager and tactical/seamless battle flow remain intact. New core has no scene, character controller, hitboxes, AI scheduling, HUD, or persistence integration.
- **Flee:** 2s follows REV 3 §8 for wild-fight flee; 1.5s applies to companion switching, not fleeing. Damage and release interrupt channel; successful channel resolves fled.
- **Animation:** no attack playback file modified. The DQ-005 packed-proof gate still applies before any future animation-affecting integration.
- **Force teardown:** prototype outcome is forced_teardown and resolves idempotently; no live scene teardown has been validated.

## Smoke/regression harness (not yet executed)
`godot --headless --path godot-project -s res://scripts/realtime_fighter_encounter_test.gd`
Exercises four outcomes: victory, Mollosar defeat, flee interruption (and channel completion), forced teardown; also 3-HP bridge and arithmetic assertion. **Test execution not evidenced**: this environment has no Godot executable and GitHub connector does not run Godot headless or packed APKs.

## Required to finish slices 1–2
1. Rev 3 supplied as operator attachment 2026-10-22; contract comparison below completed. Wrath review gate remains.
2. Wire one existing field enemy to an in-room live player/enemy real-time controller, reuse existing player vigor signals, input and animations without regressing approved Form 1.
3. Run headless harness, existing BattleUnit tests, and playable tests of all four outcomes in the real game scene.
4. Build/export a packed game and verify attack animation playback if affected; record logs/artifacts.
5. Record compatibility tests, cleanup and clear integration gaps. Slices 3–4 must pass before removing PARTIAL label.

## Gate
No merge into develop or main; no capture code; no claim of playable slice-2 completion.


## 2026-10-22 Rev 3 §1–16 re-audit at verified develop 94a4b9c

Source: liaison-provided REALTIME-BATTLE-SPEC-REV3-20261022.md (Hush BOT-014). Not obtained through Drive; retired Drive account must remain disconnected.

| Contract area | Verified develop state | Candidate / remaining |
|---|---|---|
| §1 fighter real-time, no main turn loop | legacy battle.gd and seamless path still turn-based | NOT MIGRATED; isolated fighter outcome model only |
| §2 shared clock/cooldown/action phases | player attack clock exists separately | no shared real-time combat clock, per-actor action state, hit contacts, or live movement yet |
| §2 shared damage | BattleUnit implemented own guard formula | shared CombatDamage now called from BattleUnit and fighter prototype; runtime regression pending |
| §2 plant classification | BattleUnit.is_plant returns true unconditionally | UNRESOLVED for mixed roster; do not apply plant bonus to human fighters |
| §3 fighter bridge | player.gd vigor 3 | candidate preserves vigor = HP 3; authored enemy fighter dictionary now required; creature derivation unchanged |
| §4 companion readiness | BattleManager refuses battle with no conscious party lead | BLOCKER for solo fighter path, no companion should be fabricated |
| §4 companion stance, registry, focus, XP, 1HP return | no real-time mixed cast | contract adopted but deferred to slices 3–4 |
| §5 death/taken-out | legacy faint/death paths mixed | candidate doesn't emit actor_killed; actual death opt-in and taken-out event await integration |
| §6 direct control/mobile HUD | player.gd joystick/scythe path, legacy modal battle | live in-room fighter controller/HUD not wired |
| §7 identity/modes/producers | pending uses enemy_creature_id and player party lead; no fighter stats/mode/roles | candidate core demands fighter identity/side/role/stats; coordinated manager+reader migration remains |
| §8 victory, defeat, wild flee | legacy battle resolution | isolated state tests written; wild flee corrected from erroneous 1.5 to 2 seconds; actual lifecycle not wired |
| §9 creature side duels | main legacy battle creature duel | explicit side_duel future; no migration in slice 2 |
| §10 capture conflict | old CATCH path still present | deliberately untouched; Q-a/b open; enemy-owned companions noncapturable contract |
| §11 multipart presentation | existing creature art pipeline | adapter/rig contract not yet implemented; approved Form1 unchanged |
| §12 migration/test coverage | old tactical tests remain | headless core harness exists, not executed; packed proof absent |
| §13 acceptance | none of live slice-2 scenarios validated | four model outcomes have tests but no in-game proof |
| §14 stage 2 scope | stage 1 gap-map | PARTIAL until slices 3–4 pass |
| §15–16 rulings | prior gaps | director confirmations supersede proposals; WILT values stay tuning only |

**Audit finding:** Slice 1 contract mapping has been re-reviewed against Rev3 at current develop and documented; implementation closure remains incomplete, especially manager/reader, actor registry, solo readiness and damage adapters. Slice 2 is still an isolated model and must NOT be represented as one playable field fight. No changes merged. No Android packed-build verification.


## 2026-10-23 Director B follow-up — Rev 3 corrections

Branch remains `candidate/dq003-stage2-slices1-2-20261022`; no merge.

- Opponent correction: fighter-only prototype now requires a hostile `role=fighter` actor with explicit actor_id and authored vigor/might/guard/speed. It does not instantiate BattleUnit as the opponent. Current regression fixture is a test-authored field-fighter record, **not yet wired to an existing in-game field enemy**.
- Flee correction: channel is exactly 2.0 seconds and enabled only for wild encounters. Companion switching's 1.5-second vulnerability is separate and not implemented here.
- Contract shape: added `battle_encounter_record.gd` for modes `fighter_duel`, `companion_skirmish`, `side_duel`, `peaceful`; participant records carry `actor_id`, `side`, `role`, optional species identity and authored stats. Manager pending shape carries `mode`, `player_fighter`, `enemy_fighter`, `enemy_fighter_stats`, `enemy_creatures[]`, `combatants[]`, return fields and victory flag. Core constructs a fighter_duel with Mollosar and one hostile fighter; no enemy companions.
- Tests added for the record/pending shape, 2-second wild flee, and no flee outside wild mode. Tests are written but not run.

## Slice 2 §13 acceptance status (2026-10-23)

| Required scenario | Model coverage | Live game evidence |
|---|---|---|
| Victory | regression case authored | NOT VERIFIED |
| Mollosar HP zero / defeat | regression case authored | NOT VERIFIED |
| Wild flee channel interrupted by enemy hit | regression case authored | NOT VERIFIED |
| Forced teardown | idempotent model case authored | NOT VERIFIED |

**Current status remains PARTIAL.** These are state-model tests only. The prototype is not yet launched by BattleManager in the same room, does not bridge the existing field enemy's `take_hit` contact through the shared damage adapter, does not use the shared combat clock/attack phases, and has no live scene lifecycle/pending cleanup. Thus it does not yet satisfy the complete slice-2 acceptance scope. Slice 1's contract record shape is now explicit in a helper, but BattleManager producers and battle config readers have not yet been migrated together; do not call slice 1 implementation complete.

Blockers: no Godot runtime/Android exporter is available through the current connector session, so no executable regression logs, playable four-outcome proof, or packed APK evidence can be supplied. No animation playback code was changed. Wrath BOT-003 review and director merge authorization remain required. Capture flow remains untouched; WILT values remain tuning parameters.
