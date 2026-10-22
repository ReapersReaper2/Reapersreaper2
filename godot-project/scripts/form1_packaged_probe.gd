extends SceneTree
## DQ-005: run ONLY from an exported .pck outside the source checkout.
const Clips := preload("res://scripts/form1_attack_clips.gd")
const Loader := preload("res://scripts/critical_sprite_loader.gd")
const PlayerScene := preload("res://scenes/player.tscn")

func _initialize() -> void:
	call_deferred("_probe")

func _probe() -> void:
	var path := Clips.MANIFEST_PATH
	print("[FORM1_PACKED] probe executable res=" + ProjectSettings.globalize_path("res://"))
	print("[FORM1_PACKED] manifest FileAccess.exists=" + str(FileAccess.file_exists(path)) +
		" ResourceLoader.exists=" + str(ResourceLoader.exists(path)))
	if FileAccess.file_exists(path):
		var json := FileAccess.get_file_as_string(path)
		var parsed: Variant = JSON.parse_string(json)
		print("[FORM1_PACKED] json bytes=" + str(json.length()) + " parsed dictionary=" + str(parsed is Dictionary))
		if parsed is Dictionary:
			print("[FORM1_PACKED] status=" + str(parsed.get("status")) + " entry_count=" + str(parsed.get("strips", {}).size()))
			for key in Clips.required_keys():
				var entry: Dictionary = parsed.get("strips", {}).get(key, {})
				if entry.is_empty():
					print("[FORM1_PACKED] missing entry " + key)
					continue
				var texpath := str(entry.get("texture", ""))
				print("[FORM1_PACKED] " + key + " raw=" + str(FileAccess.file_exists(texpath)) +
					" resource=" + str(ResourceLoader.exists(texpath)))
	var clips := Clips.load_approved(Callable(Loader, "load_texture"))
	print("[FORM1_PACKED] loaded_count=" + str(clips.size()))
	if clips.size() != 20:
		printerr("[FORM1_PACKED] FAIL: full set rejected in export")
		quit(1)
		return
	var actor := PlayerScene.instantiate()
	root.add_child(actor)
	var mgr = actor.sprites
	print("[FORM1_PACKED] actor_clips=" + str(mgr._attack_clips.size()))
	var ok: bool = mgr._attack_clips.size() == 20
	for facing in [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]:
		for action in [1, 2, 3, 4, 5]:
			mgr.set_mortal_sword_pose(action, 0.5, facing)
			var sample: Dictionary = Clips.sample(clips, action, 0.5, facing)
			var display_ok: bool = mgr._sprite.texture == sample.get("texture") and not mgr._mortal_blade_sprite.visible
			if not display_ok:
				print("[FORM1_PACKED] bad painted frame action=" + str(action) + " facing=" + str(facing))
			ok = ok and display_ok
		mgr.set_mortal_sword_pose(0, 0, facing)
	print("[FORM1_PACKED] " + ("PASS" if ok else "FAIL") + " all 20 clips loaded, 20 painted pose samples")
	actor.free()
	quit(0 if ok else 1)
