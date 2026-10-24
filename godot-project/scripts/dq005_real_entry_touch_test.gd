extends SceneTree
## DQ-005: title-screen -> NEW GAME -> physical-style HUD touch events.
## No bridge teleport, direct rig _start_swing, or forced clip activation.
var _failed := false

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, message: String) -> void:
	print("[DQ005_REAL_ENTRY] ", "PASS " if condition else "FAIL ", message)
	if not condition:
		_failed = true

func _run() -> void:
	ProjectSettings.set_setting("reaper/force_touch_controls", true)
	var title_scene: PackedScene = load("res://scenes/title_screen.tscn")
	_check(title_scene != null, "title resource")
	if title_scene == null:
		quit(2)
		return
	var title := title_scene.instantiate()
	root.add_child(title)
	current_scene = title
	await process_frame
	_check(title.has_method("_on_item_pressed"), "title NEW GAME control present")
	title._on_item_pressed("new")
	await process_frame
	await process_frame
	var room := current_scene
	_check(room != null and room.scene_file_path.ends_with("room_p1.tscn"), "NEW GAME selected real bridge entry")
	if room == null:
		quit(2)
		return
	var player := room.find_child("Player", true, false)
	_check(player != null, "real scene Player instance")
	if player == null:
		quit(2)
		return
	var controls := player.get_node_or_null("TouchControls")
	var overlay = controls.get("overlay") if controls != null else null
	_check(overlay != null, "mobile touch HUD available")
	if overlay == null:
		quit(2)
		return
	var sprites = player.get("sprites")
	var rig = player.get_node_or_null("ScytheRig")
	_check(sprites != null and rig != null, "real Player sprite and rig")
	if sprites == null or rig == null:
		quit(2)
		return
	var clips: int = sprites._attack_clips.size()
	print("[DQ005_REAL_ENTRY] clips=", clips, " form=", sprites._form, " native_os=", OS.get_name())
	var action_center: Vector2 = overlay._attack_center()
	var tap := InputEventScreenTouch.new()
	tap.index = 0
	tap.position = action_center
	tap.pressed = true
	overlay._input(tap)
	await process_frame
	_check(rig.is_charging(), "touch press entered charge via HUD and Player input")
	var release := InputEventScreenTouch.new()
	release.index = 0
	release.position = action_center
	release.pressed = false
	overlay._input(release)
	await process_frame
	_check(int(rig.state) == 1 or int(rig.state) == 3, "touch release dispatched combat state")
	var saw_approved := false
	var saw_fallback := false
	var frames_seen := {}
	for i in range(40):
		await physics_frame
		var state_value := int(rig.state)
		if state_value == 1 or state_value == 2 or state_value == 4:
			saw_approved = saw_approved or bool(sprites._approved_attack_active)
			saw_fallback = saw_fallback or bool(sprites._mortal_pose_active)
			frames_seen[int(sprites._sprite.region_rect.position.x / 384.0)] = true
	print("[DQ005_REAL_ENTRY] swings approved=", saw_approved, " fallback=", saw_fallback, " frame_count=", frames_seen.size(), " clips=", clips)
	_check(clips == 20, "all 20 approved attack strips present")
	_check(saw_approved and not saw_fallback, "real entry + touch dispatch stays approved through swing")
	_check(frames_seen.size() > 1, "real swing advances painted frames")
	quit(1 if _failed else 0)
