extends Node
## DQ-005 packed-Android real-entry reproduction. Candidate diagnostics only.
## CI opts in via project setting. Ordinary operator APKs do not auto-play.
var _elapsed := 0.0
var _started := false
var _finished := false

func _ready() -> void:
	if not OS.has_feature("android"):
		return
	_add_trace_button()
	DQ005Trace.record("ANDROID_PROBE_READY", "auto_real_entry=" + str(_is_auto()))
	if _is_auto():
		call_deferred("_real_entry")

func _is_auto() -> bool:
	return bool(ProjectSettings.get_setting("reaper/dq005_auto_real_entry", false))

func _real_entry() -> void:
	var scene := get_tree().current_scene
	DQ005Trace.record("ENTRY_START", "scene=" + str(scene.scene_file_path if scene != null else "<null>"))
	if scene == null or not scene.has_method("activate"):
		DQ005Trace.record("ENTRY_REJECT", "title scene or activate() not available")
		return
	scene.activate("new")
	_started = true

func _process(delta: float) -> void:
	if not _is_auto() or not _started or _finished:
		return
	_elapsed += delta
	if _elapsed < 2.5:
		return
	_finished = true
	call_deferred("_exercise_real_touch")

func _exercise_real_touch() -> void:
	var scene := get_tree().current_scene
	var player := scene.find_child("Player", true, false) if scene != null else null
	if player == null:
		DQ005Trace.record("ENTRY_REJECT", "Player absent after NEW GAME")
		return
	var mgr = player.get("sprites")
	var rig = player.get_node_or_null("ScytheRig")
	var controls = player.get_node_or_null("TouchControls")
	var overlay = controls.get("overlay") if controls != null else null
	if mgr == null or rig == null or overlay == null:
		DQ005Trace.record("ENTRY_REJECT", "Player sprite/rig/MobileHUD missing")
		return
	var count: int = mgr._attack_clips.size()
	DQ005Trace.record("BRIDGE_READY", "from_title=true form=%s clips=%s" % [mgr._form, count])
	var point: Vector2 = overlay._attack_center()
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.position = point
	down.pressed = true
	overlay._input(down)
	await get_tree().process_frame
	DQ005Trace.record("TOUCH_DOWN", "charging=" + str(rig.is_charging()))
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.position = point
	up.pressed = false
	overlay._input(up)
	await get_tree().process_frame
	DQ005Trace.record("TOUCH_UP", "state=" + str(rig.state))
	var painted := false
	var fallback := false
	var frames := {}
	for n in range(40):
		await get_tree().physics_frame
		if int(rig.state) in [1, 2, 4]:
			painted = painted or bool(mgr._approved_attack_active)
			fallback = fallback or bool(mgr._mortal_pose_active)
			frames[int(mgr._sprite.region_rect.position.x / 384.0)] = true
	DQ005Trace.record("BRIDGE_SWING", "real_entry=true approved=%s fallback=%s unique_frames=%s clips=%s" % [painted, fallback, frames.size(), count])

func _add_trace_button() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 110
	layer.name = "DQ005ExportOverlay"
	add_child(layer)
	var button := Button.new()
	button.text = "EXPORT TRACE FILE"
	button.custom_minimum_size = Vector2(205, 64)
	button.anchor_left = 1.0
	button.anchor_right = 1.0
	button.offset_left = -250.0
	button.offset_right = -12.0
	button.offset_top = 12.0
	button.offset_bottom = 76.0
	layer.add_child(button)
	button.pressed.connect(_share_trace)

func _share_trace() -> void:
	DQ005Trace.record("EXPORT_TAP", "operator requested handoff")
	if not DQ005Trace.export_native():
		DQ005Trace.record("EXPORT_FALLBACK", "native sharing unavailable")
		if not DQ005Trace.export_via_email():
			DQ005Trace.record("EXPORT_FAILED", "no mail handler")
