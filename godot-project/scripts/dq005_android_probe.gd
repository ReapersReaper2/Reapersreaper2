extends Node
## DQ005 diagnostic app startup autoload. Never include in a release APK.
const Clips := preload("res://scripts/form1_attack_clips.gd")
const Loader := preload("res://scripts/critical_sprite_loader.gd")
const PlayerScene := preload("res://scenes/player.tscn")
func _ready() -> void:
	call_deferred("_probe")
func _probe() -> void:
	print("[DQ005 ANDROID] OS=" + OS.get_name() + " Android=" + str(OS.has_feature("Android")))
	var manifest: String = Clips.MANIFEST_PATH
	print("[DQ005 ANDROID] manifest.exists=" + str(FileAccess.file_exists(manifest)) + " resource_exists=" + str(ResourceLoader.exists(manifest)))
	if FileAccess.file_exists(manifest):
		var raw := FileAccess.get_file_as_string(manifest)
		var p = JSON.parse_string(raw)
		print("[DQ005 ANDROID] manifest.bytes=" + str(raw.to_utf8_buffer().size()) + " parse_dictionary=" + str(p is Dictionary))
		if p is Dictionary:
			print("[DQ005 ANDROID] status=" + str(p.get("status", "?")) + " strips_type=" + type_string(typeof(p.get("strips"))))
	for filename in ["form1_windup_front.png", "form1_slash_front.png", "form1_heavy_back.png"]:
		var path: String = "res://sprites/mollosar/approved/" + str(filename)
		print("[DQ005 ANDROID] " + str(filename) + " raw_exists=" + str(FileAccess.file_exists(path)) + " resource_exists=" + str(ResourceLoader.exists(path)))
		var texture = Loader.load_texture(path)
		print("[DQ005 ANDROID] sample=" + ("null" if texture == null else texture.get_class() + " " + str(texture.get_size())))
	var clips: Dictionary = Clips.load_approved(Callable(Loader, "load_texture"))
	print("[DQ005 ANDROID] loaded=" + str(clips.size()))
	var actor = PlayerScene.instantiate()
	get_tree().root.add_child(actor)
	var mgr = actor.sprites
	print("[DQ005 ANDROID] actor_clips=" + str(mgr._attack_clips.size()))
	mgr.set_mortal_sword_pose(1, 0.5, Vector2.DOWN)
	print("[DQ005 ANDROID] painted=" + str(mgr._approved_attack_active) + " detached_blade=" + str(mgr._mortal_blade_sprite.visible))
	print("[DQ005 ANDROID] VERDICT=" + ("PASS" if clips.size() == 20 and mgr._attack_clips.size() == 20 and mgr._approved_attack_active and not mgr._mortal_blade_sprite.visible else "FAIL"))
	actor.queue_free()
