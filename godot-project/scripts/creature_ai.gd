extends RefCounted
## Act 2 creature special battle behaviors for Reaper's Reaper.
##
## Handles signature moves and temperament logic for the nine Act 2
## creatures. No class_name / autoload on purpose: consumers preload
## this script so it works in headless -s test scripts too.
##   const CreatureAI = preload("res://scripts/creature_ai.gd")
##
## Design (from the brief):
##   Deepjaw: Gorge (heal 25% max Vigor) + Fossil Crush (2.5x damage).
##   Spinehopper: Thermal Ride (turn 1: evasion setup) -> Dive (turn 2:
##     big damage, consumes the thermal for +50% bonus).
##   Dragonthorn: Relocate every third turn (evasion for 1 turn).
##   Docile (Cinderbloom, Echomarrow, Carrion Bloom): Stillness (won't
##     attack unless provoked), Snap Shut (defensive reaction when
##     struck), Echo (mimics the foe's last action).
##   Thornleech: Scream when burned (fire damage) — alerts, gaining
##     an attack buff ("the scream carries").
##
## State lives on the BattleUnit's `statuses` dict so it survives
## save/load and the existing tick_statuses() countdown handles expiry.
## Turn counters live here, keyed by unit instance id.

const CreatureData = preload("res://scripts/creature_data.gd")

## Evasion chance granted by thermal_ride / relocate / uphill_flight.
const EVASION_CHANCE := 0.5
## Gorge restores this fraction of max HP.
const GORGE_HEAL_FRACTION := 0.25
## Dive bonus when consuming an active thermal.
const DIVE_THERMAL_BONUS := 1.5
## Scream attack buff (multiplier on temp_mods atk_mult).
const SCREAM_ATK_BUFF := 1.5
const SCREAM_BUFF_TURNS := 3
## Snap Shut defense buff.
const SNAP_SHUT_DEF_BUFF := 2.0
const SNAP_SHUT_TURNS := 2

## Turn counters per unit (instance id -> turn count). Reset on battle end.
static var _turn_counts: Dictionary = {}


static func reset_battle_state() -> void:
	_turn_counts.clear()


static func _turns(unit: RefCounted) -> int:
	return int(_turn_counts.get(unit.get_instance_id(), 0))


static func _bump_turn(unit: RefCounted) -> void:
	var id := unit.get_instance_id()
	_turn_counts[id] = int(_turn_counts.get(id, 0)) + 1


## Temperament lookup for AI decisions.
static func temperament(unit: RefCounted) -> String:
	CreatureData.ensure_loaded()
	var c: Dictionary = CreatureData.get_creature(unit.creature_id)
	return str(c.get("temperament", "WARY"))


## Pick the enemy's action for this turn. Returns an ability_id from the
## unit's ability_ids, or "" for "do nothing" (full Stillness).
## `foe_last_ability` is the ability the foe used last turn (for Echo).
## `provoked` is true if the foe attacked this unit (for docile logic).
static func choose_action(unit: RefCounted, foe_last_ability: String, provoked: bool) -> String:
	_bump_turn(unit)
	var turn := _turns(unit)
	var cid: String = str(unit.get("creature_id"))
	var temp := temperament(unit)

	# --- Docile: Stillness unless provoked ---
	if temp == "DOCILE":
		if not provoked and not _was_provoked(unit):
			# Pure Stillness: do nothing. (Echomarrow/Carrion Bloom.)
			if unit.can_use("stillness"):
				return "stillness"
			return ""
		# Provoked docile: Snap Shut if available, else a weak answer.
		if unit.can_use("snap_shut"):
			return "snap_shut"
		if cid == "echomarrow" and foe_last_ability != "" and unit.can_use("echo"):
			return "echo"
		return _fallback_attack(unit)

	# --- Spinehopper: Thermal Ride -> Dive two-turn sequence ---
	if cid == "spinehopper":
		if unit.statuses.has("thermal"):
			return "dive"
		if unit.can_use("thermal_ride"):
			return "thermal_ride"
		return _fallback_attack(unit)

	# --- Dragonthorn: Relocate every third turn ---
	if cid == "dragonthorn":
		if turn % 3 == 0 and unit.can_use("relocate"):
			return "relocate"
		return _fallback_attack(unit)

	# --- Deepjaw: Gorge when hurt, Fossil Crush as finisher ---
	if cid == "deepjaw":
		var hp_frac := float(unit.hp) / float(maxi(1, unit.max_hp))
		if hp_frac < 0.6 and unit.can_use("gorge"):
			return "gorge"
		if unit.can_use("fossil_crush"):
			return "fossil_crush"
		return _fallback_attack(unit)

	# --- Thornleech: Scream when burned ---
	if cid == "thornleech":
		if unit.statuses.has("burned") and unit.can_use("scream"):
			return "scream"
		return _fallback_attack(unit)

	# --- Default: random damaging move ---
	return _fallback_attack(unit)


## Was this docile unit provoked in a previous turn?
static func _was_provoked(unit: RefCounted) -> bool:
	return unit.statuses.has("provoked")


## Mark a unit as provoked (call when the foe damages it).
static func mark_provoked(unit: RefCounted) -> void:
	unit.statuses["provoked"] = 99  # lasts the battle


## Pick a damaging fallback from the unit's kit.
static func _fallback_attack(unit: RefCounted) -> String:
	CreatureData.ensure_loaded()
	var damaging: Array = []
	for aid in unit.ability_ids:
		var ab: Dictionary = CreatureData.get_ability(str(aid))
		if float(ab.get("power", 0.0)) > 0.0:
			damaging.append(str(aid))
	if damaging.is_empty():
		return ""
	# Deterministic in tests: first damaging move. Battle scene can
	# randomize by shuffling ability_ids beforehand if desired.
	return str(damaging[0])


## Apply the special effect of a signature move. Called AFTER the normal
## damage step in battle_unit.use_ability (via hook) or directly by the
## battle scene. Returns a dict with "message" and any extra info.
## `ctx` may carry "foe_last_ability" for Echo.
static func apply_special(user: RefCounted, target: RefCounted, ability_id: String, ctx: Dictionary = {}) -> Dictionary:
	var result := {"message": "", "extra_damage": 0}
	match ability_id:
		"gorge":
			# Heal applied by battle_unit (heal element); message only here.
			var healed_amt := int(round(float(user.get("max_hp")) * GORGE_HEAL_FRACTION))
			result["message"] = "%s gorges and recovers Vigor!" % user.get("display_name")
		"thermal_ride":
			user.apply_status("thermal", 2)
			user.apply_status("evasion", 2)
			result["message"] = "%s rides a thermal current — evasive!" % user.display_name
		"dive":
			if user.statuses.has("thermal"):
				user.statuses.erase("thermal")
				result["extra_damage_mult"] = DIVE_THERMAL_BONUS
				result["message"] = "%s dives from the thermal — devastating!" % user.display_name
			else:
				result["message"] = "%s dives!" % user.display_name
		"relocate":
			user.apply_status("evasion", 1)
			result["message"] = "%s relocates — hard to pin down!" % user.display_name
		"uphill_flight":
			user.apply_status("evasion", 1)
			result["message"] = "%s catches an uphill draft — evasive!" % user.display_name
		"scream":
			user.temp_mods["atk_mult"] = SCREAM_ATK_BUFF
			user.temp_mods["turns"] = SCREAM_BUFF_TURNS
			result["message"] = "%s screams — the sound carries! Attack rose!" % user.display_name
		"snap_shut":
			user.temp_mods["def_mult"] = SNAP_SHUT_DEF_BUFF
			user.temp_mods["turns"] = SNAP_SHUT_TURNS
			result["message"] = "%s snaps shut — defense rose!" % user.display_name
		"stillness":
			result["message"] = "%s is perfectly still." % user.display_name
		"echo":
			var foe_ab := str(ctx.get("foe_last_ability", ""))
			if foe_ab != "":
				result["echo_ability"] = foe_ab
				result["message"] = "%s echoes %s!" % [user.display_name, foe_ab]
			else:
				result["message"] = "%s listens — nothing to echo." % user.display_name
		"resonate":
			# Resonate harmonizes: small heal if the foe is also still/calm.
			var healed2: int = user.heal(int(round(float(user.max_hp) * 0.1)))
			result["message"] = "%s resonates, recovering %d Vigor." % [user.display_name, healed2]
		"drain":
			# Siphon applied by battle_unit; message only here.
			result["message"] = "%s drains Vigor!" % user.get("display_name")
		"shed_leaves":
			user.cure_statuses(["wilt", "spore_fever", "rootbound", "burned"])
			result["message"] = "%s sheds its leaves — ailments cleared!" % user.display_name
		"retract":
			user.temp_mods["def_mult"] = 1.75
			user.temp_mods["turns"] = 2
			result["message"] = "%s retracts into its cap — defense rose!" % user.display_name
		"mourn":
			result["message"] = "%s mourns quietly." % user.display_name
		"territory_roar":
			target.apply_status("intimidated", 2)
			result["message"] = "%s roars — %s is intimidated!" % [user.display_name, target.display_name]
	return result


## Evasion check: called before damage. Returns true if the attack misses.
## Uses the unit's "evasion" status (set by thermal_ride/relocate/etc.).
static func check_evasion(defender: RefCounted) -> bool:
	if int(defender.statuses.get("evasion", 0)) <= 0:
		return false
	# Deterministic seed hook for tests: if "evasion_seed" is set in
	# statuses, use it (1 = always evade, 0 = never) instead of RNG.
	if defender.statuses.has("evasion_seed"):
		return int(defender.statuses["evasion_seed"]) == 1
	return randf() < EVASION_CHANCE


## Apply "burned" when a unit takes fire-element damage. Called from
## battle_unit.use_ability after fire damage lands.
static func apply_burn(unit: RefCounted) -> void:
	unit.apply_status("burned", 2)
