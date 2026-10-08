extends SceneTree
## Headless cutscene verification: step order, player locks, camera pan +
## restore, letterbox, fade, rumble, Luna staging, trigger flags, skip
## (hold ui_cancel), the P2 scene-step dry run, and the P2 data contract.
##
## Run: Godot --headless --path <project> -s res://scripts/cutscene_test.gd

const CutsceneScript = preload("res://scripts/cutscene.gd")
const GameStateScript = preload("res://scripts/game_state.gd")
const CutsceneP2 = preload("res://scripts/cutscene_p2.gd")

const EXPECTED: Array = [
	"a_player_locked", "a_step_order", "a_player_moved", "a_camera_panned",
	"a_camera_restored", "a_fade_peaked", "a_fade_cleared",
	"a_letterbox_peaked", "a_bars_gone", "a_trigger_flag", "a_luna_toggled",
	"a_rumble", "a_unlocked",
	"b_skip_finished", "b_skip_flag", "b_skip_unlocked", "b_skip_hold_used",
	"c_scene_reached", "c_gs_position",
	"d_p2_step_count", "d_p2_has_collapse_flag", "d_p2_scene_targets_p3",
]

var _frame: int = 0
var _phase: int = 0  # 0=setup 1=A 2=B 3=C 4=done
var _player = null
var _luna = null
var _box = null
var _cam = null
var _gs = null
var _cs = null
var _checks: Dictionary = {}

# Subtest A sampling.
var _max_fade: float = 0.0
var _max_bar: float = 0.0
var _max_trauma: float = 0.0
var _cam_mid: Vector2 = Vector2.ZERO
var _cam_mid_seen: bool = false
var _luna_hidden_seen: bool = false

# Subtest B sampling.
var _skip_pressed: bool = false
var _skip_frames: int = 0


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/player.tscn")
	_player = ps.instantiate()
	root.add_child(_player)
	_player.position = Vector2(100, 50)
	_cam = _player.get_node("Camera2D")

	var ls: PackedScene = load("res://scenes/luna.tscn")
	_luna = ls.instantiate()
	root.add_child(_luna)
	_luna.position = Vector2(60, 70)
	_luna.set_target(_player)

	var bs: PackedScene = load("res://scenes/dialogue_box.tscn")
	_box = bs.instantiate()
	root.add_child(_box)
	_wire_box()

	_gs = GameStateScript.new()
	_gs.new_game()  # pure static default; avoids the /root/SaveSystem lookup
	print("[TEST] setup: player at ", _player.position, " cam=", _cam.name)


func _wire_box() -> void:
	# @onready vars are not set when _ready() is invoked manually, so wire
	# them explicitly (harmless if the engine also runs _ready later).
	_box._panel = _box.get_node("Panel")
	_box._name_label = _box.get_node("Panel/Margin/VBox/NameLabel")
	_box._portrait_label = _box.get_node("Panel/Margin/VBox/HBox/Portrait/InitialLabel")
	_box._text_label = _box.get_node("Panel/Margin/VBox/HBox/TextLabel")
	_box._hint_label = _box.get_node("Panel/Margin/VBox/HintLabel")
	_box._choice_box = _box.get_node("Panel/Margin/VBox/ChoiceBox")
	_box._ready()
	_box.chars_per_second = 100000.0  # instant typewriter for the test


func _ctx() -> Dictionary:
	return {"player": _player, "luna": _luna, "camera": _cam,
			"dialogue_box": _box, "game_state": _gs}


func _physics_process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2 and _phase == 0:
		_start_a()
	elif _phase == 1:
		_drive_a()
	elif _phase == 2:
		_drive_b()
	if _phase == 4:
		return true
	if _frame > 2000:
		print("[TEST] TIMEOUT waiting for cutscene sequence")
		_report()
		return true
	return false


# --- Subtest A: full playthrough -----------------------------------------

func _start_a() -> void:
	_phase = 1
	_cs = CutsceneScript.new()
	root.add_child(_cs)
	_cs.cutscene_finished.connect(_on_a_finished)
	_cs.play([
		{"type": "letterbox", "on": true, "time": 0.2},
		{"type": "dialogue", "lines": [
			{"type": "dialogue", "character": "TEST", "text": "Line one."},
			{"type": "direction", "text": "A beat."},
		]},
		{"type": "move", "who": "player", "to": Vector2(300, 50), "time": 0.5},
		{"type": "camera", "to": Vector2(200, 100), "time": 0.5},
		{"type": "wait", "time": 0.3},
		{"type": "rumble", "trauma": 0.5, "time": 0.3},
		{"type": "sfx", "name": "test_sfx"},
		{"type": "luna", "active": false},
		{"type": "wait", "time": 0.2},
		{"type": "luna", "active": true},
		{"type": "fade", "to": 1.0, "time": 0.2},
		{"type": "fade", "to": 0.0, "time": 0.2},
		{"type": "trigger", "flag": "cs_test_flag"},
		{"type": "letterbox", "on": false, "time": 0.2},
	], _ctx())


func _drive_a() -> void:
	if _cs == null or not is_instance_valid(_cs):
		return
	# Drive the dialogue step like a player mashing E.
	if _cs._waiting_dialogue and not _box._typing:
		_box.advance()
	_max_fade = maxf(_max_fade, _cs._fade_a)
	_max_bar = maxf(_max_bar, _cs._bar_h)
	_max_trauma = maxf(_max_trauma, _cam.trauma)
	if not _cam_mid_seen and not _cs.step_log.is_empty() and _cs.step_log.back() == "wait":
		_cam_mid_seen = true
		_cam_mid = _cam.position
	if not _luna_hidden_seen and not _luna.visible:
		_luna_hidden_seen = true
	if _frame == 12:
		_checks["a_player_locked"] = _player.move_locked and _player.input_locked


func _on_a_finished() -> void:
	var order: Array = _cs.step_log.duplicate()
	_checks["a_step_order"] = order == ["letterbox", "dialogue", "move", "camera",
		"wait", "rumble", "sfx", "luna", "wait", "luna", "fade", "fade", "trigger", "letterbox"]
	_checks["a_player_moved"] = _player.position.distance_to(Vector2(300, 50)) < 6.0
	_checks["a_camera_panned"] = _cam_mid_seen and _cam_mid.x < -50.0
	_checks["a_camera_restored"] = _cam.position.distance_to(Vector2.ZERO) < 0.5
	_checks["a_fade_peaked"] = _max_fade > 0.9
	_checks["a_fade_cleared"] = _cs._fade_a < 0.05
	_checks["a_letterbox_peaked"] = _max_bar > 80.0
	_checks["a_bars_gone"] = _cs._bar_h < 0.5
	_checks["a_trigger_flag"] = _gs.get_flag("cs_test_flag")
	_checks["a_luna_toggled"] = _luna_hidden_seen and _luna.visible
	_checks["a_rumble"] = _max_trauma > 0.1
	_checks["a_unlocked"] = (not _player.move_locked) and (not _player.input_locked)
	_start_b()


# --- Subtest B: skip ------------------------------------------------------

func _start_b() -> void:
	_phase = 2
	_cs = CutsceneScript.new()
	root.add_child(_cs)
	_cs.cutscene_finished.connect(_on_b_finished)
	_cs.play([
		{"type": "wait", "time": 30.0},
		{"type": "letterbox", "on": true, "time": 0.2},
		{"type": "trigger", "flag": "cs_skip_flag"},
	], _ctx())


func _drive_b() -> void:
	if not _skip_pressed:
		_skip_pressed = true
		Input.action_press("ui_cancel")
		_skip_frames = 0
	else:
		_skip_frames += 1


func _on_b_finished() -> void:
	Input.action_release("ui_cancel")
	_checks["b_skip_finished"] = true
	_checks["b_skip_flag"] = _gs.get_flag("cs_skip_flag")
	_checks["b_skip_unlocked"] = (not _player.move_locked) and (not _player.input_locked)
	_checks["b_skip_hold_used"] = _skip_frames >= 50
	_start_c()


# --- Subtest C: scene-step dry run ----------------------------------------

func _start_c() -> void:
	_phase = 3
	Input.action_release("ui_cancel")
	_cs = CutsceneScript.new()
	root.add_child(_cs)
	_cs.cutscene_finished.connect(_on_c_finished)
	# Array spawn exercises the _to_vec array path; current_scene is null
	# under -s, so the scene change itself dry-runs.
	_cs.play([
		{"type": "fade", "to": 1.0, "time": 0.05},
		{"type": "scene", "path": "res://scenes/room_p3.tscn",
			"room": "p3", "spawn": [-1000, 200]},
	], _ctx())


func _on_c_finished() -> void:
	_checks["c_scene_reached"] = _cs.scene_step_reached == true
	var pos: Dictionary = _gs.get_position()
	_checks["c_gs_position"] = str(pos.get("room", "")) == "p3" \
		and float(pos.get("x", 0.0)) == -1000.0 \
		and float(pos.get("y", 0.0)) == 200.0
	_check_p2_data()
	_phase = 4
	_report()


# --- Subtest D: P2 data contract ------------------------------------------

func _check_p2_data() -> void:
	var steps: Array = CutsceneP2.steps()
	_checks["d_p2_step_count"] = steps.size() == 11
	var saw_flag := false
	var saw_scene := false
	var scene_ok := false
	for s in steps:
		var t := str((s as Dictionary).get("type", ""))
		if t == "trigger" and str((s as Dictionary).get("flag", "")) == "p2_collapse_seen":
			saw_flag = true
		if t == "scene":
			saw_scene = true
			scene_ok = str((s as Dictionary).get("path", "")) == "res://scenes/room_p3.tscn" \
				and str((s as Dictionary).get("room", "")) == "p3"
	_checks["d_p2_has_collapse_flag"] = saw_flag
	_checks["d_p2_scene_targets_p3"] = saw_scene and scene_ok


# --- Report ---------------------------------------------------------------

func _report() -> void:
	var fails: Array = []
	for key in EXPECTED:
		var ok: bool = _checks.get(key, false) == true
		print("[TEST] ", key, " = ", "PASS" if ok else "FAIL")
		if not ok:
			fails.append(key)
	if fails.is_empty():
		print("[TEST] ALL ", EXPECTED.size(), " CHECKS PASSED")
	else:
		print("[TEST] FAILURES: ", fails)
		quit(1)
