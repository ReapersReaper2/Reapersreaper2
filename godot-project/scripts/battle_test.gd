extends SceneTree
## Headless tactical-battle foundation test: JSON data loads clean, stat
## derivation matches hand-computed values, guard mitigation, fire-vs-plant
## effectiveness, defeat at 0 HP, level scaling, wilt ticks, no errors.
##
## Run: Godot --headless --path <project> -s res://scripts/battle_test.gd
##
## Hand-computed reference values (see data/*.json):
##   snapling lvl1: might mods 1+0+3+1+2+2+0=9 -> atk 15;
##     guard mods 0+1+0+1+0+2+0=4 -> def 7; hp 30; speed 9.
##   bellmaw lvl1: might mods 0+1+4+0+1+0+0=6 -> atk 20;
##     guard mods 2+1+0+0+1+3+0=7 -> def 17; hp 120.
##   bellowscap lvl1: might mods 0+0+1+0+0+0+0=1 -> atk 4;
##     guard mods 1+0+0+1+0+2+0=4 -> def 10; hp 40.
##   Damage formula: dealt = max(1, round(raw - def * 0.6)).
##   snap_bite (1.2) from snapling on bellowscap: raw 18.0 -> round(18-6)=12.
##   ember_spit (1.0, fire) from snapling on bellowscap (plant, no resist):
##     raw 15*1.5=22.5 -> round(22.5-6)=round(16.5)=17.
##   Level mult = 1 + (lvl-1)*0.08; bellmaw lvl10 hp = round(120*1.72)=206.
##   Wilt: 10% of max HP per turn; 40-hp unit drains 4/turn.
##
## Tuning placeholders (not canon): base stats per creature, trait
## might/guard mods, LEVEL_GROWTH 0.08, GUARD_MITIGATION 0.6, FIRE_VS_PLANT
## 1.5, WILT_DRAIN 0.10. dominance values are stored for future breeding.

const CreatureData = preload("res://scripts/creature_data.gd")
const BattleUnit = preload("res://scripts/battle_unit.gd")

var _failures: Array[String] = []


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failures.append(name)
		print("  FAIL: ", name)


func _initialize() -> void:
	print("=== BATTLE FOUNDATION TEST ===")
	CreatureData.ensure_loaded()

	# --- Data loads ---
	var cids: Array = CreatureData.creature_ids()
	# 18 as of the ash_wraith line (was 17 when this check was written).
	_check("eighteen_creatures", cids.size() == 18)
	_check("bellmaw_present", cids.has("bellmaw"))
	var slots_ok := true
	var traits_ok := true
	var abilities_ok := true
	var tid: Array = CreatureData.trait_ids()
	var aid: Array = CreatureData.ability_ids()
	for cid in cids:
		var c: Dictionary = CreatureData.get_creature(str(cid))
		var traits: Dictionary = c.get("traits", {})
		if traits.size() != 7:
			slots_ok = false
		for slot in traits:
			if not tid.has(str(traits[slot])):
				traits_ok = false
	for t in tid:
		for ab in CreatureData.get_trait(str(t)).get("ability_ids", []):
			if not aid.has(ab):
				abilities_ok = false
	_check("seven_slots_each", slots_ok)
	_check("all_trait_ids_valid", traits_ok)
	_check("all_ability_ids_valid", abilities_ok)
	_check("gene_pairs_present", (CreatureData.get_creature("snapling").get("genes", {}) as Dictionary).size() == 3)

	# --- Stat derivation (hand-computed) ---
	var snap := BattleUnit.new("snapling", 1)
	_check("snapling_atk", snap.attack == 15)
	_check("snapling_def", snap.defense == 7)
	_check("snapling_hp", snap.max_hp == 30 and snap.hp == 30)
	_check("snapling_speed", snap.speed == 9)
	_check("snapling_abilities", snap.can_use("snap_bite") and snap.can_use("claw_rake") and snap.can_use("quill_volley"))
	var maw := BattleUnit.new("bellmaw", 1)
	_check("bellmaw_atk", maw.attack == 20)
	_check("bellmaw_def", maw.defense == 17)
	_check("bellmaw_hp", maw.max_hp == 120)
	_check("bellmaw_boss_ability", maw.can_use("maw_gulp"))

	# --- Damage with guard mitigation ---
	var cap := BattleUnit.new("bellowscap", 1)
	_check("bellowscap_def", cap.defense == 10)
	var dealt: int = snap.use_ability("snap_bite", cap)
	_check("snap_bite_dealt_12", dealt == 12)
	_check("bellowscap_hp_28", cap.hp == 28)

	# --- Fire vs plant effectiveness ---
	snap.teach_ability("ember_spit")
	var cap2 := BattleUnit.new("bellowscap", 1)
	var fdealt: int = snap.use_ability("ember_spit", cap2)
	_check("ember_spit_dealt_17", fdealt == 17)  # 1.5x fire bonus vs plant
	_check("bellowscap_hp_23", cap2.hp == 23)
	_check("unknown_ability_rejected", snap.use_ability("nope", cap2) == -1)

	# --- Defeat at 0 HP ---
	var weak := BattleUnit.new("snapling", 1)
	var big := BattleUnit.new("bellmaw", 1)
	while not weak.fainted:
		big.use_ability("maw_gulp", weak)
	_check("fainted_at_zero", weak.fainted and weak.hp == 0)
	_check("fainted_cannot_act", weak.use_ability("snap_bite", big) == 0)

	# --- Level scaling sane ---
	var maw10 := BattleUnit.new("bellmaw", 10)
	_check("lvl10_hp_206", maw10.max_hp == 206)
	_check("lvl10_stronger", maw10.attack > maw.attack and maw10.defense > maw.defense)
	_check("lvl10_not_absurd", maw10.max_hp < maw.max_hp * 3)

	# --- Wilt status ticks ---
	var w := BattleUnit.new("bellowscap", 1)
	w.apply_status("wilt", 2)
	w.tick_statuses()
	_check("wilt_drains_4", w.hp == 36)
	_check("wilt_turns_decrement", int(w.statuses.get("wilt", 0)) == 1)
	# spore_cloud applies wilt via use_ability
	var sporer := BattleUnit.new("bellowscap", 1)
	var victim := BattleUnit.new("snapling", 1)
	sporer.use_ability("spore_cloud", victim)
	_check("spore_cloud_applies_wilt", int(victim.statuses.get("wilt", 0)) == 3)

	print("=== %d failures ===" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)
