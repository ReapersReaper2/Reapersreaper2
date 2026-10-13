extends SceneTree
## Muse-approved Form 1 blade rig: no double sword, no alpha holes in
## the cloth, and one animation timeline shared with combat.
## godot --headless --path godot-project --script res://scripts/form1_painted_blade_test.gd

const Mollosar := preload("res://scripts/mollosar_sprites.gd")
const WeaponVisual := preload("res://scripts/scythe_visual.gd")
const PlayerScene := preload("res://scenes/player.tscn")
const BaseShader := preload("res://shaders/form1_resting_blade.gdshader")
const BladeShader := preload("res://shaders/form1_swing_blade.gdshader")

var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for d in ["down", "up", "left", "right"]:
		var g: Dictionary = Mollosar.mortal_blade_geometry(d)
		_check(g.has("guard") and g.has("tip"),
			"approved sword anchor exists for " + d)
		var guard: Vector2 = g["guard"]
		var tip: Vector2 = g["tip"]
		_check(guard.x >= 0.0 and guard.x < 384.0 and
			guard.y >= 0.0 and guard.y < 384.0 and
			tip.x >= 0.0 and tip.x < 384.0 and
			tip.y >= 0.0 and tip.y < 384.0,
			"painted blade remains within its native 384px sprite cell")
		_check(guard.distance_to(tip) > 85.0,
			"blade has meaningful illustrated length for " + d)
		var first := Mollosar.mortal_blade_angle(d, 1, 0.52)
		var second := Mollosar.mortal_blade_angle(d, 2, 0.52)
		_check(absf(first) > 0.05 and
			is_equal_approx(first, -second),
			"combo hit two mirrors first blade sweep for " + d)
		_check(is_equal_approx(first, float(g["sign"]) *
			WeaponVisual.sword_stroke_angle(1, 0.52)),
			"blade uses exact timed attack arc, not a second animation timer")
	_check(Mollosar.mortal_blade_geometry("missing").is_empty(),
		"unknown source direction never invents an anchor")
	_check(BaseShader != null and BladeShader != null,
		"both Godot canvas shaders are valid imported resources")

	var player = PlayerScene.instantiate()
	root.add_child(player)
	var mgr = player.get("sprites")
	_check(mgr != null and mgr.has_sprites(),
		"approved Form1 sprite loads before painted sword test")
	if mgr != null and mgr.has_sprites():
		var art := mgr.get("_sprite") as Sprite2D
		var blade := mgr.get("_mortal_blade_sprite") as Sprite2D
		var rest_mat := mgr.get("_mortal_rest_material") as ShaderMaterial
		var blade_mat := mgr.get("_mortal_swing_material") as ShaderMaterial
		_check(art != null and blade != null,
			"the original art and a SINGLE painted-blade layer exist")
		_check(mgr.uses_painted_mortal_blade(),
			"the procedural fallback recognizes the approved sword rig")
		_check(not blade.visible and art.material == null,
			"resting weapon is already in the original walk artwork")
		_check(rest_mat != null and rest_mat.shader == BaseShader and
			blade_mat != null and blade_mat.shader == BladeShader,
			"two masks share approved sprite coordinates")
		for d in ["down", "up", "left", "right"]:
			var direction := Vector2.DOWN
			match d:
				"up": direction = Vector2.UP
				"left": direction = Vector2.LEFT
				"right": direction = Vector2.RIGHT
			mgr.tick(1.0 / 60.0, direction, false)
			mgr.set_mortal_sword_pose(1, 0.45, direction)
			_check(blade.visible and art.material == rest_mat,
				"attacking hides the baked blade and reveals ONLY one animated one")
			_check(blade.texture == art.texture and
				blade.region_rect == art.region_rect,
				"new blade samples EXACT original Muse sword pixels, not new art")
			_check(blade.position.is_equal_approx(art.position) and
				is_equal_approx(blade.rotation, art.rotation) and
				blade.scale.is_equal_approx(art.scale),
				"painted sword follows foot-grounded body rig without lag")
			var geom: Dictionary = Mollosar.mortal_blade_geometry(d)
			_check(blade_mat.get_shader_parameter("guard_px") == geom["guard"] and
				blade_mat.get_shader_parameter("tip_px") == geom["tip"],
				"right-hand grip and blade tip match " + d + " painting")
			_check(is_equal_approx(float(blade_mat.get_shader_parameter(
				"swing_angle_radians")), Mollosar.mortal_blade_angle(d, 1, 0.45)),
				"attacking sword angle tracks combo timing for " + d)
			_check(is_equal_approx(float(rest_mat.get_shader_parameter(
				"fill_side")), float(geom["fill"])),
				"resting sword matte fills cloak/armor instead of leaving a hole")
			mgr.set_mortal_sword_pose(2, 0.45, direction)
			_check(is_equal_approx(float(blade_mat.get_shader_parameter(
				"swing_angle_radians")), Mollosar.mortal_blade_angle(d, 2, 0.45)),
				"second combo hit really reverses the painted steel")
			mgr.set_mortal_sword_pose(0, 0.0, direction)
			_check(not blade.visible and art.material == null,
				"after combo recovery, painted sword and untouched idle artwork return")
		# Scene/form switches cannot leave a blade layer behind.
		mgr._release_mortal_blade()
		_check(not blade.visible and art.material == null,
			"level and form changes release the shader rig cleanly")
	player.queue_free()

	if _failures == 0:
		print("[PAINTED FORM1 SWORD] PASS %d checks" % _checks)
	else:
		push_error("[PAINTED FORM1 SWORD] FAIL %d/%d checks" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("[PAINTED FORM1 SWORD] " + description)
