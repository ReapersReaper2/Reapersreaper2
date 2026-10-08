extends RefCounted
## Player-owned Night Market stall — passive-income economic loop.
##
## NOTE: intentionally no class_name (project convention).
## Static manager; game code passes the GameState node in (merchants.gd
## pattern). State in state["stall"]:
##   {"unlocked": bool, "minder": bool,
##    "stock": {item_id: {"qty": int, "price": int}},
##    "till": int, "lifetime": int}
## Day tick: on_day_advance() is called by shrine rests (shrine.gd) — the
## natural day boundary.
##
## Canon (ui_text.json /investing/stall_unlock, used verbatim in stall_ui):
##   "Your own stall at the Night Market. Set prices. Hire a minder. The
##    Ledger takes its cut and pretends not to notice the rest."
const UiText = preload("res://scripts/ui_text.gd")

const STALL_PATH := "res://data/items.json"  # (base prices via CreatureData)

const UNLOCK_COST := 5000
const MINDER_COST := 1500
const LEDGER_CUT := 0.10
const PRICE_MIN_MULT := 0.5
const PRICE_MAX_MULT := 3.0
## Base daily sell rate at list price; scaled by 1/r^2 where r = price/base.
const BASE_RATE := 0.35
const MINDER_MULT := 2.0
const SELF_MULT := 0.5

const CreatureData = preload("res://scripts/creature_data.gd")

## Test hook: when >= 0, on_day_advance uses this roll instead of randf()
## for the fractional-unit sale. (merchants.gd test_roll pattern.)
static var test_roll: float = -1.0


## The stall block inside the save payload (lazy: old saves work).
static func _data(gs) -> Dictionary:
	if gs == null or gs.get("state") == null:
		return {"unlocked": false, "minder": false, "stock": {}, "till": 0, "lifetime": 0}
	var st: Dictionary = gs.get("state")
	if not st.has("stall") or not (st["stall"] is Dictionary):
		st["stall"] = {"unlocked": false, "minder": false, "stock": {}, "till": 0, "lifetime": 0}
	return st["stall"]


static func is_unlocked(gs) -> bool:
	return bool(_data(gs).get("unlocked", false))


static func has_minder(gs) -> bool:
	return bool(_data(gs).get("minder", false))


static func get_till(gs) -> int:
	return int(_data(gs).get("till", 0))


static func get_lifetime(gs) -> int:
	return int(_data(gs).get("lifetime", 0))


static func get_stock(gs) -> Dictionary:
	return _data(gs).get("stock", {}) as Dictionary


static func base_price(item_id: String) -> int:
	var item: Dictionary = CreatureData.get_item(item_id)
	return int(item.get("price", 0))


## Buy the stall. One-time; sets the nm_stall_unlocked flag.
static func unlock(gs) -> Dictionary:
	if is_unlocked(gs):
		return {"ok": false, "message": "The stall is already yours."}
	if not gs.spend_soul_credits(UNLOCK_COST):
		return {"ok": false, "message": "Not enough Soul Credits."}
	_data(gs)["unlocked"] = true
	gs.set_flag("nm_stall_unlocked")
	return {"ok": true, "message": UiText.invest("stall_after")}


## Hire a minder. One-time; doubles the daily sell rate.
static func hire_minder(gs) -> Dictionary:
	if not is_unlocked(gs):
		return {"ok": false, "message": "You don't own a stall yet."}
	if has_minder(gs):
		return {"ok": false, "message": "You already have a minder."}
	if not gs.spend_soul_credits(MINDER_COST):
		return {"ok": false, "message": "Not enough Soul Credits."}
	_data(gs)["minder"] = true
	gs.set_flag("nm_stall_minder")
	return {"ok": true, "message": "The minder nods and takes up the corner stool."}


## Clamp a player-set price to 50%-300% of base value.
static func clamp_price(item_id: String, price: int) -> int:
	var base := base_price(item_id)
	if base <= 0:
		return 0
	return clampi(price, int(round(base * PRICE_MIN_MULT)), int(round(base * PRICE_MAX_MULT)))


## Move qty of item_id from the player's inventory into stall stock at price.
static func stock_item(gs, item_id: String, qty: int, price: int) -> Dictionary:
	if not is_unlocked(gs):
		return {"ok": false, "message": "You don't own a stall yet."}
	var base := base_price(item_id)
	if base <= 0:
		return {"ok": false, "message": "That can't be sold."}
	qty = maxi(1, qty)
	var have: int = gs.get_item_count(item_id)
	if have < qty:
		return {"ok": false, "message": "You don't have that many."}
	price = clamp_price(item_id, price)
	var stock: Dictionary = get_stock(gs)
	if stock.has(item_id):
		var e: Dictionary = stock[item_id]
		e["qty"] = int(e["qty"]) + qty
		e["price"] = price
	else:
		stock[item_id] = {"qty": qty, "price": price}
	gs.add_item(item_id, -qty)
	return {"ok": true, "message": "Stocked."}


## Return qty of unsold units to the player's inventory.
static func unstock_item(gs, item_id: String, qty: int) -> Dictionary:
	var stock: Dictionary = get_stock(gs)
	if not stock.has(item_id):
		return {"ok": false, "message": "Not in stock."}
	var e: Dictionary = stock[item_id]
	qty = clampi(qty, 1, int(e["qty"]))
	e["qty"] = int(e["qty"]) - qty
	if int(e["qty"]) <= 0:
		stock.erase(item_id)
	gs.add_item(item_id, qty)
	return {"ok": true, "message": "Taken back."}


## Reprice a stocked item (clamped 50%-300% of base).
static func set_price(gs, item_id: String, price: int) -> Dictionary:
	var stock: Dictionary = get_stock(gs)
	if not stock.has(item_id):
		return {"ok": false, "message": "Not in stock."}
	(stock[item_id] as Dictionary)["price"] = clamp_price(item_id, price)
	return {"ok": true, "message": "Price set."}


## Expected daily sell rate for one stocked entry (0.0-1.0 of qty).
## Below base = sells fast, above base = slow. Minder doubles, self = half.
static func sell_rate(gs, item_id: String) -> float:
	var stock: Dictionary = get_stock(gs)
	if not stock.has(item_id):
		return 0.0
	var e: Dictionary = stock[item_id]
	var base := base_price(item_id)
	if base <= 0:
		return 0.0
	var r := float(int(e["price"])) / float(base)
	var rate := BASE_RATE / (r * r)
	rate = clampf(rate, 0.02, 0.95)
	rate *= MINDER_MULT if has_minder(gs) else SELF_MULT
	return clampf(rate, 0.0, 1.0)


## Daily sales tick. Called by shrine.gd on rest (the day boundary).
## Returns a summary: {"sold": {item_id: n}, "gross": int, "till_add": int}.
static func on_day_advance(gs) -> Dictionary:
	var summary := {"sold": {}, "gross": 0, "till_add": 0}
	if not is_unlocked(gs):
		return summary
	var stock: Dictionary = get_stock(gs)
	if stock.is_empty():
		return summary
	var sold: Dictionary = {}
	var gross := 0
	for item_id in stock.keys():
		var e: Dictionary = stock[item_id]
		var qty := int(e["qty"])
		if qty <= 0:
			continue
		var rate := sell_rate(gs, str(item_id))
		var expected := float(qty) * rate
		var n := int(expected)
		var frac := expected - float(n)
		var roll := test_roll if test_roll >= 0.0 else randf()
		if roll < frac:
			n += 1
		n = mini(n, qty)
		if n <= 0:
			continue
		e["qty"] = qty - n
		if int(e["qty"]) <= 0:
			stock.erase(item_id)
		sold[item_id] = n
		gross += n * int(e["price"])
	if gross > 0:
		# The Ledger takes its cut and pretends not to notice the rest.
		var net := int(floor(float(gross) * (1.0 - LEDGER_CUT)))
		var d := _data(gs)
		d["till"] = int(d["till"]) + net
		d["lifetime"] = int(d["lifetime"]) + gross
		summary["gross"] = gross
		summary["till_add"] = net
	summary["sold"] = sold
	return summary


## Collect the till into Soul Credits. Empties the till.
static func collect_till(gs) -> Dictionary:
	var till := get_till(gs)
	if till <= 0:
		return {"ok": false, "amount": 0, "message": UiText.invest("stall_empty_till")}
	_data(gs)["till"] = 0
	gs.add_soul_credits(till)
	return {"ok": true, "amount": till, "message": "Collected."}
