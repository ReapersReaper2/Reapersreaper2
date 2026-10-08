extends RefCounted
## Widowblade key-item weapon for Reaper's Reaper (wiring).
##
## Gage's ruling (signed off 2026-10-04): Ivy's defeat (Ch16, Death's Garden
## boss) sets FLAG_IVY_DEFEATED and grants the Widowblade via an acquisition
## event. The Ch16 boss fight itself is future work — when it lands, it calls
## on_ivy_defeated(gs) at the victory beat.
##
## LOCKED RULES (Gage — do not deviate):
##   - The Widowblade is a weapon, OUTSIDE the breeding model: it is never
##     breedable, never sellable, never consumed.
##   - The shadow-pool charge it draws on is the single shared definition in
##     scripts/fairy_pools.gd: Ivy's boss phase (pre-defeat) and the player's
##     Widowblade phase (post-defeat) consume the same charge data.
##
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (autoloads don't load there).
##   const Widowblade = preload("res://scripts/widowblade.gd")

const FairyPools = preload("res://scripts/fairy_pools.gd")

const ITEM_ID := "widowblade"
const FLAG_IVY_DEFEATED := "ivy_defeated"


## Item record (from data/items.json). Empty dict when unknown.
static func item_record() -> Dictionary:
	return (preload("res://scripts/creature_data.gd")).get_item(ITEM_ID)


## True when the blade is a key-item weapon (never a breedable part).
static func is_key_item_weapon() -> bool:
	return str(item_record().get("class", "")) == "key-item weapon"


## The acquisition event: call at Ivy's defeat. Sets FLAG_IVY_DEFEATED and
## grants the Widowblade into the inventory (once — re-calling is a no-op
## for the grant, the flag is idempotent). The shadow charge is NOT reset
## here: Ivy's phase and the player's phase share one charge pool.
## Returns {"ok": true, "flag": FLAG_IVY_DEFEATED, "granted": bool}.
static func on_ivy_defeated(gs: Node) -> Dictionary:
	gs.set_flag(FLAG_IVY_DEFEATED, true)
	var granted := false
	if gs.get_item_count(ITEM_ID) <= 0:
		gs.add_item(ITEM_ID, 1)
		granted = true
	return {"ok": true, "flag": FLAG_IVY_DEFEATED, "granted": granted}


## Current shared shadow charge, for the wielder's HUD (whoever holds the
## blade — Ivy pre-defeat, the player post-defeat — reads the same value).
static func shared_shadow_charge(gs: Node) -> int:
	return FairyPools.shadow_charge(gs)
