extends SceneTree
## DQ-005: run from an isolated cwd with --main-pack pointing at exported PCK.
const Clips := preload("res://scripts/form1_attack_clips.gd")
const Loader := preload("res://scripts/critical_sprite_loader.gd")
const PlayerScene := preload("res://scenes/player.tscn")
func _initialize() -> void:
	call_deferred("_probe")
func _probe() -> void:
	print("[DQ005 PACK] starting packed probe")
	print("[DQ005 PACK] manifest exists=%s" % str(FileAccess.file_exists(Clips.MANIFEST_PATH)))
	var clips := Clips.load_approved(Callable(Loader, "load_texture"))
	print("[DQ005 PACK] clips loaded=%d expected=20" % clips.size())
	if clips.size() != 20:
		printerr("[DQ005 PACK] FAIL: not all clips load from packed resources")
		quit(1)
		return
	var player = PlayerScene.instantiate()
	root.add_child(player)
	player.set_physics_process(false)
	var manager = player.sprites
	var painted := true
	for facing in [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]:
		for action_index in [1, 2, 3, 4, 5]:
			manager.set_mortal_sword_pose(action_index, 0.5, facing)
			var art: Sprite2D = manager._sprite
			if not manager._approved_attack_active or art.material != null or manager._mortal_blade_sprite.visible:
				painted = false
				printerr("[DQ005 PACK] FAIL: shader fallback action=%d facing=%s" % [action_index, str(facing)])
			var sample := Clips.sample(clips, action_index, 0.5, facing)
			if sample.is_empty() or art.texture != sample.get("texture", null):
				painted = false
				printerr("[DQ005 PACK] FAIL: incorrect painted frame action=%d facing=%s" % [action_index, str(facing)])
			manager._reset_mortal_sword_pose()
	player.free()
	print("[DQ005 PACK] %s painted attacks=20/20" % ["PASS" if painted else "FAIL"])
	quit(0 if painted else 1)
