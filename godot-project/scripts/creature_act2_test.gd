extends SceneTree
## Act 2 creature special battle behaviors test.
##
## Covers: Deepjaw Gorge heal + Fossil Crush damage, Spinehopper
## Thermal Ride -> Dive two-turn sequence, Dragonthorn Relocate every
## third turn, docile Stillness / Snap Shut / Echo, Thornleech Scream
## on burn, evasion mechanics, and burn application on fire damage.
##
## Run: Godot --headless --path <project> -s res://scripts/creature_act2_test.gd

const CreatureData = preload("res://scripts/creature_data.gd")
const BattleUnit = preload("res://scripts/battle_unit.gd")
const CreatureAI = preload("res://scripts/creature_ai.gd")

var _failures: Array[String] = []


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failures.append(name)
		print("  FAIL: ", name)


func _initialize() -> void:
	print("=== ACT 2 CREATURE BEHAVIORS TEST ===")
	CreatureData.ensure_loaded()
	CreatureAI.reset_battle_state()
	_test_deepjaw()
	CreatureAI.reset_battle_state()
	_test_spinehopper()
	CreatureAI.reset_battle_state()
	_test_dragonthorn()
	CreatureAI.reset_battle_state()
	_test_docile()
	CreatureAI.reset_battle_state()
	_test_thornleech()
	CreatureAI.reset_battle_state()
	_test_evasion_and_burn()
	CreatureAI.reset_battle_state()
	_test_other_act2()

	if _failures.is_empty():
		print("ALL ACT2 TESTS PASSED")
	else:
		print("FAILURES: ", _failures.size())
		for f in _failures:
			print("  - ", f)
	quit(1 if not _failures.is_empty() else 0)


func _make(cid: String, level: int = 12) -> RefCounted:
	var u = BattleUnit.new(cid, level)
	# Disable evasion RNG in tests unless explicitly seeded.
	return u


func _no_evasion(u: RefCounted) -> void:
	u.statuses["evasion_seed"] = 0


func _force_evasion(u: RefCounted) -> void:
	u.apply_status("evasion", 2)
	u.statuses["evasion_seed"] = 1


func _test_deepjaw() -> void:
	print("-- Deepjaw --")
	var dj = _make("deepjaw")
	var foe = _make("snapling")
	_no_evasion(foe)
	_check("deepjaw_has_gorge", dj.can_use("gorge"))
	_check("deepjaw_has_fossil_crush", dj.can_use("fossil_crush"))

	# Gorge heals 25% of max HP.
	dj.hp = dj.max_hp / 2
	var before: int = dj.hp
	var expected_heal := int(round(float(dj.max_hp) * 0.25))
	dj.use_ability("gorge", foe)
	# use_ability with heal element heals directly; no_specials skips the
	# duplicate message-only apply_special.
	_check("gorge_heals_25pct", dj.hp == mini(dj.max_hp, before + expected_heal))

	# Gorge never overheals.
	dj.hp = dj.max_hp - 5
	dj.use_ability("gorge", foe)
	_check("gorge_no_overheal", dj.hp == dj.max_hp)

	# Fossil Crush is heavy: power 2.5 vs snap_bite 1.2 baseline.
	var crush_foe = _make("snapling")
	_no_evasion(crush_foe)
	var bite_foe = _make("snapling")
	_no_evasion(bite_foe)
	var attacker = _make("deepjaw")
	_no_evasion(attacker)
	# Use a fixed attacker for both to compare fairly.
	var dmg_crush: int = attacker.use_ability("fossil_crush", crush_foe)
	attacker.teach_ability("snap_bite")
	var dmg_bite: int = attacker.use_ability("snap_bite", bite_foe)
	_check("fossil_crush_heavy", dmg_crush > dmg_bite * 1.5)

	# AI: Deepjaw gorges when hurt below 60%.
	var hurt = _make("deepjaw")
	hurt.hp = int(float(hurt.max_hp) * 0.5)
	var pick: String = CreatureAI.choose_action(hurt, "", false)
	_check("deepjaw_ai_gorge_when_hurt", pick == "gorge")
	# AI: healthy Deepjaw crushes.
	var healthy = _make("deepjaw")
	var pick2: String = CreatureAI.choose_action(healthy, "", false)
	_check("deepjaw_ai_crush_when_healthy", pick2 == "fossil_crush")


func _test_spinehopper() -> void:
	print("-- Spinehopper --")
	var sh = _make("spinehopper")
	var foe = _make("snapling")
	_no_evasion(foe)
	_check("spinehopper_has_thermal_ride", sh.can_use("thermal_ride"))
	_check("spinehopper_has_dive", sh.can_use("dive"))

	# AI turn 1: Thermal Ride (no thermal status yet).
	var pick1: String = CreatureAI.choose_action(sh, "", false)
	_check("spinehopper_ai_thermal_first", pick1 == "thermal_ride")

	# Use Thermal Ride: gains thermal + evasion.
	sh.use_ability("thermal_ride", foe)
	_check("thermal_ride_sets_thermal", sh.statuses.has("thermal"))
	_check("thermal_ride_sets_evasion", int(sh.statuses.get("evasion", 0)) > 0)

	# AI turn 2: Dive (thermal active).
	var pick2: String = CreatureAI.choose_action(sh, "", false)
	_check("spinehopper_ai_dive_second", pick2 == "dive")

	# Dive consumes thermal for bonus damage.
	var sh2 = _make("spinehopper")
	var foe2 = _make("snapling")
	_no_evasion(foe2)
	sh2.use_ability("thermal_ride", foe2)
	var dmg_buffed: int = sh2.use_ability("dive", foe2)
	_check("dive_consumes_thermal", not sh2.statuses.has("thermal"))

	var sh3 = _make("spinehopper")
	var foe3 = _make("snapling")
	_no_evasion(foe3)
	var dmg_plain: int = sh3.use_ability("dive", foe3)
	_check("dive_thermal_bonus", dmg_buffed > dmg_plain)


func _test_dragonthorn() -> void:
	print("-- Dragonthorn --")
	var dt = _make("dragonthorn")
	_check("dragonthorn_has_relocate", dt.can_use("relocate"))

	# Relocate on every third turn (turns 3, 6, 9...).
	var picks: Array = []
	for i in range(6):
		picks.append(CreatureAI.choose_action(dt, "", false))
	_check("dragonthorn_relocate_turn3", str(picks[2]) == "relocate")
	_check("dragonthorn_relocate_turn6", str(picks[5]) == "relocate")
	_check("dragonthorn_no_relocate_turn1", str(picks[0]) != "relocate")
	_check("dragonthorn_no_relocate_turn2", str(picks[1]) != "relocate")

	# Relocate grants evasion.
	var dt2 = _make("dragonthorn")
	var foe = _make("snapling")
	dt2.use_ability("relocate", foe)
	_check("relocate_sets_evasion", int(dt2.statuses.get("evasion", 0)) > 0)


func _test_docile() -> void:
	print("-- Docile behaviors --")
	# Echomarrow: Stillness when unprovoked.
	var em = _make("echomarrow")
	var pick: String = CreatureAI.choose_action(em, "", false)
	_check("echomarrow_stillness_unprovoked", pick == "stillness" or pick == "")

	# Carrion Bloom: Stillness when unprovoked.
	var cb = _make("carrion_bloom")
	var pick_cb: String = CreatureAI.choose_action(cb, "", false)
	_check("carrion_stillness_unprovoked", pick_cb == "stillness" or pick_cb == "")

	# Provoked docile: Snap Shut (Cinderbloom has it).
	var ci = _make("cinderbloom")
	var pick_calm: String = CreatureAI.choose_action(ci, "", false)
	_check("cinderbloom_stillness_calm", pick_calm == "stillness" or pick_calm == "")
	CreatureAI.mark_provoked(ci)
	var pick_mad: String = CreatureAI.choose_action(ci, "", true)
	_check("cinderbloom_snap_shut_provoked", pick_mad == "snap_shut")

	# Snap Shut buffs defense.
	var ci2 = _make("cinderbloom")
	var foe = _make("snapling")
	ci2.use_ability("snap_shut", foe)
	_check("snap_shut_def_buff", float(ci2.temp_mods.get("def_mult", 1.0)) > 1.0)

	# Echomarrow Echo: copies foe's last ability via apply_special ctx.
	var em2 = _make("echomarrow")
	var foe2 = _make("snapling")
	var res: Dictionary = CreatureAI.apply_special(em2, foe2, "echo", {"foe_last_ability": "snap_bite"})
	_check("echo_returns_ability", str(res.get("echo_ability", "")) == "snap_bite")
	# Stillness does no damage.
	var em3 = _make("echomarrow")
	var foe3 = _make("snapling")
	_no_evasion(foe3)
	var hp_before: int = foe3.hp
	em3.use_ability("stillness", foe3)
	_check("stillness_no_damage", foe3.hp == hp_before)


func _test_thornleech() -> void:
	print("-- Thornleech --")
	var tl = _make("thornleech")
	_check("thornleech_has_scream", tl.can_use("scream"))

	# Not burned: normal attack, not scream.
	var pick_calm: String = CreatureAI.choose_action(tl, "", false)
	_check("thornleech_no_scream_calm", pick_calm != "scream")

	# Burned: screams.
	tl.apply_status("burned", 2)
	var pick_burned: String = CreatureAI.choose_action(tl, "", false)
	_check("thornleech_scream_burned", pick_burned == "scream")

	# Scream buffs attack.
	var tl2 = _make("thornleech")
	var foe = _make("snapling")
	tl2.use_ability("scream", foe)
	_check("scream_atk_buff", float(tl2.temp_mods.get("atk_mult", 1.0)) > 1.0)

	# Drain siphons HP.
	var tl3 = _make("thornleech")
	tl3.hp = tl3.max_hp / 2
	var foe3 = _make("snapling")
	_no_evasion(foe3)
	var hp_before: int = tl3.hp
	tl3.use_ability("drain", foe3)
	_check("drain_siphons", tl3.hp > hp_before)


func _test_evasion_and_burn() -> void:
	print("-- Evasion & burn --")
	# Forced evasion: attack misses.
	var atk = _make("snapling")
	var dfn = _make("snapling")
	_force_evasion(dfn)
	var dmg: int = atk.use_ability("snap_bite", dfn)
	_check("evasion_miss", dmg == 0)
	_check("evasion_no_hp_loss", dfn.hp == dfn.max_hp)

	# No evasion: attack lands.
	var dfn2 = _make("snapling")
	_no_evasion(dfn2)
	var dmg2: int = atk.use_ability("snap_bite", dfn2)
	_check("no_evasion_hit", dmg2 > 0)

	# Fire damage applies burned.
	var fire_atk = _make("cinderbloom")  # has heat_bloom (fire)
	var victim = _make("snapling")
	_no_evasion(victim)
	fire_atk.use_ability("heat_bloom", victim)
	_check("fire_applies_burn", victim.statuses.has("burned"))

	# Evasion status ticks down via tick_statuses.
	var e = _make("spinehopper")
	e.apply_status("evasion", 1)
	e.tick_statuses()
	_check("evasion_expires", not e.statuses.has("evasion"))


func _test_other_act2() -> void:
	print("-- Other Act 2 kits --")
	# Bloodleaf Grazer: uphill_flight gives evasion.
	var bg = _make("bloodleaf_grazer")
	var foe = _make("snapling")
	bg.use_ability("uphill_flight", foe)
	_check("uphill_flight_evasion", int(bg.statuses.get("evasion", 0)) > 0)
	# Shed Leaves cures ailments.
	bg.apply_status("wilt", 3)
	bg.use_ability("shed_leaves", foe)
	_check("shed_leaves_cures", not bg.statuses.has("wilt"))
	# Gloomcap retract buffs defense.
	var gc = _make("gloomcap")
	gc.use_ability("retract", foe)
	_check("retract_def_buff", float(gc.temp_mods.get("def_mult", 1.0)) > 1.0)
	# All nine have their signature moves usable.
	var kits := {
		"bloodleaf_grazer": ["uphill_flight", "broadside", "shed_leaves"],
		"thornleech": ["latch", "drain", "scream"],
		"cinderbloom": ["snap_shut", "heat_bloom", "ember_seeds"],
		"echomarrow": ["echo", "resonate", "stillness"],
		"gloomcap": ["retract", "spore_cloud", "tendril_lash"],
		"deepjaw": ["gorge", "territory_roar", "fossil_crush"],
		"spinehopper": ["dive", "thermal_ride", "rake"],
		"dragonthorn": ["relocate", "thorn_volley", "crown_slam"],
		"carrion_bloom": ["mourn", "war_petal", "stillness"],
	}
	var all_ok := true
	for cid in kits:
		var u = _make(str(cid))
		for mv in kits[cid]:
			if not u.can_use(str(mv)):
				all_ok = false
				print("  MISSING: ", cid, " -> ", mv)
	_check("all_nine_kits_complete", all_ok)
