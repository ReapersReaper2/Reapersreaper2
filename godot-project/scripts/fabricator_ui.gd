extends CanvasLayer
## Living Fabricator UI (code-built, stall_ui.gd pattern).
##
## NOTE: intentionally no class_name (project convention).
## Opened from the fabricator station in room_g1 (Armor Plant Grove).
## Feed inventory feedstock (curated list only; anything else is refused
## in-fiction), graft learned traits into weapon (1) / armor (2) slots,
## or apply utility/world/quest traits. Pauses the tree while open.
## All flavor text is [WIRING] wiring-written, flagged for story-bot revision.

signal closed

const Fabricator = preload("res://scripts/fabricator.gd")

var game_state = null

var _open := false
var _built := false
var _msg := ""

var _title: Label
var _slots: Label
var _feed_list: VBoxContainer
var _learned_list: VBoxContainer
var _msg_label: Label


func _ready() -> void:
	add_to_group("fabricator")
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 14
	_build()
	visible = false


func _build() -> void:
	if _built:
		return
	_built = true
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.06, 0.03, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 580)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for m in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(m, 24)
	for m in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(m, 16)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_title = Label.new()
	_title.text = "THE LIVING FABRICATOR"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 28)
	_title.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6))
	vbox.add_child(_title)
	var sub := Label.new()
	sub.text = "[WIRING] Feed it. It decides what to grow."
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.55, 0.6, 0.55))
	vbox.add_child(sub)

	_slots = Label.new()
	_slots.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_slots)

	var feed_title := Label.new()
	feed_title.text = "FEEDSTOCK (in your pack)"
	feed_title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(feed_title)
	var scroll1 := ScrollContainer.new()
	scroll1.custom_minimum_size = Vector2(640, 130)
	vbox.add_child(scroll1)
	_feed_list = VBoxContainer.new()
	_feed_list.add_theme_constant_override("separation", 4)
	_feed_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll1.add_child(_feed_list)

	var learned_title := Label.new()
	learned_title.text = "LEARNED SHAPES"
	learned_title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(learned_title)
	var scroll2 := ScrollContainer.new()
	scroll2.custom_minimum_size = Vector2(640, 130)
	vbox.add_child(scroll2)
	_learned_list = VBoxContainer.new()
	_learned_list.add_theme_constant_override("separation", 4)
	_learned_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll2.add_child(_learned_list)

	_msg_label = Label.new()
	_msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg_label.custom_minimum_size = Vector2(640, 60)
	_msg_label.add_theme_font_size_override("font_size", 17)
	_msg_label.add_theme_color_override("font_color", Color(0.85, 0.9, 0.8))
	vbox.add_child(_msg_label)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)
	var leave := Button.new()
	leave.text = "LEAVE"
	leave.focus_mode = Control.FOCUS_NONE
	leave.add_theme_font_size_override("font_size", 20)
	leave.custom_minimum_size = Vector2(140, 44)
	leave.pressed.connect(_on_leave)
	btn_row.add_child(leave)
	var hint := Label.new()
	hint.text = "Esc: leave"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.5, 0.55, 0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)


func is_open() -> bool:
	return _open


func open_fabricator() -> void:
	_open = true
	_msg = ""
	_refresh()
	visible = true


func close_fabricator() -> void:
	_open = false
	visible = false
	closed.emit()


func _item_name(item_id: String) -> String:
	# Best-effort pretty name from the id; items.json names would need ItemData.
	var parts := str(item_id).split("_")
	var out: Array = []
	for p in parts:
		out.append(str(p).capitalize())
	return " ".join(out)


func _refresh() -> void:
	var armor_names: Array = []
	for a in Fabricator.grafted_armor(game_state):
		armor_names.append(_pretty_slot(a))
	_slots.text = "Weapon graft: %s    Armor grafts: %s" % [
		_pretty_slot(Fabricator.grafted_weapon(game_state)),
		", ".join(armor_names),
	]
	for c in _feed_list.get_children():
		c.queue_free()
	for c in _learned_list.get_children():
		c.queue_free()
	_msg_label.text = _msg
	if game_state == null:
		return
	# Feedstock rows: curated items currently held.
	var any_feed := false
	for item_id in Fabricator.FEEDSTOCK:
		var n: int = game_state.get_item_count(item_id)
		if n <= 0:
			continue
		any_feed = true
		var trait_id: String = Fabricator.FEEDSTOCK[item_id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lab := Label.new()
		lab.text = "%s x%d  →  teaches %s" % [_item_name(item_id), n, Fabricator.trait_name(trait_id)]
		lab.add_theme_font_size_override("font_size", 17)
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lab)
		var b := Button.new()
		b.text = "FEED"
		b.focus_mode = Control.FOCUS_NONE
		var iid: String = item_id
		b.pressed.connect(_on_feed.bind(iid))
		row.add_child(b)
		_feed_list.add_child(row)
	if not any_feed:
		var lab := Label.new()
		lab.text = "[WIRING] Nothing it wants. (Feedstock: broken swords, keys, beams, ore, bark, thorns.)"
		lab.add_theme_font_size_override("font_size", 16)
		lab.add_theme_color_override("font_color", Color(0.55, 0.58, 0.55))
		_feed_list.add_child(lab)
	# Learned rows.
	var learned: Array = Fabricator.learned(game_state)
	if learned.is_empty():
		var lab2 := Label.new()
		lab2.text = "[WIRING] The plant knows nothing yet. Feed it."
		lab2.add_theme_font_size_override("font_size", 16)
		lab2.add_theme_color_override("font_color", Color(0.55, 0.58, 0.55))
		_learned_list.add_child(lab2)
	for tid in learned:
		var slot: String = Fabricator.trait_slot(tid)
		var verb := "GRAFT"
		if slot == "utility" or slot == "world" or slot == "quest":
			verb = "APPLY"
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 8)
		var lab3 := Label.new()
		lab3.text = "%s (%s) — %s" % [Fabricator.trait_name(tid), slot, Fabricator.trait_desc(tid)]
		lab3.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lab3.add_theme_font_size_override("font_size", 16)
		lab3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(lab3)
		var b2 := Button.new()
		b2.text = verb
		b2.focus_mode = Control.FOCUS_NONE
		var t: String = tid
		b2.pressed.connect(_on_graft.bind(t))
		row2.add_child(b2)
		_learned_list.add_child(row2)


func _pretty_slot(tid) -> String:
	if tid == null or str(tid) == "":
		return "—"
	return Fabricator.trait_name(str(tid))


func _on_feed(item_id: String) -> void:
	var res: Dictionary = Fabricator.learn(game_state, item_id)
	_msg = str(res.get("msg", ""))
	_refresh()


func _on_graft(trait_id: String) -> void:
	var res: Dictionary = Fabricator.graft(game_state, trait_id)
	_msg = str(res.get("msg", ""))
	_refresh()


func _on_leave() -> void:
	close_fabricator()


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_fabricator()
