extends SceneTree
## Headless combat verification: swing starts -> hitbox connects -> dummy
## takes damage -> hitstop fires -> camera trauma added -> combo chains ->
## rig returns to idle and the player unlocks. No art, no rendering needed.
##
## Run: Godot --headless --path <project> -s res://scripts/combat_test.gd

const CombatTime = preload("res://scripts/combat_time.gd")

var _frame: int = 0
var _player = null
var _scythe = null
var _dummy = null
var _cam = null

var _swung: bool = false
var _combo_pressed: bool = false
var _hit_seen: bool = false
var _dummy_start_pos: Vector2 = Vector2.ZERO
var _checks: Dictionary = {}


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/player.tscn")
	_player = ps.instantiate()
	root.add_child(_player)
	_player.position = Vector2.ZERO
	_player.facing = Vector2.RIGHT
	_scythe = _player.get_node("ScytheRig")
	_cam = _player.get_node("Camera2D")

	var ds: PackedScene = load("res://scenes/dummy.tscn")
	_dummy = ds.instantiate()
	root.add_child(_dummy)
	_dummy.position = Vector2(130, 0)
	_dummy_start_pos = _dummy.position

	# Under -s, _ready() does not auto-fire for nodes added here.
	_scythe._ready()
	_dummy._ready()
	# camera_shake.gd has no _ready dependency (noise is lazy).

	_checks["input_scythe_has_pad"] = InputMap.action_get_events("scythe_swing").size() >= 3
	_checks["input_move_has_stick"] = InputMap.action_get_events("move_left").size() >= 3
	print("[TEST] setup: dummy hp=", _dummy.hp, " combat_time.scale=", CombatTime.scale)


func _physics_process(_delta: float) -> bool:
	_frame += 1

	# Frame 5: trigger the swing directly (same call the input action makes).
	if _frame == 5 and not _swung:
		_swung = true
		_scythe.try_swing()
		_checks["swing_started"] = _scythe.state == 1  # SWING1
		_checks["player_locked"] = _player.move_locked == true
		_checks["rig_rotated_to_facing"] = absf(_scythe.rotation) < 0.01

	# First damage: hitstop + shake must have fired with it.
	if _swung and not _hit_seen and _dummy.hp < _dummy.max_hp:
		_hit_seen = true
		_checks["hit_registered"] = true
		_checks["hitstop_fired"] = CombatTime.hitstop_count > 0
		_checks["shake_trauma_added"] = _cam.trauma > 0.0
		_checks["single_hit_per_swing"] = _dummy.hp == _dummy.max_hp - 1

	# Queue the combo once the swing is in its late window.
	if _swung and not _combo_pressed and _scythe.state == 1 and _scythe._swing_t >= 0.24:
		_combo_pressed = true
		_scythe.try_swing()
		_checks["combo_queued"] = _scythe._combo_queued == true

	if _combo_pressed and _scythe.state == 2 and not _checks.get("combo_chained", false):
		_checks["combo_chained"] = true
		# Spam guard: pressing during SWING2 must not restart or skip it.
		_scythe.try_swing()
		_checks["no_restart_mid_combo"] = _scythe.state == 2

	if _frame >= 400:
		_checks["returned_to_idle"] = _scythe.state == 0
		_checks["player_unlocked"] = _player.move_locked == false
		var dummy_alive: bool = is_instance_valid(_dummy)
		_checks["dummy_knocked_back"] = dummy_alive and _dummy.position.distance_to(_dummy_start_pos) > 5.0
		_checks["hitstop_released"] = CombatTime.scale == 1.0
		_report()
		return true
	if _frame > 2000:
		print("[TEST] TIMEOUT waiting for combat sequence")
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
