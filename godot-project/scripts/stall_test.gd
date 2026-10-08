extends SceneTree
## Headless stall test: unlock fee, stock/price clamps, day-tick sales,
## Ledger cut, till collect, minder rate, persistence.
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/stall_test.gd

const Stall = preload("res://scripts/stall.gd")
const SLOT := 97

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


func _initialize() -> void:
	print("stall_test: starting")
	Stall.test_roll = 0.0  # deterministic: fractional sales always round up
	var stack := _make_stack()
	var gs = stack[2]

	# --- unlock ---
	_check("locked at start", not Stall.is_unlocked(gs))
	gs.add_soul_credits(10000)
	var start_credits: int = gs.get_soul_credits()
	var r := Stall.unlock(gs)
	_check("unlock ok", bool(r["ok"]))
	_check("unlock sets flag", gs.get_flag("nm_stall_unlocked"))
	_check("unlock costs 5000", gs.get_soul_credits() == start_credits - Stall.UNLOCK_COST)
	_check("unlocked now", Stall.is_unlocked(gs))
	var r2 := Stall.unlock(gs)
	_check("no double unlock", not bool(r2["ok"]))
	_check("till starts 0", Stall.get_till(gs) == 0)

	# --- stocking ---
	gs.add_item("ashen_salt", 10)  # base price 140
	_check("price clamp low", Stall.clamp_price("ashen_salt", 10) == 70)
	_check("price clamp high", Stall.clamp_price("ashen_salt", 9999) == 420)
	_check("price passthrough", Stall.clamp_price("ashen_salt", 200) == 200)
	var s := Stall.stock_item(gs, "ashen_salt", 4, 140)
	_check("stock ok", bool(s["ok"]))
	_check("stock removes from inventory", gs.get_item_count("ashen_salt") == 6)
	var stock: Dictionary = Stall.get_stock(gs)
	_check("stock qty 4", int((stock["ashen_salt"] as Dictionary)["qty"]) == 4)
	_check("stock price 140", int((stock["ashen_salt"] as Dictionary)["price"]) == 140)
	var sp := Stall.set_price(gs, "ashen_salt", 9999)
	_check("set_price clamps to 420", int((Stall.get_stock(gs)["ashen_salt"] as Dictionary)["price"]) == 420)
	Stall.set_price(gs, "ashen_salt", 140)
	var sbad := Stall.stock_item(gs, "soul_snare", 1, 10)
	_check("zero-price item rejected", not bool(sbad["ok"]))
	var smore := Stall.stock_item(gs, "ashen_salt", 99, 140)
	_check("overstock rejected", not bool(smore["ok"]))

	# --- day tick sales (no minder: half rate) ---
	# rate at r=1: 0.35 * 0.5 = 0.175; qty 4 -> expected 0.7 -> 0 + frac(0.7>roll 0) = 1
	var sum1 := Stall.on_day_advance(gs)
	_check("sold 1 unit", int((sum1["sold"] as Dictionary).get("ashen_salt", 0)) == 1)
	_check("gross 140", int(sum1["gross"]) == 140)
	_check("till_add is 90% (126)", int(sum1["till_add"]) == 126)
	_check("Ledger cut exactly 10%", int(sum1["gross"]) - int(sum1["till_add"]) == 14)
	_check("till holds 126", Stall.get_till(gs) == 126)
	_check("lifetime tracks gross", Stall.get_lifetime(gs) == 140)
	_check("stock down to 3", int((Stall.get_stock(gs)["ashen_salt"] as Dictionary)["qty"]) == 3)

	# --- collect ---
	var c0 := Stall.collect_till(gs)
	_check("collect ok", bool(c0["ok"]))
	_check("collect amount 126", int(c0["amount"]) == 126)
	_check("till emptied", Stall.get_till(gs) == 0)
	var c1 := Stall.collect_till(gs)
	_check("empty till fails", not bool(c1["ok"]))

	# --- minder doubles rate ---
	var m0 := Stall.hire_minder(gs)
	_check("minder hire ok", bool(m0["ok"]))
	_check("minder flag set", gs.get_flag("nm_stall_minder"))
	_check("has minder", Stall.has_minder(gs))
	var m1 := Stall.hire_minder(gs)
	_check("no double minder", not bool(m1["ok"]))
	# rate at r=1 with minder: 0.35 * 2 = 0.7; qty 3 -> expected 2.1 -> 2 + 1 = 3
	var sum2 := Stall.on_day_advance(gs)
	_check("minder sells 3 units", int((sum2["sold"] as Dictionary).get("ashen_salt", 0)) == 3)
	_check("stock exhausted", not Stall.get_stock(gs).has("ashen_salt"))
	_check("gross 420", int(sum2["gross"]) == 420)
	_check("till 378 after cut", Stall.get_till(gs) == 378)

	# --- unstock ---
	gs.add_item("thorn_pod", 5)  # base 90
	Stall.stock_item(gs, "thorn_pod", 5, 90)
	var u := Stall.unstock_item(gs, "thorn_pod", 2)
	_check("unstock ok", bool(u["ok"]))
	_check("unstock returns 2", gs.get_item_count("thorn_pod") == 2)
	_check("stock left 3", int((Stall.get_stock(gs)["thorn_pod"] as Dictionary)["qty"]) == 3)
	var uall := Stall.unstock_item(gs, "thorn_pod", 99)
	_check("unstock over-qty clamps", gs.get_item_count("thorn_pod") == 5)
	_check("entry removed when empty", not Stall.get_stock(gs).has("thorn_pod"))

	# --- persistence round-trip ---
	Stall.collect_till(gs)
	gs.add_item("blossom_nectar", 2)  # base 900
	Stall.stock_item(gs, "blossom_nectar", 2, 900)
	gs.save_system = stack[0]
	gs.save_to_slot(SLOT)
	var stack2 := _make_stack()
	var gs2 = stack2[2]
	gs2.save_system = stack2[0]
	gs2.load_from_slot(SLOT)
	_check("unlocked persists", Stall.is_unlocked(gs2))
	_check("minder persists", Stall.has_minder(gs2))
	_check("stock persists", int((Stall.get_stock(gs2)["blossom_nectar"] as Dictionary)["qty"]) == 2)
	_check("lifetime persists", Stall.get_lifetime(gs2) == Stall.get_lifetime(gs))
	_check("flag persists", gs2.get_flag("nm_stall_unlocked"))

	# --- price attractiveness curve sanity ---
	gs2.add_item("ashen_salt", 100)
	Stall.stock_item(gs2, "ashen_salt", 100, 70)  # r=0.5 fire sale
	var rate_cheap := Stall.sell_rate(gs2, "ashen_salt")
	Stall.set_price(gs2, "ashen_salt", 420)  # r=3.0 luxury
	var rate_dear := Stall.sell_rate(gs2, "ashen_salt")
	_check("cheap sells faster than dear", rate_cheap > rate_dear)
	_check("dear rate positive floor", rate_dear > 0.0)

	Stall.test_roll = -1.0
	print("stall_test: %d failures" % _failures.size())
	if not _failures.is_empty():
		print("FAILED: ", _failures)
	quit(1 if not _failures.is_empty() else 0)
