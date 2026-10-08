extends RefCounted
## Old One gate for Reaper's Reaper (wiring).
##
## GATE_OLD_ONE_REQUIRES_WIDOWBLADE: the Old One encounter is blocked until
## the Widowblade is equipped or present in the player's inventory (Gage's
## ruling, signed off 2026-10-04).
##
## PLACEHOLDER HOOK ONLY. There is deliberately no encounter content, no
## dialogue, and no name here — Gage hasn't named the Old One yet. This
## script answers one question ("may the player enter?") and nothing else.
##
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (autoloads don't load there).
##   const OldOneGate = preload("res://scripts/old_one_gate.gd")

const Widowblade = preload("res://scripts/widowblade.gd")

const GATE_ID := "old_one_requires_widowblade"

# Lesser-form flag — owned by scripts/wrath_ally.gd (it fires the transform);
# the literal is used here to avoid a circular preload between the gate and
# the ally script.
const LESSER_FORM_FLAG := "old_one_lesser_form"


## Equipped/present check: the blade counts as equipped when the player's
## current weapon string names it, or present when it sits in inventory.
static func has_widowblade(gs: Node) -> bool:
	if gs.get_item_count(Widowblade.ITEM_ID) > 0:
		return true
	return is_widowblade_equipped(gs)


## Equipped-only check: the Widowblade is EQUIPPED when the player's current
## weapon names it (inventory alone does not count). Planting the blade on
## the lesser form requires this.
static func is_widowblade_equipped(gs: Node) -> bool:
	var player: Dictionary = gs.state.get("player", {})
	return str(player.get("weapon", "")) == Widowblade.ITEM_ID


## The gate. Returns {"ok": bool, "reason": String}. Callers block the Old
## One encounter whenever ok == false.
static func check(gs: Node) -> Dictionary:
	if not gs.get_flag(Widowblade.FLAG_IVY_DEFEATED, false):
		return {"ok": false, "reason": "Ivy stands between you and the Old One."}
	if not has_widowblade(gs):
		return {"ok": false, "reason": "The way opens only for the Widowblade."}
	return {"ok": true, "reason": "The Old One's gate stands open."}


## Planting gate for the lesser form: ok only when the fire meter has fired
## the lesser-form transform AND the Widowblade is equipped (Gage's ruling —
## it must be in hand, not merely in the bag). Returns {"ok", "reason"}.
static func can_plant(gs: Node) -> Dictionary:
	if not gs.get_flag(LESSER_FORM_FLAG, false):
		return {"ok": false, "reason": "The form has not lessened; the fire must finish its work."}
	if not is_widowblade_equipped(gs):
		return {"ok": false, "reason": "The Widowblade must be equipped, not merely carried."}
	return {"ok": true, "reason": "The lesser form is ready for planting."}


## True when the blade sits in inventory but is not equipped — the UI can
## prompt the player to equip it before planting.
static func needs_equip_prompt(gs: Node) -> bool:
	return gs.get_item_count(Widowblade.ITEM_ID) > 0 and not is_widowblade_equipped(gs)
