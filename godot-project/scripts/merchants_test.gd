extends SceneTree
## Headless merchants test: disposition tiers, price multipliers, haggling
## (once-per-day, fail lock, penalty), investing, tab debt, persistence.
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/merchants_test.gd
##
## NOTE: under -s, nodes added here are not inside the tree yet, so the test
## injects dependencies and calls internals directly (shop_test pattern).

const Merchants = preload("res://scripts/merchants.gd")
const SLOT := 96

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
	gs.save_system = null  # avoid file IO; state stays in memory
	return [ss, ach, gs]


func _make_shop(gs):
	var shop = (load("res://scenes/shop.tscn") as PackedScene).instantiate()
	shop.game_state = gs
	root.add_child(shop)
	shop._ready()
	return shop


func _initialize() -> void:
	print("merchants_test: starting")
	var stack := _make_stack()
	var gs = stack[2]
	Merchants.test_roll = -1.0

	# --- merchant data ---
	_check("5 merchants loaded", Merchants.merchant_ids().size() == 5)
	_check("oddments invest cost 2500", Merchants.invest_cost("oddments") == 2500)
	_check("unknown merchant empty", Merchants.get_merchant("nope").is_empty())
	_check("day starts at 1", Merchants.get_day(gs) == 1)

	# --- tiers & points ---
	_check("new merchant is stranger", Merchants.get_tier(gs, "oddments") == "stranger")
	_check("stranger buy mult 1.0", Merchants.price_multiplier(gs, "oddments") == 1.0)
	_check("stranger sell mult 1.0", Merchants.sell_multiplier(gs, "oddments") == 1.0)
	Merchants.add_points(gs, "oddments", 10)
	_check("10 pts -> regular", Merchants.get_tier(gs, "oddments") == "regular")
	_check("regular buy mult 0.95", Merchants.price_multiplier(gs, "oddments") == 0.95)
	_check("regular sell mult 1.05", Merchants.sell_multiplier(gs, "oddments") == 1.05)
	# friend requires the personal quest flag even with enough points
	Merchants.add_points(gs, "oddments", 15)
	_check("25 pts without quest stays regular", Merchants.get_tier(gs, "oddments") == "regular")
	_check("tier line flags quest pending", "quest" in Merchants.tier_line(gs, "oddments").to_lower())
	Merchants.record_personal_quest(gs, "oddments")
	_check("personal quest sets flag", gs.get_flag("quest_oddments_personal"))
	_check("quest completion -> friend", Merchants.get_tier(gs, "oddments") == "friend")
	_check("friend buy mult 0.90", Merchants.price_multiplier(gs, "oddments") == 0.90)
	_check("friend sell mult 1.10", Merchants.sell_multiplier(gs, "oddments") == 1.10)
	_check("quest gave 15 pts (40 total)", Merchants.get_points(gs, "oddments") == 40)
	Merchants.add_points(gs, "oddments", 10)
	_check("50 pts -> partner", Merchants.get_tier(gs, "oddments") == "partner")
	_check("partner buy mult 0.85", Merchants.price_multiplier(gs, "oddments") == 0.85)
	_check("partner sell mult 1.15", Merchants.sell_multiplier(gs, "oddments") == 1.15)

	# --- purchase points, daily cap ---
	var before := Merchants.get_points(gs, "apothecary")
	Merchants.record_purchase(gs, "apothecary")
	Merchants.record_purchase(gs, "apothecary")
	Merchants.record_purchase(gs, "apothecary")
	Merchants.record_purchase(gs, "apothecary")  # 4th: over the cap
	_check("purchase points capped at 3/day", Merchants.get_points(gs, "apothecary") == before + 3)
	Merchants.advance_day(gs)
	_check("day advances", Merchants.get_day(gs) == 2)
	Merchants.record_purchase(gs, "apothecary")
	_check("new day resets purchase cap", Merchants.get_points(gs, "apothecary") == before + 4)

	# --- haggling ---
	var list_price := 100
	var r := Merchants.haggle_range(list_price)
	_check("haggle range 70-95", int(r[0]) == 70 and int(r[1]) == 95)
	# out-of-range offer does not consume the attempt
	var res: Dictionary = Merchants.haggle(gs, "ferry_stall", "soul_snare", list_price, 10)
	_check("out-of-range rejected", not bool(res["ok"]))
	_check("out-of-range keeps attempt", not Merchants.haggle_attempted_today(gs, "ferry_stall"))
	# forced success (stranger tier, test roll 0.0 < 0.25)
	Merchants.test_roll = 0.0
	res = Merchants.haggle(gs, "ferry_stall", "soul_snare", list_price, 80)
	_check("haggle success", bool(res["ok"]) and int(res["price"]) == 80)
	_check("success message verbatim", str(res["message"]) == "Done. They almost smile.")
	_check("haggled price wins", Merchants.price_for(gs, "ferry_stall", "soul_snare", list_price) == 80)
	_check("attempt consumed", Merchants.haggle_attempted_today(gs, "ferry_stall"))
	res = Merchants.haggle(gs, "ferry_stall", "soul_snare", list_price, 80)
	_check("one attempt per day", not bool(res["ok"]))
	# purchase consumes the haggled price
	Merchants.record_purchase(gs, "ferry_stall", "soul_snare")
	_check("purchase clears haggled price", Merchants.price_for(gs, "ferry_stall", "soul_snare", list_price) == 100)
	# forced fail on a fresh merchant/day
	Merchants.advance_day(gs)
	Merchants.test_roll = 1.0
	res = Merchants.haggle(gs, "murrays_bar", "moon_ale", 40, 30)
	_check("haggle fail", not bool(res["ok"]))
	_check("fail message verbatim", str(res["message"]) == "No. And the look you'll remember. Prices cool until tomorrow.")
	_check("fail locks the merchant", Merchants.haggle_locked_today(gs, "murrays_bar"))
	res = Merchants.haggle(gs, "murrays_bar", "moon_ale", 40, 30)
	_check("locked merchant rejects", not bool(res["ok"]))
	_check("fail adds price penalty", Merchants.price_multiplier(gs, "murrays_bar") > 1.0)
	Merchants.advance_day(gs)
	_check("new day clears lock", not Merchants.haggle_locked_today(gs, "murrays_bar"))
	_check("new day clears penalty", Merchants.price_multiplier(gs, "murrays_bar") == 1.0)
	Merchants.test_roll = -1.0

	# --- investing ---
	gs.add_soul_credits(10000)
	var inv: Dictionary = Merchants.invest(gs, "apothecary")
	_check("invest succeeds", bool(inv["ok"]))
	_check("invest message verbatim", str(inv["message"]) == "The shop looks different. Customers comment. It was your money. It shows.")
	_check("invest grants 20 pts", Merchants.get_points(gs, "apothecary") == before + 4 + 20)
	_check("invest sets flag", Merchants.is_invested(gs, "apothecary"))
	_check("invest sets gamesave flag", gs.get_flag("merchant_apothecary_invested"))
	_check("rare item defined", Merchants.rare_item("apothecary") == "spore_sac")
	inv = Merchants.invest(gs, "apothecary")
	_check("no double invest", not bool(inv["ok"]))
	gs.spend_soul_credits(gs.get_soul_credits())
	inv = Merchants.invest(gs, "oddments")
	_check("invest blocked when broke", not bool(inv["ok"]))
	_check("invest offer names store", "Oddments" in Merchants.invest_offer_text("oddments"))

	# --- tab (friend tier) ---
	_check("stranger cannot tab", not Merchants.can_tab(gs, "ferry_stall", 100))
	# oddments is partner (friend+)
	_check("partner can tab 500", Merchants.can_tab(gs, "oddments", 400))
	_check("tab blocked over limit", not Merchants.can_tab(gs, "oddments", 600))
	_check("buy on tab works", Merchants.buy_on_tab(gs, "oddments", 400))
	_check("tab debt tracked", Merchants.tab_debt(gs, "oddments") == 400)
	_check("debt blocks more tab", not Merchants.can_tab(gs, "oddments", 100))
	gs.add_soul_credits(1000)
	var rep: Dictionary = Merchants.repay_tab(gs, "oddments")
	_check("repay clears debt", bool(rep["ok"]) and int(rep["repaid"]) == 400 and Merchants.tab_debt(gs, "oddments") == 0)
	rep = Merchants.repay_tab(gs, "oddments")
	_check("repay with no debt fails", not bool(rep["ok"]))

	# --- persistence across save/load ---
	var stack2 := _make_stack()
	var gs2 = stack2[2]
	gs2.state = gs.state.duplicate(true)
	_check("points persist", Merchants.get_points(gs2, "oddments") == Merchants.get_points(gs, "oddments"))
	_check("invested persists", Merchants.is_invested(gs2, "apothecary"))
	_check("day persists", Merchants.get_day(gs2) == Merchants.get_day(gs))
	_check("tab persists", Merchants.tab_debt(gs2, "oddments") == 0)
	_check("tier persists", Merchants.get_tier(gs2, "oddments") == "partner")

	# --- shop UI integration ---
	var shop = _make_shop(gs2)
	_check("shop opens", shop.open_shop("apothecary"))
	_check("tier label shows", "Regular" in shop._tier_label.text or "Stranger" in shop._tier_label.text or "Friend" in shop._tier_label.text or "Partner" in shop._tier_label.text)
	_check("rare stock added after invest", shop._stock.size() == 6)
	var rare_found := false
	for e in shop._stock:
		if str(e["item_id"]) == "spore_sac":
			rare_found = true
	_check("rare item is spore_sac", rare_found)
	_check("invest button shows INVESTED", shop._invest_button.text == "INVESTED")
	shop._selected = 0
	_check("buy works through UI", shop.buy_selected())
	_check("buy records disposition point", Merchants.get_points(gs2, "apothecary") == 25)
	shop.close_shop()

	print("merchants_test: %d failures" % _failures.size())
	if not _failures.is_empty():
		print("FAILED: ", _failures)
	quit(1 if not _failures.is_empty() else 0)
