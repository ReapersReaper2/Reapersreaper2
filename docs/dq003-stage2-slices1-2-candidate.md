# DQ-003 Stage 2 — slices 1–2 candidate (PARTIAL)
Base: develop @ 94a4b9ca886a51970707544713fed0418e771682 (verified 2026-10-22).
Authority: Director B, Grimley BOT-002; REV 3 §14 and director confirmations as supplied.
Status: **PARTIAL, NOT MERGEABLE**. Wrath BOT-003 slice-1 contract review + director authorization required before any merge. Slices 3–4 not implemented.

## Contract ledger / unresolved integration seams
- **Fighter bridge:** Mollosar vigor maps to fighter HP one-for-one; start default 3/3. Persisting encounter damage to GameState/player vigor remains to implement.
- **Creature bridge:** enemy instantiated via existing BattleUnit(creature_id, level) so existing derivation stays intact.
- **Damage:** CombatDamage.dealt is now the one arithmetic path used by BattleUnit.take_damage and fighter-only prototype. Existing modifiers and 0.6 guard mitigation stay the same. No WILT value was changed or frozen.
- **Companions:** taken-out returns with 1 HP after battle; no same-battle re-entry. XP lead share goes to fielded companion. Press/Guard/Focus stances. NO friendly fire. These are required contract behaviors **not implemented** in fighter-only slice.
- **Death:** actor_killed must be explicit opt-in; default actors nonkillable; companions never killed. The prototype emits fight_ended only; it never emits actor_killed. Opt-in kill reporting needs integration later.
- **Enemy-owned companions:** noncapturable. No capture logic added or changed; §10 Q-a and Q-b still need director decisions.
- **Combat and legacy:** existing BattleManager and tactical/seamless battle flow remain intact. New core has no scene, character controller, hitboxes, AI scheduling, HUD, or persistence integration.
- **Flee:** 1.5s is a provisional parameter for the isolated harness, not a director-approved final duration. Damage and release interrupt channel; successful channel resolves fled.
- **Animation:** no attack playback file modified. The DQ-005 packed-proof gate still applies before any future animation-affecting integration.
- **Force teardown:** prototype outcome is forced_teardown and resolves idempotently; no live scene teardown has been validated.

## Smoke/regression harness (not yet executed)
`godot --headless --path godot-project -s res://scripts/realtime_fighter_encounter_test.gd`
Exercises four outcomes: victory, Mollosar defeat, flee interruption (and channel completion), forced teardown; also 3-HP bridge and arithmetic assertion. **Test execution not evidenced**: this environment has no Godot executable and GitHub connector does not run Godot headless or packed APKs.

## Required to finish slices 1–2
1. Obtain accessible REALTIME-BATTLE-SPEC REV 3 §14 and compare the entire contract against the director rulings; Wrath review gate.
2. Wire one existing field enemy to an in-room live player/enemy real-time controller, reuse existing player vigor signals, input and animations without regressing approved Form 1.
3. Run headless harness, existing BattleUnit tests, and playable tests of all four outcomes in the real game scene.
4. Build/export a packed game and verify attack animation playback if affected; record logs/artifacts.
5. Record compatibility tests, cleanup and clear integration gaps. Slices 3–4 must pass before removing PARTIAL label.

## Gate
No merge into develop or main; no capture code; no claim of playable slice-2 completion.
