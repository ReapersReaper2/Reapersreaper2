extends SceneTree
## Regression: battles from every world era must return to the room they
## started in, including Garden and cottage, instead of falling back to P1.
## godot --headless --path godot-project --script res://scripts/battle_return_test.gd

const Battle := preload("res://scripts/battle.gd")
const Title := preload("res://scripts/title_screen.gd")

class PositionStub:
	extends Node
	var location: Dictionary = {}
	func set_position(room_id: String, x: float, y: float) -> void:
		location = {"room": room_id, "x": x, "y": y}

var _checks := 0
var _failed := 0
var _target: String = ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Title Continue and battle must share identical routing for all eras.
	for room in ["p1", "p3", "c1", "h1", "gd1", "gd3", "gd8", "gd_refuge",
			"f2", "d2", "hl2", "t4", "u3", "o2", "e2"]:
		var resolved: Dictionary = Battle.resolve_return_room(room)
		_check(not bool(resolved["fallback"]), room + " is a real return destination")
		_check(str(resolved["room"]) == room, room + " retains its original room ID")
		_check(str(resolved["scene"]) == Title.scene_for_room(room),
			room + " routes through canonical Continue scene")
		_check(ResourceLoader.exists(str(resolved["scene"])),
			room + " scene exists in the Godot project")
	var refuge: Dictionary = Battle.resolve_return_room("gd_refuge")
	_check(str(refuge["scene"]) == "res://scenes/garden_refuge.tscn",
		"Garden Refuge preserves its nonstandard scene filename")

	for bad in ["", "../outside", "not_a_real_room", "P1_BELLHOLLOW_BRIDGE"]:
		var result: Dictionary = Battle.resolve_return_room(bad)
		_check(bool(result["fallback"]) and str(result["room"]) == "p1",
			"invalid return is remapped to P1 instead of corrupting saved position")
		_check(str(result["scene"]) == Title.FALLBACK_SCENE,
			"invalid room scene resolves to safe P1 fallback")

	var gs = PositionStub.new()
	root.add_child(gs)
	var battle = Battle.new()
	battle.game_state = gs
	battle.scene_changer = Callable(self, "_navigate")
	battle._cfg = {
		"player_party_index": -1,
		"return_room": "gd7",
		"return_pos": Vector2(-312, 48)
	}
	battle._return_to_room()
	_check(_target == "res://scenes/room_gd7.tscn",
		"real battle return opens the original Garden room")
	_check(str(gs.location.get("room", "")) == "gd7"
		and is_equal_approx(float(gs.location.get("x", 0)), -312.0)
		and is_equal_approx(float(gs.location.get("y", 0)), 48.0),
		"real battle return keeps the exact position")
	battle._cfg["return_room"] = "gd_refuge"
	battle._cfg["return_pos"] = Vector2(34, 66)
	battle._return_to_room()
	_check(_target == "res://scenes/garden_refuge.tscn" and
		str(gs.location.get("room", "")) == "gd_refuge",
		"nonstandard cottage room is fully routable after battle")
	battle._cfg["return_room"] = "missing_room"
	battle._return_to_room()
	_check(_target == Title.FALLBACK_SCENE,
		"unknown battle return uses valid fallback scene")
	_check(str(gs.location.get("room", "")) == "p1" and
		float(gs.location.get("x", -1)) == 0.0 and
		float(gs.location.get("y", -1)) == 0.0,
		"unknown return also resets saved room/position to matching fallback")
	battle.free()
	gs.queue_free()
	if _failed == 0:
		print("[BATTLE RETURNS] PASS %d checks" % _checks)
	else:
		push_error("[BATTLE RETURNS] FAIL %d/%d checks" % [_failed, _checks])
	quit(1 if _failed > 0 else 0)

func _navigate(path: String) -> void:
	_target = path

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		push_error("[BATTLE RETURNS] " + message)
