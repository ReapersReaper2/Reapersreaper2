extends SceneTree
## Godot 4.3 headless smoke test for independent mobile fingers.
## godot --headless --path godot-project --script res://scripts/mobile_touch_test.gd
const OverlayScript := preload("res://scripts/mobile_touch_overlay.gd")
var _checks := 0
var _failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var hud = OverlayScript.new()
	root.add_child(hud)
	hud.size = Vector2(1280, 720)
	var joystick: Vector2 = hud._joy_center()
	var attack: Vector2 = hud._attack_center()
	var interact: Vector2 = hud._interact_center()
	_check(joystick.x < 300.0, "joystick stays on left")
	_check(attack.x > 900.0, "attack stays on right")
	_check(interact.x > 750.0, "interact stays on right")
	_check(attack.distance_to(interact) > 125.0, "attack and interact zones stay apart")
	hud._begin_touch(1, joystick + Vector2(70, 0))
	_check(hud._joystick_id == 1, "movement finger captured")
	_check(Input.is_action_pressed("move_right"), "joystick feeds movement action")
	hud._begin_touch(2, attack)
	_check(hud._attack_id == 2, "second finger captures attack")
	hud._begin_touch(3, interact)
	_check(hud._interact_id == 3, "third finger captures interaction")
	hud._end_touch(1)
	_check(not Input.is_action_pressed("move_right"), "joystick releases movement")
	_check(hud._attack_id == 2, "attack finger survives joystick release")
	hud._end_touch(2)
	hud._end_touch(3)
	_check(hud._attack_id == -1 and hud._interact_id == -1,
		"both action fingers released")
	hud.queue_free()
	# Leaving the room while fingers are still down must release all actions.
	# Otherwise the next scene can inherit a stuck attack or interaction.
	var leaving = OverlayScript.new()
	root.add_child(leaving)
	leaving.size = Vector2(1280, 720)
	leaving._begin_touch(4, leaving._attack_center())
	leaving._begin_touch(5, leaving._interact_center())
	_check(leaving._attack_id == 4 and leaving._interact_id == 5,
		"simultaneous action fingers captured before scene change")
	leaving._exit_tree()
	_check(leaving._attack_id == -1 and leaving._interact_id == -1,
		"scene exit clears both captured action fingers")
	_check(not Input.is_action_pressed("scythe_swing") and
		not Input.is_action_pressed("interact"),
		"scene exit releases held action states")
	leaving.queue_free()
	if _failed == 0:
		print("[MOBILE HUD] PASS %d checks" % _checks)
	else:
		push_error("[MOBILE HUD] FAIL %d/%d checks" % [_failed, _checks])
	quit(1 if _failed > 0 else 0)

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		push_error("[MOBILE HUD] " + message)
