extends CanvasLayer
## Reaper's Reaper — buy-only shop overlay.
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Opened by an NPC with `is_shopkeeper = true` (see npc.gd). Lists the stock
## of `shop_id` from data/shop.json with canon prices. Buy 1 per press;
## no selling, no bulk (noted for later). Keyboard: up/down + Enter; Esc
## closes. Clickable.
## Item flavor text is a wiring placeholder for the story bot.

signal closed

const CreatureData = preload("res://scripts/creature_data.gd")
const UiText = preload("res://scripts/ui_text.gd")
const Merchants = preload("res://scripts/merchants.gd")
const PartyScript = preload("res://scripts/party.gd")

var game_state = null  # GameState autoload or injected (headless tests)

var _shop_id: String = ""
var _open: bool = false
var _built: bool = false
var _no_haggle: bool = false  # Night Market: the price is the price.
var _stock: Array = []  # [{item_id, price, second_price?}]
var _buttons: Array = []  # Buttons in stock order
var _selected: int = 0
var _credits_label: Label = null
var _title_label: Label = null
var _desc_label: Label = null
var _tier_label: Label = null
var _stock_box: VBoxContainer = null
var _msg_label: Label = null
var _msg_timer: float = 0.0
var _haggle_button: Button = null
var _invest_button: Button = null
var _repay_button: Button = null
# Haggle panel state (one active offer at a time).
var _haggle_open: bool = false
var _haggle_offer: int = 0
var _haggle_range: Array = [0, 0]
var _haggle_panel: Control = null
var _haggle_offer_label: Label = null
var _hint_label: Label = null
# Two-price (Night Market "The Toll") release picker state.
var _release_open: bool = false
var _release_entry: Dictionary = {}
var _release_stage: int = 0  # 0 = pick creature, 1 = confirm release
var _release_index: int = -1
var _release_panel: Control = null
var _release_title: Label = null
var _release_list: VBoxContainer = null

const BONE := Color(0.92, 0.90, 0.86)
const GOLD := Color(0.95, 0.80, 0.45)
const DIM := Color(0.45, 0.44, 0.42)


func _ready() -> void:
	if _built:
		return
	_built = true
	layer = 12
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	add_to_group("shop")
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)
	var title := Label.new()
	title.name = "ShopTitle"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)
	_title_label = title
	var desc := Label.new()
	desc.name = "ShopDesc"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 18)
	desc.add_theme_color_override("font_color", DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size = Vector2(560, 0)
	box.add_child(desc)
	_desc_label = desc
	_credits_label = Label.new()
	_credits_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_credits_label.add_theme_font_size_override("font_size", 24)
	_credits_label.add_theme_color_override("font_color", BONE)
	box.add_child(_credits_label)
	_tier_label = Label.new()
	_tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tier_label.add_theme_font_size_override("font_size", 18)
	_tier_label.add_theme_color_override("font_color", GOLD)
	box.add_child(_tier_label)
	var stock_box := VBoxContainer.new()
	stock_box.name = "StockBox"
	stock_box.add_theme_constant_override("separation", 4)
	box.add_child(stock_box)
	_stock_box = stock_box
	_msg_label = Label.new()
	_msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_msg_label.add_theme_font_size_override("font_size", 20)
	_msg_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	_msg_label.text = ""
	box.add_child(_msg_label)
	var hint := Label.new()
	hint.name = "ShopHint"
	hint.text = "[Enter] buy · [H] haggle · [I] invest · [T] repay tab · [Esc] leave"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", DIM)
	box.add_child(hint)
	_hint_label = hint
	# Merchant action row: haggle / invest / repay tab.
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 12)
	box.add_child(actions)
	_haggle_button = _make_action_button(actions, "HAGGLE")
	_invest_button = _make_action_button(actions, "INVEST")
	_repay_button = _make_action_button(actions, "REPAY TAB")
	_haggle_button.pressed.connect(_on_haggle_pressed)
	_invest_button.pressed.connect(_on_invest_pressed)
	_repay_button.pressed.connect(_on_repay_pressed)
	_build_release_panel()


## Two-price release picker: hidden overlay listing the player's bound
## creatures. Stage 0 picks a creature, stage 1 confirms the release.
func _build_release_panel() -> void:
	var panel := PanelContainer.new()
	panel.name = "ReleasePanel"
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.01, 0.05, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)
	var title := Label.new()
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", GOLD)
	box.add_child(title)
	_release_title = title
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	box.add_child(list)
	_release_list = list
	add_child(panel)
	_release_panel = panel


func _make_action_button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 18)
	b.add_theme_color_override("font_color", BONE)
	b.custom_minimum_size = Vector2(150, 40)
	parent.add_child(b)
	return b


func open_shop(shop_id: String) -> bool:
	var shop: Dictionary = CreatureData.get_shop(shop_id)
	if shop.is_empty():
		push_warning("shop.gd: unknown shop_id '" + shop_id + "'")
		return false
	_shop_id = shop_id
	_no_haggle = bool(shop.get("no_haggle", false))
	_close_release_picker()
	# Duplicate: the rare-stock append below must not mutate the cached data.
	_stock = (shop.get("stock", []) as Array).duplicate(true)
	# Investing unlocks a permanent rare stock slot for this merchant.
	if Merchants.is_invested(game_state, _shop_id):
		var rare_id := Merchants.rare_item(_shop_id)
		if not rare_id.is_empty():
			var already := false
			for e in _stock:
				if str(e.get("item_id", "")) == rare_id:
					already = true
			if not already:
				_stock.append({"item_id": rare_id, "price": _rare_price(rare_id)})
	_title_label.text = str(shop.get("name", "SHOP")).to_upper()
	# Canon store description from the UI text DB (doc 08 §7). Falls back
	# to the shop.json "blurb" when the supplement has no entry (e.g. the
	# Ferry Stall is wiring-original — story bot to supply the canon line).
	var desc_text := UiText.store_desc(shop_id)
	if desc_text.is_empty():
		desc_text = str(shop.get("blurb", ""))
	_desc_label.text = desc_text
	_desc_label.visible = not desc_text.is_empty()
	var stock_box: VBoxContainer = _stock_box
	for c in stock_box.get_children():
		c.queue_free()
	_buttons.clear()
	_selected = 0
	for entry in _stock:
		var item: Dictionary = CreatureData.get_item(str(entry["item_id"]))
		var b := Button.new()
		_refresh_stock_button(b, entry, item)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 22)
		b.pressed.connect(_on_buy_pressed.bind(_buttons.size()))
		stock_box.add_child(b)
		_buttons.append(b)
	_refresh()
	_open = true
	visible = true
	_update_focus()
	return true


## Canon list price for a rare item (looked up from the other stores' stock).
func _rare_price(item_id: String) -> int:
	for mid in Merchants.merchant_ids():
		var shop: Dictionary = CreatureData.get_shop(mid)
		for e in shop.get("stock", []):
			if str(e.get("item_id", "")) == item_id:
				return int(e["price"])
	return 0


## Effective buy price: disposition multiplier (and same-day haggles) applied.
func _price_for(entry: Dictionary) -> int:
	return Merchants.price_for(game_state, _shop_id, str(entry["item_id"]), int(entry["price"]))


func is_open() -> bool:
	return _open


func close_shop() -> void:
	_close_release_picker()
	_open = false
	visible = false
	closed.emit()


## Stock button label with the disposition-adjusted price.
## Two-price entries (The Toll) show both prices.
func _refresh_stock_button(b: Button, entry: Dictionary, item: Dictionary) -> void:
	var label := "%s — %d credits" % [str(item.get("name", entry["item_id"])), _price_for(entry)]
	if not (entry.get("second_price", {}) as Dictionary).is_empty():
		label += " + release"
	b.text = label


func _refresh() -> void:
	_credits_label.text = "Soul Credits: %d" % int(game_state.get_soul_credits())
	_tier_label.text = Merchants.tier_line(game_state, _shop_id)
	_tier_label.tooltip_text = UiText.disposition_desc(Merchants.get_tier(game_state, _shop_id))
	for i in _buttons.size():
		var entry: Dictionary = _stock[i]
		var price := _price_for(entry)
		var afford: bool = int(game_state.get_soul_credits()) >= price or Merchants.can_tab(game_state, _shop_id, price)
		(_buttons[i] as Button).disabled = not afford
		_refresh_stock_button(_buttons[i] as Button, entry, CreatureData.get_item(str(entry["item_id"])))
	_refresh_actions()


## Haggle / invest / repay-tab buttons: enabled only when meaningful.
func _refresh_actions() -> void:
	if _haggle_button == null:
		return
	var has_stock := not _stock.is_empty()
	# Night Market: the price is the price — no haggling, no investing.
	var known_merchant := not Merchants.get_merchant(_shop_id).is_empty()
	_haggle_button.visible = not _no_haggle
	_haggle_button.disabled = _no_haggle or not has_stock or Merchants.haggle_attempted_today(game_state, _shop_id)
	_haggle_button.tooltip_text = UiText.haggle("haggle_prompt")
	_invest_button.visible = known_merchant
	var invested := Merchants.is_invested(game_state, _shop_id)
	_invest_button.disabled = invested
	if invested:
		_invest_button.text = "INVESTED"
	else:
		_invest_button.text = "INVEST (%d)" % Merchants.invest_cost(_shop_id)
		_invest_button.tooltip_text = Merchants.invest_offer_text(_shop_id)
	var debt := Merchants.tab_debt(game_state, _shop_id)
	_repay_button.disabled = debt <= 0
	_repay_button.visible = debt > 0
	if _hint_label != null:
		var parts: Array[String] = ["[Enter] buy"]
		if not _no_haggle:
			parts.append("[H] haggle")
		if known_merchant:
			parts.append("[I] invest")
		if debt > 0:
			parts.append("[T] repay tab")
		parts.append("[Esc] leave")
		_hint_label.text = " · ".join(parts)


func _update_focus() -> void:
	if _buttons.is_empty():
		return
	(_buttons[clampi(_selected, 0, _buttons.size() - 1)] as Button).grab_focus()


func _on_buy_pressed(idx: int) -> void:
	_selected = idx
	buy_selected()


## Buy one of the selected stock entry. Returns true on success.
## Two-price entries (The Toll) open the release picker instead and
## return false — the purchase completes from the picker.
func buy_selected() -> bool:
	if not _open or _stock.is_empty():
		return false
	var entry: Dictionary = _stock[clampi(_selected, 0, _stock.size() - 1)]
	var second: Dictionary = entry.get("second_price", {})
	if not second.is_empty():
		_open_release_picker(entry)
		return false
	var price := _price_for(entry)
	var item_id := str(entry["item_id"])
	if game_state.spend_soul_credits(price):
		game_state.add_item(item_id, 1)
		Merchants.record_purchase(game_state, _shop_id, item_id)
		_flash("Bought. The merchant nods.")
		_refresh()
		_update_focus()
		return true
	# Friend tier: buy on tab when short on credits.
	if Merchants.buy_on_tab(game_state, _shop_id, price):
		game_state.add_item(item_id, 1)
		Merchants.record_purchase(game_state, _shop_id, item_id)
		_flash("On the tab. %s will remember." % UiText.store_name(_shop_id))
		_refresh()
		_update_focus()
		return true
	_flash("Not enough Soul Credits.")
	return false


## ---- Two-price release picker ("The Toll") ----
## The signature Night Market mechanic: some items cost credits AND a
## creature release. "contract" second prices are a flag hook for later;
## only "release" is implemented today.

func _second_price_kind(entry: Dictionary) -> String:
	return str((entry.get("second_price", {}) as Dictionary).get("type", ""))


func _open_release_picker(entry: Dictionary) -> void:
	if _second_price_kind(entry) != "release":
		_flash("The Toll does not take that price. (Not yet.)")
		return
	var price := _price_for(entry)
	if game_state.get_soul_credits() < price:
		_flash("Not enough Soul Credits.")
		return
	if PartyScript.size(game_state) <= 0:
		_flash("The Toll demands a release. You have no creatures bound.")
		return
	_release_entry = entry
	_release_stage = 0
	_release_index = -1
	_show_release_list()
	_release_open = true
	_release_panel.visible = true


func _show_release_list() -> void:
	for c in _release_list.get_children():
		c.queue_free()
	_release_stage = 0
	_release_title.text = "The second price: release one bound creature."
	var n := PartyScript.size(game_state)
	for i in n:
		var e: Dictionary = PartyScript.get_entry(game_state, i)
		var b := Button.new()
		b.text = _creature_label(e)
		b.add_theme_font_size_override("font_size", 20)
		b.pressed.connect(_on_release_pick.bind(i))
		_release_list.add_child(b)
	var cancel := Button.new()
	cancel.text = "Walk away"
	cancel.add_theme_font_size_override("font_size", 20)
	cancel.pressed.connect(_close_release_picker)
	_release_list.add_child(cancel)
	if _release_list.get_child_count() > 0:
		(_release_list.get_child(0) as Button).grab_focus()


func _creature_label(e: Dictionary) -> String:
	var cid := str(e.get("creature_id", ""))
	var nm := str(e.get("nickname", ""))
	if nm.is_empty():
		nm = str(CreatureData.get_creature(cid).get("name", cid))
	return "%s — Lv %d" % [nm, int(e.get("level", 1))]


func _on_release_pick(idx: int) -> void:
	if not PartyScript.is_valid_index(game_state, idx):
		return
	_release_index = idx
	_release_stage = 1
	for c in _release_list.get_children():
		c.queue_free()
	var e: Dictionary = PartyScript.get_entry(game_state, idx)
	_release_title.text = "Release %s? It will be gone." % _creature_label(e)
	var confirm := Button.new()
	confirm.text = "Release it"
	confirm.add_theme_font_size_override("font_size", 20)
	confirm.pressed.connect(_on_release_confirm)
	_release_list.add_child(confirm)
	var back := Button.new()
	back.text = "Back"
	back.add_theme_font_size_override("font_size", 20)
	back.pressed.connect(_show_release_list)
	_release_list.add_child(back)
	confirm.grab_focus()


func _on_release_confirm() -> void:
	var entry := _release_entry
	var idx := _release_index
	if entry.is_empty() or not PartyScript.is_valid_index(game_state, idx):
		_close_release_picker()
		return
	var price := _price_for(entry)
	var item_id := str(entry["item_id"])
	var e: Dictionary = PartyScript.get_entry(game_state, idx)
	var nm := _creature_label(e)
	# Credits first: a failed payment must never eat the creature.
	if not game_state.spend_soul_credits(price):
		_flash("Not enough Soul Credits.")
		_close_release_picker()
		return
	if not PartyScript.remove_creature(game_state, idx):
		# Refund: the release failed after payment.
		game_state.add_soul_credits(price)
		_flash("The release failed. Your credits were returned.")
		_close_release_picker()
		return
	game_state.add_item(item_id, 1)
	Merchants.record_purchase(game_state, _shop_id, item_id)
	_close_release_picker()
	_flash("Paid in full. Both prices. %s is free now." % nm)
	_refresh()
	_update_focus()


func _close_release_picker() -> void:
	_release_open = false
	_release_entry = {}
	_release_index = -1
	_release_stage = 0
	if _release_panel != null:
		_release_panel.visible = false


func _flash(text: String) -> void:
	_msg_label.text = text
	_msg_timer = 1.5


func _process(delta: float) -> void:
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			_msg_label.text = ""


## ---- Merchant actions: haggle / invest / repay tab ----

func _on_haggle_pressed() -> void:
	if _no_haggle:
		return  # Night Market: the price is the price.
	_open_haggle()


func _on_invest_pressed() -> void:
	if not _open or Merchants.is_invested(game_state, _shop_id):
		return
	var res: Dictionary = Merchants.invest(game_state, _shop_id)
	_flash(res.get("message", ""))
	# Re-open to pick up the new rare stock slot.
	open_shop(_shop_id)


func _on_repay_pressed() -> void:
	if not _open:
		return
	var res: Dictionary = Merchants.repay_tab(game_state, _shop_id)
	if bool(res.get("ok", false)):
		_flash("Tab cleared: %d credits." % int(res.get("repaid", 0)))
	else:
		_flash("Not enough Soul Credits to clear the tab.")
	_refresh()


## Haggle overlay: up/down adjusts the offer in 5% steps inside the shown
## range, Enter confirms, Esc cancels. One attempt per merchant per day.
func _open_haggle() -> void:
	if not _open or _stock.is_empty() or _haggle_open:
		return
	if Merchants.haggle_attempted_today(game_state, _shop_id):
		_flash(UiText.haggle("haggle_prompt"))
		return
	var entry: Dictionary = _stock[clampi(_selected, 0, _stock.size() - 1)]
	var list_price := int(entry["price"])
	_haggle_range = Merchants.haggle_range(list_price)
	_haggle_offer = int((_haggle_range[0] + _haggle_range[1]) / 2)
	_haggle_open = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	center.add_child(box)
	var prompt := Label.new()
	prompt.text = UiText.haggle("haggle_prompt")
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 20)
	prompt.add_theme_color_override("font_color", BONE)
	box.add_child(prompt)
	var rng := Label.new()
	rng.text = "List %d — offer between %d and %d" % [list_price, _haggle_range[0], _haggle_range[1]]
	rng.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rng.add_theme_font_size_override("font_size", 18)
	rng.add_theme_color_override("font_color", DIM)
	box.add_child(rng)
	_haggle_offer_label = Label.new()
	_haggle_offer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_haggle_offer_label.add_theme_font_size_override("font_size", 40)
	_haggle_offer_label.add_theme_color_override("font_color", GOLD)
	box.add_child(_haggle_offer_label)
	var keys := Label.new()
	keys.text = "[up/down] adjust · [Enter] offer · [Esc] walk away"
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.add_theme_font_size_override("font_size", 16)
	keys.add_theme_color_override("font_color", DIM)
	box.add_child(keys)
	_haggle_panel = dim
	_update_haggle_offer()


func _update_haggle_offer() -> void:
	if _haggle_offer_label != null:
		_haggle_offer_label.text = "%d credits" % _haggle_offer


func _close_haggle() -> void:
	_haggle_open = false
	if _haggle_panel != null and is_instance_valid(_haggle_panel):
		_haggle_panel.queue_free()
	_haggle_panel = null
	_haggle_offer_label = null


func _confirm_haggle() -> void:
	if not _haggle_open:
		return
	var entry: Dictionary = _stock[clampi(_selected, 0, _stock.size() - 1)]
	var res: Dictionary = Merchants.haggle(game_state, _shop_id, str(entry["item_id"]), int(entry["price"]), _haggle_offer)
	_close_haggle()
	_flash(str(res.get("message", "")))
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if _release_open:
		# The picker is button-driven; Esc walks away.
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_close_release_picker()
		return
	if _haggle_open:
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_close_haggle()
		elif event.is_action_pressed("ui_up"):
			_haggle_offer = mini(_haggle_offer + int(maxi(1, int((_haggle_range[1] - _haggle_range[0]) / 8))), _haggle_range[1])
			_update_haggle_offer()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_down"):
			_haggle_offer = maxi(_haggle_offer - int(maxi(1, int((_haggle_range[1] - _haggle_range[0]) / 8))), _haggle_range[0])
			_update_haggle_offer()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
			_confirm_haggle()
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_shop()
		return
	if event.is_action_pressed("ui_down"):
		_selected = (_selected + 1) % _buttons.size()
		_update_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_selected = (_selected - 1 + _buttons.size()) % _buttons.size()
		_update_focus()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		buy_selected()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_H:
				get_viewport().set_input_as_handled()
				_on_haggle_pressed()
			KEY_I:
				get_viewport().set_input_as_handled()
				_on_invest_pressed()
			KEY_T:
				get_viewport().set_input_as_handled()
				_on_repay_pressed()
