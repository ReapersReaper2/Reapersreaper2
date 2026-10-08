extends RefCounted
## Depower — Ch13-14 depower mechanics (flag enforcement).
##
## LOCKED DESIGN (from the decision log — do not deviate):
## - ch13_depowered: set on HL1 entry, stays set through Ch13 (hl1-hl4)
##   and Ch14 (t1-t6).
## - ch13_repowered_partial: set at U2 Absorption (partial: map sense +
##   Roots tab + weak plant abilities).
## - ch13_repowered: set at U3 Wings (full: everything online + flight).
##
## Depower state = FULL when ch13_depowered AND NOT ch13_repowered,
## unless ch13_repowered_partial (also AND NOT ch13_repowered) which is
## PARTIAL. Anything else is NONE.
##
## NOTE: intentionally no class_name (project convention). Use via
## `const Depower = preload("res://scripts/depower.gd")` and call the
## static query functions with a GameState (or any object with get_flag).
##
## Other systems query this module; flag-setting logic lives in the room
## shells and is NOT touched here.

enum State { NONE, PARTIAL, FULL }

const FLAG_DEPOWER := "ch13_depowered"
const FLAG_PARTIAL := "ch13_repowered_partial"
const FLAG_REPOWER := "ch13_repowered"
const FLAG_FORM9 := "form9_unlocked"

## Damage multiplier for scythe swings.
const DMG_FULL := 0.5
const DMG_PARTIAL := 0.75
## Walk-speed multiplier while fully depowered.
const SPEED_FULL := 0.85


static func _flag(gs, flag: String) -> bool:
	if gs == null:
		return false
	if gs.has_method("get_flag"):
		return bool(gs.get_flag(flag, false))
	return false


## Current depower state from the three locked flags.
static func state(gs) -> int:
	var depowered := _flag(gs, FLAG_DEPOWER)
	var repowered := _flag(gs, FLAG_REPOWER)
	if not depowered or repowered:
		return State.NONE
	if _flag(gs, FLAG_PARTIAL):
		return State.PARTIAL
	return State.FULL


static func is_depowered(gs) -> bool:
	return state(gs) == State.FULL


static func is_partial(gs) -> bool:
	return state(gs) == State.PARTIAL


## Scythe damage multiplier: 0.5 full, 0.75 partial, 1.0 otherwise.
static func damage_mult(gs) -> float:
	match state(gs):
		State.FULL:
			return DMG_FULL
		State.PARTIAL:
			return DMG_PARTIAL
	return 1.0


## Walk-speed multiplier: 0.85 while fully depowered, 1.0 otherwise.
static func walk_speed_mult(gs) -> float:
	if state(gs) == State.FULL:
		return SPEED_FULL
	return 1.0


## Form gating. Locked canon (doc 00 Ch13: "You are back to Form 3 stats";
## doc 06c Sc1: "[TRIGGER: Depowered state begins — Form 3 stats only]") has
## the player AT Form 3 during full depower, so FULL and PARTIAL both allow
## forms 1-3. Armor forms 4-7 stay locked until U3 wings (full repower).
## NONE allows everything.
static func can_use_form(gs, form: int) -> bool:
	match state(gs):
		State.FULL:
			return form <= 3
		State.PARTIAL:
			return form <= 3
	return true


## Luna's combat assist is disabled while fully depowered.
## (Luna is currently a follower stub; this query exists for the
## future combat-assist system.)
static func combat_assist_enabled(gs) -> bool:
	return state(gs) != State.FULL


## Map sense + Roots tab unlock at partial repower (and stay on).
static func map_sense_unlocked(gs) -> bool:
	return state(gs) != State.FULL


## Weak plant abilities are available from partial repower onward.
static func plant_abilities_available(gs) -> bool:
	return state(gs) != State.FULL


## Flight is available once fully repowered AND the U3 wings flag is set.
## Flight physics are NOT implemented; this is the flag gate for later.
static func flight_available(gs) -> bool:
	return state(gs) == State.NONE and _flag(gs, FLAG_FORM9)


## HUD status text: "" when not depowered.
static func state_label(gs) -> String:
	match state(gs):
		State.FULL:
			return "DEPOWERED"
		State.PARTIAL:
			return "WEAKENED"
	return ""
