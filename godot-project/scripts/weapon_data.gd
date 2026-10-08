extends RefCounted
## Weapon x power-source data table for Reaper's Reaper combat.
##
## The moveset is weapon x power source, not just weapon: Ch13-14's sword +
## Luna's fairy energy is a distinct moveset from sword-alone, and late-game
## bloom scaling rides the same architecture. The swing controller
## (scythe.gd) reads its tuning numbers from here at swing start, so the
## same hitbox/feel code serves every (weapon, power) pair.
##
## Design beats covered (groundwork only — no unlock events or UI yet):
## - Scythe-break (Ch12-14): scythe shatters -> father's longsword Ch13-14
##   -> plant grows the living Scythe-Tail (Form 8). The sword stays on the
##   hip from Form 8 as a cosmetic keepsake; post-Ch14 it has no combat
##   function.
## - Fairy-energy (Ch13-14): sword + mid-tier fairy energy, Luna as the power
##   source — the only power that never came from the armor. No scythe,
##   plant/cannon, or Bloom in that window. Fairy energy scales up late-game.
##
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (autoloads don't load there).
##   const WeaponData = preload("res://scripts/weapon_data.gd")
##
## Gameplay state (unlocks, current weapon/power) lives in GameState and is
## passed in as `gs` — the table itself holds no mutable state.

const WEAPON_SCYTHE := "scythe"          # Forms 1-3, 6-7. The baseline.
const WEAPON_LONGSWORD := "longsword"    # Father's sword, Ch13-14. Post-Ch14: cosmetic keepsake only.
const WEAPON_SCYTHE_TAIL := "scythe_tail"  # Living Scythe-Tail, Form 8+.

const POWER_ARMOR := "armor"  # Default: power drawn from the armor forms.
const POWER_FAIRY := "fairy"  # Luna's fairy energy — the only power never from the armor.
const POWER_BLOOM := "bloom"  # Late-game bloom scaling.


static var _TABLE: Dictionary = {
	"scythe/armor": {
		"name": "Reaper's Scythe",
		"description": "Mollosar's own scythe, armor-forged. The baseline every other moveset is tuned against.",
		"damage_mult": 1.0,
		"swing1_time": 0.35,
		"swing2_time": 0.30,
		"hitstop_duration": 0.07,
		"shake_trauma": 0.32,
		"arc_radius": 150.0,
		"arc_color": Color(0.70, 0.30, 1.0),
	},
	"longsword/fairy": {
		"name": "Father's Longsword (Fairy-Touched)",
		"description": "The father's sword hybridized with Luna's mid-tier fairy energy. Depowered, not helpless — Ch13-14, no scythe, no plant/cannon, no Bloom.",
		"damage_mult": 0.7,
		"swing1_time": 0.28,
		"swing2_time": 0.24,
		"hitstop_duration": 0.06,
		"shake_trauma": 0.28,
		"arc_radius": 140.0,
		"arc_color": Color(1.0, 0.78, 0.35),
	},
	"scythe_tail/armor": {
		"name": "Scythe-Tail",
		"description": "The plant-grown living Scythe-Tail, Form 8+. Heavier than the scythe, wider arcs.",
		"damage_mult": 1.3,
		"swing1_time": 0.40,
		"swing2_time": 0.345,
		"hitstop_duration": 0.09,
		"shake_trauma": 0.40,
		"arc_radius": 175.0,
		"arc_color": Color(0.75, 0.25, 0.55),
	},
	"scythe_tail/bloom": {
		"name": "Scythe-Tail (Bloom Ascendant)",
		"description": "Endgame: the Scythe-Tail drinking deep Bloom. Luna's fairy energy at full scale.",
		"damage_mult": 1.6,
		"swing1_time": 0.385,
		"swing2_time": 0.33,
		"hitstop_duration": 0.10,
		"shake_trauma": 0.45,
		"arc_radius": 185.0,
		"arc_color": Color(0.95, 0.96, 1.0),
	},
}


static func weapon_ids() -> Array:
	return [WEAPON_SCYTHE, WEAPON_LONGSWORD, WEAPON_SCYTHE_TAIL]


static func power_ids() -> Array:
	return [POWER_ARMOR, POWER_FAIRY, POWER_BLOOM]


static func starting_weapons() -> Array:
	return [WEAPON_SCYTHE]


static func is_known_weapon(weapon_id: String) -> bool:
	return weapon_ids().has(weapon_id)


static func is_known_power(power_id: String) -> bool:
	return power_ids().has(power_id)


## Look up the tuning entry for a (weapon, power) pair. Unknown pairs fall
## back to scythe/armor (the baseline) with a warning — never crash combat.
## (Named get_entry, not get: Object.get is native and can't be shadowed.)
static func get_entry(weapon_id: String, power_id: String) -> Dictionary:
	var key: String = weapon_id + "/" + power_id
	if _TABLE.has(key):
		return _TABLE[key]
	push_warning("WeaponData: unknown pair '%s', falling back to scythe/armor" % key)
	return _TABLE["scythe/armor"]


## Unlock a weapon, persisted in the GameState ledger. Unknown ids are
## refused (warning, no write) so a typo can't poison a save.
static func unlock(gs: Node, weapon_id: String) -> void:
	if not is_known_weapon(weapon_id):
		push_warning("WeaponData: refusing to unlock unknown weapon '%s'" % weapon_id)
		return
	var ledger: Dictionary = gs.state.get("ledger", {})
	var weapons: Array = ledger.get("weapons", [])
	if not weapons.has(weapon_id):
		weapons.append(weapon_id)
	ledger["weapons"] = weapons
	gs.state["ledger"] = ledger


static func is_unlocked(gs: Node, weapon_id: String) -> bool:
	var ledger: Dictionary = gs.state.get("ledger", {})
	return (ledger.get("weapons", []) as Array).has(weapon_id)


static func current_weapon(gs: Node) -> String:
	var wid: String = str((gs.state.get("player", {}) as Dictionary).get("weapon", WEAPON_SCYTHE))
	return wid if is_known_weapon(wid) else WEAPON_SCYTHE


static func current_power(gs: Node) -> String:
	var pid: String = str((gs.state.get("player", {}) as Dictionary).get("power_source", POWER_ARMOR))
	return pid if is_known_power(pid) else POWER_ARMOR


## Equip a weapon/power pair (unlock events call this when the story says so).
static func set_current(gs: Node, weapon_id: String, power_id: String) -> void:
	if not is_known_weapon(weapon_id):
		push_warning("WeaponData: refusing to equip unknown weapon '%s'" % weapon_id)
		return
	if not is_known_power(power_id):
		push_warning("WeaponData: refusing to equip unknown power '%s'" % power_id)
		return
	var p: Dictionary = gs.state.get("player", {})
	p["weapon"] = weapon_id
	p["power_source"] = power_id
	gs.state["player"] = p
