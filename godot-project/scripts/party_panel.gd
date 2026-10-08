extends CanvasLayer
## Reaper's Reaper — out-of-battle party panel.
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Code-built greybox UI (pause_menu / storage_ui pattern): party list ->
## per-member action menu (USE ITEM / SWAP / SUMMARY / BACK) -> item list,
## swap picker, or summary readout. Keyboard: up/down + Enter, Esc backs out.
## Opened from the pause menu; closing returns to it (tree stays paused).
##
## game_state may be injected (headless tests) or resolved from the tree.

signal closed

const Party = preload("res://scripts/party.gd")
const BattleUnit = preload("res://scripts/battle_unit.gd")
const CreatureData = preload("res://scripts/creature_data.gd")

var game_state = null

var _open: bool = false
var _built: bool = false
var _state: String = "list"  # list | action | items | swap | summary
var _member: int = -1  # selected party index for action/items/swap/summary
var _cursor: int = 0  # cursor within the current list
var _msg: String = ""
var _msg_timer: float = 0.0

var _title: Label
var _hint: Label
var _list_box: VBoxContainer
var _msg_label: Label
var _buttons: Array = []  # Buttons for the current list (parallel to _rows)
var _rows: Array = []  # row descriptors for the current list

const BONE := Color(0.92, 0.90, 0.86)
const DIM := Color(0.55, 0.55, 0.60)
const ACCENT := Color(1.0, 0.85, 0.45)
const FAINT := Color(0.45, 0.42, 0.45)

## Item effect types usable outside battle.
const OOB_TYPES := ["heal_hp", "heal_full_party", "cure_status", "revive"]


func _ready() -> void:
	if _built:
		return
	_built = true
	layer = 12
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	add_to_group("party_panel")
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
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	center.add_child(vbox)
	_title = Label.new()
	_title.text = "PARTY"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 36)
	_title.add_theme_color_override("font_color", ACCENT)
	vbox.add_child(_title)
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", DIM)
	vbox.add_child(_hint)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 4)
	vbox.add_child(_list_box)
	_msg_label = Label.new()
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.add_theme_font_size_override("font_size", 20)
	_msg_label.add_theme_color_override("font_color", BONE)
	vbox.add_child(_msg_label)


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	if game_state == null:
		if is_inside_tree():
			game_state = get_node_or_null("/root/GameState")
		if game_state == null:
			push_warning("PartyPanel: no game_state, refusing to open")
			return
	_open = true
	_state = "list"
	_member = -1
	_cursor = 0
	_msg = ""
	visible = true
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	closed.emit()


# --- row building -----------------------------------------------------------

func _clear_list() -> void:
	for b in _buttons:
		(b as Button).queue_free()
	_buttons.clear()
	_rows.clear()


func _add_row(text: String, row: Dictionary, dimmed: bool = false) -> void:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(560, 40)
	b.add_theme_font_size_override("font_size", 22)
	b.add_theme_color_override("font_color", BONE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	var idx := _rows.size()
	b.pressed.connect(_on_row_pressed.bind(idx))
	b.mouse_entered.connect(_on_row_hovered.bind(idx))
	_list_box.add_child(b)
	_buttons.append(b)
	row["dim"] = dimmed
	_rows.append(row)
	if dimmed:
		b.modulate = Color(0.45, 0.45, 0.48)


func _member_name(e: Dictionary) -> String:
	var nick := str(e.get("nickname", ""))
	if nick != "":
		return nick
	return str(CreatureData.get_creature(str(e.get("creature_id", ""))).get("name", "?"))


func _slot_text(i: int) -> String:
	var e: Dictionary = Party.get_entry(game_state, i)
	if e.is_empty():
		return "— empty —"
	var unit_max := Party.max_hp_for(e)
	var hp := int(e.get("current_hp", 0))
	var fainted := hp <= 0
	var statuses := Party.get_statuses(game_state, i)
	var st := ""
	if not statuses.is_empty():
		st = " [" + ", ".join(statuses) + "]"
	var mark := " (fainted)" if fainted else ""
	return "%d. %s  Lv%d  HP %d/%d%s%s" % [i + 1, _member_name(e), int(e.get("level", 1)), hp, unit_max, mark, st]


func _refresh() -> void:
	_clear_list()
	_msg_label.text = _msg
	match _state:
		"list":
			_title.text = "PARTY"
			_hint.text = "up/down + Enter — Esc closes"
			for i in Party.MAX_SIZE:
				_add_row(_slot_text(i), {"kind": "member", "index": i}, Party.get_entry(game_state, i).is_empty())
		"action":
			var e: Dictionary = Party.get_entry(game_state, _member)
			_title.text = _member_name(e).to_upper()
			_hint.text = "choose an action — Esc back"
			for d in [
				{"id": "item", "text": "USE ITEM"},
				{"id": "swap", "text": "SWAP"},
				{"id": "summary", "text": "SUMMARY"},
				{"id": "back", "text": "BACK"},
			]:
				_add_row(str(d["text"]), {"kind": "action", "id": str(d["id"])})
		"items":
			_title.text = "USE ITEM"
			_hint.text = "choose an item — Esc back"
			var any := false
			for item_id in _oob_item_ids():
				any = true
				var usable := _item_usability(item_id, _member)
				var item: Dictionary = CreatureData.get_item(item_id)
				var label := "%s x%d" % [str(item.get("name", item_id)), game_state.get_item_count(item_id)]
				if not bool(usable.get("ok", false)):
					label += "  (%s)" % str(usable.get("reason", ""))
				_add_row(label, {"kind": "item", "id": item_id}, not bool(usable.get("ok", false)))
			if not any:
				_add_row("(no usable items)", {"kind": "none"}, true)
		"swap":
			_title.text = "SWAP WITH…"
			_hint.text = "pick a party member — Esc back"
			for i in Party.MAX_SIZE:
				var e: Dictionary = Party.get_entry(game_state, i)
				if e.is_empty() or i == _member:
					continue
				_add_row(_slot_text(i), {"kind": "swap_target", "index": i})
		"summary":
			var e2: Dictionary = Party.get_entry(game_state, _member)
			_title.text = _member_name(e2).to_upper()
			_hint.text = "Enter/Esc back"
			for line in _summary_lines(e2):
				_add_row(line, {"kind": "info"}, true)
	_cursor = clampi(_cursor, 0, maxi(0, _rows.size() - 1))
	_paint_cursor()


func _paint_cursor() -> void:
	for i in _buttons.size():
		var b: Button = _buttons[i]
		var prefix := "> " if i == _cursor else "   "
		var t: String = b.text
		if t.begins_with("> "):
			t = t.substr(2)
		elif t.begins_with("   "):
			t = t.substr(3)
		b.text = prefix + t
		if i == _cursor:
			b.modulate = Color(1, 1, 1)
		elif bool((_rows[i] as Dictionary).get("dim", false)):
			b.modulate = Color(0.45, 0.45, 0.48)
		else:
			b.modulate = Color(0.75, 0.75, 0.78)


# --- items ------------------------------------------------------------------

## Item ids in the inventory that have an out-of-battle-usable effect.
func _oob_item_ids() -> Array:
	var out: Array = []
	for item_id in _inventory_ids():
		var item: Dictionary = CreatureData.get_item(item_id)
		var effect: Dictionary = item.get("effect", {})
		if str(effect.get("type", "")) in OOB_TYPES and game_state.get_item_count(item_id) > 0:
			out.append(item_id)
	return out


func _inventory_ids() -> Array:
	# game_state._inventory() is "private" by convention; the public path is
	# get_item_count, but we need the key list — CreatureData knows all items.
	var ids: Array = []
	for item_id in CreatureData.item_ids():
		if game_state.get_item_count(str(item_id)) > 0:
			ids.append(str(item_id))
	return ids


## {"ok": bool, "reason": String} for using item_id on party member index.
func _item_usability(item_id: String, index: int) -> Dictionary:
	var item: Dictionary = CreatureData.get_item(item_id)
	var effect: Dictionary = item.get("effect", {})
	var etype := str(effect.get("type", ""))
	var e: Dictionary = Party.get_entry(game_state, index)
	if e.is_empty():
		return {"ok": false, "reason": "no member"}
	var hp := int(e.get("current_hp", 0))
	var maxhp := Party.max_hp_for(e)
	match etype:
		"heal_hp":
			if hp <= 0:
				return {"ok": false, "reason": "fainted — needs revive"}
			if hp >= maxhp:
				return {"ok": false, "reason": "HP full"}
			return {"ok": true, "reason": ""}
		"heal_full_party":
			for i in Party.size(game_state):
				var m: Dictionary = Party.get_entry(game_state, i)
				var mhp := int(m.get("current_hp", 0))
				if mhp > 0 and mhp < Party.max_hp_for(m):
					return {"ok": true, "reason": ""}
			return {"ok": false, "reason": "party fully healed"}
		"cure_status":
			var want: Array = effect.get("statuses", [])
			for sid in Party.get_statuses(game_state, index):
				if str(sid) in want:
					return {"ok": true, "reason": ""}
			return {"ok": false, "reason": "no curable status"}
		"revive":
			if hp > 0:
				return {"ok": false, "reason": "not fainted"}
			return {"ok": true, "reason": ""}
	return {"ok": false, "reason": "not usable here"}


## Apply item_id to the selected member. Returns a feedback message.
func use_item_on(item_id: String, index: int) -> String:
	var usable := _item_usability(item_id, index)
	if not bool(usable.get("ok", false)):
		return "Can't use that (%s)." % str(usable.get("reason", ""))
	var item: Dictionary = CreatureData.get_item(item_id)
	var effect: Dictionary = item.get("effect", {})
	var etype := str(effect.get("type", ""))
	var iname := str(item.get("name", item_id))
	if not game_state.use_item(item_id):
		return "No %s left!" % iname
	var msg := ""
	match etype:
		"heal_hp":
			var healed := Party.heal(game_state, index, int(effect.get("amount", 0)))
			msg = "%s restored %d HP!" % [iname, healed]
		"heal_full_party":
			Party.heal_all(game_state)
			msg = "%s — the whole party is restored!" % iname
		"cure_status":
			var n := Party.cure_statuses(game_state, index, effect.get("statuses", []))
			msg = "%s cured %d status effect(s)!" % [iname, n]
		"revive":
			Party.revive(game_state, index, float(effect.get("hp_fraction", 0.5)))
			msg = "%s — %s is back on its feet!" % [iname, _member_name(Party.get_entry(game_state, index))]
	_msg = msg
	_msg_timer = 2.5
	_refresh()
	return msg


func _summary_lines(e: Dictionary) -> Array:
	var u = BattleUnit.new(str(e.get("creature_id", "")), int(e.get("level", 1)))
	var ab_names: Array = []
	for ab_id in (e.get("ability_ids", []) as Array):
		ab_names.append(str(CreatureData.get_ability(str(ab_id)).get("name", ab_id)))
	var statuses := Party.get_statuses(game_state, _member)
	return [
		"Lv%d  HP %d/%d" % [int(e.get("level", 1)), int(e.get("current_hp", 0)), u.max_hp],
		"Might %d  Guard %d  Speed %d" % [u.attack, u.defense, u.speed],
		"Abilities: " + (", ".join(ab_names) if not ab_names.is_empty() else "—"),
		"Status: " + (", ".join(statuses) if not statuses.is_empty() else "healthy"),
		"XP %d / %d" % [int(e.get("xp", 0)), Party.xp_to_next(int(e.get("level", 1)))],
	]


# --- input ------------------------------------------------------------------

func _on_row_pressed(idx: int) -> void:
	_cursor = idx
	_activate_row()


func _on_row_hovered(idx: int) -> void:
	_cursor = idx
	_paint_cursor()


func _activate_row() -> void:
	if _rows.is_empty():
		return
	var row: Dictionary = _rows[clampi(_cursor, 0, _rows.size() - 1)]
	match str(row.get("kind", "")):
		"member":
			var i := int(row.get("index", -1))
			if Party.get_entry(game_state, i).is_empty():
				return
			_member = i
			_state = "action"
			_cursor = 0
			_refresh()
		"action":
			_do_action(str(row.get("id", "")))
		"item":
			use_item_on(str(row.get("id", "")), _member)
		"swap_target":
			var j := int(row.get("index", -1))
			Party.swap(game_state, _member, j)
			_msg = "Swapped party order."
			_state = "action"
			_cursor = 0
			_refresh()
		"info", "none":
			pass


func _do_action(action_id: String) -> void:
	match action_id:
		"item":
			_state = "items"
			_cursor = 0
			_refresh()
		"swap":
			_state = "swap"
			_cursor = 0
			_refresh()
		"summary":
			_state = "summary"
			_cursor = 0
			_refresh()
		"back":
			_state = "list"
			_member = -1
			_cursor = 0
			_refresh()


func _back() -> void:
	match _state:
		"list":
			close()
		"action":
			_state = "list"
			_member = -1
			_cursor = 0
			_refresh()
		"items", "swap", "summary":
			_state = "action"
			_cursor = 0
			_refresh()


func move_cursor(dir: int) -> void:
	if _rows.is_empty():
		return
	_cursor = posmod(_cursor + dir, _rows.size())
	_paint_cursor()


func _process(delta: float) -> void:
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0 and _msg != "":
			_msg = ""
			if _open:
				_refresh()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		_back()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		move_cursor(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		move_cursor(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_activate_row()
		get_viewport().set_input_as_handled()
