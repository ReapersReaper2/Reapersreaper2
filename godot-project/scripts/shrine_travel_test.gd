extends SceneTree
## Headless Lantern Shrine fast-travel test: network lighting on rest,
## destination listing, travel execution, menu wiring, save persistence.
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/shrine_travel_test.gd
## Uses throwaway slot 96 so real saves are never touched.
##
## Same cold-tree pattern as shrine_test: inject dependencies, call
## internals directly.

const SLOT := 96

var _failures: Array[String] = []


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failures.append(name)
		print("  FAIL: ", name)


func _make_stack() -> Array:
	var save_system_script = load("res://scripts/save_system.gd")
	var game_state_script = load("res://scripts/game_state.gd")
	var ach_script = load("res://scripts/achievements.gd")
	var ss = save_system_script.new()
	root.add_child(ss)
	var ach = ach_script.new()
	root.add_child(ach)
	var gs = game_state_script.new()
	gs.save_system = ss
	gs.achievements = ach
	root.add_child(gs)
	gs._ready()
	ach.game_state = gs
	return [ss, ach, gs]


func _make_shrine(gs, shrine_id: String, pos: Vector2):
	var shrine = (load("res://scenes/shrine.tscn") as PackedScene).instantiate()
	shrine.shrine_id = shrine_id
	shrine.game_state = gs
	root.add_child(shrine)
	shrine.position = pos
	shrine._ready()
	return shrine


func _initialize() -> void:
	print("=== SHRINE TRAVEL TEST ===")
	var stack: Array = _make_stack()
	var ss = stack[0]
	var gs = stack[2]
	ss.delete_save(SLOT)
	gs.set_current_slot(SLOT)

	# 1. Network starts empty; nothing listed.
	var s1 = _make_shrine(gs, "p1_1", Vector2(100, 200))
	_check("network starts empty", gs.get_lit_shrines().is_empty())
	_check("no destinations when unlit", s1._travel_destinations().is_empty())

	# 2. Resting lights the shrine (room parsed from id, position captured).
	s1.rest()
	var lit: Dictionary = gs.get_lit_shrines()
	_check("rest lights p1_1", lit.has("p1_1"))
	_check("lit room parsed from id", str(lit["p1_1"]["room"]) == "p1")
	_check("lit x captured", float(lit["p1_1"]["x"]) == 100.0)
	_check("lit y captured", float(lit["p1_1"]["y"]) == 200.0)

	# 3. A second shrine, rested: destinations exclude the current one.
	var s2 = _make_shrine(gs, "c1_1", Vector2(300, 400))
	s2.rest()
	var dests: Array = s1._travel_destinations()
	_check("one destination from p1_1", dests.size() == 1)
	_check("destination is c1_1", str(dests[0]["id"]) == "c1_1")
	_check("destination text names the room",
		str(dests[0]["text"]).find("River") >= 0)
	var dests2: Array = s2._travel_destinations()
	_check("destination from c1_1 is p1_1",
		dests2.size() == 1 and str(dests2[0]["id"]) == "p1_1")

	# 4. Travel executes: returns the scene path, sets the spawn position.
	var path: String = s1._travel_to("c1_1")
	_check("travel returns room_c1 scene", path == "res://scenes/room_c1.tscn")
	var pos: Dictionary = gs.get_position()
	_check("travel sets target room", str(pos["room"]) == "c1")
	_check("travel sets spawn x", float(pos["x"]) == 300.0)
	_check("travel sets spawn y", float(pos["y"]) == 400.0)

	# 5. Unknown / unlit destinations fail safe.
	_check("travel to unknown returns empty", s1._travel_to("zz_9") == "")
	_check("travel to unlit returns empty", s1._travel_to("h1_1") == "")

	# 6. Shrine menu now has four entries, TRAVEL second.
	s1._open_shrine_menu()
	var ids: Array = []
	for b in s1._menu_buttons:
		ids.append(str(b["id"]))
	_check("menu has 4 entries", ids == ["rest", "travel", "vault", "leave"])
	s1._close_shrine_menu()

	# 7. Travel submenu lists destinations + BACK.
	s1._open_shrine_menu()
	s1._menu_selected = 1  # TRAVEL
	s1._activate_menu_item()
	var tids: Array = []
	for b in s1._menu_buttons:
		tids.append(str(b["id"]))
	_check("travel submenu shows dest + back", tids == ["dest:c1_1", "back"])
	s1._close_shrine_menu()

	# 8. Travel submenu with no other lit shrines: BACK only (+ notice).
	var stack_b: Array = _make_stack()
	var ss_b = stack_b[0]
	var gs_b = stack_b[2]
	ss_b.delete_save(SLOT + 1)
	gs_b.set_current_slot(SLOT + 1)
	var lone = _make_shrine(gs_b, "h1_1", Vector2(0, 0))
	lone.rest()
	lone._open_shrine_menu()
	lone._menu_selected = 1
	lone._activate_menu_item()
	var lids: Array = []
	for b in lone._menu_buttons:
		lids.append(str(b["id"]))
	_check("lone shrine travel shows notice + back", lids == ["none", "back"])
	lone._close_shrine_menu()

	# 9. Network persists across save/load.
	gs.save_to_slot(SLOT)
	var stack_c: Array = _make_stack()
	var gs_c = stack_c[2]
	gs_c.set_current_slot(SLOT)
	_check("load round-trip ok", gs_c.load_from_slot(SLOT))
	var lit_c: Dictionary = gs_c.get_lit_shrines()
	_check("lit shrines survive save/load",
		lit_c.has("p1_1") and lit_c.has("c1_1"))
	_check("lit positions survive save/load",
		float(lit_c["c1_1"]["x"]) == 300.0)

	# 10. Static room display names.
	var shrine_script = load("res://scripts/shrine.gd")
	_check("room display name p1", shrine_script.room_display_name("p1") == "Bellhollow Bridge")
	_check("room display name fallback", shrine_script.room_display_name("xx") == "XX")

	print("=== TRAVEL TEST DONE: %d failures ===" % _failures.size())
	if not _failures.is_empty():
		quit(1)
	else:
		quit(0)
