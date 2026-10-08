extends SceneTree
## Headless Night Market test: gate flag, vendors, two-price mechanic,
## locked stall teaser, exits, no-haggle rule, moonlit snare wiring.
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/night_market_test.gd
## Uses throwaway slot 96 so real saves are never touched.
##
## NOTE: under -s, nodes added here are not inside the tree yet, so the test
## injects dependencies (shop.game_state) and calls internals directly — the
## same pattern as shop_test.gd.

const SLOT := 96

const UiText = preload("res://scripts/ui_text.gd")
const PartyScript = preload("res://scripts/party.gd")
const Merchants = preload("res://scripts/merchants.gd")

var _failures: Array[String] = []


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failures.append(name)
		print("  FAIL: ", name)


func _make_stack() -> Array:
	var save_system_script = load("res://scripts/save_system.gd")
	var game_state_script = load("res://scripts/game_state.gd")
	var ach_script = load("res://scripts/achievements.gd")
	var ss = save_system_script.new()
	root.add_child(ss)
	var ach = ach_script.new()
	root.add_child(ach)
	var gs = game_state_script.new()
	gs.save_system = ss
	gs.achievements = ach
	root.add_child(gs)
	gs._ready()
	ach.game_state = gs
	return [ss, ach, gs]


func _make_shop(gs):
	var shop = (load("res://scenes/shop.tscn") as PackedScene).instantiate()
	shop.game_state = gs
	root.add_child(shop)
	shop._ready()
	return shop


func _initialize() -> void:
	print("night_market_test: starting")
	var stack := _make_stack()
	var gs = stack[2]

	# --- canon strings verbatim from ui_text ---
	_check("entry line verbatim",
		UiText.night_market("entry") == "The Night Market. Everything has a price. Some things have two.")
	_check("ivy_sign verbatim",
		UiText.night_market("ivy_sign") == "The price is the price, little reaper.")

	# --- shop data exists ---
	var shop = _make_shop(gs)
	_check("open nm_ivy", shop.open_shop("nm_ivy"))
	_check("ivy has 3 stock", shop._stock.size() == 3)
	_check("ivy no_haggle", shop._no_haggle)
	_check("ivy haggle button hidden", not shop._haggle_button.visible)
	_check("ivy blurb is ivy_sign", shop._desc_label.text == "The price is the price, little reaper.")
	_check("open nm_rares", shop.open_shop("nm_rares"))
	_check("rares has 5 stock", shop._stock.size() == 5)
	var rare_ids: Array = []
	for e in shop._stock:
		rare_ids.append(str(e["item_id"]))
	_check("rares has moonlit_snare", "moonlit_snare" in rare_ids)
	_check("rares has nightshade_poultice", "nightshade_poultice" in rare_ids)
	_check("open nm_twoprice", shop.open_shop("nm_twoprice"))
	_check("twoprice has 4 stock", shop._stock.size() == 4)
	var all_two := true
	for e in shop._stock:
		var sp: Dictionary = e.get("second_price", {})
		if str(sp.get("type", "")) != "release":
			all_two = false
	_check("all twoprice entries are release type", all_two)
	_check("twoprice label shows + release",
		str(shop._buttons[0].text).ends_with("+ release"))

	# --- Ivy: plain buy works, no haggle path ---
	gs.state["soul_credits"] = 1000
	shop.open_shop("nm_ivy")
	shop._selected = 0  # soul_snare, 150
	var c0: int = gs.get_soul_credits()
	_check("ivy buy succeeds", shop.buy_selected())
	_check("ivy buy charged 150", gs.get_soul_credits() == c0 - 150)
	shop._on_haggle_pressed()
	_check("ivy haggle is a no-op", not shop._haggle_open)

	# --- merchants fallback for night vendors doesn't crash ---
	_check("night vendor tier stranger", Merchants.get_tier(gs, "nm_ivy") == "stranger")
	_check("night vendor mult 1.0", Merchants.price_multiplier(gs, "nm_ivy") == 1.0)
	_check("night vendor invest hidden", not shop._invest_button.visible)

	# --- two-price: empty party blocks gracefully ---
	shop.open_shop("nm_twoprice")
	while PartyScript.size(gs) > 0:
		PartyScript.remove_creature(gs, 0)
	_check("party emptied", PartyScript.size(gs) == 0)
	gs.state["soul_credits"] = 1000
	shop._selected = 0  # moonlit_snare, 200 + release
	var c1: int = gs.get_soul_credits()
	_check("twoprice with no party fails", not shop.buy_selected())
	_check("no charge on blocked twoprice", gs.get_soul_credits() == c1)
	_check("blocked message shown", shop._msg_label.text != "")
	_check("picker did not open", not shop._release_open)

	# --- two-price: full flow charges both prices ---
	_check("add test creature", PartyScript.add_creature(gs, "snapling", 5))
	_check("party has 1", PartyScript.size(gs) == 1)
	gs.state["soul_credits"] = 1000
	var snares0: int = gs.get_item_count("moonlit_snare")
	shop._selected = 0
	_check("twoprice opens picker (not direct buy)", not shop.buy_selected())
	_check("picker open", shop._release_open)
	_check("picker lists 1 creature + walk away", shop._release_list.get_child_count() == 2)
	shop._on_release_pick(0)
	_check("pick moves to confirm stage", shop._release_stage == 1)
	_check("confirm title names creature", str(shop._release_title.text).begins_with("Release "))
	shop._on_release_confirm()
	_check("picker closed after confirm", not shop._release_open)
	_check("credits charged 200", gs.get_soul_credits() == 800)
	_check("moonlit snare granted", gs.get_item_count("moonlit_snare") == snares0 + 1)
	_check("creature released", PartyScript.size(gs) == 0)

	# --- two-price: broke on credits blocks before picker ---
	_check("add creature again", PartyScript.add_creature(gs, "wispwillow", 3))
	gs.state["soul_credits"] = 10
	shop._selected = 0
	_check("twoprice broke fails", not shop.buy_selected())
	_check("picker stays shut when broke", not shop._release_open)
	_check("creature kept when broke", PartyScript.size(gs) == 1)

	# --- moonlit snare item data ---
	var ms: Dictionary = shop.CreatureData.get_item("moonlit_snare")
	_check("moonlit snare catch_bonus 0.25", float(ms.get("catch_bonus", 0.0)) == 0.25)
	var np: Dictionary = shop.CreatureData.get_item("nightshade_poultice")
	_check("nightshade heals 120", int((np.get("effect", {}) as Dictionary).get("amount", 0)) == 120)
	shop.close_shop()

	# --- room_nm scene structure ---
	var nm = (load("res://scenes/room_nm.tscn") as PackedScene).instantiate()
	_check("room_nm id", str(nm.get("room_id")) == "nm")
	_check("ivy vendor npc", str(nm.get_node("Ivy").get("shop_id")) == "nm_ivy")
	_check("masked vendor npc", str(nm.get_node("Masked").get("shop_id")) == "nm_rares")
	_check("tollkeeper vendor npc", str(nm.get_node("Tollkeeper").get("shop_id")) == "nm_twoprice")
	_check("stall is not a shopkeeper", not bool(nm.get_node("RopedStall").get("is_shopkeeper")))
	_check("stall teaser lines present", (nm.get_node("RopedStall").get("lines") as PackedStringArray).size() >= 2)
	var exit_h1 = nm.get_node("ExitH1")
	_check("nm exit targets h1", str(exit_h1.get_meta("target_room_id")) == "h1")
	_check("nm entry trigger exists", nm.get_node("EntryTrigger").get_meta("trigger_id") == "nm_entry")
	nm.queue_free()

	# --- H1 moon-gate: locked until the announcement ---
	var h1 = (load("res://scenes/room_h1.tscn") as PackedScene).instantiate()
	var gate = h1.get_node("ExitMoonGate")
	_check("moongate lock flag", str(gate.get_meta("lock_flag")) == "h2_announcement_done")
	_check("moongate targets nm", str(gate.get_meta("target_room_id")) == "nm")
	_check("moongate has hint", str(gate.get_meta("locked_hint")) != "")
	h1.queue_free()

	# --- save/load round-trip keeps night market state ---
	gs.state["soul_credits"] = 777
	_check("save writes", gs.save_to_slot(SLOT))
	gs.state["soul_credits"] = 0
	_check("load restores", gs.load_from_slot(SLOT))
	_check("credits round-trip", gs.get_soul_credits() == 777)

	print("night_market_test: %d failures" % _failures.size())
	if _failures.is_empty():
		print("night_market_test: ALL PASS")
	else:
		print("night_market_test: FAILURES: ", _failures)
	# Cleanup slot so throwaway saves never linger (shop_test pattern).
	for c in root.get_children():
		if c.has_method("delete_save"):
			c.delete_save(SLOT)
	quit(1 if not _failures.is_empty() else 0)
