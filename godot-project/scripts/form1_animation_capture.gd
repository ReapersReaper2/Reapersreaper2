extends SceneTree
## Diagnostic studio: actual Player scene and runtime sprite manager.
## Poses are sampled at controlled times, not a real-time input playthrough.
## Separate rebirth_gameplay_capture verifies actual title/bridge/input flow.
const PlayerScene = preload("res://scenes/player.tscn")
const Clips = preload("res://scripts/form1_attack_clips.gd")
var output: String
var actor: Node
var manager: Node
var label: Label
var samples: Array = []
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DisplayServer.get_name() == "headless":
		push_error("Animation capture needs graphics and one output directory")
		quit(1)
		return
	output = args[0]
	root.size = Vector2i(512, 512)
	root.content_scale_size = Vector2i(512, 512)
	actor = PlayerScene.instantiate()
	root.add_child(actor)
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	manager = actor.sprites
	if manager._attack_clips.size() != 20 or not manager._canon_walk_active:
		push_error("Cannot capture delivery: required Form 1 art did not load")
		quit(1)
		return
	var camera: Camera2D = actor.get_node("Camera2D")
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2(2.5, 2.5)
	camera.reset_smoothing()
	camera.force_update_scroll()
	actor.get_node("TouchControls").visible = false
	var layer := CanvasLayer.new()
	root.add_child(layer)
	label = Label.new()
	label.position = Vector2(12, 8)
	label.add_theme_font_size_override("font_size", 14)
	layer.add_child(label)
	# Native 384px cells render at 0.4 actor scale * 2.5 camera zoom.
	var faces := [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]
	var dirs := ["front", "back", "side-l", "side-r"]
	for direction in range(4):
		var facing: Vector2 = faces[direction]
		manager._reset_mortal_sword_pose()
		manager.tick(0.0, facing, false)
		for frame in range(6):
			manager._walk_t = 0.0
			manager.tick((float(frame) + 0.1) / 10.0, facing, true)
			await _shot("walk-%s-%02d" % [dirs[direction], frame], facing)
		for action in [3, 1, 2, 4, 5]:
			manager._reset_mortal_sword_pose()
			var count := 8 if action == 4 else 6
			for frame in range(count):
				manager.set_mortal_sword_pose(action, (float(frame) + 0.1) / float(count), facing)
				await _shot("attack-%s-%d-%02d" % [dirs[direction], action, frame], facing)
	# Same direction change between phases exposes the baseline splice.
	manager._reset_mortal_sword_pose()
	manager.set_mortal_sword_pose(3, 0.5, Vector2.DOWN)
	await _shot("continuity-0-windup", Vector2.DOWN)
	manager.set_mortal_sword_pose(1, 0.5, Vector2.RIGHT)
	await _shot("continuity-1-strike", Vector2.RIGHT)
	manager.set_mortal_sword_pose(5, 0.5, Vector2.RIGHT)
	await _shot("continuity-2-recovery", Vector2.RIGHT)
	manager._reset_mortal_sword_pose()
	manager.tick(0.07, Vector2.RIGHT, true)
	manager.tick(0.0, Vector2.RIGHT, false)
	await _shot("gait-0-stop", Vector2.RIGHT)
	manager.tick(0.04, Vector2.RIGHT, true)
	await _shot("gait-1-restart", Vector2.RIGHT)
	var report := {"scenario": "form1-controlled-player-v1", "display": DisplayServer.get_name(),
		"renderer": RenderingServer.get_video_adapter_name(), "samples": samples, "failures": failures}
	var file := FileAccess.open(output.path_join("animation-trace.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	actor.free()
	layer.free()
	print("FORM1_ANIMATION_CAPTURE_COMPLETE frames=%d failures=%d" % [samples.size(), failures])
	quit(0 if failures == 0 else 1)

func _shot(name: String, requested: Vector2) -> void:
	var art: Sprite2D = manager._sprite
	var source := "unknown"
	for key in manager._attack_clips:
		if manager._attack_clips[key].texture == art.texture:
			source = "approved/" + key
	for key in manager._strips:
		if manager._strips[key] is Texture2D and manager._strips[key] == art.texture:
			source = "canon_walk/" + key
	label.text = name + "\n" + source + "  frame=" + str(int(art.region_rect.position.x / 384.0))
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.save_png(output.path_join(name + ".png")) != OK:
		push_error("Capture write failed: " + name)
		failures += 1
	samples.append({"name": name, "source": source, "texture_class": art.texture.get_class(),
		"frame": int(art.region_rect.position.x / 384.0), "approved": manager._approved_attack_active,
		"requested_facing": [requested.x, requested.y],
		"committed_facing": [manager._approved_facing.x, manager._approved_facing.y],
		"walk_clock": manager._walk_t, "scale": [art.scale.x, art.scale.y],
		"position": [art.position.x, art.position.y], "shader": art.material != null})
