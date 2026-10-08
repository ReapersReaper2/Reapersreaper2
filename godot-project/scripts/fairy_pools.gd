extends RefCounted
## Fairy pool mechanics for Reaper's Reaper (wiring).
##
## TWO pools, one data definition (res://data/fairy_pools.json):
##   - Light pool: source armor_plant; plain energy counter (add/spend).
##   - Shadow pool: source widowblade; charge 0..max_charge.
##     * Refilled ONLY at Driftcap contact (driftcap_contact) — there is no
##       other refill path, by design.
##     * Blasts spend charge (blast); a blast can never birth a widow.
##     * A widow birth (try_widow_birth) requires slow_focus AND charge, and
##       is rare (birth_chance). Never from blasts.
##
## SHARED DATA RULE: the shadow-pool charge state lives in
## state["fairy_pools"]["shadow"]["charge"] and is read/written through THIS
## module only. Ivy's boss phase (pre-defeat, when she wields the Widowblade)
## and the player's Widowblade phase (post-defeat) both consume this one
## definition — it is never duplicated.
##
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (autoloads don't load there).
##   const FairyPools = preload("res://scripts/fairy_pools.gd")

static var _pools: Dictionary = {}
static var _loaded := false
static var _rng := RandomNumberGenerator.new()


## Test hook: seed the RNG for deterministic widow-birth rolls.
static func set_seed(s: int) -> void:
	_rng.seed = s


static func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("fairy_pools: cannot open " + path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


static func ensure_loaded() -> void:
	if _loaded:
		return
	_pools = _load_json("res://data/fairy_pools.json")
	_loaded = true


static func _state(gs: Node) -> Dictionary:
	if not gs.state.has("fairy_pools") or not (gs.state["fairy_pools"] is Dictionary):
		gs.state["fairy_pools"] = {"light": {"energy": 0}, "shadow": {"charge": 0}}
	return gs.state["fairy_pools"]


static func _def(pool: String) -> Dictionary:
	ensure_loaded()
	return _pools.get(pool, {})


## Canon source of a pool (armor_plant / widowblade). From the JSON def.
static func pool_source(pool: String) -> String:
	return str(_def(pool).get("source", ""))


## ---- light pool -------------------------------------------------------

static func light_energy(gs: Node) -> int:
	return int((_state(gs).get("light", {}) as Dictionary).get("energy", 0))


static func add_light_energy(gs: Node, n: int) -> int:
	var st := _state(gs)
	var l: Dictionary = st.get("light", {})
	l["energy"] = maxi(0, int(l.get("energy", 0)) + n)
	st["light"] = l
	return int(l["energy"])


## Spend light energy. False (no write) when there isn't enough.
static func spend_light_energy(gs: Node, n: int) -> bool:
	var st := _state(gs)
	var l: Dictionary = st.get("light", {})
	if int(l.get("energy", 0)) < n:
		return false
	l["energy"] = int(l.get("energy", 0)) - n
	st["light"] = l
	return true


## ---- shadow pool ------------------------------------------------------

static func max_charge() -> int:
	return int(_def("shadow_pool").get("max_charge", 3))


## Current shadow charge (0..max). The single shared read for Ivy's phase
## and the player's Widowblade phase.
static func shadow_charge(gs: Node) -> int:
	return clampi(int((_state(gs).get("shadow", {}) as Dictionary).get("charge", 0)), 0, max_charge())


static func _set_charge(gs: Node, n: int) -> int:
	var st := _state(gs)
	var s: Dictionary = st.get("shadow", {})
	s["charge"] = clampi(n, 0, max_charge())
	st["shadow"] = s
	return int(s["charge"])


## THE only refill path: Driftcap contact restores charge to max. Any other
## attempted refill is a wiring bug — there is deliberately no other.
static func driftcap_contact(gs: Node) -> int:
	return _set_charge(gs, max_charge())


## Spend `blast_cost` charge on a shadow blast. False (no write) when the
## charge can't cover it. Blasts NEVER birth widows.
static func blast(gs: Node) -> bool:
	var cost := int(_def("shadow_pool").get("blast_cost", 1))
	if shadow_charge(gs) < cost:
		return false
	_set_charge(gs, shadow_charge(gs) - cost)
	return true


## Widow birth: requires slow_focus AND charge > 0; rare (birth_chance).
## Never happens from blasts. A successful birth consumes one charge
## (tuning placeholder) and records the event flag "widow_born".
## Returns {"ok": bool, "reason": String}.
static func try_widow_birth(gs: Node, slow_focus: bool) -> Dictionary:
	if not slow_focus:
		return {"ok": false, "reason": "needs slow_focus"}
	if shadow_charge(gs) <= 0:
		return {"ok": false, "reason": "no charge"}
	var chance := float(_def("shadow_pool").get("birth_chance", 0.05))
	if _rng.randf() >= chance:
		return {"ok": false, "reason": "the shadow does not answer"}
	_set_charge(gs, shadow_charge(gs) - 1)
	if gs.has_method("set_flag"):
		gs.set_flag("widow_born", true)
	return {"ok": true, "reason": "a widow is born"}
