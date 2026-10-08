extends CanvasLayer
## Reaper's Reaper — breeding & nursery panel.
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Code-built greybox UI (party_panel pattern): parent picker (one male, one
## female — the gate refuses anything else) + nursery (eggs with incubation
## progress, growing young with FEED buttons). Keyboard: up/down + Enter,
## Esc backs out. Opened from the pause menu; closing returns to it.
##
## game_state may be injected (headless tests) or resolved from the tree.

signal closed

const Party = preload("res://scripts/party.gd")
const Breeding = preload("res://scripts/breeding.gd")
const CreatureData = preload("res://scripts/creature_data.gd")

var game_state = null

var _open: bool = false
var _built: bool = false
var _cursor: int = 0
var _msg: String = ""
var _sire_idx: int = -1  # selected male party index
var _dam_idx: int = -1   # selected female party index

var _title: Label
var _hint: Label
var _list_box: VBoxContainer
var _msg_label: Label
var _rows: Array = []  # {kind, label, action: Callable, disabled}

const BONE := Color(0.92, 0.90, 0.86)
const DIM := Color(0.55, 0.55, 0.60)
const ACCENT := Color(1.0, 0.85, 0.45)
const PINK := Color(1.0, 0.62, 0.72)
const BLUE := Color(0.55, 0.78, 1.0)


func _ready() -> void:
	if _built:
		return
	_built = true
	layer = 12
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	add_to_group("breeding_ui")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(760, 600)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.08, 0.10, 1)
	style.set_border_width_all(2)
	style.border_color = ACCENT
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)
	_title = Label.new()
	_title.text = "BREEDING & NURSERY"
	_title.add_theme_font_size_override("font_size", 30)
	_title.add_theme_color_override("font_color", ACCENT)
	vbox.add_child(_title)
	_hint = Label.new()
	_hint.text = "Up/Down + Enter — pick one male and one female, then BREED. Esc closes."
	_hint.add_theme_font_size_override("font_size", 15)
	_hint.add_theme_color_override("font_color", DIM)
	vbox.add_child(_hint)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(720, 420)
	vbox.add_child(scroll)
	_list_box = VBoxContainer.new()
	_list_box.add_theme_constant_override("separation", 4)
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_box)
	_msg_label = Label.new()
	_msg_label.add_theme_font_size_override("font_size", 17)
	_msg_label.add_theme_color_override("font_color", BONE)
	_msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_msg_label)


func is_open() -> bool:
	return _open


func open() -> void:
	_sire_idx = -1
	_dam_idx = -1
	_cursor = 0
	_msg = ""
	_open = true
	visible = true
	_refresh()


func close() -> void:
	_open = false
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_move_cursor(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_move_cursor(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_activate_cursor()
		get_viewport().set_input_as_handled()


func _move_cursor(d: int) -> void:
	if _rows.is_empty():
		return
	_cursor = (_cursor + d + _rows.size()) % _rows.size()
	_refresh()


func _activate_cursor() -> void:
	if _cursor < 0 or _cursor >= _rows.size():
		return
	var row: Dictionary = _rows[_cursor]
	if bool(row.get("disabled", false)):
		return
	var action: Callable = row.get("action", Callable())
	if action.is_valid():
		action.call()
	_refresh()


func _say(t: String) -> void:
	_msg = t


func _section(text: String) -> void:
	_rows.append({"kind": "header", "label": text, "disabled": true})


func _row(label: String, action: Callable, disabled: bool = false) -> void:
	_rows.append({"kind": "row", "label": label, "action": action, "disabled": disabled})


func _refresh() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	_rows.clear()
	_build_rows()
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		if str(row.get("kind", "")) == "header":
			var h := Label.new()
			h.text = str(row["label"])
			h.add_theme_font_size_override("font_size", 20)
			h.add_theme_color_override("font_color", ACCENT)
			_list_box.add_child(h)
			continue
		var b := Button.new()
		b.text = ("▶ " if i == _cursor else "  ") + str(row["label"])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.disabled = bool(row.get("disabled", false))
		b.add_theme_font_size_override("font_size", 17)
		b.add_theme_color_override("font_color", BONE)
		b.add_theme_color_override("font_disabled_color", DIM)
		var idx := i
		b.pressed.connect(func() -> void:
			_cursor = idx
			_activate_cursor()
		)
		_list_box.add_child(b)
	_msg_label.text = _msg


func _build_rows() -> void:
	if game_state == null:
		return
	CreatureData.ensure_loaded()
	# --- parents ---
	_section("— PARENTS (one male + one female, no exceptions) —")
	var males: Array = []
	var females: Array = []
	var p: Array = Party._party(game_state)
	for i in p.size():
		var e: Dictionary = p[i]
		var nm := _entry_name(e)
		if Breeding.sex_of(e) == "M":
			males.append(i)
		else:
			females.append(i)
	_section("MALES")
	if males.is_empty():
		_row("(no males in party)", Callable(), true)
	for i in males:
		var e: Dictionary = p[i]
		var mark := " ✓" if i == _sire_idx else ""
		var ii: int = i
		_row("♂ " + _entry_name(e) + mark, func() -> void:
			_sire_idx = ii
			_say("Sire selected.")
		)
	_section("FEMALES")
	if females.is_empty():
		_row("(no females in party)", Callable(), true)
	for i in females:
		var e: Dictionary = p[i]
		var mark := " ✓" if i == _dam_idx else ""
		var ii: int = i
		_row("♀ " + _entry_name(e) + mark, func() -> void:
			_dam_idx = ii
			_say("Dam selected.")
		)
	_row("[ BREED ]", func() -> void:
		if _sire_idx < 0 or _dam_idx < 0:
			_say("Select one male and one female first.")
			return
		var res := Breeding.breed(game_state, _sire_idx, _dam_idx)
		_say(str(res.get("msg", "")))
		if bool(res.get("ok", false)):
			_sire_idx = -1
			_dam_idx = -1
	)
	# --- nursery ---
	_section("— NURSERY —")
	var nursery: Array = Breeding._nursery(game_state)
	if nursery.is_empty():
		_row("(no eggs)", Callable(), true)
	for k in nursery.size():
		var egg: Dictionary = nursery[k]
		var done := int(egg.get("steps_done", 0))
		var total := int(egg.get("steps_total", Breeding.EGG_STEPS))
		var kk := k
		if done >= total:
			_row("[ HATCH ] egg %d/%d steps" % [done, total], func() -> void:
				var res := Breeding.hatch_egg(game_state, kk)
				_say(str(res.get("msg", "")))
			)
		else:
			_row("Egg — incubating %d/%d steps" % [done, total], Callable(), true)
	# --- growing young ---
	var any_young := false
	for i in p.size():
		var e: Dictionary = p[i]
		if Breeding.is_adult(e):
			continue
		any_young = true
		var pts := int(e.get("growth_points", 0))
		var stage := str(e.get("growth_stage", Breeding.STAGE_HATCHLING))
		var ii: int = i
		_row("[ FEED ] %s — %s (%d/%d)" % [_entry_name(e), stage, pts, Breeding.GROWTH_TO_ADULT],
			func() -> void:
				var res := Breeding.feed(game_state, ii)
				_say(str(res.get("msg", "")))
		)
	if not any_young:
		_row("(no growing young — feed advances hatchlings to adults)", Callable(), true)


func _entry_name(e: Dictionary) -> String:
	CreatureData.ensure_loaded()
	var c: Dictionary = CreatureData.get_creature(str(e.get("creature_id", "")))
	var nm := str(e.get("nickname", ""))
	if nm == "":
		nm = str(c.get("name", e.get("creature_id", "?")))
	return "%s Lv%d" % [nm, int(e.get("level", 1))]
