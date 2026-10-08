extends CanvasLayer
## Player-owned Night Market stall UI (code-built, shop.gd pattern).
##
## NOTE: intentionally no class_name (project convention).
## Two modes: locked (unlock offer) and owned (stock management).
## Keyboard: up/down select, left/right adjust price, Enter stock one,
## I toggle inventory, U unstock selected, C collect till, M hire minder,
## Esc close/back. Mouse: click buttons/rows.

signal closed

const Stall = preload("res://scripts/stall.gd")
const CreatureData = preload("res://scripts/creature_data.gd")
const UiText = preload("res://scripts/ui_text.gd")

var game_state = null

var _open := false
var _show_inventory := false
var _selected := 0
var _rows: Array = []        # stock rows (Buttons)
var _inv_rows: Array = []    # inventory rows (Buttons)
var _msg := ""

var _root: Control
var _title: Label
var _info: Label
var _list: VBoxContainer
var _msg_label: Label
var _hint: Label


func _ready() -> void:
	add_to_group("stall")
	_build()
	visible = false


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(760, 560)
	panel.position -= panel.custom_minimum_size * 0.5
	_root.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 30)
	vbox.add_child(_title)
	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 20)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_info)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(700, 300)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 4)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_msg_label = Label.new()
	_msg_label.add_theme_font_size_override("font_size", 20)
	_msg_label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.5))
	vbox.add_child(_msg_label)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 18)
	_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	vbox.add_child(_hint)


func is_open() -> bool:
	return _open


func open_stall() -> bool:
	_open = true
	_show_inventory = false
	_selected = 0
	_msg = ""
	_refresh()
	visible = true
	return true


func close_stall() -> void:
	_open = false
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not _open or not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		if _show_inventory:
			_show_inventory = false
			_selected = 0
			_refresh()
		else:
			close_stall()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_up"):
		_move_sel(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_move_sel(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_left"):
		_adjust_price(-1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_adjust_price(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_on_accept()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_I:
				_show_inventory = not _show_inventory
				_selected = 0
				_refresh()
				get_viewport().set_input_as_handled()
			KEY_U:
				_unstock_selected()
				get_viewport().set_input_as_handled()
			KEY_C:
				_collect()
				get_viewport().set_input_as_handled()
			KEY_M:
				_hire_minder()
				get_viewport().set_input_as_handled()


func _move_sel(d: int) -> void:
	var n := _inv_rows.size() if _show_inventory else _rows.size()
	if n <= 0:
		return
	_selected = posmod(_selected + d, n)
	_refresh()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	_rows.clear()
	_inv_rows.clear()
	if game_state == null:
		return
	if not Stall.is_unlocked(game_state):
		_title.text = "YOUR STALL"
		_info.text = UiText.invest("stall_offer")
		_msg_label.text = _msg
		var b := _mk_button("BUY THE STALL — %d Soul Credits" % Stall.UNLOCK_COST)
		b.pressed.connect(_unlock)
		_list.add_child(b)
		_rows.append(b)
		_hint.text = "[Enter] buy   [Esc] leave"
		return
	# Owned view.
	_title.text = "YOUR STALL"
	var minder := "minder on duty" if Stall.has_minder(game_state) else "no minder (half sales)"
	_info.text = "Till: %d c   |   You: %d c   |   %s   |   Lifetime: %d c" % [
		Stall.get_till(game_state), game_state.get_soul_credits(),
		minder, Stall.get_lifetime(game_state)]
	_msg_label.text = _msg
	if _show_inventory:
		_refresh_inventory()
	else:
		_refresh_stock()
	_hint.text = "[I] inventory   [left/right] price   [U] unstock   [C] collect till   [M] minder   [Esc] close"


func _refresh_stock() -> void:
	var stock: Dictionary = Stall.get_stock(game_state)
	var ids := stock.keys()
	ids.sort()
	for i in ids.size():
		var item_id := str(ids[i])
		var e: Dictionary = stock[item_id]
		var item: Dictionary = CreatureData.get_item(item_id)
		var label := "%s  x%d  @  %d c" % [str(item.get("name", item_id)), int(e["qty"]), int(e["price"])]
		if i == _selected:
			label = "> " + label
		var b := _mk_button(label)
		b.pressed.connect(_on_stock_row.bind(i))
		_list.add_child(b)
		_rows.append(b)
	if ids.is_empty():
		var l := Label.new()
		l.text = "(nothing stocked — press I to browse your inventory)"
		l.add_theme_font_size_override("font_size", 20)
		_list.add_child(l)


func _refresh_inventory() -> void:
	var inv: Dictionary = game_state.state.get("inventory", {})
	var ids := inv.keys()
	ids.sort()
	for i in ids.size():
		var item_id := str(ids[i])
		var n := int(inv[item_id])
		if n <= 0:
			continue
		var item: Dictionary = CreatureData.get_item(item_id)
		var base := int(item.get("price", 0))
		if base <= 0:
			continue
		var label := "%s  x%d  (base %d c)" % [str(item.get("name", item_id)), n, base]
		if i == _selected:
			label = "> " + label
		var b := _mk_button(label)
		b.pressed.connect(_on_inv_row.bind(item_id))
		b.set_meta("item_id", item_id)
		_list.add_child(b)
		_inv_rows.append(b)


func _mk_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 22)
	return b


func _on_accept() -> void:
	if not Stall.is_unlocked(game_state):
		_unlock()
		return
	if _show_inventory:
		if _selected < _inv_rows.size():
			_on_inv_row(str(_inv_rows[_selected].get_meta("item_id")))
	else:
		pass  # stock rows use left/right for pricing


func _on_stock_row(idx: int) -> void:
	_selected = idx
	_refresh()


func _on_inv_row(item_id: String) -> void:
	var r := Stall.stock_item(game_state, item_id, 1, Stall.base_price(item_id))
	_msg = str(r["message"])
	_refresh()


func _adjust_price(d: int) -> void:
	if _show_inventory or not Stall.is_unlocked(game_state):
		return
	var stock: Dictionary = Stall.get_stock(game_state)
	var ids := stock.keys()
	ids.sort()
	if _selected >= ids.size():
		return
	var item_id := str(ids[_selected])
	var e: Dictionary = stock[item_id]
	var step := maxi(1, int(round(Stall.base_price(item_id) * 0.1)))
	var r := Stall.set_price(game_state, item_id, int(e["price"]) + d * step)
	_msg = str(r["message"])
	_refresh()


func _unstock_selected() -> void:
	if _show_inventory or not Stall.is_unlocked(game_state):
		return
	var stock: Dictionary = Stall.get_stock(game_state)
	var ids := stock.keys()
	ids.sort()
	if _selected >= ids.size():
		return
	var item_id := str(ids[_selected])
	var e: Dictionary = stock[item_id]
	var r := Stall.unstock_item(game_state, item_id, int(e["qty"]))
	_msg = str(r["message"])
	_selected = 0
	_refresh()


func _collect() -> void:
	if not Stall.is_unlocked(game_state):
		return
	var r := Stall.collect_till(game_state)
	_msg = str(r["message"])
	if bool(r.get("ok", false)):
		_msg = UiText.invest("stall_collect") + " (%d Soul Credits.)" % int(r["amount"])
	_refresh()


func _hire_minder() -> void:
	if not Stall.is_unlocked(game_state):
		return
	var r := Stall.hire_minder(game_state)
	_msg = str(r["message"])
	_refresh()


func _unlock() -> void:
	var r := Stall.unlock(game_state)
	_msg = str(r["message"])
	if bool(r.get("ok", false)):
		_msg = UiText.invest("stall_unlock") + " " + _msg
	_refresh()
