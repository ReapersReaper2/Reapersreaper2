extends CanvasLayer
## Reaper's Reaper — Mollosar's Journal.
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## The POKeNAV replacement: a worn journal given by Grimley. Quest log,
## creature ledger, and lore codex. Read-only (no map markers, no tracking
## toggle — M3 scope). Data-driven: quests from data/quests.json, notes from
## data/journal_notes.json, creatures from creature_data. The story bot can
## extend all three JSON files directly.
##
## Code-built UI (party_panel pattern): tab row (QUESTS / LEDGER / NOTES),
## scrollable content list, detail pane. Keyboard: left/right switch tabs,
## up/down + Enter select, Esc backs out / closes. Opened from the pause
## menu (JOURNAL entry) or the J hotkey (room.gd).
##
## game_state may be injected (headless tests) or resolved from the tree.

signal closed

const CreatureData = preload("res://scripts/creature_data.gd")
const UiText = preload("res://scripts/ui_text.gd")
const Party = preload("res://scripts/party.gd")
const Contracts = preload("res://scripts/contracts.gd")
const Fabricator = preload("res://scripts/fabricator.gd")

var game_state = null

var _open: bool = false
var _built: bool = false
var _tab: int = 0  # 0 quests, 1 ledger, 2 notes
var _cursor: int = 0
var _rows: Array = []  # row descriptors for the current tab
var _detail: String = ""

var _title: Label
var _tab_row: HBoxContainer
var _tab_buttons: Array = []
var _list_box: VBoxContainer
var _detail_label: Label
var _hint: Label

const BONE := Color(0.92, 0.90, 0.86)
const DIM := Color(0.55, 0.55, 0.60)
const ACCENT := Color(1.0, 0.85, 0.45)
const GOOD := Color(0.55, 0.85, 0.55)

const TABS := ["QUESTS", "LEDGER", "NOTES", "FABRICATOR", "MEMORIES"]
const MemoriesScript := preload("res://scripts/memories.gd")
const QUESTS_PATH := "res://data/quests.json"
const NOTES_PATH := "res://data/journal_notes.json"

static var _quests_cache: Array = []
static var _notes_cache: Array = []


func _ready() -> void:
	if _built:
		return
	_built = true
	layer = 12
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	add_to_group("journal")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)

	_title = Label.new()
	_title.text = "MOLLOSAR'S JOURNAL"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 36)
	_title.add_theme_color_override("font_color", ACCENT)
	box.add_child(_title)

	var sub := Label.new()
	sub.text = "Grimley's gift — write it down, the underworld forgets."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", DIM)
	box.add_child(sub)

	_tab_row = HBoxContainer.new()
	_tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_tab_row.add_theme_constant_override("separation", 24)
	box.add_child(_tab_row)
	for i in TABS.size():
		var b := Button.new()
		b.text = TABS[i]
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 24)
		b.add_theme_color_override("font_color", DIM)
		b.add_theme_color_override("font_hover_color", Color.WHITE)
		var idx := i
		b.pressed.connect(_on_tab.bind(idx))
		_tab_row.add_child(b)
		_tab_buttons.append(b)

	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 4)
	_list_box.custom_minimum_size = Vector2(640, 300)
	box.add_child(_list_box)

	_detail_label = Label.new()
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.custom_minimum_size = Vector2(640, 140)
	_detail_label.add_theme_font_size_override("font_size", 18)
	_detail_label.add_theme_color_override("font_color", BONE)
	box.add_child(_detail_label)

	_hint = Label.new()
	_hint.text = "←/→ tabs · ↑/↓ select · Enter open · Esc back"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 14)
	_hint.add_theme_color_override("font_color", DIM)
	box.add_child(_hint)


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_tab = 0
	_cursor = 0
	visible = true
	_refresh()


func close() -> void:
	_open = false
	visible = false
	closed.emit()


# --- Data ---------------------------------------------------------------

static func load_quests() -> Array:
	if not _quests_cache.is_empty():
		return _quests_cache
	if FileAccess.file_exists(QUESTS_PATH):
		var f := FileAccess.open(QUESTS_PATH, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_quests_cache = d.get("quests", [])
	return _quests_cache


static func load_notes() -> Array:
	if not _notes_cache.is_empty():
		return _notes_cache
	if FileAccess.file_exists(NOTES_PATH):
		var f := FileAccess.open(NOTES_PATH, FileAccess.READ)
		if f != null:
			var d = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_notes_cache = d.get("notes", [])
	return _notes_cache


## Quest with per-objective completion derived from GameState flags.
func quest_status(q: Dictionary) -> Dictionary:
	var done := 0
	var total := 0
	var lines: Array = []
	for o in q.get("objectives", []):
		total += 1
		var flag: String = str(o.get("flag", ""))
		var complete: bool = flag != "" and game_state != null and game_state.has_method("get_flag") and game_state.get_flag(flag)
		if complete:
			done += 1
		lines.append({"text": str(o.get("text", "")), "done": complete})
	return {"quest": q, "done": done, "total": total, "complete": total > 0 and done == total, "lines": lines}


## Notes unlocked by their flag (empty flag = always unlocked).
func unlocked_notes() -> Array:
	var out: Array = []
	for n in load_notes():
		var flag: String = str(n.get("unlock_flag", ""))
		if flag == "" or (game_state != null and game_state.has_method("get_flag") and game_state.get_flag(flag)):
			out.append(n)
	return out


## Ledger entry state: "unseen" (???), "seen" (name + temperament), "caught" (full data).
func ledger_state(creature_id: String) -> String:
	if game_state == null:
		return "unseen"
	if _is_caught(creature_id):
		return "caught"
	if game_state.has_method("has_seen") and game_state.has_seen(creature_id):
		return "seen"
	return "unseen"


func _is_caught(creature_id: String) -> bool:
	if game_state == null or not game_state.has_method("get"):
		return false
	# Check party.
	if game_state.state.has("party"):
		for e in game_state.state["party"]:
			if str(e.get("creature_id", "")) == creature_id:
				return true
	# Check storage.
	if game_state.state.has("storage"):
		var st: Dictionary = game_state.state["storage"]
		for box in st.get("boxes", []):
			for slot in box:
				if slot is Dictionary and str(slot.get("creature_id", "")) == creature_id:
					return true
	return false


# --- UI -----------------------------------------------------------------

func _refresh() -> void:
	for i in _tab_buttons.size():
		var b: Button = _tab_buttons[i]
		b.add_theme_color_override("font_color", ACCENT if i == _tab else DIM)
	_rows.clear()
	for c in _list_box.get_children():
		c.queue_free()
	_detail = ""
	_detail_label.text = ""
	match _tab:
		0:
			_build_quest_rows()
		1:
			_build_ledger_rows()
		2:
			_build_note_rows()
		3:
			_build_fabricator_rows()
		4:
			_build_memory_rows()
	_update_cursor()


func _add_row(text: String, color: Color, row: Dictionary) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(640, 32)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	var idx := _rows.size()
	b.pressed.connect(_on_row.bind(idx))
	b.mouse_entered.connect(_on_hover.bind(idx))
	_list_box.add_child(b)
	_rows.append(row)


func _build_quest_rows() -> void:
	for q in load_quests():
		var st := quest_status(q)
		var mark := "[✓]" if st["complete"] else "[%d/%d]" % [st["done"], st["total"]]
		var color := GOOD if st["complete"] else BONE
		_add_row("%s %s" % [mark, str(q.get("name", "?"))], color, {"kind": "quest", "status": st})
	# Accepted bounty contracts (read live from contracts.gd — no duplicated data).
	if game_state != null:
		for cid in Contracts.accepted_ids(game_state):
			if Contracts.is_turned_in(game_state, str(cid)):
				continue
			var c := Contracts.get_contract(str(cid))
			if c.is_empty():
				continue
			var prog := Contracts.objectives_progress(game_state, str(cid))
			var pdone := 0
			for p in prog:
				if bool((p as Dictionary).get("done", false)):
					pdone += 1
			var complete := Contracts.is_complete(game_state, str(cid))
			var cmark := "[✓]" if complete else "[%d/%d]" % [pdone, prog.size()]
			var ccolor := GOOD if complete else BONE
			_add_row("%s %s (contract)" % [cmark, str(c.get("name", "?"))], ccolor,
				{"kind": "contract", "id": str(cid), "contract": c, "progress": prog, "complete": complete})


func _build_ledger_rows() -> void:
	CreatureData.ensure_loaded()
	for cid in CreatureData.creature_ids():
		var c: Dictionary = CreatureData.get_creature(cid)
		var state := ledger_state(cid)
		var text := "??? — unseen"
		var color := DIM
		if state == "seen":
			text = "%s — glimpsed (%s)" % [str(c.get("name", cid)), str(c.get("temperament", "?")).to_lower()]
			color = BONE
		elif state == "caught":
			text = "%s — caught" % str(c.get("name", cid))
			color = GOOD
		_add_row(text, color, {"kind": "ledger", "id": cid, "state": state, "creature": c})


## Memory-currency page: memories Mollosar still holds, and the ones that
## are gone. The elder's warning lives here: "spend your remaining
## memories wisely."
func _build_memory_rows() -> void:
	if game_state == null:
		return
	var n := MemoriesScript.count(game_state)
	_add_row("Memories held: %d" % n, ACCENT, {"kind": "memory", "id": ""})
	if MemoriesScript.projection_unlocked(game_state):
		_add_row("[WIRING] Whisper-line learned. Press C to project a memory (burns 1).", GOOD,
			{"kind": "memory", "id": ""})
	for key in MemoriesScript.MEMORIES.keys():
		if MemoriesScript.has(game_state, key):
			_add_row("◆ " + MemoriesScript.memory_name(key), BONE,
				{"kind": "memory", "id": key, "held": true})
	for key in MemoriesScript.MEMORIES.keys():
		if MemoriesScript.gone(game_state, key):
			_add_row("✕ " + MemoriesScript.memory_name(key) + " (gone)", DIM,
				{"kind": "memory", "id": key, "held": false})


func _memory_detail(r: Dictionary) -> String:
	var key := str(r.get("id", ""))
	if key == "":
		return "The only currency that matters. Spend them wisely — they're gone for good."
	var name := MemoriesScript.memory_name(key)
	var desc := MemoriesScript.memory_desc(key)
	if bool(r.get("held", false)):
		return "== " + name + " ==\n" + desc + "\n\nHeld. It can be traded, or projected — and then it's gone."
	return "== " + name + " ==\n" + desc + "\n\nGone. Not suppressed. Gone."


func _build_note_rows() -> void:
	for n in unlocked_notes():
		_add_row(str(n.get("title", "?")), BONE, {"kind": "note", "note": n})


## Living Fabricator page: learned shapes + grafted traits (appears once
## the player has fed the plant anything; empty state otherwise).
func _build_fabricator_rows() -> void:
	if game_state == null:
		return
	var learned: Array = Fabricator.learned(game_state)
	if learned.is_empty():
		_add_row("[WIRING] The plant knows nothing yet. Feed it in the Grove.", DIM,
			{"kind": "fabricator", "id": ""})
		return
	_add_row("— GRAFTS —", ACCENT, {"kind": "fabricator", "id": ""})
	var w := Fabricator.grafted_weapon(game_state)
	_add_row("Weapon: " + (Fabricator.trait_name(w) if w != "" else "[WIRING] empty"), BONE,
		{"kind": "fabricator", "id": w})
	var i := 1
	for a in Fabricator.grafted_armor(game_state):
		var label := "Armor %d: " % i
		label += Fabricator.trait_name(str(a)) if a != null and str(a) != "" else "[WIRING] empty"
		_add_row(label, BONE, {"kind": "fabricator", "id": str(a) if a != null else ""})
		i += 1
	_add_row("— LEARNED SHAPES —", ACCENT, {"kind": "fabricator", "id": ""})
	for tid in learned:
		_add_row("%s (%s)" % [Fabricator.trait_name(tid), Fabricator.trait_slot(tid)], GOOD,
			{"kind": "fabricator", "id": tid})


func _on_tab(idx: int) -> void:
	_tab = idx
	_cursor = 0
	_refresh()


func _on_row(idx: int) -> void:
	_cursor = idx
	_update_cursor()
	_show_detail()


func _on_hover(idx: int) -> void:
	_cursor = idx
	_update_cursor()


func _update_cursor() -> void:
	var kids := _list_box.get_children()
	for i in kids.size():
		var b := kids[i] as Button
		if b != null:
			b.add_theme_color_override("font_color", Color.WHITE if i == _cursor else _row_color(i))


func _row_color(i: int) -> Color:
	if i < 0 or i >= _rows.size():
		return BONE
	var r: Dictionary = _rows[i]
	if r.get("kind") == "quest":
		return GOOD if bool(r["status"]["complete"]) else BONE
	if r.get("kind") == "contract":
		return GOOD if bool(r.get("complete", false)) else BONE
	if r.get("kind") == "ledger":
		var s: String = str(r.get("state", ""))
		return GOOD if s == "caught" else (BONE if s == "seen" else DIM)
	if r.get("kind") == "memory":
		return BONE if bool(r.get("held", true)) else DIM
	return BONE


func _show_detail() -> void:
	if _cursor < 0 or _cursor >= _rows.size():
		return
	var r: Dictionary = _rows[_cursor]
	var kind: String = str(r.get("kind", ""))
	if kind == "quest":
		var st: Dictionary = r["status"]
		var q: Dictionary = st["quest"]
		var lines: Array = ["== " + str(q.get("name", "?")) + " ==", str(q.get("description", ""))]
		for o in st["lines"]:
			lines.append(("[✓] " if o["done"] else "[ ] ") + str(o["text"]))
		_detail_label.text = "\n".join(lines)
	elif kind == "contract":
		var c: Dictionary = r["contract"]
		var clines: Array = ["== " + str(c.get("name", "?")) + " (contract) ==",
			"From: " + str(c.get("giver", "")), str(c.get("description", ""))]
		for p in r["progress"]:
			var o: Dictionary = p
			clines.append("%s [%d/%d] %s" % ["✓" if bool(o.get("done", false)) else "·",
				int(o.get("current", 0)), int(o.get("target", 1)), str(o.get("text", ""))])
		if bool(r.get("complete", false)):
			clines.append("Complete — turn it in at the bounty board.")
		_detail_label.text = "\n".join(clines)
	elif kind == "ledger":
		_detail_label.text = _ledger_detail(r)
	elif kind == "note":
		var n: Dictionary = r["note"]
		_detail_label.text = "== " + str(n.get("title", "?")) + " ==\n" + str(n.get("body", ""))
	elif kind == "fabricator":
		_detail_label.text = _fabricator_detail(r)
	elif kind == "memory":
		_detail_label.text = _memory_detail(r)


func _fabricator_detail(r: Dictionary) -> String:
	var tid := str(r.get("id", ""))
	if tid == "":
		return "[WIRING] The Living Fabricator page. Feed the mother plant in the Grove to teach it shapes."
	var lines: Array = ["== " + Fabricator.trait_name(tid) + " =="]
	lines.append("Slot: " + Fabricator.trait_slot(tid))
	lines.append(Fabricator.trait_desc(tid))
	lines.append("Feedstock: " + Fabricator.feedstock_for(tid).replace("_", " "))
	if Fabricator.has_graft(game_state, tid):
		lines.append("[WIRING] Grafted. Permanent — the plant doesn't take things back.")
	return "\n".join(lines)


func _ledger_detail(r: Dictionary) -> String:
	var c: Dictionary = r["creature"]
	var state: String = str(r.get("state", ""))
	var cid: String = str(r.get("id", ""))
	if state == "unseen":
		return "???\nNo record. The underworld forgets — but the journal remembers what you've met."
	var lines: Array = ["== " + str(c.get("name", cid)) + " =="]
	lines.append("Temperament: " + str(c.get("temperament", "?")).to_lower())
	if state == "caught":
		var base: Dictionary = c.get("base", {})
		lines.append("Vigor %d · Might %d · Guard %d · Speed %d" % [
			int(base.get("vigor", 0)), int(base.get("might", 0)),
			int(base.get("guard", 0)), int(base.get("speed", 0))])
		var abs_: Array = CreatureData.creature_abilities(c)
		if not abs_.is_empty():
			lines.append("Abilities: " + ", ".join(abs_))
		# Family flavor from the UI text DB where it maps.
		var fam := _family_for(cid)
		if fam != "":
			lines.append("\"" + fam + "\"")
	else:
		lines.append("Glimpsed but not caught. Weaken it and throw a Soul Snare.")
	return "\n".join(lines)


## Best-effort family header mapping for flavor text.
func _family_for(creature_id: String) -> String:
	var c: Dictionary = CreatureData.get_creature(creature_id)
	var traits: Dictionary = c.get("traits", {})
	var bloom: String = str(traits.get("bloom", ""))
	if "flower" in bloom or "bloom" in bloom:
		return UiText.family_desc("plant_creatures")
	if creature_id in ["siltmaw", "floatbladder"]:
		return UiText.family_desc("sea_creatures")
	return ""


func _unhandled_key_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_on_tab((_tab - 1 + TABS.size()) % TABS.size())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_on_tab((_tab + 1) % TABS.size())
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_cursor = maxi(0, _cursor - 1)
		_update_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_cursor = mini(_rows.size() - 1, _cursor + 1)
		_update_cursor()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_show_detail()
		get_viewport().set_input_as_handled()
