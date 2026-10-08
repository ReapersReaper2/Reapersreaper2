extends SceneTree
## Headless guide-touch verification: E near a wisp starts the guide,
## the soothe meter fills while the player stays close, guided fires and
## the player unlocks; walking away cancels; the scythe can never harm
## a wisp (zero damage by construction).
##
## Run: Godot --headless --path <project> -s res://scripts/guide_test.gd

var _frame: int = 0
var _player = null
var _rig = null
var _wisp = null
var _wisp2 = null
var _wisp3 = null
var _checks: Dictionary = {}

var _completed_wisp = null
var _cancelled: bool = false
var _meter_seen: float = 0.0
var _locked_during_hold: bool = false


func _initialize() -> void:
	var ps: PackedScene = load("res://scenes/player.tscn")
	_player = ps.instantiate()
	root.add_child(_player)
	_player.position = Vector2(0, 0)
	_rig = _player.get_node("GuideRig")
	_rig.guide_completed.connect(_on_completed)
	_rig.guide_cancelled.connect(_on_cancelled)

	var ws: PackedScene = load("res://scenes/wisp.tscn")
	_wisp = ws.instantiate()
	root.add_child(_wisp)
	_wisp.position = Vector2(100, 0)
	print("[TEST] guide setup: rig=", _rig != null,
		" wisp_guidable=", _wisp.is_guidable(),
		" wisp_hittable=", _wisp.is_in_group("hittable"),
		" wisp_has_take_hit=", _wisp.has_method("take_hit"))


func _on_completed(wisp) -> void:
	_completed_wisp = wisp


func _on_cancelled() -> void:
	_cancelled = true


func _phase() -> String:
	if _frame <= 400:
		return "guide"
	elif _frame <= 560:
		return "cancel"
	else:
		return "nodamage"


func _physics_process(_delta: float) -> bool:
	_frame += 1
	var phase: String = _phase()

	if phase == "guide":
		if _frame == 2:
			var started: bool = bool(_rig.try_guide())
			_checks["guide_activates"] = started and _rig.state != 0
			print("[TEST] try_guide -> ", started, " state=", _rig.state)
		if _frame == 120:
			_meter_seen = float(_rig.meter)
			_locked_during_hold = bool(_player.move_locked) and bool(_player.guide_active)
		if _frame == 380:
			_checks["meter_fills"] = _meter_seen > 0.2
			_checks["player_locked_during_hold"] = _locked_during_hold
			_checks["guided_fires"] = _completed_wisp == _wisp
			_checks["player_unlocks_after"] = (not bool(_player.move_locked)) and (not bool(_player.guide_active)) and _rig.state == 0
			_checks["wisp_freed_after_release"] = not is_instance_valid(_wisp)
			print("[TEST] guide done: meter_seen=", _meter_seen,
				" completed=", _completed_wisp != null)

	elif phase == "cancel":
		if _frame == 410:
			var ws: PackedScene = load("res://scenes/wisp.tscn")
			_wisp2 = ws.instantiate()
			root.add_child(_wisp2)
			_wisp2.position = Vector2(100, 0)
			_cancelled = false
			var started2: bool = bool(_rig.try_guide())
			_checks["guide_reactivates"] = started2
		if _frame == 440:
			# Walk away mid-hold: beyond break_distance.
			_player.position = Vector2(1000, 0)
		if _frame == 520:
			_checks["cancel_on_distance"] = _cancelled
			_checks["player_unlocks_on_cancel"] = (not bool(_player.move_locked)) and (not bool(_player.guide_active))
			_checks["wisp_returns_to_idle"] = is_instance_valid(_wisp2) and int(_wisp2.get("wisp_state")) == 0
			_player.position = Vector2(0, 0)
			print("[TEST] cancel done: cancelled=", _cancelled)

	else:
		if _frame == 570:
			# Fresh wisp overlapping the scythe hitbox: swing at it.
			var ws2: PackedScene = load("res://scenes/wisp.tscn")
			_wisp3 = ws2.instantiate()
			root.add_child(_wisp3)
			_wisp3.position = Vector2(75, 0)
			var srig = _player.get_node("ScytheRig")
			srig.try_swing()
		if _frame == 660:
			var srig2 = _player.get_node("ScytheRig")
			_checks["swing_completed"] = not bool(srig2.is_swinging())
			_checks["wisp_not_hittable"] = not _wisp3.is_in_group("hittable")
			_checks["wisp_no_take_hit"] = not _wisp3.has_method("take_hit")
			_checks["wisp_unaffected_by_swing"] = bool(_wisp3.is_guidable()) and int(_wisp3.get("wisp_state")) == 0
			print("[TEST] nodamage done: swing_done=", _checks["swing_completed"],
				" wisp_guidable=", _wisp3.is_guidable())

	if _frame >= 680:
		_report()
		return true
	return false


func _report() -> void:
	var order: Array = [
		"guide_activates", "meter_fills", "player_locked_during_hold",
		"guided_fires", "player_unlocks_after", "wisp_freed_after_release",
		"guide_reactivates", "cancel_on_distance", "player_unlocks_on_cancel",
		"wisp_returns_to_idle", "swing_completed", "wisp_not_hittable",
		"wisp_no_take_hit", "wisp_unaffected_by_swing",
	]
	var fails: int = 0
	for key in order:
		var ok: bool = bool(_checks.get(key, false))
		print("[TEST] ", key, ": ", "PASS" if ok else "FAIL")
		if not ok:
			fails += 1
	print("[TEST] guide_test: ", order.size() - fails, "/", order.size(), " PASS")
	if fails > 0:
		push_error("guide_test: FAILURES PRESENT")
	quit(1 if fails > 0 else 0)
