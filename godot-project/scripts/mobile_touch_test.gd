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
	# Mobile players need a way to open the pause/save/settings menu.
	var pause: Vector2 = hud._pause_center()
	_check(pause.x > 1150.0 and pause.y > 100.0 and pause.y < 190.0,
		"pause control clears top-right clock overlay")
	_check(pause.y - 31.0 > 62.0,
		"pause circle cannot cover ReserveClockHUD's bottom edge")
	_check(pause.distance_to(attack) > 120.0 and pause.distance_to(interact) > 120.0,
		"pause zone stays apart from combat buttons")
	# Pausing with three other fingers held must release every action
	# (otherwise returning from the pause menu resumes a stuck attack).
	hud._begin_touch(6, joystick + Vector2(70, 0))
	hud._begin_touch(7, attack)
	hud._begin_touch(8, interact)
	hud._begin_touch(9, pause)
	_check(hud._pause_id == 9, "fourth finger captures pause")
	_check(hud._joystick_id == -1 and hud._attack_id == -1 and hud._interact_id == -1,
		"pause drops all active gameplay finger captures")
	_check(not Input.is_action_pressed("move_right") and
		not Input.is_action_pressed("scythe_swing") and
		not Input.is_action_pressed("interact") and
		not Input.is_action_pressed("ui_cancel"),
		"pause leaves no synthetic actions stuck")
	hud._end_touch(9)
	_check(hud._pause_id == -1, "pause finger releases")
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
	# An Android app switch, notification shade or phone call may swallow
	# touch release events; focus/pause notifications must release all inputs.
	var interrupted = OverlayScript.new()
	root.add_child(interrupted)
	interrupted.size = Vector2(1280, 720)
	interrupted._begin_touch(10, interrupted._joy_center() + Vector2(70, 0))
	interrupted._begin_touch(11, interrupted._attack_center())
	interrupted._begin_touch(12, interrupted._interact_center())
	# parse_input_event() queues synthetic action handling; unlike the
	# joystick's Input.action_press(), attack/interact need not report held
	# synchronously in this headless frame. Verify finger ownership instead.
	_check(interrupted._joystick_id == 10 and interrupted._attack_id == 11 and
		interrupted._interact_id == 12 and Input.is_action_pressed("move_right"),
		"multiple fingers are captured before the application loses focus")
	interrupted._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(interrupted._joystick_id == -1 and interrupted._attack_id == -1 and
		interrupted._interact_id == -1,
		"application focus loss discards all captured finger indices")
	_check(not Input.is_action_pressed("move_right") and
		not Input.is_action_pressed("scythe_swing") and
		not Input.is_action_pressed("interact"),
		"application focus loss releases all synthetic gameplay actions")
	# Reused Android finger indices must work after resuming.
	interrupted._begin_touch(10, interrupted._joy_center() + Vector2(70, 0))
	_check(interrupted._joystick_id == 10 and Input.is_action_pressed("move_right"),
		"first fresh touch after resume can move again")
	interrupted._end_touch(10)
	interrupted._begin_touch(13, interrupted._attack_center())
	interrupted._begin_touch(14, interrupted._interact_center())
	interrupted._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	_check(interrupted._attack_id == -1 and interrupted._interact_id == -1 and
		not Input.is_action_pressed("scythe_swing") and
		not Input.is_action_pressed("interact"),
		"mobile OS backgrounding releases action fingers without touch-up")
	interrupted._begin_touch(15, interrupted._pause_center())
	_check(interrupted._pause_id == 15, "menu gesture exists before window defocus")
	interrupted._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	_check(interrupted._pause_id == -1,
		"window focus loss also clears menu finger capture")
	interrupted.queue_free()
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
