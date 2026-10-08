extends Node
## Data-driven cutscene player for Reaper's Reaper.
##
## NOTE: intentionally no class_name (project convention).
##
## Usage: add to the tree ROOT (so the fade survives scene changes), then:
##   play(steps, {"player": p, "luna": l, "camera": cam,
##                "dialogue_box": box, "game_state": gs})
##
## STEP REFERENCE (for story-side authoring — an Array of Dictionaries):
##
##   {"type": "letterbox", "on": true, "time": 0.5}
##       Cinematic bars slide in (on=true) or out (on=false).
##
##   {"type": "dialogue", "lines": [ ... ]}
##       Plays entries through the room's DialogueBox — the same entry
##       format DialogueParser produces (dialogue / direction / trigger /
##       choice dicts). Waits until the player advances through them all.
##       Placeholder lines are fine; the story bot swaps in canon later.
##
##   {"type": "move", "who": "player", "to": Vector2(300, 50), "time": 1.0}
##       Eased glide of a node to a world position. "who" accepts "player",
##       "luna", or a node name looked up in the current scene. (Arrays
##       like [300, 50] also work wherever a Vector2 is expected.)
##
##   {"type": "wait", "time": 1.0}
##       Hold for N seconds.
##
##   {"type": "camera", "to": Vector2(-600, 0), "time": 2.5}
##       Pan the player camera so it looks at a world point (measured from
##       the player's position when the step starts). Optional
##       "zoom": Vector2. {"type": "camera", "reset": true} goes home.
##       The camera always returns home when the cutscene ends.
##
##   {"type": "fade", "to": 1.0, "time": 0.8}
##       Fade the fullscreen black overlay to alpha `to` (0 = clear).
##
##   {"type": "trigger", "flag": "my_flag"}
##       Set a GameState flag instantly.
##
##   {"type": "sfx", "name": "tower_collapse"}
##       Placeholder: prints. Real audio hooks in later.
##
##   {"type": "rumble", "trauma": 0.7, "time": 1.2}
##       Camera trauma (screen shake) that plays out over `time` seconds.
##
##   {"type": "luna", "active": false}
##       Show/hide Luna for cutscene staging.
##
##   {"type": "scene", "path": "res://scenes/room_p3.tscn",
##                    "room": "p3", "spawn": Vector2(-1000, 200)}
##       Persist the spawn in GameState, emit cutscene_finished, change
##       scene, fade back in, then finish. Put it last: after the change,
##       player/camera/luna refs are stale.
##
## Skip: holding ui_cancel (Escape) for 1 second fast-forwards — remaining
## "trigger" / "luna" / "scene" steps are applied as if played, everything
## else is dropped, and cutscene_finished still fires.

signal cutscene_finished

const SKIP_HOLD_TIME: float = 1.0
const BAR_H: float = 90.0

## Executed step types, in order (tests + authoring debug).
var step_log: Array = []
## True once a "scene" step has run (headless dry-run sets this too).
var scene_step_reached: bool = false

var _steps: Array = []
var _idx: int = 0
var _playing: bool = false
var _done: bool = false
var _skipped: bool = false
var _skip_hold: float = 0.0
var _scene_changed: bool = false
var _post_t: float = 0.0
var _post_dur: float = 0.6
var _post_fade_from: float = 1.0

# Context (from play()).
var _player = null
var _luna = null
var _camera: Camera2D = null
var _box = null
var _gs = null

# Current-step state.
var _cur_type: String = ""
var _t: float = 0.0
var _dur: float = 0.0
var _waiting_dialogue: bool = false

# Scratch per step kind.
var _bar_h: float = 0.0
var _bar_from: float = 0.0
var _bar_to: float = 0.0
var _fade_a: float = 0.0
var _fade_from: float = 0.0
var _fade_to: float = 0.0
var _move_node: Node2D = null
var _move_from: Vector2 = Vector2.ZERO
var _move_to: Vector2 = Vector2.ZERO
var _luna_stash = null
var _cam_from: Vector2 = Vector2.ZERO
var _cam_to: Vector2 = Vector2.ZERO
var _zoom_from: Vector2 = Vector2.ONE
var _zoom_to: Vector2 = Vector2.ONE
var _cam_home_pos: Vector2 = Vector2.ZERO
var _cam_home_zoom: Vector2 = Vector2.ONE
var _luna_home_active: bool = true

# UI (children of self; self lives on the tree root).
var _chrome: CanvasLayer = null
var _bar_top: ColorRect = null
var _bar_bottom: ColorRect = null
var _skip_label: Label = null
var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null


func play(steps: Array, ctx: Dictionary) -> void:
	if _playing:
		push_warning("cutscene.gd: play() called while already playing")
		return
	_steps = steps
	_player = ctx.get("player")
	_luna = ctx.get("luna")
	_camera = ctx.get("camera") as Camera2D
	_box = ctx.get("dialogue_box")
	_gs = ctx.get("game_state")
	if _camera != null:
		_cam_home_pos = _camera.position
		_cam_home_zoom = _camera.zoom
	if _luna != null and "active" in _luna:
		_luna_home_active = bool(_luna.active)
	_build_ui()
	if _box != null and _box.has_signal("dialogue_finished"):
		if not _box.dialogue_finished.is_connected(_on_box_finished):
			_box.dialogue_finished.connect(_on_box_finished)
	# Lock the player down for the whole sequence. Re-asserted every
	# frame in _process (a mid-swing ScytheRig finishing would otherwise
	# clear move_locked underneath us).
	_lock_player(true)
	_idx = 0
	_playing = true
	_done = false
	_skipped = false
	add_to_group("cutscene")
	if _steps.is_empty():
		push_warning("cutscene.gd: empty step list")
		_finish()
		return
	_begin_step()


func _process(delta: float) -> void:
	if not _playing or _done:
		return
	# Post-scene-change fade-in: the UI survived on the tree root.
	if _scene_changed:
		_post_t += delta
		var p: float = clampf(_post_t / maxf(_post_dur, 0.01), 0.0, 1.0)
		_set_fade(lerpf(_post_fade_from, 0.0, p))
		if p >= 1.0:
			_teardown()
		return
	_lock_player(true)
	# Skip: hold ui_cancel.
	if Input.is_action_pressed("ui_cancel"):
		_skip_hold += delta
		if _skip_label != null:
			_skip_label.visible = _skip_hold > 0.25
		if _skip_hold >= SKIP_HOLD_TIME:
			_do_skip()
			return
	else:
		_skip_hold = 0.0
		if _skip_label != null:
			_skip_label.visible = false
	if _waiting_dialogue:
		return
	_t += delta
	_update_step()
	if _t >= _dur:
		_next_step()


func _lock_player(lock: bool) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	_player.move_locked = lock
	# input_locked is the cutscene guard added to player.gd; older or
	# foreign player nodes simply won't have it.
	if "input_locked" in _player:
		_player.input_locked = lock


# --- Step machinery -----------------------------------------------------

func _begin_step() -> void:
	if _idx >= _steps.size():
		_finish()
		return
	var s: Dictionary = _steps[_idx]
	_cur_type = str(s.get("type", ""))
	step_log.append(_cur_type)
	_t = 0.0
	_dur = maxf(float(s.get("time", 0.5)), 0.0)
	_waiting_dialogue = false
	match _cur_type:
		"letterbox":
			_bar_from = _bar_h
			_bar_to = BAR_H if bool(s.get("on", true)) else 0.0
			_dur = maxf(_dur, 0.01)
		"dialogue":
			_start_dialogue_step(s)
		"move":
			_start_move_step(s)
		"wait":
			pass
		"camera":
			_start_camera_step(s)
		"fade":
			_fade_from = _fade_a
			_fade_to = clampf(float(s.get("to", 1.0)), 0.0, 1.0)
			_dur = maxf(_dur, 0.01)
		"trigger":
			_apply_trigger(s)
			_next_step()
		"sfx":
			print("[SFX] ", str(s.get("name", "?")), " (placeholder — audio later)")
			_next_step()
		"rumble":
			_apply_rumble(s)
		"luna":
			_apply_luna(s)
			_next_step()
		"scene":
			_apply_scene_step(s)
		_:
			push_warning("cutscene.gd: unknown step type '" + _cur_type + "' — skipped")
			_next_step()


func _end_step_cleanup() -> void:
	# Restore Luna's follow target if a move step stashed it.
	if _luna_stash != null and is_instance_valid(_luna) and _luna.has_method("set_target"):
		_luna.set_target(_luna_stash)
	_luna_stash = null
	_move_node = null


func _next_step() -> void:
	_end_step_cleanup()
	_idx += 1
	_begin_step()


func _update_step() -> void:
	var p: float = _ease(clampf(_t / maxf(_dur, 0.001), 0.0, 1.0))
	match _cur_type:
		"letterbox":
			_bar_h = lerpf(_bar_from, _bar_to, p)
			_apply_bars()
		"move":
			if _move_node != null and is_instance_valid(_move_node):
				_move_node.global_position = _move_from.lerp(_move_to, p)
		"camera":
			if _camera != null and is_instance_valid(_camera):
				_camera.position = _cam_from.lerp(_cam_to, p)
				_camera.zoom = _zoom_from.lerp(_zoom_to, p)
		"fade":
			_set_fade(lerpf(_fade_from, _fade_to, p))
		# "wait" / "rumble": time passing is the effect.


func _ease(x: float) -> float:
	return x * x * (3.0 - 2.0 * x)


func _start_dialogue_step(s: Dictionary) -> void:
	var lines: Array = s.get("lines", [])
	if lines.is_empty():
		push_warning("cutscene.gd: dialogue step with no lines — skipped")
		_next_step()
		return
	if _box == null or not _box.has_method("start_dialogue"):
		push_warning("cutscene.gd: dialogue step with no dialogue box — skipped")
		_next_step()
		return
	_waiting_dialogue = true
	_box.start_dialogue(lines)


func _on_box_finished() -> void:
	if not _waiting_dialogue or _skipped:
		return
	_waiting_dialogue = false
	_next_step()


func _start_move_step(s: Dictionary) -> void:
	_move_node = _resolve_who(str(s.get("who", "player")))
	if _move_node == null:
		push_warning("cutscene.gd: move step could not resolve who='" + str(s.get("who", "")) + "'")
		_next_step()
		return
	_move_from = _move_node.global_position
	_move_to = _to_vec(s.get("to", _move_from))
	_dur = maxf(_dur, 0.01)
	# Luna's follow AI would fight a scripted move; park her target.
	if _move_node == _luna and _luna != null and _luna.has_method("set_target"):
		if _luna.has_method("get_target"):
			_luna_stash = _luna.get_target()
		_luna.set_target(null)


func _start_camera_step(s: Dictionary) -> void:
	if _camera == null or not is_instance_valid(_camera):
		push_warning("cutscene.gd: camera step with no camera — skipped")
		_next_step()
		return
	_dur = maxf(_dur, 0.01)
	_cam_from = _camera.position
	_zoom_from = _camera.zoom
	if bool(s.get("reset", false)):
		_cam_to = _cam_home_pos
		_zoom_to = _cam_home_zoom
		return
	_cam_to = _cam_from
	_zoom_to = _zoom_from
	if s.has("to"):
		var world: Vector2 = _to_vec(s["to"])
		var anchor: Vector2 = _camera.global_position
		var parent := _camera.get_parent()
		if parent is Node2D and parent != null:
			anchor = (parent as Node2D).global_position
		# Camera rides on the player; offset so it looks at `world`.
		_cam_to = world - anchor + _cam_home_pos
	if s.has("zoom"):
		_zoom_to = _to_vec(s["zoom"], _zoom_from)


func _apply_trigger(s: Dictionary) -> void:
	var flag := str(s.get("flag", ""))
	if flag == "":
		push_warning("cutscene.gd: trigger step with no flag")
		return
	if _gs != null and _gs.has_method("set_flag"):
		_gs.set_flag(flag)
	else:
		push_warning("cutscene.gd: trigger step with no game state")
	# Flag-based achievements (e.g. p2_collapse_seen -> collapse_seen).
	var ach = get_node_or_null("/root/Achievements")
	if ach != null and ach.has_method("unlock_for_flag"):
		ach.unlock_for_flag(flag)


func _apply_rumble(s: Dictionary) -> void:
	if _camera != null and is_instance_valid(_camera) and _camera.has_method("add_trauma"):
		_camera.add_trauma(clampf(float(s.get("trauma", 0.5)), 0.0, 1.0))
	else:
		push_warning("cutscene.gd: rumble step with no trauma-capable camera")
	# Controller vibration mirrors the trauma when the player enables it.
	# Headless/no-joypad: Input.start_joy_vibration is a safe no-op.
	var SettingsScript = load("res://scripts/settings.gd")
	var vib := true
	if SettingsScript != null and SettingsScript.has_method("vibration_enabled"):
		vib = SettingsScript.vibration_enabled()
	if vib:
		var strength := clampf(float(s.get("trauma", 0.5)), 0.0, 1.0)
		var duration := clampf(float(s.get("time", 1.0)), 0.1, 5.0)
		Input.start_joy_vibration(0, strength * 0.7, strength, duration)


func _apply_luna(s: Dictionary) -> void:
	if _luna != null and is_instance_valid(_luna) and _luna.has_method("set_active"):
		_luna.set_active(bool(s.get("active", true)))


func _apply_scene_step(s: Dictionary) -> void:
	var path := str(s.get("path", ""))
	var room_id := str(s.get("room", ""))
	var spawn := _to_vec(s.get("spawn", Vector2.ZERO))
	if room_id != "" and _gs != null and _gs.has_method("set_position"):
		_gs.set_position(room_id, spawn.x, spawn.y)
	scene_step_reached = true
	_playing = false  # no more steps; _process handles the fade-in.
	if path != "" and get_tree().current_scene != null:
		_scene_changed = true
		_post_t = 0.0
		_post_dur = 0.6
		_post_fade_from = _fade_a
		_playing = true  # keep _process alive for the fade-in.
		cutscene_finished.emit()
		get_tree().change_scene_to_file(path)
	else:
		# Headless / dry run: no live scene to change.
		# _finish() emits cutscene_finished exactly once.
		_finish()


func _resolve_who(who: String):
	if who == "player":
		return _player
	if who == "luna":
		return _luna
	var scene := get_tree().current_scene
	if scene != null:
		return scene.get_node_or_null(who)
	return null


func _to_vec(v, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if v is Vector2:
		return v
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return fallback


# --- Skip ---------------------------------------------------------------

func _do_skip() -> void:
	_skipped = true
	_waiting_dialogue = false
	if _box != null and _box.has_method("force_close"):
		_box.force_close()
	# Consequential steps land as if the cutscene played out.
	for i in range(_idx, _steps.size()):
		var s: Dictionary = _steps[i]
		match str(s.get("type", "")):
			"trigger":
				_apply_trigger(s)
			"luna":
				_apply_luna(s)
			"scene":
				_apply_scene_step(s)
	if not _scene_changed and not _done:
		_finish()


# --- Finish / teardown --------------------------------------------------

func _finish() -> void:
	if _done:
		return
	_done = true
	_playing = false
	_waiting_dialogue = false
	if is_instance_valid(_camera):
		_camera.position = _cam_home_pos
		_camera.zoom = _cam_home_zoom
	_lock_player(false)
	if is_instance_valid(_luna) and _luna.has_method("set_active"):
		_luna.set_active(_luna_home_active)
	cutscene_finished.emit()
	_teardown()


func _teardown() -> void:
	_playing = false
	remove_from_group("cutscene")
	queue_free()


## True while the sequence is running (used by room.gd to gate the
## pause menu — Esc is the cutscene skip hold, not a pause request).
func is_playing() -> bool:
	return _playing and not _done


# --- UI -----------------------------------------------------------------

func _build_ui() -> void:
	_chrome = CanvasLayer.new()
	_chrome.layer = 5  # below the dialogue box (10), above the world
	add_child(_chrome)
	_bar_top = ColorRect.new()
	_bar_top.color = Color.BLACK
	_bar_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_bar_top.offset_top = 0.0
	_bar_top.offset_bottom = 0.0
	_chrome.add_child(_bar_top)
	_bar_bottom = ColorRect.new()
	_bar_bottom.color = Color.BLACK
	_bar_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bar_bottom.offset_top = 0.0
	_bar_bottom.offset_bottom = 0.0
	_chrome.add_child(_bar_bottom)
	_skip_label = Label.new()
	_skip_label.text = "hold ESC to skip"
	_skip_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_skip_label.position = Vector2(-70, -130)
	_skip_label.add_theme_font_size_override("font_size", 16)
	_skip_label.modulate = Color(0.7, 0.7, 0.75, 0.8)
	_skip_label.visible = false
	_chrome.add_child(_skip_label)
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 30  # above everything, for transitions
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.modulate.a = 0.0
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)


func _apply_bars() -> void:
	if _bar_top != null:
		_bar_top.offset_bottom = _bar_h
	if _bar_bottom != null:
		_bar_bottom.offset_top = -_bar_h


func _set_fade(a: float) -> void:
	_fade_a = clampf(a, 0.0, 1.0)
	if _fade_rect != null:
		_fade_rect.modulate.a = _fade_a
