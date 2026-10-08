extends SceneTree
## Headless M3 Act 2 verification: all 12 rooms load, exits chain,
## shrines present, NPCs/lore objects/wild zones wired, key data exists,
## no script errors.
##
## Run: Godot --headless --path <project> -s res://scripts/m3_test.gd

var _frame: int = 0
var _room = null
var _room_index: int = -1
var _failed: int = 0
var _passed: int = 0

const ROOMS: Array = [
	{"scene": "res://scenes/room_f1.tscn", "id": "f1", "bg": true, "shrine": "f1_1",
	 "npcs": ["Apprentice"],
	 "npc_art": {"Apprentice": "apprentice"}, "lores": [], "wild": "f1",
	 "exits": [{"scene": "res://scenes/room_f2.tscn", "room": "f2"},
			   {"scene": "res://scenes/room_h1.tscn", "room": "h1"},
			   {"scene": "res://scenes/room_f2.tscn", "room": "f2", "lock": "f2_bridge_repaired"}]},
	{"scene": "res://scenes/room_f2.tscn", "id": "f2", "bg": true, "shrine": "f2_1",
	 "npcs": ["ApprenticeF2", "Smith", "Flint"],
	 "npc_art": {"ApprenticeF2": "apprentice", "Flint": "flint"}, "lores": ["ForgeDoor"], "wild": "",
	 "exits": [{"scene": "res://scenes/room_f3.tscn", "room": "f3"},
			   {"scene": "res://scenes/room_f1.tscn", "room": "f1"}]},
	{"scene": "res://scenes/room_f3.tscn", "id": "f3", "bg": true, "shrine": "f3_1",
	 "npcs": [], "lores": ["PaleRoot1", "PaleRoot2", "PaleRoot3", "Longsword"], "wild": "f3",
	 "exits": [{"scene": "res://scenes/room_g1.tscn", "room": "g1"},
			   {"scene": "res://scenes/room_f2.tscn", "room": "f2"}]},
	{"scene": "res://scenes/room_g1.tscn", "id": "g1", "bg": true, "shrine": "g1_1",
	 "npcs": [], "lores": ["ArmorPlant"], "wild": "",
	 "exits": [{"scene": "res://scenes/room_g2.tscn", "room": "g2"},
			   {"scene": "res://scenes/room_f3.tscn", "room": "f3"}]},
	{"scene": "res://scenes/room_g2.tscn", "id": "g2", "bg": true, "shrine": "g2_1",
	 "npcs": [], "lores": [], "wild": "g2",
	 "tendrils": ["TendrilAnchor1", "TendrilAnchor2", "TendrilAnchor3", "TendrilAnchor4"],
	 "exits": [{"scene": "res://scenes/room_s1.tscn", "room": "s1"},
			   {"scene": "res://scenes/room_g1.tscn", "room": "g1"}]},
	{"scene": "res://scenes/room_s1.tscn", "id": "s1", "bg": true, "shrine": "s1_1",
	 "npcs": [], "lores": ["PaleRootS1", "PaleRootS2", "Gravemaw"], "wild": "s1",
	 "exits": [{"scene": "res://scenes/room_s2.tscn", "room": "s2"},
			   {"scene": "res://scenes/room_g2.tscn", "room": "g2"}]},
	{"scene": "res://scenes/room_s2.tscn", "id": "s2", "shrine": "s2_1",
	 "npcs": ["Tucker", "SlothElder"],
	 "npc_art": {"SlothElder": "sloth_elder"}, "lores": ["OathCeremony"], "wild": "",
	 "exits": [{"scene": "res://scenes/room_c2.tscn", "room": "c2"},
			   {"scene": "res://scenes/room_s1.tscn", "room": "s1"}]},
	{"scene": "res://scenes/room_c2.tscn", "id": "c2", "bg": true, "shrine": "c2_1",
	 "npcs": [], "lores": ["MiniCannon", "Fence"], "wild": "",
	 "exits": [{"scene": "res://scenes/room_v1.tscn", "room": "v1"},
			   {"scene": "res://scenes/room_s2.tscn", "room": "s2"}]},
	{"scene": "res://scenes/room_v1.tscn", "id": "v1", "bg": true, "shrine": "v1_1",
	 "npcs": ["Innkeeper"],
	 "npc_art": {"Innkeeper": "innkeeper"}, "lores": ["ProjectionEntry"], "wild": "",
	 "exits": [{"scene": "res://scenes/room_b1.tscn", "room": "b1"},
			   {"scene": "res://scenes/room_c2.tscn", "room": "c2"}]},
	{"scene": "res://scenes/room_b1.tscn", "id": "b1", "bg": true, "shrine": "b1_1",
	 "npcs": [], "lores": ["SilverBloom1", "SilverBloom2", "SilverBloom3", "Bellmaw"], "wild": "",
	 "exits": [{"scene": "res://scenes/room_d1.tscn", "room": "d1"},
			   {"scene": "res://scenes/room_v1.tscn", "room": "v1"}]},
	{"scene": "res://scenes/room_d1.tscn", "id": "d1", "shrine": "d1_1",
	 "npcs": [], "lores": [], "wild": "d1",
	 "exits": [{"scene": "res://scenes/room_d2.tscn", "room": "d2"},
			   {"scene": "res://scenes/room_b1.tscn", "room": "b1"}]},
	{"scene": "res://scenes/room_d2.tscn", "id": "d2", "bg": true, "shrine": "d2_1",
	 "npcs": [], "lores": ["SummitBoss"], "wild": "",
	 "exits": [{"scene": "res://scenes/room_d1.tscn", "room": "d1"}]},
]


func _initialize() -> void:
	print("[TEST] m3 test starting")


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("[TEST] FAIL: " + label)


func _physics_process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_check_data()
		_load_next_room()
		return false
	if _room_index >= 0 and _room != null and _frame % 8 == 0:
		_verify_room(ROOMS[_room_index])
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
	_check(ps != null and ps.can_instantiate(), "scene loads: " + str(spec["scene"]))
	if ps == null or not ps.can_instantiate():
		_room = null
		return
	_room = ps.instantiate()
	root.add_child(_room)


func _verify_room(spec: Dictionary) -> void:
	if _room == null:
		_check(false, "room instantiated: " + str(spec["id"]))
		return
	var rid: String = str(_room.get("room_id"))
	_check(rid == str(spec["id"]), "room_id == " + str(spec["id"]) + " (got " + rid + ")")
	# Core nodes.
	_check(_room.get_node_or_null("Player") != null, rid + ": Player present")
	_check(_room.get_node_or_null("Luna") != null, rid + ": Luna present")
	_check(_room.get_node_or_null("DialogueBox") != null, rid + ": DialogueBox present")
	if (spec as Dictionary).get("bg", false):
		var bg := _room.get_node_or_null("Background") as Sprite2D
		_check(bg != null and bg.texture != null, rid + ": Background art wired")
	# Shrine.
	var found_shrine := false
	for child in _room.get_children():
		if child.has_method("get") and str(child.get("shrine_id")) == str(spec["shrine"]):
			found_shrine = true
	_check(found_shrine, rid + ": shrine " + str(spec["shrine"]) + " present")
	# NPCs.
	for npc_name in spec["npcs"]:
		_check(_room.get_node_or_null(npc_name) != null, rid + ": NPC " + npc_name + " present")
	# NPC art wiring.
	var art_map: Dictionary = (spec as Dictionary).get("npc_art", {})
	for npc_name in art_map.keys():
		var npc = _room.get_node_or_null(str(npc_name))
		var want: String = str(art_map[npc_name])
		_check(npc != null and str(npc.get("art_id")) == want,
			rid + ": NPC " + str(npc_name) + " art_id=" + want)
		_check(ResourceLoader.exists("res://assets/npc/" + want + ".png"),
			rid + ": art file assets/npc/" + want + ".png exists")
	# Lore objects.
	for lore_name in spec["lores"]:
		var lo = _room.get_node_or_null(lore_name)
		_check(lo != null, rid + ": lore object " + lore_name + " present")
		if lo != null:
			_check(lo.get("lines") != null and (lo.get("lines") as PackedStringArray).size() > 0,
				rid + ": " + lore_name + " has dialogue lines")
	# Tendrils (climbable traversal).
	for tendril_name in (spec as Dictionary).get("tendrils", []):
		var tn = _room.get_node_or_null(str(tendril_name))
		_check(tn != null, rid + ": tendril " + str(tendril_name) + " present")
		if tn != null:
			var wps: PackedVector2Array = tn.get("waypoints")
			_check(wps != null and wps.size() >= 2,
				rid + ": " + str(tendril_name) + " has ride path")
			_check(float(tn.get("ride_speed")) > 0.0,
				rid + ": " + str(tendril_name) + " has ride speed")
			_check(str(tn.get("prompt_text")).contains("tendril"),
				rid + ": " + str(tendril_name) + " has grab prompt")
	# Wild zone.
	if str(spec["wild"]) != "":
		var found_wild := false
		for child in _room.get_children():
			if str(child.get("table_key")) == str(spec["wild"]):
				found_wild = true
		_check(found_wild, rid + ": wild zone table " + str(spec["wild"]))
	# Exits.
	var exits: Array = _room.get_tree().get_nodes_in_group("exit")
	var room_exits: Array = exits.filter(func(e): return e.get_parent() == _room)
	_check(room_exits.size() == (spec["exits"] as Array).size(),
		rid + ": exit count " + str(room_exits.size()) + " == " + str((spec["exits"] as Array).size()))
	for es in spec["exits"]:
		var ok := false
		var exit_node: Area2D = null
		for e in room_exits:
			if str(e.get_meta("target_scene", "")) == str(es["scene"]) \
			and str(e.get_meta("target_room_id", "")) == str(es["room"]):
				ok = true
				exit_node = e
		_check(ok, rid + ": exit -> " + str(es["room"]) + " (" + str(es["scene"]) + ")")
		_check(FileAccess.file_exists(str(es["scene"])),
			rid + ": exit target file exists " + str(es["scene"]))
		# Spawn-clearance: landing spot must be >= 200px from every exit
		# in the target room (prevents instant bounce-back loops).
		if exit_node != null:
			var spawn: Vector2 = exit_node.get_meta("spawn", Vector2.ZERO)
			var tps: PackedScene = load(str(es["scene"]))
			if tps != null and tps.can_instantiate():
				var troom = tps.instantiate()
				root.add_child(troom)
				for te in get_nodes_in_group("exit"):
					if te.get_parent() == troom:
						var d: float = (te.position - spawn).length()
						_check(d >= 200.0, rid + ": spawn clear of " + str(es["room"]) + " exit (" + str(int(d)) + "px)")
				troom.get_parent().remove_child(troom)
				troom.queue_free()
	# player_spawn itself must be clear of this room's own exits.
	var ps: Vector2 = _room.get("player_spawn")
	for e in room_exits:
		var d: float = (e.position - ps).length()
		_check(d >= 200.0, rid + ": player_spawn clear of own exit (" + str(int(d)) + "px)")


func _check_data() -> void:
	var items = _load_json("res://data/items.json")
	_check((items.get("items", {}) as Dictionary).has("fathers_longsword"), "data: fathers_longsword item exists")
	# Living Fabricator feedstock + products.
	for fid in ["broken_sword", "rusted_key", "iron_beam", "silvered_ore", "ash_bark", "briar_thorns", "living_key"]:
		_check((items.get("items", {}) as Dictionary).has(fid), "data: fabricator item " + fid)
	# BrokenCrossing exit is locked behind the bridge repair flag.
	var f1text := FileAccess.get_file_as_string("res://scenes/room_f1.tscn")
	_check(f1text.contains("BrokenCrossing") and f1text.contains("f2_bridge_repaired"),
		"f1: BrokenCrossing exit gated on f2_bridge_repaired")
	_check(f1text.contains("act2_unlocked"), "f1: act2 flag trigger present")
	var f2text := FileAccess.get_file_as_string("res://scenes/room_f2.tscn")
	_check(f2text.contains("SupplyDoor") and f2text.contains("key_door.gd"),
		"f2: SupplyDoor (living key) present")
	var g1text := FileAccess.get_file_as_string("res://scenes/room_g1.tscn")
	_check(g1text.contains("FabricatorStation") and g1text.contains("fabricator_station.gd"),
		"g1: FabricatorStation present")
	var shops = _load_json("res://data/shop.json")
	var smithy = (shops.get("shops", {}) as Dictionary).get("forge_smithy", {})
	_check(not (smithy as Dictionary).is_empty(), "data: forge_smithy shop exists")
	_check(((smithy as Dictionary).get("stock", []) as Array).size() >= 3, "data: forge_smithy has stock")
	var enc = _load_json("res://data/encounters.json")
	for key in ["f1", "f3", "g2", "s1", "d1"]:
		_check((enc.get(key, []) as Array).size() > 0, "data: encounter table " + key)
	# h1 -> f1 entry exit exists in the saved scene text.
	var h1text := FileAccess.get_file_as_string("res://scenes/room_h1.tscn")
	_check(h1text.contains("ExitM3") and h1text.contains("room_f1.tscn"), "data: h1 has ExitM3 -> f1")


func _load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}


func _report() -> void:
	print("[TEST] m3: %d passed, %d failed" % [_passed, _failed])
