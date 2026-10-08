extends SceneTree
## Headless M1 room verification: each room loads, background texture is
## present, player spawns, Luna follows, exits/triggers/NPCs are wired,
## exit metadata is correct, no script errors.
##
## Run: Godot --headless --path <project> -s res://scripts/room_test.gd

var _frame: int = 0
var _room = null
var _room_index: int = -1
var _checks: Dictionary = {}
var _failed: int = 0

const ROOMS: Array = [
	{"scene": "res://scenes/room_p1.tscn", "id": "p1", "bg": true,
	 "npcs": ["Mira", "WoundedSoldier"], "dummies": 0, "spawner": true,
	 "triggers": ["tutorial", "bridge_end"], "exits": 0},
	{"scene": "res://scenes/room_p3.tscn", "id": "p3", "bg": true,
	 "npcs": [], "dummies": 0,
	 "triggers": [], "exits": 1, "exit_target": "res://scenes/room_c1.tscn"},
	{"scene": "res://scenes/room_c1.tscn", "id": "c1", "bg": true,
	 "npcs": ["Styx"], "dummies": 0,
	 "triggers": ["bounty_a", "tentacle_b"], "exits": 1, "exit_target": "res://scenes/room_h1.tscn"},
]


func _initialize() -> void:
	print("[TEST] room test starting")


func _physics_process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_load_next_room()
		return false
	if _room_index >= 0 and _room != null and _frame % 10 == 0:
		# Give the room a few frames, then verify and move on.
		_verify_room(ROOMS[_room_index])
		# Detach immediately (not just queue_free) so the next room's
		# group lookups can't see stale nodes.
		_room.get_parent().remove_child(_room)
		_room.queue_free()
		_room = null
		_load_next_room()
	if _room_index >= ROOMS.size():
		_report()
		quit(1 if _failed > 0 else 0)
	return false


func _load_next_room() -> void:
	_room_index += 1
	if _room_index >= ROOMS.size():
		return
	var spec: Dictionary = ROOMS[_room_index]
	var ps: PackedScene = load(spec["scene"])
	_room = ps.instantiate()
	root.add_child(_room)


func _verify_room(spec: Dictionary) -> void:
	var id := str(spec["id"])
	_check(id + "_room_id", _room.room_id == id)
	var bg := _room.get_node_or_null("Background") as Sprite2D
	_check(id + "_background", bg != null and bg.texture != null)
	var player: Node = _room.get_node_or_null("Player")
	_check(id + "_player", player != null and player.is_in_group("player"))
	var luna: Node = _room.get_node_or_null("Luna")
	_check(id + "_luna", luna != null)
	_check(id + "_luna_target", luna != null and luna.has_method("get_target") and luna.get_target() == player)
	# Camera limits match the room rect.
	var cam = player.get_node_or_null("Camera2D") as Camera2D if player != null else null
	if cam != null:
		var r: Rect2 = _room.room_rect
		_check(id + "_camera_limits",
			cam.limit_left == int(r.position.x) and cam.limit_top == int(r.position.y)
			and cam.limit_right == int(r.end.x) and cam.limit_bottom == int(r.end.y))
	# NPCs.
	for npc_name in spec["npcs"]:
		var npc: Node = _room.get_node_or_null(npc_name)
		_check(id + "_npc_" + str(npc_name).to_lower(),
			npc != null and npc.has_method("_talk") and not (npc.lines as PackedStringArray).is_empty())
	# Dummies.
	var dummy_count := 0
	for child in _room.get_children():
		if child.is_in_group("hittable"):
			dummy_count += 1
	_check(id + "_dummies", dummy_count == int(spec["dummies"]))
	# Wave spawner (replaces static dummies in p1).
	if bool(spec.get("spawner", false)):
		var spawner: Node = _room.get_node_or_null("WaveSpawner")
		var markers := 0
		if spawner != null:
			for child in spawner.get_children():
				if child is Marker2D and child.is_in_group("invader_spawn"):
					markers += 1
		_check(id + "_spawner", spawner != null and spawner.has_method("start_waves"))
		_check(id + "_spawner_markers", markers == 3)
		_check(id + "_spawner_waves", spawner != null and (spawner.get("waves") as Array).size() == 3)
	# Triggers by id.
	var found_triggers: Array = []
	for node in _room.get_tree().get_nodes_in_group("trigger"):
		if node.get_parent() == _room:
			found_triggers.append(str(node.get_meta("trigger_id", "")))
	for tid in spec["triggers"]:
		_check(id + "_trigger_" + str(tid), str(tid) in found_triggers)
	# Exits.
	var exits: Array = []
	for node in _room.get_tree().get_nodes_in_group("exit"):
		if node.get_parent() == _room:
			exits.append(node)
	_check(id + "_exit_count", exits.size() == int(spec["exits"]))
	if spec.has("exit_target") and exits.size() > 0:
		_check(id + "_exit_target", str(exits[0].get_meta("target_scene", "")) == str(spec["exit_target"]))
	# Dialogue box present for NPCs/triggers.
	var box = _room.get_tree().get_first_node_in_group("dialogue_box")
	_check(id + "_dialogue_box", box != null and box.has_method("start_dialogue"))


func _check(name: String, ok: bool) -> void:
	_checks[name] = ok
	if not ok:
		_failed += 1
		print("[TEST] FAIL: ", name)
	else:
		print("[TEST] pass: ", name)


func _report() -> void:
	var total := _checks.size()
	print("[TEST] room results: ", total - _failed, "/", total, " PASS")
