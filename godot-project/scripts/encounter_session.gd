extends RefCounted
## Pure creature encounter state — ENCOUNTER-IMPL-wrath §§1-2.
## Only the EncounterDirector may write records to GameState.state.encounters.
## This module never controls input, inventory, camera, rendering, or time.
## Species response/tending numbers MUST arrive from approved data; no
## unapproved response tables, random capture rates or mantle awards.
const AMBIENT := "ambient"
const ATTENDING := "attending"
const ASKING := "asking"
const INTERESTED := "interested"
const NEUTRAL := "neutral"
const WARY := "wary"
const SCARED_OFF := "scared_off"

## Persistent Dictionary from GameState.state["encounters"]["creatures"].
var records: Dictionary = {}
## Transient session state NEVER included in saved records.
var states: Dictionary = {}
var active_creature_id: String = ""
var held_fruit: String = ""
var held_lean: String = ""
var approaching: bool = false

func _init(persistent_records: Dictionary = {}) -> void:
	records = persistent_records

func has_active_asking() -> bool:
	return not active_creature_id.is_empty()

func state_of(id: String) -> String:
	return str(states.get(id, ""))

func record_of(id: String) -> Dictionary:
	var value: Variant = records.get(id, {})
	return value as Dictionary if value is Dictionary else {}


## An ID is authored in a room scene and is NOT an art/species ID.
## Existing save fields always beat incoming tunable defaults.
func register(id: String, lean: String, awareness_px: float,
		tend_affinity: float, today: int = 1) -> bool:
	if id.is_empty() or awareness_px <= 0.0 or tend_affinity < 0.0 or tend_affinity > 1.0:
		return false
	if not ["sun", "shade", "rot"].has(lean):
		return false
	if states.has(id):
		return false
	var value: Variant = records.get(id, {})
	var record: Dictionary = value if value is Dictionary else {}
	if not record.has("lean"):
		record["lean"] = lean
	if not record.has("awareness_px"):
		record["awareness_px"] = awareness_px
	if not record.has("tend_affinity"):
		record["tend_affinity"] = tend_affinity
	if not record.has("warmth"):
		record["warmth"] = 0.0
	if not record.has("wariness_until_day"):
		record["wariness_until_day"] = -1
	if not record.has("last_outcome"):
		record["last_outcome"] = NEUTRAL
	if not record.has("met"):
		record["met"] = false
	records[id] = record
	var scared := str(record.get("last_outcome", "")) == SCARED_OFF
	var still_wary := int(record.get("wariness_until_day", -1)) > today
	states[id] = SCARED_OFF if (scared and still_wary) else AMBIENT
	return true


func notice(id: String, today: int) -> bool:
	if not states.has(id) or active_creature_id == id:
		return false
	if state_of(id) == SCARED_OFF and is_wary(id, today):
		return false
	if not [AMBIENT, NEUTRAL, INTERESTED, WARY, SCARED_OFF].has(state_of(id)):
		return false
	states[id] = WARY if is_wary(id, today) else ATTENDING
	var record := record_of(id)
	record["met"] = true
	records[id] = record
	return true


func is_wary(id: String, today: int) -> bool:
	var record := record_of(id)
	return not record.is_empty() and int(record.get("wariness_until_day", -1)) > today


## One creature's asking at a time, and never after a scythe scare.
func try_ask(id: String, today: int) -> bool:
	if has_active_asking() or not [ATTENDING, WARY].has(state_of(id)):
		return false
	if state_of(id) == SCARED_OFF and is_wary(id, today):
		return false
	active_creature_id = id
	states[id] = ASKING
	held_fruit = ""
	held_lean = ""
	approaching = false
	return true


## Merely presenting fruit must not subtract it from player inventory.
func offer(id: String, item_id: String, lean: String) -> bool:
	if id != active_creature_id or item_id.is_empty() or not ["sun", "shade", "rot"].has(lean):
		return false
	held_fruit = item_id
	held_lean = lean
	return true


## Answer is supplied by the SPECIES RESPONSE TABLE, not rolled here.
## A consumed fruit is removed only at the precise "ate" moment by the
## director-injected inventory callback. A failed removal leaves ASKING.
func answer_offer(id: String, answer: String, consume_fruit: Callable) -> bool:
	if id != active_creature_id or held_fruit.is_empty():
		return false
	if answer == "hold":
		return true
	if answer == "decline":
		_clear_held()
		_finish(id, NEUTRAL)
		return true
	if not ["eat_stay", "eat_leave"].has(answer) or not consume_fruit.is_valid():
		return false
	if not bool(consume_fruit.call(held_fruit)):
		return false
	_clear_held()
	_finish(id, INTERESTED if answer == "eat_stay" else NEUTRAL)
	return true


## Tending costs no item. Delta is an injected [PROPOSED] per-species
## tuning value; callers must not invent a warmth gain without a table.
func tend(id: String, warmth_delta: float, leaning: bool) -> bool:
	if id != active_creature_id or warmth_delta < 0.0 or warmth_delta > 1.0:
		return false
	var record := record_of(id)
	if record.is_empty():
		return false
	record["warmth"] = clampf(float(record.get("warmth", 0.0)) + warmth_delta, 0.0, 1.0)
	records[id] = record
	approaching = leaning
	return true


func set_approaching(id: String, is_approaching: bool) -> bool:
	if id != active_creature_id:
		return false
	approaching = is_approaching
	return true


## "Withdraw" is clean except during a creature's mid-approach.
## The duration is [PROPOSED] and injected by the director, not canon.
func withdraw(id: String, today: int, wary_days: int) -> bool:
	if id != active_creature_id:
		return false
	if approaching:
		_stamp_wariness(id, today, wary_days)
		_finish(id, WARY)
	else:
		var record := record_of(id)
		record["wariness_until_day"] = -1
		records[id] = record
		_finish(id, NEUTRAL)
	return true


## Walking away mid-asking is a non-answer, never a penalty.
func walk_away(id: String) -> bool:
	if id != active_creature_id:
		return false
	_finish(id, NEUTRAL)
	return true


## Scythe-in-awareness is NOT a creature attack or encounter starter.
## Can fire while ATTENDING or ASKING; the caller chooses whom it reached.
func scare(id: String, today: int, wary_days: int) -> bool:
	if not states.has(id):
		return false
	_stamp_wariness(id, today, wary_days)
	_finish(id, SCARED_OFF)
	return true


## "Pushing" an already-wary creature is an explicit external trigger,
## not implied by a single look or by reading an interaction prompt.
func push_wary(id: String, today: int, scared_days: int) -> bool:
	if not is_wary(id, today) or not [ASKING, WARY].has(state_of(id)):
		return false
	return scare(id, today, scared_days)


## Guide eligibility is a query, never a forced transfer/automatic bond.
## The caller verifies a planted, OPEN + baited Lullmother in the SAME room.
func may_guide(id: String, open_baited_nearby: bool,
		threshold: float) -> bool:
	if not open_baited_nearby or threshold < 0.0 or threshold > 1.0:
		return false
	if id != active_creature_id and state_of(id) != INTERESTED:
		return false
	return state_of(id) == INTERESTED or (state_of(id) == ASKING and
		float(record_of(id).get("warmth", 0.0)) >= threshold and approaching)


## Saving/reloading/room transitions discard the session UI and held
## fruit but preserve stable per-creature relationship history.
func clear_runtime() -> void:
	for id in states.keys():
		if states[id] == ASKING:
			states[id] = ATTENDING
	active_creature_id = ""
	_clear_held()
	approaching = false


func _stamp_wariness(id: String, today: int, days: int) -> void:
	var record := record_of(id)
	record["wariness_until_day"] = maxi(int(record.get("wariness_until_day", -1)),
		today + maxi(0, days))
	records[id] = record


func _finish(id: String, outcome: String) -> void:
	var record := record_of(id)
	if not record.is_empty():
		record["last_outcome"] = outcome
		records[id] = record
	states[id] = outcome
	if active_creature_id == id:
		active_creature_id = ""
		_clear_held()
		approaching = false


func _clear_held() -> void:
	held_fruit = ""
	held_lean = ""
