extends Node
## DQ-005 instrumented Android reproduction — diagnostic branch ONLY.
## Does not change the loader, approval rules, attack timing or animations.
var _elapsed: float = 0.0
var _done: bool = false

func _ready() -> void:
	if OS.has_feature("android"):
		_add_trace_button()
		print("[DQ005_ANDROID] boot platform=", OS.get_name())
		call_deferred("_enter_bridge")

func _enter_bridge() -> void:
	print("[DQ005_ANDROID] switching to opening bridge")
	var err := get_tree().change_scene_to_file("res://scenes/room_p1.tscn")
	print("[DQ005_ANDROID] change_scene status=", err)

func _process(delta: float) -> void:
	if not OS.has_feature("android") or _done:
		return
	_elapsed += delta
	if _elapsed < 2.5:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var player := scene.find_child("Player", true, false)
	if player == null:
		if _elapsed > 20.0:
			_done = true
			push_error("[DQ005_ANDROID] no Player node after 20 seconds")
		return
	_done = true
	var mgr = player.get("sprites")
	if mgr == null:
		push_error("[DQ005_ANDROID] Player has no sprite manager")
		return
	var clip_count: int = mgr._attack_clips.size()
	print("[DQ005_ANDROID] bridge form=", mgr._form, " clips=", clip_count)

	# Exercise the EXACT Player -> rig -> sprite-manager path used by a swing,
	# not just Form1AttackClips.sample() or a direct _try_approved_attack() call.
	player.facing = Vector2.DOWN
	mgr.tick(0.0, Vector2.DOWN, true)
	var rig = player.get_node_or_null("ScytheRig")
	if rig == null:
		push_error("[DQ005_ANDROID] Missing ScytheRig in bridge")
		return
	rig._start_swing(1)
	var seen: Dictionary = {}
	var all_painted: bool = true
	var sample_tex: Texture2D = mgr._attack_clips["slash_front"]["texture"] if clip_count == 20 else null
	var frames: int = int(ceilf(rig._swing_duration() * 60.0))
	for n in range(frames):
		rig._swing_t = float(n) / 60.0
		player._physics_process(0.0)
		var frame_id := int(mgr._sprite.region_rect.position.x / 384.0)
		seen[frame_id] = true
		var is_painted: bool = (mgr._approved_attack_active and
				mgr._sprite.texture == sample_tex and
				mgr._sprite.material == null and
				not mgr._mortal_blade_sprite.visible)
		if not is_painted:
			print("[DQ005_ANDROID] fallback at swing step=", n,
				" frame=", frame_id, " approved=", mgr._approved_attack_active,
				" material=", mgr._sprite.material,
				" blade_visible=", mgr._mortal_blade_sprite.visible)
			all_painted = false
	print("[DQ005_ANDROID] real bridge swing painted=", all_painted,
		" unique_frames=", seen.size(), " clips=", clip_count)
	print("[DQ005_ANDROID] RESULT ", "PASS" if all_painted and seen.size() > 1 and clip_count == 20 else "FAIL")

func _add_trace_button() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 110
	layer.name = "DQ005ExportOverlay"
	add_child(layer)
	var button := Button.new()
	button.text = "SEND DQ005 TRACE"
	button.custom_minimum_size = Vector2(205, 64)
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.position = Vector2(1020, 10)
	layer.add_child(button)
	button.pressed.connect(_share_trace)

func _share_trace() -> void:
	DQ005Trace.record("EXPORT_TAP", "operator requested handoff")
	if not DQ005Trace.export_via_email():
		DQ005Trace.record("EXPORT_FAILED", "no mail handler or trace file")
