extends RefCounted
## Variant-A mantle ledger: creature-sheet data, not a tenth breeding slot.
## Director rulings 2026-10-12: D-1, D-6, D-8, D-12, D-21, D-23,
## D-25, D-38 and D-41. This is a validation/storage boundary only.
## No capture outcome, cost, heredity, or magnitude is inferred here.

const EFFECT_FAMILIES := [
	"CALM", "VIGOR", "NIGHTSIGHT", "FRUITFLAVOR", "THREADRESONANCE"
]
const EXPRESSION_STATES := [
	"UNMANTLED", "TENDED", "EXPRESSED", "DORMANT", "FADED"
]
const DEPLOYMENT_CLASSES := ["ground", "waterline", "hanging", "UNRESOLVED"]
const MAX_EXPRESSED := 1

## Read-only. Old creatures have no mantle field and correctly read empty.
static func records(creature: Dictionary) -> Array:
	var value = creature.get("mantles", [])
	if not (value is Array):
		return []
	return (value as Array).duplicate(true)

## Validates the complete collection, so a writer cannot bypass the
## one-EXPRESSED rule by appending records directly. Invalid data is never
## silently repaired: callers must request a director ruling for new classes.
static func validate(creature: Dictionary) -> Dictionary:
	var value = creature.get("mantles", [])
	if not (value is Array):
		return {"ok": false, "reason": "mantles_not_array"}
	var expressed := 0
	for value_entry in value:
		if not (value_entry is Dictionary):
			return {"ok": false, "reason": "mantle_not_dictionary"}
		var entry: Dictionary = value_entry
		var family := str(entry.get("effect_family", ""))
		if not EFFECT_FAMILIES.has(family):
			return {"ok": false, "reason": "unknown_effect_family"}
		var state := str(entry.get("expression_state", ""))
		if not EXPRESSION_STATES.has(state):
			return {"ok": false, "reason": "invalid_expression_state"}
		var deployment := str(entry.get("deployment_class", "UNRESOLVED"))
		if not DEPLOYMENT_CLASSES.has(deployment):
			return {"ok": false, "reason": "invalid_deployment_class"}
		if (str(entry.get("heritability_flag", "NONE")) != "NONE"
			or bool(entry.get("heritable", false))):
			return {"ok": false, "reason": "mantle_inheritance_forbidden"}
		if state == "EXPRESSED":
			if deployment == "UNRESOLVED":
				return {"ok": false, "reason": "unresolved_mantle_inert"}
			expressed += 1
			if expressed > MAX_EXPRESSED:
				return {"ok": false, "reason": "expressed_limit"}
	return {"ok": true, "reason": ""}

## Transactional: if the new record violates any invariant, the original
## collection is unchanged. A later capture system owns when to call this.
static func add_record(creature: Dictionary, record: Dictionary) -> Dictionary:
	var old_value = creature.get("mantles", [])
	if not (old_value is Array):
		return {"ok": false, "reason": "mantles_not_array"}
	var proposed: Array = (old_value as Array).duplicate(true)
	proposed.append(record.duplicate(true))
	var trial := {"mantles": proposed}
	var verdict := validate(trial)
	if not bool(verdict.get("ok", false)):
		return verdict
	creature["mantles"] = proposed
	return {"ok": true, "reason": ""}

## Breeding is permitted to read this qualitative flag, never transmit
## the record, write genotype slots, or turn it into a priced modifier.
static func breeding_affinity(creature: Dictionary) -> bool:
	if not bool(validate(creature).get("ok", false)):
		return false
	for record in records(creature):
		if str((record as Dictionary).get("expression_state", "")) == "EXPRESSED":
			return true
	return false
