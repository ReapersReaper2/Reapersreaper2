extends SceneTree
## Run from the Godot project directory:
## godot --headless --path . --script res://scripts/garden_world_test.gd
## Deterministic route tests, no imported textures or autoloads required.

const GardenWorld := preload("res://scripts/garden_world.gd")
const TitleScreen := preload("res://scripts/title_screen.gd")
var _failed: int = 0
var _checks: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check_room("gd1", Rect2(-1280, -360, 2560, 720), 117,
		Vector2(300, 100), Vector2(-1000, 200),
		PackedVector2Array([Vector2(-500, 165), Vector2(-750, -140),
			Vector2(-350, 180), Vector2(420, -120), Vector2(700, 160), Vector2(950, -100)]))
	_check_room("gd2", Rect2(-640, -360, 1280, 720), 227,
		Vector2(0, 50), Vector2(-360, 200), PackedVector2Array())
	_check_room("gd3", Rect2(-640, -360, 1280, 720), 319,
		Vector2(120, -80), Vector2(-360, 200),
		PackedVector2Array([Vector2(320, -100), Vector2(380, -40), Vector2(260, -160)]))
	_check(Vector2(-500, 265).distance_to(Vector2(-500, 118)) > 120.0,
		"refuge return spawn must be outside garden door trigger + player capsule")
	_check(Vector2(0, 130).distance_to(Vector2(0, 295)) > 120.0,
		"refuge interior spawn must be outside return door trigger")
	_check(TitleScreen.scene_for_room("gd_refuge") == "res://scenes/garden_refuge.tscn",
		"Continue must restore the refuge")
	_check(TitleScreen.scene_for_room("gd2") == "res://scenes/room_gd2.tscn",
		"Continue must restore later garden rooms")
	if _failed == 0:
		print("[GARDEN WORLD TEST] PASS %d checks" % _checks)
	else:
		push_error("[GARDEN WORLD TEST] FAILED %d/%d checks" % [_failed, _checks])
	quit(1 if _failed > 0 else 0)

func _check_room(room_id: String, rect: Rect2, seed_number: int,
	landmark_pos: Vector2, shrine_pos: Vector2, extra: PackedVector2Array) -> void:
	var garden = GardenWorld.new()
	garden.bounds = rect
	garden.seed_value = seed_number
	garden.landmark = landmark_pos
	garden.shrine = shrine_pos
	garden.feature_points = extra
	var left := Vector2(rect.position.x + 70.0, 100.0)
	var right := Vector2(rect.end.x - 70.0, 100.0)
	_check(garden._walkway(left), room_id + " west exit must be clear")
	_check(garden._walkway(right), room_id + " east exit must be clear")
	for i in range(25):
		var x: float = lerpf(left.x, right.x, float(i) / 24.0)
		var spine := Vector2(x, garden._route_y(x))
		_check(garden._walkway(spine), room_id + " main route must stay open")
	var landmarks := PackedVector2Array([landmark_pos, shrine_pos])
	landmarks.append_array(extra)
	for destination in landmarks:
		_check(garden._walkway(destination), room_id + " feature must be accessible")
		var spine := Vector2(destination.x, garden._route_y(destination.x))
		_check(garden._walkway(destination.lerp(spine, 0.5)),
			room_id + " side path must connect to main road")
	garden.free()

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failed += 1
		push_error("[GARDEN WORLD TEST] " + description)
