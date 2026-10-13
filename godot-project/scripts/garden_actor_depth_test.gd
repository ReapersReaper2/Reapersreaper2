extends SceneTree
## Painted-garden y-depth regression, no native sprites or asset approval.
## godot --headless --path godot-project --script res://scripts/garden_actor_depth_test.gd
const Depth := preload("res://scripts/garden_actor_depth.gd")
const GD1 := preload("res://scenes/room_gd1.tscn")
const GD2 := preload("res://scenes/room_gd2.tscn")
const GD3 := preload("res://scenes/room_gd3.tscn")

class FakeResident:
	extends Sprite2D
	var ground_y: float = 0.0
	func depth_ground_y() -> float:
		return ground_y

var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(Depth.layer_for_ground_y(-250.0) < Depth.layer_for_ground_y(-150.0),
		"northern positions sort behind southern positions")
	_check(Depth.layer_for_ground_y(90.0) > Depth.layer_for_ground_y(-15.0),
		"southern figures draw in front of a northern tree")
	_check(Depth.layer_for_ground_y(50000.0) <= 1900 and
		Depth.layer_for_ground_y(-50000.0) >= -1890,
		"all actor layers stay within garden canvas Z bounds")

	for scene in [GD1, GD2, GD3]:
		var room = scene.instantiate()
		_check(room.get_node_or_null("GardenActorDepth") != null,
			"painted garden room includes a Y-sort controller: " + room.name)
		room.free()

	var room := Node2D.new()
	root.add_child(room)
	var player := Node2D.new()
	player.name = "Player"
	player.position = Vector2(20, -150)
	room.add_child(player)
	var luna := Node2D.new()
	luna.name = "Luna"
	luna.position = Vector2(0, -155)
	luna.z_index = 10
	room.add_child(luna)
	var ivy := Node2D.new()
	ivy.name = "Ivy"
	ivy.position = Vector2(100, -100)
	room.add_child(ivy)
	var residents := Node2D.new()
	residents.name = "Creatures"
	room.add_child(residents)
	var dragon = FakeResident.new()
	dragon.name = "Dragonthorn"
	dragon.position = Vector2(100, -190)
	dragon.ground_y = -205.0
	residents.add_child(dragon)
	var prompt := Label.new()
	prompt.name = "Dragonthorn_InteractPrompt"
	residents.add_child(prompt)
	var sensor := Area2D.new()
	sensor.name = "Dragonthorn_Awareness"
	sensor.z_index = 550
	residents.add_child(sensor)
	var guide := Depth.new()
	room.add_child(guide)
	guide._ready()
	_check(player.z_index == -86 and not player.z_as_relative,
		"Mollosar is placed by grounded painted feet (+64px)")
	_check(luna.z_index == -143 and not luna.z_as_relative,
		"Luna follows the same ground-depth convention")
	_check(ivy.z_index == -100, "stationary Ivy keeps her authored contact point")
	_check(dragon.z_index == -205,
		"resident hovers but depth stays at contact baseline, not animated bob")
	_check(prompt.z_index == -204 and not prompt.z_as_relative,
		"interaction caption appears above its own resident at any depth")
	_check(sensor.z_index == 550, "invisible proximity sensors are not sorted")

	var tree_ground := -40.0 + 18.0
	_check(player.z_index < int(tree_ground) and dragon.z_index < int(tree_ground),
		"creatures and Mollosar behind a nearer painted tree")
	player.position.y = 75.0
	dragon.position.y = 90.0
	dragon.ground_y = 90.0
	guide.apply_depths()
	_check(player.z_index == 139 and player.z_index > int(tree_ground),
		"walking in front of tree moves Mollosar to foreground")
	_check(dragon.z_index == 90 and prompt.z_index == 91,
		"resident/prompt sort updates after movement without scene reload")
	_check(sensor.z_index == 550, "sensor retains its untouched draw state")
	room.queue_free()

	if _failures == 0:
		print("[GARDEN ACTOR DEPTH] PASS %d checks" % _checks)
	else:
		push_error("[GARDEN ACTOR DEPTH] FAIL %d/%d" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("[GARDEN ACTOR DEPTH] " + description)
