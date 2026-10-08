extends SceneTree
## Headless Luna follower verification: follows a moving target, hovers at
## stop distance, teleports on room-transition distance, bob/flap animate
## without error, set_active hides/shows.
##
## Run: Godot --headless --path <project> -s res://scripts/luna_test.gd

var _frame: int = 0
var _luna = null
var _target: Node2D = null
var _checks: Dictionary = {}

var _luna_start: Vector2 = Vector2.ZERO
var _moved_toward: bool = false
var _bob_seen: bool = false
var _flap_seen: bool = false


func _initialize() -> void:
	var ls: PackedScene = load("res://scenes/luna.tscn")
	_luna = ls.instantiate()
	root.add_child(_luna)
	_luna.position = Vector2(0, 0)

	_target = Node2D.new()
	_target.name = "TestTarget"
	root.add_child(_target)
	_target.position = Vector2(0, 0)

	_luna.set_target(_target)
	_luna_start = _luna.position
	print("[TEST] luna setup: visuals=",
		_luna.get_node_or_null("Visual") != null,
		" wings=", _luna.get_node_or_null("Visual/WingL") != null)


func _physics_process(delta: float) -> bool:
	_frame += 1
	var phase: String = _phase()

	if phase == "move":
		# Target walks right at 200 px/s; Luna should trail behind.
		_target.position += Vector2(200, 0) * delta
		if _luna.position.x > _luna_start.x + 5.0:
			_moved_toward = true
	elif phase == "settle":
		# Target stops; Luna should converge to the stop ring.
		pass
	elif phase == "teleport":
		if _frame == 331:
			_target.position = Vector2(1500, 800)
	elif phase == "active":
		if _frame == 341:
			_luna.set_active(false)
			_checks["hide_on_deactivate"] = (not _luna.visible) and (not _luna.is_physics_processing())
		if _frame == 346:
			_luna.set_active(true)
			_checks["show_on_activate"] = _luna.visible and _luna.is_physics_processing()

	# Bob/flap animation sampling (runs even while following).
	var vis: Node2D = _luna.get_node_or_null("Visual")
	if vis != null and absf(vis.position.y) > 0.5:
		_bob_seen = true
	var wing: Polygon2D = _luna.get_node_or_null("Visual/WingL")
	if wing != null and absf(wing.scale.y - 1.0) > 0.05:
		_flap_seen = true

	if _frame == 240:
		var d: float = _luna.position.distance_to(_target.position)
		_checks["follows_target"] = _moved_toward
		_checks["stops_at_ring"] = d <= _luna.stop_distance + 12.0
		print("[TEST] settle: dist=", d, " ring=", _luna.stop_distance)

	if _frame == 340:
		var d2: float = _luna.position.distance_to(_target.position)
		_checks["teleports_when_far"] = d2 < _luna.teleport_distance
		print("[TEST] teleport: dist=", d2)

	if _frame >= 360:
		_checks["bob_animates"] = _bob_seen
		_checks["flap_animates"] = _flap_seen
		_report()
		return true
	if _frame > 2000:
		print("[TEST] TIMEOUT")
		_report()
		return true
	return false


func _phase() -> String:
	if _frame <= 120:
		return "move"      # 2s of walking
	if _frame <= 240:
		return "settle"    # 2s stopped
	if _frame <= 340:
		return "teleport"  # far jump, then re-follow
	return "active"


func _report() -> void:
	var fails: Array = []
	for key in _checks.keys():
		var ok: bool = _checks[key] == true
		print("[TEST] ", key, " = ", "PASS" if ok else "FAIL")
		if not ok:
			fails.append(key)
	if fails.is_empty():
		print("[TEST] ALL ", _checks.size(), " CHECKS PASSED")
	else:
		print("[TEST] FAILURES: ", fails)
		quit(1)
