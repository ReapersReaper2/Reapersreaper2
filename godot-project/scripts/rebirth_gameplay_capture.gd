extends SceneTree
## Explicit diagnostic entry only; never loaded by normal gameplay.
## Real title -> New Game -> bridge, input-driven movement and sword attack.
var output: String
var events: Array = []
var failures: int = 0

func _initialize() -> void:
	seed(20261027)
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DisplayServer.get_name() == "headless":
		push_error("Capture requires a graphical renderer and one output directory")
		quit(1)
		return
	output = args[0]
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/title_screen.tscn")
	await _frames(30)
	await _shot("00-title")
	_input("ui_accept", true)
	await _frames(1)
	_input("ui_accept", false)
	await _frames(60)
	if current_scene == null or current_scene.scene_file_path != "res://scenes/room_p1.tscn":
		push_error("New Game did not reach the real bridge")
		quit(1)
		return
	var player := current_scene.get_node("Player") as CharacterBody2D
	var start := player.position
	await _shot("01-bridge-idle")
	_input("move_right", true)
	await _frames(30)
	await _shot("02-bridge-walk")
	_input("move_right", false)
	await _frames(2)
	if player.position.distance_to(start) < 10.0:
		push_error("Movement input did not move the real player")
		failures += 1
	_input("scythe_swing", true)
	await _frames(2)
	_input("scythe_swing", false)
	var active_attack := false
	var approved_seen := false
	for i in range(24):
		await _frames(2)
		var rig = player.get_node("ScytheRig")
		if int(rig.get("state")) != 0:
			active_attack = true
		var manager = player.sprites
		approved_seen = approved_seen or manager._approved_attack_active
		if int(rig.get("state")) != 0 and not manager._approved_attack_active:
			push_error("Live sword action selected fallback instead of approved art")
			failures += 1
		events.append({"attack_sample": i, "state": rig.get("state"),
			"approved": manager._approved_attack_active, "clips": manager._attack_clips.size(),
			"frame": int(manager._sprite.region_rect.position.x / 384.0),
			"position": [player.position.x, player.position.y]})
		await _shot("attack-%02d" % i)
	if not active_attack or not approved_seen:
		push_error("Sword input did not activate the real attack rig")
		failures += 1
	var file := FileAccess.open(output.path_join("input-trace.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"seed": 20261027, "scene": current_scene.scene_file_path, "renderer": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name(), "events": events, "failures": failures}, "\t"))
	file.close()
	if failures == 0:
		print("REBIRTH_CAPTURE_COMPLETE")
	quit(0 if failures == 0 else 1)

func _input(action: String, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	events.append({"physics_frame": Engine.get_physics_frames(), "action": action, "pressed": pressed})

func _frames(count: int) -> void:
	for i in range(count):
		await physics_frame

func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(output.path_join(label + ".png")) != OK:
		push_error("Could not save frame " + label)
		failures += 1
