extends SceneTree
## Synthetic images prove the approved artist-sheet interface WITHOUT
## importing or accidentally authorizing the Muse candidate artwork.
const Clips := preload("res://scripts/form1_attack_clips.gd")
const Sprites := preload("res://scripts/mollosar_sprites.gd")
var checks := 0
var failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error("[FORM1 APPROVED ATTACK] " + label)

func _run() -> void:
	var normal_image := Image.create(2304, 384, false, Image.FORMAT_RGBA8)
	normal_image.fill(Color(0.2, 0.3, 0.4, 0.6))
	var heavy_image := Image.create(3072, 384, false, Image.FORMAT_RGBA8)
	heavy_image.fill(Color(0.4, 0.3, 0.2, 0.6))
	var six := ImageTexture.create_from_image(normal_image)
	var eight := ImageTexture.create_from_image(heavy_image)
	var spec: Dictionary = {"status": "APPROVED", "strips": {}}
	var inventory: Dictionary = {}
	for name in Clips.required_keys():
		var heavy := name.begins_with("heavy_")
		var path := "res://sprites/mollosar/approved/" + name + ".png"
		spec["strips"][name] = {
			"texture": path,
			"frames": 8 if heavy else 6,
			"cell": [384, 384],
			"fps": 12.0,
			"pivot": [192, 360],
		}
		inventory[path] = eight if heavy else six
	var loader := func(path: String) -> Texture2D:
		return inventory.get(path)
	var accepted := Clips.validate_manifest(spec, loader)
	_check(Clips.validate_manifest(JSON.parse_string(JSON.stringify(spec)), loader).size() == 20,
		"real JSON numeric types accept the same complete manifest as in-memory fixtures")
	_check(accepted.size() == 20, "all 20 direction/action strips accepted atomically")
	_check(Clips.direction_for_facing(Vector2.DOWN) == "front" and
		Clips.direction_for_facing(Vector2.UP) == "back" and
		Clips.direction_for_facing(Vector2.LEFT) == "side-l" and
		Clips.direction_for_facing(Vector2.RIGHT) == "side-r",
		"four directions map to the approved artist-facing convention")
	_check(is_equal_approx(Clips.grounded_sprite_y(Vector2(192, 360), 0.4), -3.2),
		"approved pivot keeps feet on the same +64px world-ground position")
	var mid := Clips.sample(accepted, 1, 0.30, Vector2.DOWN)
	_check(mid.get("action") == "slash" and int(mid.get("frame", -1)) >= 1,
		"normal sword swing uses painted slash cells in attack window")
	var rev := Clips.sample(accepted, 2, 0.30, Vector2.LEFT)
	_check(rev.get("action") == "rslash" and rev.get("direction") == "side-l",
		"combo's opposite strike uses correct left art")
	var charged := Clips.sample(accepted, 3, 1.0, Vector2.UP)
	_check(charged.get("action") == "windup" and int(charged.get("frame", -1)) == 5,
		"held charge settles on the final windup frame, never loops")
	var heavy := Clips.sample(accepted, 4, 0.99, Vector2.RIGHT)
	_check(heavy.get("action") == "heavy" and int(heavy.get("frame", -1)) == 7,
		"heavy eight-frame strike lands at its last committed frame")
	var recover := Clips.sample(accepted, 5, 0.92, Vector2.RIGHT)
	_check(recover.get("action") == "recover" and int(recover.get("frame", -1)) > 0,
		"release transitions to painted recovery without a detached blade")
	_check(Clips.sample(accepted, 5, 1.0, Vector2.DOWN).get("frame") == 5,
		"recovery samples final frame without wrapping to first")
	_check(Clips.sample(accepted, 0, 0.0, Vector2.DOWN).is_empty(),
		"idle remains the previously approved walk and idle art")

	# The new seven-frame replacement is intentionally front-only until other
	# directions pass art QA. Never substitute its front art for a side/back pose.
	var replacement := {"slash_front": {"texture": six, "frames": 7, "pivot": Vector2(192, 192)}}
	var forward := Clips.sample(replacement, 1, 0.5, Vector2.DOWN)
	_check(forward.get("texture") == six and forward.get("frames") == 7,
		"front-only replacement samples all seven frames without changing actor")
	_check(Clips.sample(replacement, 1, 0.5, Vector2.LEFT).is_empty() and
		Clips.sample(replacement, 1, 0.5, Vector2.RIGHT).is_empty() and
		Clips.sample(replacement, 1, 0.5, Vector2.UP).is_empty(),
		"no front sword pose is incorrectly mirrored into other directions")

	var candidate: Dictionary = spec.duplicate(true)
	candidate["status"] = "CANDIDATE"
	_check(Clips.validate_manifest(candidate, loader).is_empty(),
		"the current 19 delivered candidate sheets cannot enter production")
	var missing: Dictionary = spec.duplicate(true)
	missing["strips"].erase("heavy_back")
	_check(Clips.validate_manifest(missing, loader).is_empty(),
		"19 of 20 clips is never considered an approved complete animation")
	var bleed: Dictionary = spec.duplicate(true)
	bleed["strips"]["heavy_front"]["pivot"] = [192, 410]
	_check(Clips.validate_manifest(bleed, loader).is_empty(),
		"invalid foot pivot is rejected before touching player animation")
	var bad_resolution: Dictionary = spec.duplicate(true)
	bad_resolution["strips"]["heavy_front"]["frames"] = 6
	_check(Clips.validate_manifest(bad_resolution, loader).is_empty(),
		"invalid heavy strip geometry rejected before game launch")

	# Integration path: same single character sprite, no weapon overlay;
	# returning from sword strike must restore walking source texture.
	var manager = Sprites.new()
	manager._sprite = Sprite2D.new()
	manager._form = 1
	manager._strips["down"] = six
	manager._frames["down"] = 6
	manager._strip_dir = "down"
	manager._attack_clips = accepted
	_check(manager._try_approved_attack(4, 0.99, Vector2.RIGHT),
		"player renderer can display approved painted attack when available")
	_check(manager._sprite.texture == eight and
		manager._sprite.region_rect.size == Vector2(384, 384) and
		manager._sprite.material == null and
		manager._mortal_blade_sprite == null,
		"approved attack uses one coherent sprite, no external sword shader")
	manager._reset_mortal_sword_pose()
	_check(manager._sprite.texture == six and not manager._approved_attack_active,
		"recovering to idle restores the real walking artwork")
	manager.free()
	# Production rejected this asset set; synthetic fixture above still
	# validates the future 20-strip interface without reinstating it.
	var real := Clips.load_approved(Callable(preload("res://scripts/critical_sprite_loader.gd"), "load_texture"))
	if FileAccess.file_exists(Clips.MANIFEST_PATH):
		_check(real.size() == 20, "only a complete 20-strip approved set can load")
	else:
		_check(real.is_empty(), "without a manifest no attack textures are promoted")
	_check(Clips.sample(accepted, 1, 0.70, Vector2.DOWN).get("action") == "slash",
		"damage window never swaps to recovery artwork early")

	if failed == 0:
		print("[FORM1 APPROVED ATTACK] PASS %d checks" % checks)
	else:
		push_error("[FORM1 APPROVED ATTACK] FAIL %d/%d" % [failed, checks])
	quit(1 if failed > 0 else 0)
