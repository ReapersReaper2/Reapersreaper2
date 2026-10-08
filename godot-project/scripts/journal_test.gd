extends SceneTree
## Mollosar's Journal — headless test.
##
## Covers: quest objective completion from flags, ledger states
## (unseen/seen/caught), note unlocking, tab switching, seen-set
## persistence through save/load, pause-menu JOURNAL entry.

const JournalScript := preload("res://scripts/journal.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const CreatureData := preload("res://scripts/creature_data.gd")

var _failures := 0
var _passes := 0


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("  PASS: ", name)
	else:
		_failures += 1
		print("  FAILED: ", name)


func _make_gs() -> Node:
	var gs = GameStateScript.new()
	gs.save_system = null  # avoid file IO; state stays in memory
	gs.new_game()
	return gs


func _init() -> void:
	print("[journal_test] starting")
	_run.call_deferred()


func _run() -> void:
	var gs = _make_gs()

	# --- Data loads ---
	var quests: Array = JournalScript.load_quests()
	_check("quests.json loads (%d quests)" % quests.size(), quests.size() >= 5)
	var notes_all: Array = JournalScript.load_notes()
	_check("journal_notes.json loads (%d notes)" % notes_all.size(), notes_all.size() >= 3)

	var j = JournalScript.new()
	j.game_state = gs
	root.add_child(j)
	j._ready()

	# --- Quest objectives from flags ---
	var q0: Dictionary = quests[0]  # q_bridge
	var st0: Dictionary = j.quest_status(q0)
	_check("bridge quest starts 0/%d" % st0["total"], st0["done"] == 0 and not st0["complete"])
	gs.set_flag("p1_bridge_cleared")
	st0 = j.quest_status(q0)
	_check("bridge quest 1/2 after wave flag", st0["done"] == 1 and not st0["complete"])
	gs.set_flag("p2_collapse_seen")
	st0 = j.quest_status(q0)
	_check("bridge quest complete after collapse", st0["complete"])

	# --- Ledger states ---
	_check("siltmaw unseen initially", j.ledger_state("siltmaw") == "unseen")
	gs.mark_seen("siltmaw")
	_check("siltmaw seen after mark_seen", j.ledger_state("siltmaw") == "seen")
	_check("has_seen true", gs.has_seen("siltmaw"))
	_check("has_seen false for others", not gs.has_seen("bellmaw"))
	# Caught: add to party.
	var PartyScript = load("res://scripts/party.gd")
	PartyScript.add_creature(gs, "bellmaw", 12)
	_check("bellmaw caught (in party)", j.ledger_state("bellmaw") == "caught")
	_check("siltmaw still seen (not caught)", j.ledger_state("siltmaw") == "seen")

	# --- Notes ---
	var notes: Array = j.unlocked_notes()
	_check("4 default notes unlocked", notes.size() == 4)
	gs.set_flag("h1_board_read")
	notes = j.unlocked_notes()
	_check("board note unlocks on flag", notes.size() == 5)
	_check("board note has title", str(notes[3].get("title", "")).length() > 0)

	# --- Tab switching ---
	j.open()
	_check("journal opens", j.is_open())
	_check("starts on quests tab", j._tab == 0)
	j._on_tab(1)
	CreatureData.ensure_loaded()
	_check("switches to ledger", j._tab == 1 and j._rows.size() == CreatureData.creature_ids().size())
	j._on_tab(2)
	_check("switches to notes", j._tab == 2 and j._rows.size() == 5)
	j._on_tab(0)
	_check("back to quests", j._tab == 0)
	# Detail rendering doesn't crash.
	j._cursor = 0
	j._show_detail()
	_check("quest detail renders", j._detail_label.text.length() > 0)
	j._on_tab(1)
	# Find a row that's still unseen (bellmaw is caught, siltmaw is seen).
	var unseen_idx := -1
	for i in j._rows.size():
		if str(j._rows[i].get("state", "")) == "unseen":
			unseen_idx = i
			break
	_check("an unseen ledger row exists", unseen_idx >= 0)
	j._cursor = unseen_idx
	j._show_detail()
	_check("ledger detail renders (unseen)", "???" in j._detail_label.text)
	j.close()
	_check("journal closes", not j.is_open())

	# --- Persistence: seen set survives save/load round-trip ---
	# (in-memory: duplicate the state dict like save_system does)
	var saved: Dictionary = gs.state.duplicate(true)
	var gs2 = _make_gs()
	gs2.state = saved
	_check("seen set persists", gs2.has_seen("siltmaw"))
	var j2 = JournalScript.new()
	j2.game_state = gs2
	root.add_child(j2)
	j2._ready()
	_check("ledger reflects loaded seen", j2.ledger_state("siltmaw") == "seen")
	_check("quest reflects loaded flags", bool(j2.quest_status(quests[0])["complete"]))

	# --- Pause menu has JOURNAL ---
	var PauseScript = load("res://scripts/pause_menu.gd")
	var pm = PauseScript.new()
	pm.game_state = gs
	root.add_child(pm)
	pm._ready()
	var ids: Array = []
	for item in pm._items:
		ids.append(str(item["id"]))
	_check("pause menu has journal entry", ids.has("journal"))
	_check("journal entry labeled", pm._item_text("journal") == "JOURNAL")

	print("[journal_test] passes: %d failures: %d" % [_passes, _failures])
	if _failures > 0:
		print("JOURNAL TEST: %d failures" % _failures)
	else:
		print("JOURNAL TEST: ALL PASS")
	quit(_failures)
