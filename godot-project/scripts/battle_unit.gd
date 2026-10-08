extends RefCounted
## Runtime battle combatant for Reaper's Reaper tactical battles (foundation).
##
## A BattleUnit is instantiated from a creature_data entry + level:
##   const BattleUnit = preload("res://scripts/battle_unit.gd")
##   var u = BattleUnit.new("snapling", 5)
##
## Derived stats: attack = (base might + trait might_mods) * level_mult,
## defense = (base guard + trait guard_mods) * level_mult, HP from vigor.
## Damage: dealt = max(1, round(raw - defense * GUARD_MITIGATION)).
## Fire-element abilities deal FIRE_VS_PLANT x vs plant creatures (every wild
## creature in Game 1 is a plant), negated by fire_resist trait tags.
## WILT drains 10% of max HP per turn. All numbers are tuning placeholders.
##
## Scope: data + unit logic only. No battle scene, UI, breeding, or party.

const CreatureData = preload("res://scripts/creature_data.gd")
const CreatureAI = preload("res://scripts/creature_ai.gd")

const LEVEL_GROWTH := 0.08        # +8% per level over level 1 (tuning placeholder)
const GUARD_MITIGATION := 0.6     # each point of defense soaks 0.6 raw damage
const FIRE_VS_PLANT := 1.5        # fire abilities vs plants (roster doc 03)
const WILT_DRAIN := 0.10          # wilt drains 10% of max HP per turn
const SPORE_FEVER_FAIL := 0.30    # spore-fever: 30% chance the afflicted can't act (tuning placeholder)

var creature_id: String
var display_name: String
var level: int
var max_hp: int
var hp: int
var attack: int
var defense: int
var speed: int
var ability_ids: Array = []
var statuses: Dictionary = {}
var fainted: bool = false
## Spore Needle infection (set by SporeNeedle.infect_unit(); read by
## SporeNeedle.battle_snapshot() on faint). Not a status: it persists past
## fainting so the death hook can grow the fruit plant.
var spore_infected: bool = false
var spore_lean: String = ""
## Temporary battle modifiers from items (e.g. Ironwood Bark):
## {"atk_mult": 1.0, "def_mult": 1.75, "spd_mult": 0.6, "turns": 3}.
var temp_mods: Dictionary = {}
## Daily Hunt modifiers (set by battle.gd when a hunt battle is active).
## Only ever set on the player's unit.
var mod_incoming_mult := 1.0   # frail: 2.0 / heavy_hits: 1.25
var mod_outgoing_mult := 1.0   # heavy_hits: 1.5
var mod_no_armor := false      # no_armor: Guard soaks nothing


func _init(creature_id_: String, level_: int) -> void:
	CreatureData.ensure_loaded()
	var c: Dictionary = CreatureData.get_creature(creature_id_)
	creature_id = creature_id_
	display_name = str(c.get("name", creature_id_))
	level = maxi(1, level_)
	var mult := 1.0 + float(level - 1) * LEVEL_GROWTH
	var base: Dictionary = c.get("base", {})
	var mods: Dictionary = CreatureData.trait_mods(c)
	max_hp = int(round(float(base.get("vigor", 20)) * mult))
	attack = int(round(float(base.get("might", 5) + mods["might"]) * mult))
	defense = int(round(float(base.get("guard", 5) + mods["guard"]) * mult))
	speed = int(round(float(base.get("speed", 5)) * mult))
	hp = max_hp
	ability_ids = CreatureData.creature_abilities(c)


func is_plant() -> bool:
	# Every wild creature in Game 1 is a plant. Revisit for Oni-class etc.
	return true


## Effective stats after temporary item modifiers (Ironwood Bark etc.).
func effective_attack() -> int:
	return int(round(float(attack) * float(temp_mods.get("atk_mult", 1.0))))


func effective_defense() -> int:
	return int(round(float(defense) * float(temp_mods.get("def_mult", 1.0))))


func effective_speed() -> int:
	return int(round(float(speed) * float(temp_mods.get("spd_mult", 1.0))))


## Heal up to `amount` HP (never overheals). Returns the actual HP restored.
func heal(amount: int) -> int:
	if fainted or amount <= 0:
		return 0
	var before := hp
	hp = mini(max_hp, hp + amount)
	return hp - before


## Remove any of the listed statuses. Returns how many were cured.
func cure_statuses(ids: Array) -> int:
	var cured := 0
	for sid in ids:
		if statuses.has(str(sid)):
			statuses.erase(str(sid))
			cured += 1
	return cured


## Direct unmitigated damage (Thorn Pod: fixed plant damage). Returns dealt.
func take_fixed_damage(amount: int) -> int:
	var dealt := maxi(1, amount)
	hp = maxi(0, hp - dealt)
	if hp <= 0:
		fainted = true
	return dealt


## End-of-turn status processing: WILT drains HP; all other statuses
## (spore_fever, rootbound) and item temp_mods count down.
func tick_statuses() -> void:
	if fainted:
		return
	var wilt_turns := int(statuses.get("wilt", 0))
	if wilt_turns > 0:
		var drain := maxi(1, int(round(float(max_hp) * WILT_DRAIN)))
		hp = maxi(0, hp - drain)
		if hp <= 0:
			fainted = true
		if wilt_turns - 1 <= 0:
			statuses.erase("wilt")
		else:
			statuses["wilt"] = wilt_turns - 1
	for sid in ["spore_fever", "rootbound", "evasion", "thermal", "burned", "intimidated"]:
		var t := int(statuses.get(sid, 0))
		if t > 0:
			if t - 1 <= 0:
				statuses.erase(sid)
			else:
				statuses[sid] = t - 1
	var mt := int(temp_mods.get("turns", 0))
	if mt > 0:
		if mt - 1 <= 0:
			temp_mods.clear()
		else:
			temp_mods["turns"] = mt - 1


func has_fire_resist() -> bool:
	CreatureData.ensure_loaded()
	var c: Dictionary = CreatureData.get_creature(creature_id)
	var traits: Dictionary = c.get("traits", {})
	for slot in traits:
		var t: Dictionary = CreatureData.get_trait(str(traits[slot]))
		if (t.get("tags", []) as Array).has("fire_resist"):
			return true
	return false


## Dev/test hook: grant an ability outside the creature's parts.
func teach_ability(ability_id: String) -> void:
	if not ability_ids.has(ability_id):
		ability_ids.append(ability_id)


func can_use(ability_id: String) -> bool:
	return ability_ids.has(ability_id)


## Use an ability against a target. Returns damage dealt, or -1 if unknown.
## Special behaviors (gorge heal, thermal_ride->dive, evasion, burn, etc.)
## are handled via CreatureAI. `ctx` carries battle context (e.g.
## "foe_last_ability" for Echo, "no_specials" to skip them in tests).
func use_ability(ability_id: String, target: RefCounted, ctx: Dictionary = {}) -> int:
	if fainted:
		return 0
	if not can_use(ability_id):
		return -1
	var ab: Dictionary = CreatureData.get_ability(ability_id)

	# Evasion check (thermal_ride / relocate / uphill_flight).
	if CreatureAI.check_evasion(target):
		return 0

	# Heal-element abilities (Gorge): restore HP, no damage.
	if str(ab.get("element", "physical")) == "heal":
		var frac := float(ab.get("heal_fraction", 0.25))
		heal(int(round(float(max_hp) * frac)))
		if not bool(ctx.get("no_specials", false)):
			CreatureAI.apply_special(self, target, ability_id, ctx)
		return 0

	# Zero-power abilities (Stillness, etc.) deal no damage.
	var power := float(ab.get("power", 1.0))
	if power <= 0.0:
		var special0 := str(ab.get("special", ""))
		if special0 != "" and not bool(ctx.get("no_specials", false)):
			CreatureAI.apply_special(self, target, ability_id, ctx)
		return 0

	var raw := float(effective_attack()) * power * mod_outgoing_mult
	var is_fire := str(ab.get("element", "physical")) == "fire"
	if is_fire and target.is_plant() and not target.has_fire_resist():
		raw *= FIRE_VS_PLANT
	# Dive consumes an active thermal for bonus damage.
	var special := str(ab.get("special", ""))
	if special == "dive" and statuses.has("thermal"):
		raw *= CreatureAI.DIVE_THERMAL_BONUS
		statuses.erase("thermal")
	var dealt: int = target.take_damage(raw, self)
	if is_fire and dealt > 0:
		CreatureAI.apply_burn(target)
	var status := str(ab.get("status", ""))
	if status != "" and not target.fainted:
		target.apply_status(status, int(ab.get("status_turns", 3)))
	# Drain siphons half the damage dealt back as HP.
	if special == "drain" and dealt > 0:
		heal(maxi(1, dealt / 2))
	# Other specials (scream buff, snap_shut, relocate evasion, etc.).
	if special != "" and not bool(ctx.get("no_specials", false)):
		CreatureAI.apply_special(self, target, ability_id, ctx)
	return dealt


func take_damage(raw_amount: float, _attacker: RefCounted) -> int:
	var soak := 0.0 if mod_no_armor else float(effective_defense()) * GUARD_MITIGATION
	var dealt := maxi(1, int(round(raw_amount * mod_incoming_mult - soak)))
	hp = maxi(0, hp - dealt)
	if hp <= 0:
		fainted = true
	return dealt


func apply_status(status_id: String, turns: int) -> void:
	statuses[status_id] = maxi(int(statuses.get(status_id, 0)), turns)
