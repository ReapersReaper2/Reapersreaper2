extends SceneTree
## Explicit delivery probe, run in source and from an isolated exported pack.
const Clips = preload("res://scripts/form1_attack_clips.gd")
const Loader = preload("res://scripts/critical_sprite_loader.gd")
const PlayerScene = preload("res://scenes/player.tscn")
var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[FORM1 RESOURCE] " + label)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] not in ["source", "packed"]:
		push_error("Expected source|packed and report path")
		quit(1)
		return
	var packed := args[0] == "packed"
	var report := {"mode": args[0], "manifest_raw": FileAccess.file_exists(Clips.MANIFEST_PATH),
		"manifest_resource": ResourceLoader.exists(Clips.MANIFEST_PATH), "textures": []}
	_check(report.manifest_raw, "required manifest exists in delivered resources")
	var clips := Clips.load_approved(Callable(Loader, "load_texture"))
	_check(clips.size() == 20, "all 20 clips load; fallback is not a delivery pass")
	var paths: Array[String] = []
	for key in Clips.required_keys():
		paths.append(Clips.ALLOWED_ROOT + "form1_" + key + ".png")
	for direction in ["down", "up", "left", "right"]:
		paths.append("res://sprites/mollosar/canon_walk/form1_walk_%s_spec384.png" % direction)
	for path in paths:
		var raw := FileAccess.file_exists(path)
		var resource := ResourceLoader.exists(path)
		_check(resource, "imported texture resolves: " + path)
		if packed:
			_check(not raw, "packed probe has no loose source PNG: " + path)
		var tex := Loader.load_texture(path)
		_check(tex != null, "texture loads: " + path)
		if packed:
			_check(tex is CompressedTexture2D, "uses imported resource, not bundled substitute: " + path)
		var entry := {"path": path, "raw": raw, "resource": resource,
			"class": tex.get_class() if tex != null else "null"}
		if tex != null:
			entry["size"] = [tex.get_width(), tex.get_height()]
		report.textures.append(entry)
	var actor = PlayerScene.instantiate()
	root.add_child(actor)
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	_check(actor.sprites._canon_walk_active, "real Player selects complete canon walk")
	_check(actor.sprites._attack_clips.size() == 20, "real Player loads all attacks")
	for facing in [Vector2.DOWN, Vector2.UP, Vector2.LEFT, Vector2.RIGHT]:
		actor.sprites._reset_mortal_sword_pose()
		actor.sprites.set_mortal_sword_pose(1, 0.5, facing)
		_check(actor.sprites._approved_attack_active and actor.sprites._sprite.material == null,
			"real Player displays painted attack without shader fallback: " + str(facing))
	actor.free()
	report["checks"] = checks
	report["failures"] = failures
	report["clips"] = clips.size()
	var file := FileAccess.open(args[1], FileAccess.WRITE)
	if file == null:
		_check(false, "report file opens")
	else:
		file.store_string(JSON.stringify(report, "\t"))
		file.close()
	print("FORM1_RESOURCE %s checks=%d failures=%d clips=%d" % [args[0], checks, failures, clips.size()])
	quit(0 if failures == 0 else 1)
