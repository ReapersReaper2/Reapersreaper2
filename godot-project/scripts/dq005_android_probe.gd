extends Node2D
## Only used by the DQ005 emulator diagnostic export, never by the game.
const Clips := preload("res://scripts/form1_attack_clips.gd")
const Loader := preload("res://scripts/critical_sprite_loader.gd")
const PlayerScene := preload("res://scenes/player.tscn")
func _ready() -> void:
	call_deferred("_probe")
func _probe() -> void:
	print("[DQ005 ANDROID] begin")
	var clips := Clips.load_approved(Callable(Loader, "load_texture"))
	print("[DQ005 ANDROID] clips_loaded=%d" % clips.size())
	if clips.size() != 20:
		printerr("[DQ005 ANDROID] FAIL clips incomplete")
		get_tree().quit(1)
		return
	var player = PlayerScene.instantiate()
	add_child(player)
	player.set_physics_process(false)
	var mgr = player.sprites
	var valid := true
	for facing in [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]:
		for act in [1,2,3,4,5]:
			mgr.set_mortal_sword_pose(act,0.5,facing)
			var art: Sprite2D = mgr._sprite
			var expected := Clips.sample(clips, act, 0.5, facing)
			if not mgr._approved_attack_active or art.material != null or mgr._mortal_blade_sprite.visible or expected.is_empty() or art.texture != expected["texture"]:
				valid = false
				printerr("[DQ005 ANDROID] FAIL action=%d facing=%s" % [act,str(facing)])
			mgr._reset_mortal_sword_pose()
	print("[DQ005 ANDROID] %s all 20 real-art samples" % ("PASS" if valid else "FAIL"))
	get_tree().quit(0 if valid else 1)
