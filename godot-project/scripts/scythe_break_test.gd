extends SceneTree
## Headless scythe-break / longsword-phase verification: break sequence
## fires, weapon swaps to longsword/fairy, restoration at ch13_repowered
## swaps back, save/load preserves state, achievement flag fires.
##
## Run: Godot --headless --path <project> -s res://scripts/scythe_break_test.gd

const WeaponData = preload("res://scripts/weapon_data.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const ScytheBreak = preload("res://scripts/scythe_break.gd")

var _gs = null
var _checks: Dictionary = {}


func _initialize() -> void:
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		_gs = GameStateScript.new()
		_gs.name = "GameState"
		root.add_child(_gs)
		_gs._ready()
	else:
		_gs.new_game()
	# Wire the Achievements autoload (autoload order: GameState loads before
	# Achievements, so game_state._ready() can't see it — same pattern as
	# achievements_test.gd).
	var ach = root.get_node_or_null("Achievements")
	if ach != null:
		if ach.has_method("reset_all"):
			ach.reset_all()
		ach.set("game_state", _gs)
		_gs.achievements = ach

	_run()
	_report()
	quit()


func _run() -> void:
	# --- Baseline: scythe equipped, not broken ---
	_checks["baseline_weapon"] = WeaponData.current_weapon(_gs) == "scythe"
	_checks["baseline_power"] = WeaponData.current_power(_gs) == "armor"
	_checks["not_broken"] = not ScytheBreak.is_broken(_gs)
	_checks["no_broken_flag"] = not _gs.get_flag("scythe_broken", false)

	# --- Break: set scythe_broken (as d2 SummitBoss extra_flags does) ---
	_gs.set_flag("scythe_broken", true)
	_checks["flag_set"] = _gs.get_flag("scythe_broken", false)
	_checks["is_broken"] = ScytheBreak.is_broken(_gs)
	_checks["weapon_swapped"] = WeaponData.current_weapon(_gs) == "longsword"
	_checks["power_swapped"] = WeaponData.current_power(_gs) == "fairy"

	# --- Longsword moveset is the thinner, weaker one ---
	var entry: Dictionary = WeaponData.get_entry(
		WeaponData.current_weapon(_gs), WeaponData.current_power(_gs))
	_checks["longsword_entry"] = str(entry.get("name", "")) != ""
	_checks["longsword_weaker"] = float(entry.get("damage_mult", 1.0)) < 1.0
	_checks["longsword_faster"] = float(entry.get("swing1_time", 9.0)) < 0.35
	_checks["longsword_gold_arc"] = (entry.get("arc_color") as Color) == Color(1.0, 0.78, 0.35)

	# --- Longsword item granted (fallback when player lacks it) ---
	_checks["longsword_item"] = int(_gs.get_item_count("fathers_longsword")) >= 1

	# --- Achievement flag: scythe_broken maps to scythe_breaks ---
	_checks["achievement_fired"] = _gs.achievements.is_unlocked("scythe_breaks")

	# --- Idempotent: breaking again doesn't double-grant or crash ---
	var count_before: int = int(_gs.get_item_count("fathers_longsword"))
	ScytheBreak.on_break(_gs)
	_checks["idempotent_item"] = int(_gs.get_item_count("fathers_longsword")) == count_before
	_checks["idempotent_weapon"] = WeaponData.current_weapon(_gs) == "longsword"

	# --- Restoration: ch13_repowered (U3) clears the phase ---
	_gs.set_flag("ch13_repowered", true)
	_checks["broken_flag_cleared"] = not _gs.get_flag("scythe_broken", false)
	_checks["not_broken_after"] = not ScytheBreak.is_broken(_gs)
	_checks["scythe_restored"] = WeaponData.current_weapon(_gs) == "scythe"
	_checks["power_restored"] = WeaponData.current_power(_gs) == "armor"

	# --- Longsword stays as inventory keepsake (no combat function) ---
	_checks["keepsake_kept"] = int(_gs.get_item_count("fathers_longsword")) >= 1

	# --- Save/load preserves the broken state ---
	_gs.new_game()
	_gs.set_flag("scythe_broken", true)
	var saved: Dictionary = _gs.state.duplicate(true)
	# Simulate a load: fresh state, restore the saved dict.
	_gs.new_game()
	_gs.state = saved.duplicate(true)
	_checks["load_broken_flag"] = _gs.get_flag("scythe_broken", false)
	_checks["load_weapon"] = WeaponData.current_weapon(_gs) == "longsword"
	_checks["load_power"] = WeaponData.current_power(_gs) == "fairy"
	_checks["load_item"] = int(_gs.get_item_count("fathers_longsword")) >= 1


func _report() -> void:
	var fails: Array = []
	for key in _checks.keys():
		var ok: bool = _checks[key] == true
		print("[TEST] ", key, " = ", "PASS" if ok else "FAIL")
		if not ok:
			fails.append(key)
	if fails.is_empty():
		print("[TEST] ALL ", _checks.size(), " CHECKS PASSED")
	else:
		print("[TEST] FAILURES: ", fails)
