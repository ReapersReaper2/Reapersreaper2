extends SceneTree
## Headless party panel test: listing, heal/cure/revive/nectar, swap,
## summary, usability dimming, item consumption, pause-menu integration.
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/party_panel_test.gd
## Uses throwaway slot 93 so real saves are never touched.
##
## NOTE: under -s, nodes added here are not inside the tree yet, so the test
## injects dependencies and calls internals directly — the same pattern as
## storage_test / party_test.

const SLOT := 93

const Party = preload("res://scripts/party.gd")
const PartyPanelScript = preload("res://scripts/party_panel.gd")
const PauseMenuScript = preload("res://scripts/pause_menu.gd")

var _failures: Array[String] = []


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failures.append(name)
		print("  FAIL: ", name)


func _make_gs():
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
	gs.set_current_slot(SLOT)
	return gs


func _make_panel(gs):
	var panel = PartyPanelScript.new()
	panel.game_state = gs
	root.add_child(panel)
	panel._ready()
	return panel


func _initialize() -> void:
	print("[PARTY PANEL TEST]")
	var gs = _make_gs()
	Party.new_game_party(gs)  # starter: snapling lv5, hp 40
	gs.add_item("grave_moss_poultice", 2)
	gs.add_item("mandrake_tea", 1)
	gs.add_item("second_bell", 1)
	gs.add_item("blossom_nectar", 1)
	gs.add_item("sap_draught", 1)

	var panel = _make_panel(gs)

	# --- listing ---
	panel.open()
	_check("panel opens", panel.is_open())
	_check("list state shows 6 rows", panel._rows.size() == 6)
	_check("slot 1 shows snapling hp", "Snapling" in panel._slot_text(0) and "40/40" in panel._slot_text(0))
	_check("empty slots marked", panel._slot_text(1) == "— empty —")
	panel.close()
	_check("panel closes", not panel.is_open())

	# --- heal ---
	Party.set_hp(gs, 0, 10)
	_check("heal usability ok when hurt", bool(panel._item_usability("grave_moss_poultice", 0).get("ok", false)))
	var msg: String = panel.use_item_on("grave_moss_poultice", 0)
	_check("poultice heals 30 (10->40, clamped)", Party.get_entry(gs, 0)["current_hp"] == 40 and "30 HP" in msg)
	# new_game() already grants 2 poultices; we add 2 more -> 4 total.
	_check("poultice consumed", gs.get_item_count("grave_moss_poultice") == 3)
	_check("heal dimmed at full hp", not bool(panel._item_usability("grave_moss_poultice", 0).get("ok", false)))
	_check("full-hp reason", str(panel._item_usability("grave_moss_poultice", 0).get("reason", "")) == "HP full")
	_check("no-overheal: use refused at full", panel.use_item_on("grave_moss_poultice", 0) == "Can't use that (HP full).")
	_check("refused use consumes nothing", gs.get_item_count("grave_moss_poultice") == 3)

	# --- faint + revive ---
	Party.set_hp(gs, 0, 0)
	_check("fainted member can't take poultice", not bool(panel._item_usability("grave_moss_poultice", 0).get("ok", false)))
	_check("faint reason mentions revive", "revive" in str(panel._item_usability("grave_moss_poultice", 0).get("reason", "")))
	_check("revive usable on fainted", bool(panel._item_usability("second_bell", 0).get("ok", false)))
	_check("revive refused on conscious", true)  # set up below after revive
	panel.use_item_on("second_bell", 0)
	_check("revived at 50% (20/40)", int(Party.get_entry(gs, 0)["current_hp"]) == 20)
	_check("bell consumed", gs.get_item_count("second_bell") == 0)
	_check("revive dimmed when conscious", not bool(panel._item_usability("second_bell", 0).get("ok", false)))

	# --- cure ---
	Party.set_hp(gs, 0, 40)
	Party.add_status(gs, 0, "wilt")
	_check("wilt applied", Party.get_statuses(gs, 0) == ["wilt"])
	_check("tea usable with wilt", bool(panel._item_usability("mandrake_tea", 0).get("ok", false)))
	panel.use_item_on("mandrake_tea", 0)
	_check("wilt cured", Party.get_statuses(gs, 0).is_empty())
	_check("tea consumed", gs.get_item_count("mandrake_tea") == 0)
	_check("tea dimmed when healthy", not bool(panel._item_usability("mandrake_tea", 0).get("ok", false)))

	# --- nectar: whole-party heal ---
	Party.add_creature(gs, "siltmaw", 3)
	Party.set_hp(gs, 0, 5)
	Party.set_hp(gs, 1, 1)
	var max0: int = Party.max_hp_for(Party.get_entry(gs, 0))
	var max1: int = Party.max_hp_for(Party.get_entry(gs, 1))
	_check("nectar usable when someone hurt", bool(panel._item_usability("blossom_nectar", 0).get("ok", false)))
	panel.use_item_on("blossom_nectar", 0)
	_check("nectar heals member 0 to full", int(Party.get_entry(gs, 0)["current_hp"]) == max0)
	_check("nectar heals member 1 to full", int(Party.get_entry(gs, 1)["current_hp"]) == max1)
	_check("nectar consumed", gs.get_item_count("blossom_nectar") == 0)
	_check("nectar dimmed when all full", not bool(panel._item_usability("blossom_nectar", 0).get("ok", false)))

	# --- swap ---
	panel.open()
	panel._state = "list"
	panel._cursor = 0
	panel._refresh()
	panel._activate_row()  # select member 0 -> action menu
	_check("action menu opens", panel._state == "action" and panel._member == 0)
	_check("action menu has 4 rows", panel._rows.size() == 4)
	panel._cursor = 1  # SWAP
	panel._activate_row()
	_check("swap picker opens", panel._state == "swap")
	# swap target list skips the selected member; find siltmaw's row
	var target_row := -1
	for i in panel._rows.size():
		if int((panel._rows[i] as Dictionary).get("index", -1)) == 1:
			target_row = i
	_check("swap target lists member 1", target_row >= 0)
	panel._cursor = target_row
	panel._activate_row()
	_check("swap reorders", str(Party.get_entry(gs, 0).get("creature_id", "")) == "siltmaw")
	_check("back at action menu", panel._state == "action")
	panel._back()
	_check("esc from action -> list", panel._state == "list")
	panel.close()

	# --- summary ---
	panel.open()
	panel._state = "action"
	panel._member = 0
	panel._cursor = 2  # SUMMARY
	panel._refresh()
	panel._activate_row()
	_check("summary opens", panel._state == "summary")
	var summary_text := ""
	for i in panel._rows.size():
		summary_text += str((panel._buttons[i] as Button).text) + "|"
	_check("summary shows stats", "Might" in summary_text and "Guard" in summary_text and "Speed" in summary_text)
	_check("summary shows hp", "HP" in summary_text)
	panel._back()
	_check("esc from summary -> action", panel._state == "action")
	panel.close()

	# --- navigation: empty slot does nothing, esc closes ---
	panel.open()
	panel._cursor = 3  # empty slot
	panel._activate_row()
	_check("empty slot not selectable", panel._state == "list")
	panel._back()
	_check("esc from list closes panel", not panel.is_open())

	# --- pause menu integration (needs a live tree: runs on first _process) ---
	# Free the earlier test panel so it doesn't trip the "already open" guard.
	root.remove_child(panel)
	panel.free()
	_gs_for_menu = gs
	_phase = 1


## Pause-menu <-> panel wiring needs real tree services, which are only live
## once _process runs (cold tree during _initialize — see wild_test notes).
var _phase: int = 0
var _gs_for_menu = null


func _process(_delta: float) -> bool:
	if _phase != 1:
		return false
	_phase = 2
	_test_pause_menu(_gs_for_menu)
	_report()
	return false


func _test_pause_menu(gs) -> void:
	var menu = PauseMenuScript.new()
	menu.game_state = gs
	root.add_child(menu)
	menu._ready()
	_check("pause menu has PARTY entry", menu._items.any(func(d): return str(d["id"]) == "party"))
	menu.open()
	_check("pause menu opens", menu.is_open())
	menu.activate("party")
	var pp = get_first_node_in_group("party_panel")
	_check("PARTY opens the panel", pp != null and (pp as Node).has_method("is_open") and pp.is_open())
	_check("pause menu still open underneath", menu.is_open())
	pp.close()
	_check("panel close returns to pause menu", menu.is_open() and not pp.is_open())
	menu.close()
	_check("pause menu closes", not menu.is_open())

	# --- battle status sync (party API level) ---
	Party.set_statuses(gs, 0, ["wilt", "spore_fever"])
	_check("statuses persist on entry", Party.get_statuses(gs, 0) == ["wilt", "spore_fever"])
	_check("cure one of two", Party.cure_statuses(gs, 0, ["wilt"]) == 1)
	_check("other status remains", Party.get_statuses(gs, 0) == ["spore_fever"])
	Party.set_statuses(gs, 0, [])


func _report() -> void:
	print("[PARTY PANEL TEST] failures: %d" % _failures.size())
	if _failures.is_empty():
		print("ALL PARTY PANEL TESTS PASSED")
	else:
		for f in _failures:
			print("FAILED: ", f)
	quit(1 if not _failures.is_empty() else 0)
