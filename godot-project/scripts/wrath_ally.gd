extends RefCounted
## Wrath ally combat actor for the Old One endgame fight (wiring).
##
## LOCKED SCOPE (collaboration with Sweet Potato Creature):
##   - Wrath joins as a scripted ally (turn_order: "after_player",
##     tactics: "scripted_beats") with one action: "blue_fire_volley".
##   - Blue-fire volleys: every round carries armor_bypass: true. Blue fire
##     passes metal and plant armor entirely — when damage is applied through
##     the Might/Guard core (battle_unit.gd), the defender's armor
##     contribution (the soak term) is skipped, exactly like the no_armor
##     daily mod's mod_no_armor flag does in take_damage().
##   - Cylinder rhythm: 6 shots per chambering cycle, then a breath reload
##     beat. glow_state() exposes the chambered color ("blue" = armed and
##     ready, "green" = breath reload) for the FX hook.
##   - Dialogue slot references are STORY-BOT OWNED ids. This script only
##     references the ids; the story bot writes the lines in their dialogue
##     docs. NEVER author lines here.
##   - fire_phoenix_rebirth() is the named hook the future Wrath endgame
##     fight's end beat calls; the Old One encounter then opens in the
##     "claimed" phase. There is deliberately no Wrath endgame fight script,
##     no Old One encounter content, no dialogue, and no name here —
##     Gage's open slot.
##
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (autoloads don't load there).
##   const WrathAlly = preload("res://scripts/wrath_ally.gd")

const OldOneGate = preload("res://scripts/old_one_gate.gd")

# Actor contract for the future fight's turn queue.
const ACTOR_ID := "wrath"
const SIDE := "ally"
const ACTION_VOLLEY := "blue_fire_volley"
const TURN_ORDER := "after_player"
const TACTICS := "scripted_beats"

# Cylinder rhythm + fire.
const SHOTS_PER_CYCLE := 6
const BLUE_ROUND_DAMAGE := 4
const FIRE_METER := "old_one_fire_meter"
# [TUNING] Placeholder value — NOT a canon lock. Story bot re-weights heavier/
# lighter after the dialogue-pass timing and the playtest read; do not let
# this number harden into a balance assumption without that pass.
const LESSER_FORM_THRESHOLD := 48  # 2 full 6-shot cycles at 4 dmg/round

# GameState keys.
const FLAG_JOINED := "wrath_ally_joined"
const FLAG_LESSER_FORM := "old_one_lesser_form"
const FLAG_PHOENIX_REBIRTH := "wrath_phoenix_rebirth"
const FLAG_TWINS_GRANTED := "twins_keepable_granted"
const FLAG_PLANTED := "widowblade_planted"
const STAT_BREATH_RELOAD := "wrath_breath_reload"
const STAT_BARK_IDX := "wrath_bark_idx"

# The Twins (lent): granted keepable when the Old One fight ends.
const ITEM_TWINS := "twins_lent"

# Dialogue slot ids (STORY-BOT OWNED — text lives in their dialogue docs).
const BARK_ENTRANCE := "wrath_oldone_entrance"
const BARK_VOLLEYS := ["wrath_blue_volley_01", "wrath_blue_volley_02", "wrath_blue_volley_03"]
const BARK_LESSER_TRIGGER := "wrath_lesser_trigger"
const BARK_FIGHT_END := "wrath_fight_end"
# Planting prompt beat slot (STORY-BOT OWNED — the story bot writes the
# lines; wiring only references the id and parses its structure).
const PLANT_BEAT_SLOT := "widowblade_planting_beat"

# Glow/chambered colors for the FX hook.
const GLOW_BLUE := "blue"
const GLOW_GREEN := "green"


## The ally actor record the future fight's turn queue consumes.
static func actor_record() -> Dictionary:
	return {
		"actor_id": ACTOR_ID,
		"side": SIDE,
		"actions": [ACTION_VOLLEY],
		"turn_order": TURN_ORDER,
		"tactics": TACTICS,
	}


## Ally-join beat. Returns the entrance bark slot id; the story bot owns the
## line. Idempotent per fight (first:true only on the first call).
static func join_ally(gs: Node) -> Dictionary:
	var first: bool = not gs.get_flag(FLAG_JOINED, false)
	gs.set_flag(FLAG_JOINED, true)
	return {
		"action": "wrath_join",
		"actor": actor_record(),
		"bark": BARK_ENTRANCE,
		"first": first,
	}


## Next volley bark in rotation: 01 -> 02 -> 03 -> 01 ...
static func next_volley_bark(gs: Node) -> String:
	var idx := int(gs.get_stat(STAT_BARK_IDX, 0)) % BARK_VOLLEYS.size()
	gs.set_stat(STAT_BARK_IDX, idx + 1)
	return BARK_VOLLEYS[idx]


## Chamber glow for the FX hook: "blue" when armed, "green" mid breath reload.
static func glow_state(gs: Node) -> String:
	return GLOW_GREEN if bool(gs.get_stat(STAT_BREATH_RELOAD, false)) else GLOW_BLUE


## Fire one 6-shot blue-fire volley. Each round's damage accumulates into the
## GameState counter "old_one_fire_meter" with armor_bypass: true. Firing
## enters the breath reload state; the fight must call take_breath() before
## the next volley. Returns the volley event (and a lesser_form check result
## when the threshold is crossed).
static func fire_volley(gs: Node) -> Dictionary:
	if bool(gs.get_stat(STAT_BREATH_RELOAD, false)):
		return {
			"action": ACTION_VOLLEY,
			"fired": false,
			"breath_reload": true,
			"chamber": GLOW_GREEN,
			"bark": "",
		}
	var total := SHOTS_PER_CYCLE * BLUE_ROUND_DAMAGE
	for i in total:
		gs.bump_counter(FIRE_METER)
	gs.set_stat(STAT_BREATH_RELOAD, true)
	var lesser := check_lesser_form(gs)
	return {
		"action": ACTION_VOLLEY,
		"fired": true,
		"shots": SHOTS_PER_CYCLE,
		"damage_per_round": BLUE_ROUND_DAMAGE,
		"armor_bypass": true,
		"damage_total": total,
		"meter": gs.get_counter(FIRE_METER),
		"breath_reload": true,
		"chamber": GLOW_GREEN,
		"bark": next_volley_bark(gs),
		"lesser_form": lesser,
	}


## The breath beat between chambering cycles: clears the reload state and
## re-arms the chamber to blue.
static func take_breath(gs: Node) -> Dictionary:
	gs.set_stat(STAT_BREATH_RELOAD, false)
	return {"action": "wrath_breath", "chamber": GLOW_BLUE, "breath_reload": false}


## Current fire meter value.
static func fire_meter(gs: Node) -> int:
	return gs.get_counter(FIRE_METER)


## Lesser-form transform: fires exactly once when the fire meter reaches the
## threshold, setting flag "old_one_lesser_form". Idempotent afterwards.
static func check_lesser_form(gs: Node) -> Dictionary:
	if gs.get_flag(FLAG_LESSER_FORM, false):
		return {"fired": false}
	if gs.get_counter(FIRE_METER) >= LESSER_FORM_THRESHOLD:
		gs.set_flag(FLAG_LESSER_FORM, true)
		return {"fired": true, "flag": FLAG_LESSER_FORM, "bark": BARK_LESSER_TRIGGER}
	return {"fired": false}


## Phoenix rebirth: the named hook the future Wrath endgame fight's end beat
## calls. One-per-fight and idempotent: sets flag "wrath_phoenix_rebirth"
## once and returns the phase-transition event; the Old One encounter opens
## in "claimed" phase.
static func fire_phoenix_rebirth(gs: Node) -> Dictionary:
	var first: bool = not gs.get_flag(FLAG_PHOENIX_REBIRTH, false)
	gs.set_flag(FLAG_PHOENIX_REBIRTH, true)
	return {"event": "old_one_phase_claimed", "flag": FLAG_PHOENIX_REBIRTH, "first": first}


## Planting prompt beat availability. Returns PLANT_BEAT_SLOT when the
## planting prompt may open, "" otherwise. Gated EXACTLY as: fires ONLY
## when the lesser-form transform has fired AND the Widowblade is EQUIPPED
## (built on old_one_gate.can_plant so the prompt gate and plant() agree).
## No other trigger may open the prompt — every other state returns "".
static func planting_prompt_slot(gs: Node) -> String:
	if not bool(OldOneGate.can_plant(gs).get("ok", false)):
		return ""
	return PLANT_BEAT_SLOT


## Plant the Widowblade on the lesser form. Delegates to the gate's equipped
## check (equipped, not merely in inventory). Idempotent.
static func plant(gs: Node) -> Dictionary:
	var gate := OldOneGate.can_plant(gs)
	if not bool(gate.get("ok", false)):
		return {"ok": false, "reason": str(gate.get("reason", ""))}
	var first: bool = not gs.get_flag(FLAG_PLANTED, false)
	gs.set_flag(FLAG_PLANTED, true)
	return {"ok": true, "flag": FLAG_PLANTED, "first": first}


## Old One fight end: grant the lent Twin item (keepable). Once, ever.
static func on_old_one_fight_end(gs: Node) -> Dictionary:
	var granted := false
	if not gs.get_flag(FLAG_TWINS_GRANTED, false):
		gs.add_item(ITEM_TWINS, 1)
		gs.set_flag(FLAG_TWINS_GRANTED, true)
		granted = true
	return {
		"ok": true,
		"granted": granted,
		"flag": FLAG_TWINS_GRANTED,
		"bark": BARK_FIGHT_END,
	}
