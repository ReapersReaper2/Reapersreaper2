extends SceneTree
## Headless title screen + pause menu test.
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/title_test.gd
## Uses slot 3 as the throwaway (backed up first, restored after) because the
## title screen's slot selector is 1-3 by design.
##
## NOTE: under -s the tree is cold during _initialize(), so the test body runs
## on the first _process() frame when nodes can actually enter the tree.

const SLOT := 3

var _failures: Array[String] = []
var _nav_paths: Array = []
var _ran: bool = false
var _ss = null
var _backup: PackedByteArray = []


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failures.append(name)
		print("  FAIL: ", name)


func _make_stack() -> Array:
	var ss = (load("res://scripts/save_system.gd")).new()
	root.add_child(ss)
	var ach = (load("res://scripts/achievements.gd")).new()
	root.add_child(ach)
	var gs = (load("res://scripts/game_state.gd")).new()
	gs.save_system = ss
	gs.achievements = ach
	root.add_child(gs)
	gs._ready()
	ach.game_state = gs
	return [ss, ach, gs]


func _make_title(gs):
	var ts = (load("res://scripts/title_screen.gd")).new()
	ts.game_state = gs
	ts.scene_changer = _nav_paths.append
	root.add_child(ts)
	return ts


func _make_pause(gs):
	var pm = (load("res://scripts/pause_menu.gd")).new()
	pm.game_state = gs
	pm.scene_changer = _nav_paths.append
	root.add_child(pm)
	return pm


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return true


func _run() -> void:
	print("== title_test ==")
	var stack := _make_stack()
	var ss = stack[0]
	var gs = stack[2]
	_ss = ss
	# Back up any real slot-3 save, then clear the throwaway.
	var slot_path: String = "user://saves/save_%d.json" % SLOT
	if FileAccess.file_exists(slot_path):
		_backup = FileAccess.get_file_as_bytes(slot_path)
	ss.delete_save(SLOT)
	gs.set_current_slot(SLOT)

	# --- Continue disabled with no saves ---
	var ts = _make_title(gs)
	_check("continue disabled with no save", not ts._item_enabled("continue"))
	_check("new game always enabled", ts._item_enabled("new"))
	_check("slot summary empty", ts.slot_summary(SLOT) == "— empty —")

	# --- Menu navigation skips disabled items and wraps ---
	# Items: new(0), continue(1, disabled), settings(2), quit(3). Start at 0.
	_check("starts on new game", ts._selected == 0)
	ts.move_selection(1)
	_check("move down skips disabled continue", ts._selected == 2)
	ts.move_selection(1)
	_check("move down to quit", ts._selected == 3)
	ts.move_selection(1)
	_check("move down wraps to new", ts._selected == 0)
	ts.move_selection(-1)
	_check("move up wraps to quit", ts._selected == 3)
	ts.move_selection(-1)
	_check("move up to settings", ts._selected == 2)
	ts.move_selection(-1)
	_check("move up back to new", ts._selected == 0)

	# --- Settings entry opens the settings panel ---
	ts.activate("settings")
	var sp = ts.get_tree().get_first_node_in_group("settings")
	_check("settings panel opened", sp != null and sp.is_open())
	if sp != null:
		sp.close()
		sp.queue_free()

	# --- New Game starts p1 with fresh state ---
	ts.activate("new")
	_check("new game navigates to room_p1", _nav_paths.size() == 1 and _nav_paths[0] == "res://scenes/room_p1.tscn")
	_check("new game resets form to 1", gs.get_form() == 1)
	_check("new game clears flags", not gs.get_flag("p1_bridge_cleared"))

	# --- Continue enabled with a save present ---
	gs.set_flag("p1_bridge_cleared")
	gs.set_position("c1", 100.0, 200.0)
	gs.state["chapter"] = "chapter one"
	gs.state["playtime"] = 3723.0
	_check("save_to_slot works", gs.save_to_slot(SLOT))
	var ts2 = _make_title(gs)
	_check("continue enabled with save", ts2._item_enabled("continue"))
	var summary: String = ts2.slot_summary(SLOT)
	_check("slot summary shows chapter", "Chapter One" in summary)
	_check("slot summary shows playtime 1:02:03", "1:02:03" in summary)

	# --- Continue restores the saved room ---
	ts2.activate("continue")
	_check("continue navigates to saved room c1", _nav_paths.size() == 2 and _nav_paths[1] == "res://scenes/room_c1.tscn")
	_check("continue restored flag", gs.get_flag("p1_bridge_cleared"))
	var pos: Dictionary = gs.get_position()
	_check("continue restored position", str(pos.get("room")) == "c1" and float(pos.get("x")) == 100.0)

	# --- Slot switching changes current_slot ---
	var ts3 = _make_title(gs)
	var before: int = ts3._slot
	ts3.cycle_slot(1)
	_check("cycle_slot changes slot", ts3._slot != before)
	_check("cycle_slot writes game_state", gs.get_current_slot() == ts3._slot)
	ts3.cycle_slot(-1)
	_check("cycle_slot back restores", ts3._slot == before)

	# --- format_playtime ---
	_check("format_playtime zero", ts3.format_playtime(0.0) == "0:00:00")
	_check("format_playtime padded", ts3.format_playtime(3723.0) == "1:02:03")

	# --- Pause menu: save writes the slot ---
	var pm = _make_pause(gs)
	_check("pause starts closed", not pm.is_open())
	pm.open()
	_check("pause opens and pauses tree", pm.is_open() and paused)
	pm.activate("save")
	_check("pause save wrote slot", ss.has_save(SLOT))
	var info: Dictionary = ss.get_save_info(SLOT)
	_check("pause save has info", bool(info.get("exists", false)))
	pm.close()
	_check("pause closes and unpauses", not pm.is_open() and not paused)

	# --- Pause menu: quit to title ---
	pm.open()
	pm.activate("title")
	_check("quit-to-title navigates to title", _nav_paths.size() == 3 and _nav_paths[2] == "res://scenes/title_screen.tscn")
	_check("quit-to-title unpauses", not paused)
	_check("quit-to-title closes menu", not pm.is_open())

	# --- Pause menu: resume closes ---
	pm.open()
	pm.activate("resume")
	_check("resume closes menu", not pm.is_open() and not paused)

	# --- Pause menu: Esc toggles (room-style guard) ---
	pm.open()
	_check("reopen works", pm.is_open())
	pm.close()
	_check("close works twice", not pm.is_open())

	# Restore the real slot-3 save (or leave it deleted if none existed).
	if _backup.is_empty():
		ss.delete_save(SLOT)
	else:
		var f := FileAccess.open(slot_path, FileAccess.WRITE)
		f.store_buffer(_backup)
		f.close()
	print("== title_test: %d failures ==" % _failures.size())
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if not _failures.is_empty() else 0)
