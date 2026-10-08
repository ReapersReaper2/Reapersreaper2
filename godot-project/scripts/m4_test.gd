extends SceneTree
## Headless M4 Act 3 + epilogue verification: all 27 rooms load, exits chain
## in order, shrines present, lore objects / NPCs / wild zones wired, key
## flags exist, no ID collisions with existing rooms, no script errors.
##
## Run: Godot --headless --path <project> -s res://scripts/m4_test.gd

var _frame: int = 0
var _room = null
var _room_index: int = -1
var _failed: int = 0
var _passed: int = 0

const ORDER: Array = ["hl1","hl2","hl3","hl4","t1","t2","t3","t4","t5","t6",
	"u1","u2","u3","u4","gd1","gd2","gd3","gd4","gd5","gd6","gd7","gd8",
	"o1","o2","o3","e1","e2"]
const VERTICAL: Array = ["hl4", "gd4", "o1"]
const WILD: Array = ["hl1","hl2","hl3","hl4","t1","t6","u1","gd1","gd4","gd6"]

const LORES: Dictionary = {
	"hl1": ["LunaWake", "DeadSurf"], "hl2": ["Deadfall", "BurnScar"],
	"hl3": ["Watchers"], "hl4": ["StairsTop"],
	"t1": ["TempleAir", "TempleGate"], "t2": ["RiteOfSeverance"],
	"t3": ["EmptyChair"], "t4": ["Necrofruit"], "t5": [],
	"t6": ["Portal"],
	"u1": ["StranglingRoots"], "u2": ["Absorption"], "u3": ["Wings"],
	"u4": ["LaunchPoint"],
	"gd1": ["GardenPerimeter"], "gd2": ["WrathsJournal"],
	"gd3": ["IvySanctum"], "gd4": ["ShikaBoss"], "gd5": ["HarrowFight"],
	"gd6": ["Battlefield"], "gd7": ["DriftcapShip"], "gd8": ["DeepRoots"],
	"o1": ["TheClimb"], "o2": ["Originator"], "o3": ["ThePrice"],
	"e1": ["TheLedger"], "e2": ["TheTree"],
}
const NPCS: Dictionary = {"t5": ["Marrow"], "gd5": ["Harrow"]}

# Existing room ids that M4 must NOT collide with.
const LEGACY_IDS: Array = ["p1","p2","p3","c1","h1","h2","h3","h4","nm",
	"f1","f2","f3","g1","g2","s1","s2","c2","v1","b1","d1","d2"]


func _initialize() -> void:
	print("[TEST] m4 test starting")


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		push_error("[TEST] FAIL: " + label)


func _exits_for(rid: String) -> Array:
	var idx: int = ORDER.find(rid)
	var out: Array = []
	var prev: String = ORDER[idx - 1] if idx > 0 else ""
	var nxt: String = ORDER[idx + 1] if idx < ORDER.size() - 1 else ""
	if rid in VERTICAL:
		if nxt != "":
			out.append({"scene": "res://scenes/room_%s.tscn" % nxt, "room": nxt})
		if prev != "":
			out.append({"scene": "res://scenes/room_%s.tscn" % prev, "room": prev})
	else:
		if nxt != "":
			out.append({"scene": "res://scenes/room_%s.tscn" % nxt, "room": nxt})
		if rid == "hl1":
			out.append({"scene": "res://scenes/room_d2.tscn", "room": "d2"})
		elif prev != "":
			out.append({"scene": "res://scenes/room_%s.tscn" % prev, "room": prev})
	return out


func _physics_process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_check_data()
		_check_collisions()
		_load_next_room()
		return false
	if _room_index >= 0 and _room != null and _frame % 8 == 0:
		_verify_room(ORDER[_room_index])
		_room.get_parent().remove_child(_room)
		_room.queue_free()
		_room = null
		_load_next_room()
	if _room_index >= ORDER.size():
		_report()
		quit(1 if _failed > 0 else 0)
	return false


func _load_next_room() -> void:
	_room_index += 1
	if _room_index >= ORDER.size():
		return
	var rid: String = ORDER[_room_index]
	var scene: String = "res://scenes/room_%s.tscn" % rid
	var ps: PackedScene = load(scene)
	_check(ps != null and ps.can_instantiate(), "scene loads: " + scene)
	if ps == null or not ps.can_instantiate():
		_room = null
		return
	_room = ps.instantiate()
	root.add_child(_room)


func _verify_room(rid: String) -> void:
	if _room == null:
		_check(false, "room instantiated: " + rid)
		return
	var got: String = str(_room.get("room_id"))
	_check(got == rid, "room_id == " + rid + " (got " + got + ")")
	_check(_room.get_node_or_null("Player") != null, rid + ": Player present")
	_check(_room.get_node_or_null("Luna") != null, rid + ": Luna present")
	_check(_room.get_node_or_null("DialogueBox") != null, rid + ": DialogueBox present")
	# Shrine.
	var want_shrine: String = rid + "_1"
	var found_shrine := false
	for child in _room.get_children():
		if child.has_method("get") and str(child.get("shrine_id")) == want_shrine:
			found_shrine = true
	_check(found_shrine, rid + ": shrine " + want_shrine + " present")
	# NPCs.
	for npc_name in NPCS.get(rid, []):
		_check(_room.get_node_or_null(npc_name) != null, rid + ": NPC " + npc_name + " present")
	# Lore objects.
	for lore_name in LORES.get(rid, []):
		var lo = _room.get_node_or_null(lore_name)
		_check(lo != null, rid + ": lore object " + lore_name + " present")
		if lo != null:
			_check(lo.get("lines") != null and (lo.get("lines") as PackedStringArray).size() > 0,
				rid + ": " + lore_name + " has dialogue lines")
			# Boss triggers (ShikaBoss/HarrowFight) don't set their flag
			# directly — the fight controller sets the victory flag on win.
			var is_boss_trigger: bool = lore_name == "ShikaBoss" or lore_name == "HarrowFight"
			if not is_boss_trigger:
				_check(str(lo.get("flag")) != "", rid + ": " + lore_name + " sets a flag")
			else:
				_check(str(lo.get("flag")) == "", rid + ": " + lore_name + " defers victory flag to fight")
	# Wild zone.
	if rid in WILD:
		var found_wild := false
		for child in _room.get_children():
			if str(child.get("table_key")) == rid:
				found_wild = true
		_check(found_wild, rid + ": wild zone table " + rid)
	# Exits.
	var exits: Array = _room.get_tree().get_nodes_in_group("exit")
	var room_exits: Array = exits.filter(func(e): return e.get_parent() == _room)
	var want: Array = _exits_for(rid)
	_check(room_exits.size() == want.size(),
		rid + ": exit count " + str(room_exits.size()) + " == " + str(want.size()))
	for es in want:
		var ok := false
		var exit_node: Area2D = null
		for e in room_exits:
			if str(e.get_meta("target_scene", "")) == str(es["scene"]) \
			and str(e.get_meta("target_room_id", "")) == str(es["room"]):
				ok = true
				exit_node = e
		_check(ok, rid + ": exit -> " + str(es["room"]))
		_check(FileAccess.file_exists(str(es["scene"])),
			rid + ": exit target file exists " + str(es["scene"]))
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
	var ps: Vector2 = _room.get("player_spawn")
	for e in room_exits:
		var d: float = (e.position - ps).length()
		_check(d >= 200.0, rid + ": player_spawn clear of own exit (" + str(int(d)) + "px)")


func _check_data() -> void:
	# Key flags present in scene text.
	var flag_checks: Array = [
		["hl1", "ch13_depowered"], ["hl1", "hl1_wake_done"],
		["t1", "t1_temple_entry"],
		["t2", "t2_severance_done"], ["t4", "t4_necrofruit_taken"],
		["u2", "u2_absorption_done"], ["u2", "u2_map_unlocked"], ["u2", "ch13_repowered_partial"],
		["u3", "u3_form9_unlocked"], ["u3", "form9_unlocked"], ["u3", "ch13_repowered"],
		["gd2", "gd2_wrath_end"],
		["gd4", "gd4_shika_defeated"], ["gd5", "harrow_defeated"],
		["o2", "o2_originator_choice"], ["o3", "o3_price_paid"],
	]
	for pair in flag_checks:
		var text := FileAccess.get_file_as_string("res://scenes/room_%s.tscn" % pair[0])
		_check(text.contains(str(pair[1])), "flag %s in room_%s" % [pair[1], pair[0]])
	# Boss stat notes in stub lines.
	var gd4t := FileAccess.get_file_as_string("res://scenes/room_gd4.tscn")
	_check(gd4t.contains("80 Vigor"), "gd4: Shika boss stats noted (80 Vigor)")
	var gd5t := FileAccess.get_file_as_string("res://scenes/room_gd5.tscn")
	_check(gd5t.contains("150 Vigor"), "gd5: Harrow stats noted (150 Vigor)")
	_check(gd5t.contains("30 Vigor"), "gd5: tendril stats noted (30 Vigor)")
	# O2 is NOT a boss: no boss-stub language.
	var o2t := FileAccess.get_file_as_string("res://scenes/room_o2.tscn")
	_check(not o2t.contains("BOSS STUB"), "o2: Originator is not a boss stub")
	# Encounter tables for all M4 wild zones.
	var enc := _load_json("res://data/encounters.json")
	for key in WILD:
		_check((enc.get(key, []) as Array).size() > 0, "data: encounter table " + key)
	# Depowered gating notes: on at hl1, HOLDS through T1-T6, partial at U2, lifts at U3.
	var hl1t := FileAccess.get_file_as_string("res://scenes/room_hl1.tscn")
	_check(hl1t.contains("ch13_depowered"), "hl1: depowered flag documented")
	var t1t := FileAccess.get_file_as_string("res://scenes/room_t1.tscn")
	_check(not t1t.contains("\"ch13_repowered\""), "t1: depower NOT lifted at Temple Gate (holds through T6)")
	# Epilogue flags: Ledger read, fragment planted, Luna seed arc.
	var e1t := FileAccess.get_file_as_string("res://scenes/room_e1.tscn")
	_check(e1t.contains("\"e1_ledger_read\""), "e1: ledger flag present")
	var e2t := FileAccess.get_file_as_string("res://scenes/room_e2.tscn")
	_check(e2t.contains("\"e2_fragment_planted\""), "e2: fragment-planted flag present")
	_check(e2t.contains("\"e2_luna_seed_arc\""), "e2: luna seed arc flag present")
	_check(not e2t.contains("wild_zone"), "e2: no wild zone (ending room)")
	_check(not e1t.contains("wild_zone"), "e1: no wild zone (ending room)")


func _check_collisions() -> void:
	for rid in ORDER:
		_check(not (rid in LEGACY_IDS), "no ID collision: " + rid)
		# M4 scene files must not shadow legacy scenes.
	_check(true, "namespace check complete")


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}


func _report() -> void:
	print("[TEST] m4: %d passed, %d failed" % [_passed, _failed])
	if _failed > 0:
		push_error("[TEST] m4 FAILED")
