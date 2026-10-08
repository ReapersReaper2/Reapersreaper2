extends RefCounted
## Merchant disposition / haggling / investing for Reaper's Reaper.
##
## NOTE: intentionally no class_name (project convention).
## Static manager; game code passes the GameState node in (contracts.gd
## pattern). State in state["merchants"]:
##   {"points": {mid: n}, "invested": [mids], "haggle_attempt": {mid: day},
##    "haggle_lock": {mid: day}, "tab": {mid: debt}, "daily": {mid: {day: n}},
##    "haggled": {mid: {item_id: {"price": n, "day": n}}}}
## Day counter: state["day"] (lazy, starts at 1). advance_day() is called by
## shrine rests (shrine.gd) — the natural day boundary.
##
## Canon tiers (ui_text.json /disposition, text used verbatim in shop.gd):
##   stranger: list prices
##   regular: 5% better prices
##   friend: 10% better prices + tab access
##   partner: 15% better prices + first refusal on rare stock

const MERCHANTS_PATH := "res://data/merchants.json"

const TIERS := ["stranger", "regular", "friend", "partner"]
const TIER_POINTS := {"stranger": 0, "regular": 10, "friend": 25, "partner": 50}
const BUY_MULT := {"stranger": 1.0, "regular": 0.95, "friend": 0.90, "partner": 0.85}
const SELL_MULT := {"stranger": 1.0, "regular": 1.05, "friend": 1.10, "partner": 1.15}
const INVEST_POINTS := 20
const QUEST_POINTS := 15
const PURCHASE_POINTS := 1
const DAILY_PURCHASE_CAP := 3
const TAB_LIMIT := 500
const HAGGLE_MIN := 0.70
const HAGGLE_MAX := 0.95
const HAGGLE_FAIL_PENALTY := 0.10
const HAGGLE_CHANCE := {"stranger": 0.25, "regular": 0.40, "friend": 0.60, "partner": 0.80}

const UiText = preload("res://scripts/ui_text.gd")

static var _cache: Array = []
## Test hook: when >= 0, haggle() uses this roll instead of randf().
static var test_roll: float = -1.0


static func load_merchants() -> Array:
	if not _cache.is_empty():
		return _cache
	if not FileAccess.file_exists(MERCHANTS_PATH):
		return []
	var f := FileAccess.open(MERCHANTS_PATH, FileAccess.READ)
	if f == null:
		return []
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_cache = d.get("merchants", [])
	return _cache


static func get_merchant(merchant_id: String) -> Dictionary:
	for m in load_merchants():
		if str(m.get("id", "")) == merchant_id:
			return m
	return {}


static func merchant_ids() -> Array:
	var out: Array = []
	for m in load_merchants():
		out.append(str(m.get("id", "")))
	return out


## The merchants block inside the save payload (lazy: old saves work).
static func _data(gs) -> Dictionary:
	if gs == null or gs.get("state") == null:
		return {"points": {}, "invested": [], "haggle_attempt": {}, "haggle_lock": {}, "tab": {}, "daily": {}, "haggled": {}}
	var st: Dictionary = gs.get("state")
	if not st.has("merchants") or not (st["merchants"] is Dictionary):
		st["merchants"] = {"points": {}, "invested": [], "haggle_attempt": {}, "haggle_lock": {}, "tab": {}, "daily": {}, "haggled": {}}
	return st["merchants"]


static func get_day(gs) -> int:
	if gs == null or gs.get("state") == null:
		return 1
	return int((gs.get("state") as Dictionary).get("day", 1))


## Called by shrine.gd when the player rests — the natural day boundary.
static func advance_day(gs) -> int:
	if gs == null or gs.get("state") == null:
		return 1
	var st: Dictionary = gs.get("state")
	var day := int(st.get("day", 1)) + 1
	st["day"] = day
	return day


static func get_points(gs, merchant_id: String) -> int:
	return int(_data(gs).get("points", {}).get(merchant_id, 0))


static func add_points(gs, merchant_id: String, n: int) -> void:
	var d := _data(gs)
	var pts: Dictionary = d["points"]
	pts[merchant_id] = int(pts.get(merchant_id, 0)) + n


## Points thresholds are 0/10/25/50, but friend and partner ALSO require the
## merchant's personal quest flag (data hook — quest content is unwritten).
static func get_tier(gs, merchant_id: String) -> String:
	var pts := get_points(gs, merchant_id)
	var tier := "stranger"
	for t in TIERS:
		if pts >= int(TIER_POINTS[t]):
			tier = t
	if (tier == "friend" or tier == "partner") and not _quest_done(gs, merchant_id):
		tier = "regular"
	return tier


static func _quest_done(gs, merchant_id: String) -> bool:
	var m := get_merchant(merchant_id)
	var flag := str(m.get("personal_quest_flag", ""))
	if flag.is_empty() or gs == null or not gs.has_method("get_flag"):
		return false
	return gs.get_flag(flag)


static func price_multiplier(gs, merchant_id: String) -> float:
	var mult: float = float(BUY_MULT[get_tier(gs, merchant_id)])
	if int(_data(gs).get("haggle_lock", {}).get(merchant_id, 0)) >= get_day(gs):
		mult += HAGGLE_FAIL_PENALTY
	return mult


static func sell_multiplier(gs, merchant_id: String) -> float:
	return float(SELL_MULT[get_tier(gs, merchant_id)])


## Effective buy price for an item: a successful same-day haggle wins,
## otherwise list price with the disposition (and fail-penalty) multiplier.
static func price_for(gs, merchant_id: String, item_id: String, list_price: int) -> int:
	var d := _data(gs)
	var day := get_day(gs)
	var haggled: Dictionary = (d.get("haggled", {}) as Dictionary).get(merchant_id, {})
	if haggled.has(item_id) and int((haggled[item_id] as Dictionary).get("day", 0)) == day:
		return int((haggled[item_id] as Dictionary).get("price", list_price))
	return int(ceil(list_price * price_multiplier(gs, merchant_id)))


## +1 disposition per transaction, capped per in-game day. Clears any
## same-day haggled price for the item (it was single-use).
static func record_purchase(gs, merchant_id: String, item_id: String = "") -> void:
	var d := _data(gs)
	var day := get_day(gs)
	var daily: Dictionary = d["daily"]
	var rec: Dictionary = daily.get(merchant_id, {"day": 0, "count": 0})
	if int(rec.get("day", 0)) != day:
		rec = {"day": day, "count": 0}
	if int(rec.get("count", 0)) < DAILY_PURCHASE_CAP:
		rec["count"] = int(rec.get("count", 0)) + 1
		add_points(gs, merchant_id, PURCHASE_POINTS)
	daily[merchant_id] = rec
	if not item_id.is_empty():
		(d.get("haggled", {}) as Dictionary).get(merchant_id, {}).erase(item_id)


## Personal quest completion: sets the quest flag and grants points.
static func record_personal_quest(gs, merchant_id: String) -> void:
	var m := get_merchant(merchant_id)
	var flag := str(m.get("personal_quest_flag", ""))
	if not flag.is_empty() and gs != null and gs.has_method("set_flag"):
		gs.set_flag(flag)
	add_points(gs, merchant_id, QUEST_POINTS)


static func haggle_range(list_price: int) -> Array:
	return [int(floor(list_price * HAGGLE_MIN)), int(ceil(list_price * HAGGLE_MAX))]


static func haggle_attempted_today(gs, merchant_id: String) -> bool:
	return int(_data(gs).get("haggle_attempt", {}).get(merchant_id, 0)) >= get_day(gs)


static func haggle_locked_today(gs, merchant_id: String) -> bool:
	return int(_data(gs).get("haggle_lock", {}).get(merchant_id, 0)) >= get_day(gs)


## One attempt per merchant per in-game day. offer must be inside the shown
## range (70–95% of list). Success chance scales with disposition tier.
## Fail → locked until tomorrow + temp price penalty. Returns
## {"ok": bool, "price": int, "message": String}.
static func haggle(gs, merchant_id: String, item_id: String, list_price: int, offer: int) -> Dictionary:
	if get_merchant(merchant_id).is_empty():
		return {"ok": false, "price": 0, "message": "No such merchant."}
	var d := _data(gs)
	var day := get_day(gs)
	if haggle_locked_today(gs, merchant_id):
		return {"ok": false, "price": 0, "message": UiText.haggle("haggle_fail")}
	if int(d.get("haggle_attempt", {}).get(merchant_id, 0)) >= day:
		return {"ok": false, "price": 0, "message": UiText.haggle("haggle_prompt")}
	var r := haggle_range(list_price)
	if offer < int(r[0]) or offer > int(r[1]):
		return {"ok": false, "price": 0, "message": UiText.haggle("haggle_prompt"), "range": r}
	d["haggle_attempt"][merchant_id] = day
	var chance: float = float(HAGGLE_CHANCE[get_tier(gs, merchant_id)])
	var roll: float = test_roll if test_roll >= 0.0 else randf()
	if roll < chance:
		var per_merchant: Dictionary = d["haggled"]
		if not per_merchant.has(merchant_id):
			per_merchant[merchant_id] = {}
		(per_merchant[merchant_id] as Dictionary)[item_id] = {"price": offer, "day": day}
		return {"ok": true, "price": offer, "message": UiText.haggle("haggle_success")}
	d["haggle_lock"][merchant_id] = day
	return {"ok": false, "price": 0, "message": UiText.haggle("haggle_fail")}


static func invest_cost(merchant_id: String) -> int:
	return int(get_merchant(merchant_id).get("invest_cost", 0))


static func is_invested(gs, merchant_id: String) -> bool:
	return str(merchant_id) in _data(gs).get("invested", [])


## One-time per store: lump sum for +20 disposition and a permanent rare
## stock slot (flag the shop UI reads). Returns {"ok", "message"}.
static func invest(gs, merchant_id: String) -> Dictionary:
	var m := get_merchant(merchant_id)
	if m.is_empty():
		return {"ok": false, "message": "No such merchant."}
	if is_invested(gs, merchant_id):
		return {"ok": false, "message": "Already invested."}
	var cost := invest_cost(merchant_id)
	if gs == null or not gs.has_method("spend_soul_credits"):
		return {"ok": false, "message": "No wallet."}
	if not gs.spend_soul_credits(cost):
		return {"ok": false, "message": "Not enough Soul Credits."}
	_data(gs)["invested"].append(merchant_id)
	add_points(gs, merchant_id, INVEST_POINTS)
	if gs.has_method("set_flag"):
		gs.set_flag("merchant_" + merchant_id + "_invested")
	return {"ok": true, "message": UiText.invest("invest_after")}


static func invest_offer_text(merchant_id: String) -> String:
	return UiText.invest("invest_offer").replace("[store]", UiText.store_name(merchant_id))


static func rare_item(merchant_id: String) -> String:
	return str(get_merchant(merchant_id).get("rare_item", ""))


## Tab access (friend tier): buy with negative credits up to TAB_LIMIT.
## Debt must be repaid before buying more on tab.
static func tab_debt(gs, merchant_id: String) -> int:
	return int(_data(gs).get("tab", {}).get(merchant_id, 0))


static func can_tab(gs, merchant_id: String, price: int) -> bool:
	if get_tier(gs, merchant_id) != "friend" and get_tier(gs, merchant_id) != "partner":
		return false
	if tab_debt(gs, merchant_id) > 0:
		return false
	return price <= TAB_LIMIT


static func buy_on_tab(gs, merchant_id: String, price: int) -> bool:
	if not can_tab(gs, merchant_id, price):
		return false
	_data(gs)["tab"][merchant_id] = tab_debt(gs, merchant_id) + price
	return true


static func repay_tab(gs, merchant_id: String) -> Dictionary:
	var debt := tab_debt(gs, merchant_id)
	if debt <= 0:
		return {"ok": false, "repaid": 0}
	if gs == null or not gs.has_method("spend_soul_credits"):
		return {"ok": false, "repaid": 0}
	if not gs.spend_soul_credits(debt):
		return {"ok": false, "repaid": 0}
	_data(gs)["tab"][merchant_id] = 0
	return {"ok": true, "repaid": debt}


## "Name (12/25)" style tier line for the shop UI.
static func tier_line(gs, merchant_id: String) -> String:
	var tier := get_tier(gs, merchant_id)
	var pts := get_points(gs, merchant_id)
	var next := ""
	for i in TIERS.size():
		if int(TIER_POINTS[TIERS[i]]) > pts:
			next = "/%d" % int(TIER_POINTS[TIERS[i]])
			break
	var label := str(UiText._load().get("disposition", {}).get(tier, {}).get("name", tier))
	var line := "%s (%d%s)" % [label, pts, next]
	if (tier == "regular") and pts >= int(TIER_POINTS["friend"]):
		line += " — personal quest pending"
	return line
