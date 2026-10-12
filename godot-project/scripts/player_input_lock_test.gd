extends SceneTree
## Regression: cutscene input locks must suppress directional movement, not
## merely prevent combat and step-counting.
## godot --headless --path godot-project --script res://scripts/player_input_lock_test.gd

const PlayerScript := preload("res://scripts/player.gd")

var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null and gs.has_method("new_game"):
		gs.new_game()
	var player = PlayerScript.new()
	root.add_child(player)
	player.facing = Vector2.DOWN
	player.velocity = Vector2.ZERO
	Input.action_press("move_right")
	player.input_locked = true
	player._physics_process(1.0 / 60.0)
	_check(is_zero_approx(player.velocity.length()),
		"cutscene movement lock prevents movement from rest")
	_check(player.facing == Vector2.DOWN,
		"cutscene input does not turn the player")
	_check(is_zero_approx(player.global_position.length()),
		"cutscene does not translate the player")
	player.input_locked = false
	player._physics_process(1.0 / 60.0)
	_check(player.velocity.x > 0.0 and player.facing.x > 0.0,
		"unlock restores normal directional movement")
	player.input_locked = true
	player.velocity = Vector2(200, 0)
	player._physics_process(0.2)
	_check(is_zero_approx(player.velocity.length()),
		"cutscene lock decelerates existing movement")
	Input.action_release("move_right")
	player.get_parent().remove_child(player)
	player.free()
	if _failures == 0:
		print("[PLAYER INPUT LOCK] PASS %d checks" % _checks)
	else:
		push_error("[PLAYER INPUT LOCK] FAIL %d/%d" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("[PLAYER INPUT LOCK] " + message)
