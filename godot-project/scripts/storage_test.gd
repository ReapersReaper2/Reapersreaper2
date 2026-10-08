extends SceneTree
## Headless Soul Vault (storage) test: deposit/withdraw/move/release,
## box capacity, full-party catch routing, withdraw blocking, save/load
## round-trip, storage UI open/close, shrine menu wiring.
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/storage_test.gd
## Uses throwaway slot 94 so real saves are never touched.
##
## NOTE: under -s, nodes added here are not inside the tree yet, so the test
## injects dependencies and calls internals directly — the same pattern as
## party_test / shrine_test.

const SLOT := 94

const Party = preload("res://scripts/party.gd")
const Storage = preload("res://scripts/storage.gd")

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


func _initialize() -> void:
	print("[STORAGE TEST]")
	var stack := _make_stack()
	var gs = stack[2]
	gs.set_current_slot(SLOT)  # rest()/save paths must never touch real slots

	# --- basics ---
	_check("vault starts empty", Storage.total_stored(gs) == 0)
	_check("not full", not Storage.is_full(gs))
	_check("first free slot is box 0 slot 0",
		Storage.first_free_slot(gs) == [0, 0])
	Party.new_game_party(gs)  # starter snapling
	_check("party has starter", Party.size(gs) == 1)

	# --- deposit ---
	var spot: Array = Storage.deposit(gs, 0)
	_check("deposit returns [0,0]", spot == [0, 0])
	_check("party shrunk", Party.size(gs) == 0)
	_check("box 0 has 1", Storage.box_count(gs, 0) == 1)
	_check("stored entry is the snapling",
		str(Storage.get_entry(gs, 0, 0).get("creature_id")) == "snapling")
	_check("deposit invalid index fails", Storage.deposit(gs, 5) == [-1, -1])

	# --- withdraw ---
	Party.add_creature(gs, "siltmaw", 4)
	_check("withdraw to party", Storage.withdraw(gs, 0, 0))
	_check("party now 2", Party.size(gs) == 2)
	_check("box 0 empty", Storage.box_count(gs, 0) == 0)
	_check("withdrawn entry kept level",
		int(Party.get_entry(gs, 1).get("level")) == 5)
	_check("withdraw empty slot fails", not Storage.withdraw(gs, 0, 0))

	# --- withdraw blocked when party full ---
	for i in 4:
		Party.add_creature(gs, "snapling", 3)
	_check("party full at 6", Party.size(gs) == 6)
	Party.remove_creature(gs, 0)
	Storage.deposit(gs, 0)  # one creature in the vault
	for i in 2:
		Party.add_creature(gs, "snapling", 3)
	_check("party full again", Party.size(gs) == 6)
	_check("withdraw blocked when party full", not Storage.withdraw(gs, 0, 0))
	_check("entry still in vault", Storage.box_count(gs, 0) == 1)
	Party.remove_creature(gs, 0)
	_check("withdraw works after room", Storage.withdraw(gs, 0, 0))

	# --- move_within_box ---
	Storage.deposit(gs, 0)
	Storage.deposit(gs, 0)
	_check("two in box", Storage.box_count(gs, 0) == 2)
	Party.add_creature(gs, "thornchoir", 6)
	Storage.deposit(gs, Party.size(gs) - 1)
	var first_id := str(Storage.get_entry(gs, 0, 0).get("creature_id"))
	var third_id := str(Storage.get_entry(gs, 0, 2).get("creature_id"))
	_check("swap within box", Storage.move_within_box(gs, 0, 0, 2))
	_check("swap took effect",
		str(Storage.get_entry(gs, 0, 0).get("creature_id")) == third_id
		and str(Storage.get_entry(gs, 0, 2).get("creature_id")) == first_id)
	_check("swap invalid fails", not Storage.move_within_box(gs, 0, 0, 9))

	# --- move_between_boxes ---
	_check("move to box 1", Storage.move_between_boxes(gs, 0, 0, 1, 0))
	_check("box 0 shrunk", Storage.box_count(gs, 0) == 2)
	_check("box 1 grew", Storage.box_count(gs, 1) == 1)
	_check("move invalid fails", not Storage.move_between_boxes(gs, 0, 9, 1, 0))

	# --- release ---
	var released: Dictionary = Storage.release(gs, 1, 0)
	_check("release returns entry", not released.is_empty())
	_check("box 1 empty after release", Storage.box_count(gs, 1) == 0)
	_check("release invalid returns {}", Storage.release(gs, 1, 0).is_empty())

	# --- capacity: fill box 0 to BOX_SIZE ---
	while Storage.box_count(gs, 0) < Storage.BOX_SIZE:
		Storage.deposit_entry(gs, Party.make_entry("snapling", 2))
	_check("box 0 at capacity", Storage.box_count(gs, 0) == Storage.BOX_SIZE)
	_check("first free is box 1", Storage.first_free_slot(gs)[0] == 1)

	# --- save/load round-trip ---
	gs.save_to_slot(SLOT)
	var before := Storage.total_stored(gs)
	gs.state["storage"] = []
	_check("storage wiped in memory", Storage.total_stored(gs) == 0)
	gs.load_from_slot(SLOT)
	_check("storage restored after load", Storage.total_stored(gs) == before)
	_check("box 0 still full", Storage.box_count(gs, 0) == Storage.BOX_SIZE)
	_check("entry identity survived",
		str(Storage.get_entry(gs, 0, 7).get("creature_id")) == "snapling")

	# --- storage UI: open/close + pickup/place ---
	var ui = (load("res://scripts/storage_ui.gd") as GDScript).new()
	ui.game_state = gs
	root.add_child(ui)
	ui._ready()
	_check("ui starts closed", not ui.is_open())
	ui.open()
	_check("ui opens", ui.is_open())
	_check("ui starts on box 0", ui._box == 0)
	# Pickup from box 0 slot 0, place on box 2 (change box, cursor 0).
	ui.activate_slot("box", 0)
	_check("picked up from box", not ui._held.is_empty())
	_check("box 0 slot removed", Storage.box_count(gs, 0) == Storage.BOX_SIZE - 1)
	ui.change_box(1)  # box 1
	ui.change_box(1)  # box 2
	ui.activate_slot("box", 0)
	_check("placed on box 2", Storage.box_count(gs, 2) == 1)
	_check("hand empty after place", ui._held.is_empty())
	# Pick up from box 2, place into party (party has room: size 4).
	ui.activate_slot("box", 0)
	_check("picked up again", not ui._held.is_empty())
	var psize_before := Party.size(gs)
	ui.activate_slot("party", psize_before)  # first empty party slot
	_check("placed into party", Party.size(gs) == psize_before + 1)
	_check("box 2 empty", Storage.box_count(gs, 2) == 0)
	# Close with something held: must not lose the creature.
	ui.activate_slot("box", 0)  # box 0 still has many; pick one up
	var total_before := Storage.total_stored(gs) + Party.size(gs)
	ui.close()
	_check("ui closes", not ui.is_open())
	_check("no creature lost on close",
		Storage.total_stored(gs) + Party.size(gs) == total_before)

	# --- shrine menu wiring ---
	var shrine = (load("res://scenes/shrine.tscn") as PackedScene).instantiate()
	_check("shrine scene loads", shrine != null)
	if shrine == null:
		_finish_with_cleanup(stack)
		return
	shrine.shrine_id = "p1_9"
	shrine.game_state = gs
	root.add_child(shrine)
	shrine._ready()
	_check("menu starts closed", not shrine._menu_open)
	shrine._open_shrine_menu()
	_check("menu opens", shrine._menu_open)
	_check("menu defaults to REST", shrine._menu_id() == "rest")
	_check("four menu buttons", shrine._menu_buttons.size() == 4)
	shrine._close_shrine_menu()
	_check("menu closes", not shrine._menu_open)
	# rest() itself is untouched: still works directly.
	shrine.rest()
	_check("rest sets shrine flag", gs.get_flag("shrine_p1_9"))

	_finish_with_cleanup(stack)


## Cleanup + final report. Split out so an early failure above can't skip
## quit() (a SceneTree that never quits looks like a hang).
func _finish_with_cleanup(stack: Array) -> void:
	var ss2 = stack[0]
	if ss2.has_method("delete_save"):
		ss2.delete_save(SLOT)
	else:
		var dir := DirAccess.open("user://saves")
		if dir != null:
			dir.remove("save_%d.json" % SLOT)

	print("[STORAGE TEST] failures: %d" % _failures.size())
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if _failures.size() > 0 else 0)
