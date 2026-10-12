extends RefCounted
## Per-individual wild-creature encounter memory. Director decisions
## D-36, D-38, D-39; D-40 has an INTERIM split but no approved cooldown.
##
## IMPORTANT: this is an inert state/data layer, NOT a new capture mechanic.
## No lore, bond, mantle, currency, timer length, or automatic acceptance is
## created here. The live creature/roster entry owns its own offer_memory.
## A caller must provide an individual encounter ID (never a species ID).
## Combat does not write these records.

const OUTCOME_NEUTRAL := "fed_stayed"
const OUTCOME_FLED := "fled"
const OUTCOME_ATE_PLANT := "ate_plant"
const OUTCOME_WITHDREW := "withdrew"
const NEUTRAL_VISITS_FOR_ATTUNEMENT := 2

const HARD_REFUSALS := [OUTCOME_FLED, OUTCOME_ATE_PLANT, OUTCOME_WITHDREW]
const ALL_OUTCOMES := [OUTCOME_NEUTRAL, OUTCOME_FLED, OUTCOME_ATE_PLANT, OUTCOME_WITHDREW]

## Records live on the individual creature, never on a species table.
## Older creature entries without a record correctly start untouched.
static func snapshot(creature: Dictionary) -> Dictionary:
	var raw = creature.get("offer_memory", {})
	if not (raw is Dictionary):
		return {}
	return (raw as Dictionary).duplicate(true)


## The field journal belongs to the run, separate from mantle/breeding.
## Persisted automatically with GameState.state; legacy saves need no
## destructive migration. Every entry identifies an individual encounter.
static func field_log(gs: Node) -> Array:
	if not (gs.get("state") is Dictionary):
		return []
	if not (gs.state.get("field_encounters", null) is Array):
		gs.state["field_encounters"] = []
	return gs.state["field_encounters"]


## An event is processed once, even if the player double taps Use.
## caller must supply a stable UNIQUE encounter key and individual ref;
## neither may be a species-level pseudo-identity.
## The source system supplies the genuine outcome after observing the
## creature. The game cannot infer acceptance from pressing Interact.
static func record_outcome(creature: Dictionary, individual_ref: String,
		encounter_ref: String, outcome: String, journal: Array) -> Dictionary:
	if individual_ref.strip_edges().is_empty() or encounter_ref.strip_edges().is_empty():
		return {"ok": false, "reason": "missing_individual_or_encounter_ref"}
	if not ALL_OUTCOMES.has(outcome):
		return {"ok": false, "reason": "unknown_outcome"}
	var memory = creature.get("offer_memory", {})
	if not (memory is Dictionary):
		return {"ok": false, "reason": "malformed_offer_memory"}
	var proposed: Dictionary = (memory as Dictionary).duplicate(true)
	var seen = proposed.get("encounters_seen", [])
	if not (seen is Array):
		return {"ok": false, "reason": "malformed_encounters"}
	if (seen as Array).has(encounter_ref):
		return {"ok": true, "reason": "already_recorded", "changed": false}
	if bool(proposed.get("reoffer_blocked", false)):
		return {"ok": false, "reason": "reoffer_pending_ruling"}
	var visits := int(proposed.get("neutral_visits", 0))
	if visits < 0:
		return {"ok": false, "reason": "malformed_visit_count"}
	var entry := {
		"individual_ref": individual_ref,
		"encounter_ref": encounter_ref,
		"outcome": outcome,
	}
	var events = proposed.get("outcomes", [])
	if not (events is Array):
		return {"ok": false, "reason": "malformed_outcome_history"}
	(seen as Array).append(encounter_ref)
	(events as Array).append(entry.duplicate(true))
	proposed["encounters_seen"] = seen
	proposed["outcomes"] = events
	if outcome == OUTCOME_NEUTRAL:
		# Only a fed creature that remained present counts as a visit.
		# Two visits make attunement possible, not automatic or assured.
		proposed["neutral_visits"] = mini(visits + 1, NEUTRAL_VISITS_FOR_ATTUNEMENT)
	else:
		# Rejection NEVER advances visits and NEVER writes a tended marker.
		# Reoffer interval/length awaits the final D-40 story ruling.
		# Until then, fail closed; do not accidentally allow instant retries.
		proposed["neutral_visits"] = visits
		proposed["reoffer_blocked"] = true
		proposed["reoffer_rule_pending"] = true
		journal.append(entry.duplicate(true))
	creature["offer_memory"] = proposed
	return {"ok": true, "reason": "", "changed": true}


## Eligibility to *attempt* the later, separately approved attunement beat.
## Never bonds a creature, writes a mantle, or spends a resource.
static func can_attempt_attunement(creature: Dictionary) -> bool:
	var mem := snapshot(creature)
	return not bool(mem.get("reoffer_blocked", false)) and \
		int(mem.get("neutral_visits", 0)) >= NEUTRAL_VISITS_FOR_ATTUNEMENT


## A director-approved later system can clear the block after observing
## its specified interval/ruling. There is deliberately no timer here.
## Refusal history and existing neutral visits are NEVER erased.
static func reopen_after_ruling(creature: Dictionary) -> bool:
	var memory = creature.get("offer_memory", {})
	if not (memory is Dictionary) or not bool(memory.get("reoffer_blocked", false)):
		return false
	var proposed: Dictionary = (memory as Dictionary).duplicate(true)
	proposed["reoffer_blocked"] = false
	proposed["reoffer_rule_pending"] = false
	creature["offer_memory"] = proposed
	return true
