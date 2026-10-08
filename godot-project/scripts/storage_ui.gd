extends CanvasLayer
## Soul Vault storage UI for Reaper's Reaper.
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Code-built greybox UI (like pause_menu): PARTY panel (6 slots) + BOX panel
## (30-slot grid, 6x5), box tabs with [ ], Tab switches panel, arrows move,
## Enter picks up / places an entry, Esc closes. Pickup/place model:
##   - pick up from party: entry removed from party into the hand
##   - pick up from box: entry removed from the box into the hand
##   - place on empty slot: entry lands there
##   - place on occupied slot: swap (the displaced entry stays in the hand)
## A creature is never duplicated or lost: every path is remove-then-insert.
##
## game_state may be injected (headless tests) or resolved from the tree.

signal closed

const Storage = preload("res://scripts/storage.gd")
const Party = preload("res://scripts/party.gd")

var game_state = null

var _open: bool = false
var _built: bool = false
var _box: int = 0
var _panel: String = "party"  # "party" | "box"
var _cursor: int = 0  # party index or box slot index
var _held: Dictionary = {}  # picked-up entry, or {}

var _title: Label
var _held_label: Label
var _party_buttons: Array = []
var _box_buttons: Array = []

const BONE := Color(0.92, 0.90, 0.86)
const DIM := Color(0.55, 0.55, 0.60)
const ACCENT := Color(1.0, 0.85, 0.45)


func _ready() -> void:
	if _built:
		return
	_built = true
	layer = 11
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	center.add_child(vbox)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 36)
	_title.add_theme_color_override("font_color", ACCENT)
	vbox.add_child(_title)
	_held_label = Label.new()
	_held_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_held_label.add_theme_font_size_override("font_size", 20)
	_held_label.add_theme_color_override("font_color", BONE)
	vbox.add_child(_held_label)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 24)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)
	var party_box := VBoxContainer.new()
	party_box.add_theme_constant_override("separation", 4)
	hbox.add_child(party_box)
	var pl := Label.new()
	pl.text = "PARTY"
	pl.add_theme_font_size_override("font_size", 22)
	pl.add_theme_color_override("font_color", BONE)
	party_box.add_child(pl)
	for i in 6:
		var b := _slot_button(200, 40, 20)
		var idx := i
		b.pressed.connect(_on_slot_pressed.bind("party", idx))
		b.mouse_entered.connect(_on_slot_hovered.bind("party", idx))
		party_box.add_child(b)
		_party_buttons.append(b)
	var box_vbox := VBoxContainer.new()
	box_vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(box_vbox)
	var bl := Label.new()
	bl.text = "BOX  ( [ ] change box, Tab switch panel )"
	bl.add_theme_font_size_override("font_size", 22)
	bl.add_theme_color_override("font_color", BONE)
	box_vbox.add_child(bl)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	box_vbox.add_child(grid)
	for i in 30:
		var b := _slot_button(150, 40, 16)
		var idx := i
		b.pressed.connect(_on_slot_pressed.bind("box", idx))
		b.mouse_entered.connect(_on_slot_hovered.bind("box", idx))
		grid.add_child(b)
		_box_buttons.append(b)


func _slot_button(w: int, h: int, fs: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(w, h)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", fs)
	b.add_theme_color_override("font_color", BONE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	return b


func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_resolve_gs()
	_open = true
	_panel = "party"
	_cursor = 0
	_held = {}
	_refresh()
	visible = true
	if is_inside_tree():
		get_tree().paused = true


func close() -> void:
	if not _open:
		return
	# Dropping the hand must never lose a creature: if something is held,
	# return it to where it came from (we tracked the origin).
	if not _held.is_empty():
		_put_back()
	_open = false
	visible = false
	if is_inside_tree():
		get_tree().paused = false
	closed.emit()


func _resolve_gs() -> void:
	if game_state == null and is_inside_tree():
		game_state = get_node_or_null("/root/GameState")


## Emergency restore for a held entry if the UI closes mid-carry: put it
## back in its origin slot, else anywhere legal.
func _put_back() -> void:
	var origin: Dictionary = _held.get("_origin", {})
	var entry: Dictionary = _held.get("entry", {})
	_held = {}
	if entry.is_empty():
		return
	if str(origin.get("kind", "")) == "party":
		if not Party.insert_entry(game_state, int(origin.get("index", 0)), entry):
			Party.append_entry(game_state, entry)
	elif str(origin.get("kind", "")) == "box":
		var bi := int(origin.get("box", 0))
		var si := int(origin.get("slot", 0))
		var b: Array = Storage._box(game_state, bi)
		if si <= b.size() and b.size() < Storage.BOX_SIZE:
			b.insert(si, entry)
		else:
			Storage.deposit_entry(game_state, entry)


## Enter on a slot: pick up when the hand is empty, place when carrying.
func activate_slot(panel: String, index: int) -> void:
	_resolve_gs()
	if game_state == null:
		return
	if _held.is_empty():
		_pick_up(panel, index)
	else:
		_place(panel, index)
	_refresh()


func _pick_up(panel: String, index: int) -> void:
	if panel == "party":
		var e: Dictionary = Party.get_entry(game_state, index)
		if e.is_empty():
			return
		Party.remove_creature(game_state, index)
		_held = {"entry": e, "_origin": {"kind": "party", "index": index}}
	else:
		var e2: Dictionary = Storage.release(game_state, _box, index)
		if e2.is_empty():
			return
		_held = {"entry": e2, "_origin": {"kind": "box", "box": _box, "slot": index}}


func _place(panel: String, index: int) -> void:
	var entry: Dictionary = _held.get("entry", {})
	if entry.is_empty():
		_held = {}
		return
	if panel == "party":
		var target: Dictionary = Party.get_entry(game_state, index)
		if target.is_empty():
			# Empty party slot: append if it is the first empty one.
			if index == Party.size(game_state) and Party.append_entry(game_state, entry):
				_held = {}
			# (Cursor can't reach beyond size+1 anyway.)
		else:
			# Swap: the displaced entry goes into the hand.
			Party.remove_creature(game_state, index)
			Party.insert_entry(game_state, index, entry)
			_held = {"entry": target, "_origin": _held.get("_origin", {})}
	else:
		var b: Array = Storage._box(game_state, _box)
		if index < b.size():
			var displaced: Dictionary = b[index]
			b[index] = entry
			_held = {"entry": displaced, "_origin": _held.get("_origin", {})}
		elif index == b.size() and b.size() < Storage.BOX_SIZE:
			b.append(entry)
			_held = {}
		# (Beyond the first empty slot the cursor can't reach.)


func change_box(dir: int) -> void:
	_box = posmod(_box + dir, Storage.BOX_COUNT)
	_cursor = 0
	_refresh()


func _entry_text(e: Dictionary) -> String:
	if e.is_empty():
		return "---"
	var nick := str(e.get("nickname", ""))
	var base := str(e.get("creature_id", "?"))
	if nick != "":
		base = nick
	return "%s %d" % [base.capitalize(), int(e.get("level", 1))]


func _refresh() -> void:
	if not _built:
		return
	_title.text = "%s — Box %d/%d" % [Storage.VAULT_NAME.to_upper(), _box + 1, Storage.BOX_COUNT]
	if _held.is_empty():
		_held_label.text = "Tab: switch panel   [ ]: change box   Enter: pick up / place   Esc: close"
	else:
		_held_label.text = "Holding: " + _entry_text(_held.get("entry", {}))
	var psize := Party.size(game_state) if game_state != null else 0
	for i in _party_buttons.size():
		var b: Button = _party_buttons[i]
		var e: Dictionary = Party.get_entry(game_state, i) if game_state != null else {}
		b.text = _entry_text(e)
		var active := _panel == "party" and _cursor == i
		b.modulate = ACCENT if active else (BONE if i < psize else DIM * 0.7)
	var bsize := Storage.box_count(game_state, _box) if game_state != null else 0
	for i in _box_buttons.size():
		var b2: Button = _box_buttons[i]
		var e2: Dictionary = Storage.get_entry(game_state, _box, i) if game_state != null else {}
		b2.text = _entry_text(e2)
		var active2 := _panel == "box" and _cursor == i
		b2.modulate = ACCENT if active2 else (BONE if i < bsize else DIM * 0.7)


func _on_slot_pressed(panel: String, index: int) -> void:
	_panel = panel
	_cursor = index
	activate_slot(panel, index)


func _on_slot_hovered(panel: String, index: int) -> void:
	_panel = panel
	_cursor = index
	_refresh()


func _max_cursor() -> int:
	if _panel == "party":
		# Cursor reaches occupied slots plus the first empty one (placement).
		var psize := Party.size(game_state) if game_state != null else 0
		return mini(5, psize)
	return mini(29, Storage.box_count(game_state, _box)) if game_state != null else 0


func _move(dx: int, dy: int) -> void:
	var cols := 1 if _panel == "party" else 6
	var rows := 6 if _panel == "party" else 5
	var col := _cursor % cols
	var row := _cursor / cols
	col = posmod(col + dx, cols)
	row = posmod(row + dy, rows)
	_cursor = mini(row * cols + col, _max_cursor())
	_refresh()


func _input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_focus_next"):  # Tab
		_panel = "box" if _panel == "party" else "party"
		_cursor = 0
		_refresh()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_move(-1, 0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_move(1, 0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_move(0, -1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_move(0, 1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		activate_slot(_panel, _cursor)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).keycode
		if k == KEY_BRACKETLEFT:
			change_box(-1)
			get_viewport().set_input_as_handled()
		elif k == KEY_BRACKETRIGHT:
			change_box(1)
			get_viewport().set_input_as_handled()
