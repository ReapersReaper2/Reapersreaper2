extends SceneTree
## Regression for missing joystick on Android phones that return false for
## DisplayServer.is_touchscreen_available(). Runs headless without a phone.
## godot --headless --path godot-project --script res://scripts/mobile_touch_visibility_test.gd

const TouchHUD := preload("res://scripts/touch_controls.gd")
const PlayerScene := preload("res://scenes/player.tscn")
const Resident := preload("res://scripts/reserve_creature.gd")

var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(TouchHUD.should_show_controls(true, false, false),
		"Android/iOS must always have a joystick even if touchscreen probe is false")
	_check(TouchHUD.should_show_controls(true, true, false),
		"native mobile stays enabled when touchscreen probe is true")
	_check(TouchHUD.should_show_controls(false, true, false),
		"browser/tablet with reported touchscreen displays controls")
	_check(TouchHUD.should_show_controls(false, false, true),
		"desktop QA override displays controls")
	_check(not TouchHUD.should_show_controls(false, false, false),
		"ordinary keyboard-only desktop does not show an unused HUD")

	# Regression: on the same Android devices whose touchscreen probe returns
	# false, resident prompts must still say USE (the actual HUD button).
	_check(Resident.should_show_touch_prompt(true, false, false),
		"native Android shows USE even when touchscreen detection is false")
	_check(Resident.interaction_caption(Resident.should_show_touch_prompt(true, false, false)) == "USE",
		"creature interaction instruction matches the mobile button")
	_check(Resident.should_show_touch_prompt(false, true, false),
		"touchscreen browser also shows USE prompts")
	_check(Resident.should_show_touch_prompt(false, false, true),
		"forced touch QA uses USE prompts")
	_check(not Resident.should_show_touch_prompt(false, false, false),
		"keyboard desktop retains E / INTERACT prompts")

	var player_scene := PlayerScene.instantiate()
	var touch_scene = player_scene.get_node_or_null("TouchControls")
	_check(touch_scene != null, "player scene contains touch controls")
	_check(touch_scene != null and (touch_scene as CanvasLayer).layer == 8,
		"touch canvas draws above the bridge scenery and below pause menu")
	player_scene.free()

	# Reproduce the old failure: native Android detection is mocked by the
	# pure decision helper, while headless lacks a touchscreen and uses an
	# explicit force override to exercise the actual CanvasLayer _ready.
	var touch = TouchHUD.new()
	touch.force_touch_controls = true
	root.add_child(touch)
	_check(touch.visible, "mobile controls remain visible once enabled")
	_check(touch.layer == 8, "mobile canvas is raised into the HUD layer")
	_check(touch.overlay != null, "mobile overlay is instantiated")
	if touch.overlay != null:
		var hud := touch.overlay as Control
		_check(hud.name == "MobileHUD", "named mobile overlay exists")
		_check(hud.mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"HUD permits non-action touches to reach game world")
		_check(hud.get_anchor(SIDE_LEFT) == 0.0 and hud.get_anchor(SIDE_RIGHT) == 1.0,
			"mobile control root stretches to full viewport width")
		_check(hud.get_anchor(SIDE_TOP) == 0.0 and hud.get_anchor(SIDE_BOTTOM) == 1.0,
			"mobile control root stretches to full viewport height")
		_check(hud.size.x >= 640.0 and hud.size.y >= 360.0,
			"overlay has real screen dimensions, not a zero-size canvas")
		var joystick: Vector2 = hud.call("_joy_center")
		var attack: Vector2 = hud.call("_attack_center")
		var use: Vector2 = hud.call("_interact_center")
		_check(joystick.x > 0.0 and joystick.x < hud.size.x * 0.3,
			"joystick drawn inside lower-left viewport")
		_check(attack.x < hud.size.x and use.x < hud.size.x,
			"action buttons drawn inside right viewport")
		_check(joystick.y > hud.size.y * 0.6 and attack.y > hud.size.y * 0.5,
			"controls drawn below gameplay and story text")
		# A repeated setup must not stack invisible duplicate input consumers.
		touch._ready()
		_check(touch.get_child_count() == 1,
			"reentering ready does not duplicate mobile touch overlays")
	touch.queue_free()

	# Integration: actual resident prompt is created as USE and stays USE
	# after its per-frame text refresh under the HUD's project-wide QA flag.
	var setting_path := "reaper/force_touch_controls"
	var had_setting := ProjectSettings.has_setting(setting_path)
	var prior_setting = ProjectSettings.get_setting(setting_path, false)
	ProjectSettings.set_setting(setting_path, true)
	var room := Node2D.new()
	root.add_child(room)
	var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.3, 0.5, 0.3, 1.0))
	var resident = Resident.new()
	resident.name = "PromptProbe"
	resident.texture = ImageTexture.create_from_image(image)
	room.add_child(resident)
	var prompt = resident.get("_prompt") as Label
	_check(prompt != null and prompt.text == "USE",
		"actual resident awareness prompt uses visible HUD action label")
	resident._process(0.05)
	_check(prompt != null and prompt.text == "USE",
		"per-frame resident update never changes USE back to keyboard E")
	room.queue_free()
	if had_setting:
		ProjectSettings.set_setting(setting_path, prior_setting)
	else:
		ProjectSettings.set_setting(setting_path, null)

	if _failures == 0:
		print("[MOBILE HUD VISIBILITY] PASS %d checks" % _checks)
	else:
		push_error("[MOBILE HUD VISIBILITY] FAIL %d/%d" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("[MOBILE HUD VISIBILITY] " + message)
