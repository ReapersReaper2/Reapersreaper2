extends SceneTree
## DQ005 reproduction-only: run against a Godot export pack, NOT an editor checkout.
const Clips = preload("res://scripts/form1_attack_clips.gd")
const Loader = preload("res://scripts/critical_sprite_loader.gd")
const PlayerScene = preload("res://scenes/player.tscn")
func _initialize() -> void:
	call_deferred("_check_packed")
func _check_packed() -> void:
	var path := Clips.MANIFEST_PATH
	print("[DQ005 PACKED] manifest_file_exists=" + str(FileAccess.file_exists(path)))
	print("[DQ005 PACKED] manifest_resource_exists=" + str(ResourceLoader.exists(path)))
	if FileAccess.file_exists(path):
		var json := FileAccess.get_file_as_string(path)
		var p = JSON.parse_string(json)
		print("[DQ005 PACKED] bytes=" + str(json.to_utf8_buffer().size()) + " status=" + str(p.get("status", "?") if p is Dictionary else "INVALID"))
	for file in ["form1_windup_front.png", "form1_slash_front.png", "form1_heavy_back.png"]:
		var tex_path: String = "res://sprites/mollosar/approved/" + str(file)
		print("[DQ005 PACKED] check " + file + " FileAccess=" + str(FileAccess.file_exists(tex_path)) + " ResourceLoader=" + str(ResourceLoader.exists(tex_path)))
		var candidate = Loader.load_texture(tex_path)
		print("[DQ005 PACKED] check result=" + ("NULL" if candidate == null else str(candidate.get_class()) + " " + str(candidate.get_size())))
	var clips: Dictionary = Clips.load_approved(Callable(Loader, "load_texture"))
	print("[DQ005 PACKED] approved_clip_count=" + str(clips.size()))
	if clips.size() == 20:
		var actor = PlayerScene.instantiate()
		root.add_child(actor)
		var mgr = actor.sprites
		print("[DQ005 PACKED] manager_loaded_clips=" + str(mgr._attack_clips.size()))
		mgr.set_mortal_sword_pose(1, 0.45, Vector2.DOWN)
		print("[DQ005 PACKED] after_slash painted=" + str(mgr._approved_attack_active) + " blade_overlay=" + str(mgr._mortal_blade_sprite.visible) + " texture=" + str(mgr._sprite.texture.get_size() if mgr._sprite.texture != null else Vector2.ZERO))
		actor.free()
	quit(0 if clips.size() == 20 else 7)
