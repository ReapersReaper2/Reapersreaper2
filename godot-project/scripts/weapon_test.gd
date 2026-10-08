extends SceneTree
## Headless weapon-system verification: data table lookups, fallback,
## unlock persistence via GameState, and scythe.gd picking up the equipped
## (weapon, power) pair at swing start. No art, no rendering needed.
##
## Run: Godot --headless --path <project> -s res://scripts/weapon_test.gd

const WeaponData = preload("res://scripts/weapon_data.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const CombatTime = preload("res://scripts/combat_time.gd")

var _frame: int = 0
var _gs = null
var _player = null
var _scythe = null
var _dummy = null
var _dummy_hp0: int = 0
var _checks: Dictionary = {}
var _swung: bool = false


func _initialize() -> void:
	# In -s runs the real autoloads are present under /root — use the live
	# GameState so the scythe's own /root/GameState lookup hits this exact
	# state (adding a second node would shadow it and desync the test).
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		_gs = GameStateScript.new()
		_gs.name = "GameState"
		root.add_child(_gs)
		_gs._ready()  # doesn't auto-fire under -s; builds the default save.
	else:
		_gs.new_game()  # reset the autoload to a known state.

	# --- Table lookups (synchronous) ---
	var base: Dictionary = WeaponData.get_entry("scythe", "armor")
	_checks["base_swing1"] = is_equal_approx(float(base["swing1_time"]), 0.35)
	_checks["base_damage"] = is_equal_approx(float(base["damage_mult"]), 1.0)
	_checks["base_hitstop"] = is_equal_approx(float(base["hitstop_duration"]), 0.07)

	var fairy: Dictionary = WeaponData.get_entry("longsword", "fairy")
	_checks["fairy_faster"] = float(fairy["swing1_time"]) < float(base["swing1_time"])
	_checks["fairy_softer"] = float(fairy["damage_mult"]) < float(base["damage_mult"])
	_checks["fairy_warmer_arc"] = (fairy["arc_color"] as Color) != (base["arc_color"] as Color)

	var tail: Dictionary = WeaponData.get_entry("scythe_tail", "armor")
	_checks["tail_heavier"] = float(tail["damage_mult"]) > float(base["damage_mult"])
	_checks["tail_bigger_arc"] = float(tail["arc_radius"]) > float(base["arc_radius"])

	var bloom: Dictionary = WeaponData.get_entry("scythe_tail", "bloom")
	_checks["bloom_endgame"] = float(bloom["damage_mult"]) >= 1.6

	var unknown: Dictionary = WeaponData.get_entry("scythe", "void")
	_checks["unknown_falls_back"] = is_equal_approx(float(unknown["swing1_time"]), 0.35)

	_checks["ids_listed"] = WeaponData.weapon_ids().has("longsword") and WeaponData.power_ids().has("fairy")

	# --- Unlock persistence ---
	_checks["scythe_unlocked_by_default"] = WeaponData.is_unlocked(_gs, "scythe")
	WeaponData.unlock(_gs, "longsword")
	_checks["unlock_persists"] = WeaponData.is_unlocked(_gs, "longsword")
	WeaponData.unlock(_gs, "not_a_weapon")
	_checks["unknown_unlock_refused"] = not WeaponData.is_unlocked(_gs, "not_a_weapon")

	# --- Current weapon/power defaults ---
	_checks["default_weapon"] = WeaponData.current_weapon(_gs) == "scythe"
	_checks["default_power"] = WeaponData.current_power(_gs) == "armor"
	WeaponData.set_current(_gs, "longsword", "fairy")
	_checks["set_current"] = WeaponData.current_weapon(_gs) == "longsword" and WeaponData.current_power(_gs) == "fairy"

	# --- Scythe integration: swing picks up longsword/fairy numbers ---
	var ps: PackedScene = load("res://scenes/player.tscn")
	_player = ps.instantiate()
	root.add_child(_player)
	_player.position = Vector2.ZERO
	_player.facing = Vector2.RIGHT
	_scythe = _player.get_node("ScytheRig")
	_scythe._ready()  # doesn't auto-fire under -s.

	var ds: PackedScene = load("res://scenes/dummy.tscn")
	_dummy = ds.instantiate()
	root.add_child(_dummy)
	_dummy.position = Vector2(130, 0)
	_dummy._ready()
	_dummy_hp0 = _dummy.hp


func _physics_process(_delta: float) -> bool:
	_frame += 1

	if _frame == 5 and not _swung:
		_swung = true
		_scythe.try_swing()
		_checks["swing_uses_fairy_entry"] = is_equal_approx(float(_scythe._entry["swing1_time"]), 0.28)
		_checks["swing_fairy_arc_color"] = (_scythe._entry["arc_color"] as Color) == Color(1.0, 0.78, 0.35)

	# Dummy should take exactly 1 damage (0.7 mult rounds to 1) — and the
	# swing must not crash with a non-baseline entry active.
	if _swung and _dummy.hp < _dummy_hp0 and not _checks.get("dummy_damaged", false):
		_checks["dummy_damaged"] = true
		_checks["damage_scales_down"] = _dummy.hp == _dummy_hp0 - 1
		_checks["hitstop_fired"] = CombatTime.hitstop_count > 0

	if _frame >= 300:
		_checks["swing_completed"] = _scythe.state == 0
		_report()
		return true
	if _frame > 2000:
		print("[TEST] TIMEOUT waiting for weapon swing")
		_report()
		return true
	return false


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
		quit(1)
