extends RefCounted
## Assimilation form table for the metal plant (wiring).
##
## LOCKED DESIGN (Sweet Potato Creature, confirmed):
##   - One SpeciesID for the metal plant: "armor_plant"
##     (== breeding.gd's ARMOR_PLANT_ID). Forms are a FUNCTION OF THE
##     ASSIMILATED METAL — never separate species, never separate
##     creature lines.
##   - The form table (FORM_TABLE) is keyed by metal id; each metal entry
##     may carry per-host overrides in "hosts", keyed by host id.
##   - The breeding model is UNCHANGED: breeding produces the plant (the
##     base species id, unassimilated); assimilation is a GROWTH-TIME
##     event that happens after the plant exists. The armor variants it
##     unlocks are growth-only per-playthrough config and are NEVER
##     heritable — entry-level keys "assimilated_metal" /
##     "assimilation_host" never enter breeding snapshots (breeding.gd's
##     _snapshot() copies creature_id / traits / genes / base only), so
##     offspring always hatch as the plain plant. Only the metal line
##     (the plant species itself) breeds true.
##   - The armor accumulator (scripts/armor_accumulator.gd) reads the
##     RESOLVED form traits via form_traits_of().
##
## Metal ids and form contents are STORY-BOT OWNED data: extend
## FORM_TABLE with their metals (material ids from data/items.json).
## This script only resolves.
##
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (autoloads don't load there).
##   const Assimilation = preload("res://scripts/assimilation.gd")

## The one SpeciesID for the metal plant. Must stay == Breeding.ARMOR_PLANT_ID
## ("armor_plant"); breeding.gd stays unchanged, so this is a literal with
## the invariant pinned by assimilation_test.gd.
const SPECIES_ID := "armor_plant"

## Growth-record keys on a party entry (entry-level, never snapshotted).
const KEY_METAL := "assimilated_metal"
const KEY_HOST := "assimilation_host"

## Form table keyed by metal id. A form record:
##   {"form_id": String, "metal": metal_id, "traits": {slot: trait_id},
##    "guard_bonus": int, "hosts": {host_id: {form_id, traits, guard_bonus}}}
## Trait ids must exist in data/traits.json (their guard_mod is what the
## armor accumulator sums). Story-bot owned rows — wiring only resolves.
const FORM_TABLE := {
	"iron_beam": {
		"form_id": "assim_iron_beam",
		"metal": "iron_beam",
		"traits": {"armor": "ironwood_plates", "stem": "ironwood_trunk"},
		"guard_bonus": 1,
		"hosts": {
			"mollosar": {
				"form_id": "assim_iron_beam_mollosar",
				"traits": {"armor": "ironwood_plates", "stem": "ironwood_trunk", "appendage": "bark_plates"},
				"guard_bonus": 2,
			},
		},
	},
	"silvered_ore": {
		"form_id": "assim_silvered_ore",
		"metal": "silvered_ore",
		"traits": {"armor": "soot_plates", "stem": "woody_trunk"},
		"guard_bonus": 0,
		"hosts": {},
	},
	## [STORY-BOT OWNED / PROVISIONAL] Third seeded metal, per Sweet
	## Potato Creature's spec (00:49 EDT): dragon_gold — golden-dragon
	## gold, the metal of the Twins, the only metal that chambers
	## soul-flame without cracking. Discovery-tier, NOT an early seed;
	## late-game rarity. Trait ids and guard_bonus are provisional;
	## the story bot's balance pass re-weights. The Widowblade's dark
	## leaf-metal stays story-only and NEVER seeds here.
	"dragon_gold": {
		"form_id": "assim_dragon_gold",
		"metal": "dragon_gold",
		"traits": {"armor": "soot_plates", "bloom": "ember_crown", "stem": "gnarled_trunk"},
		"guard_bonus": 2,
		"hosts": {},
	},
}


## Resolve the form for a species + assimilated metal + host. Returns the
## form record (with the host override merged in when one exists), or {}
## when the species is not the metal plant or the metal is unknown.
static func resolve_form(species: String, assimilated_metal: String, host: String = "") -> Dictionary:
	if species != SPECIES_ID:
		return {}
	if not FORM_TABLE.has(assimilated_metal):
		return {}
	var row: Dictionary = (FORM_TABLE[assimilated_metal] as Dictionary).duplicate(true)
	var hosts: Dictionary = row.get("hosts", {})
	if host != "" and hosts.has(host):
		var ov: Dictionary = hosts[host]
		var merged: Dictionary = row.duplicate(true)
		merged["form_id"] = str(ov.get("form_id", row.get("form_id", "")))
		merged["traits"] = (ov.get("traits", {}) as Dictionary).duplicate(true)
		merged["guard_bonus"] = int(ov.get("guard_bonus", 0))
		merged["host"] = host
		merged.erase("hosts")
		return merged
	row["host"] = host
	row.erase("hosts")
	return row


## True when the party entry carries an assimilation growth record.
static func is_assimilated(entry: Dictionary) -> bool:
	return str(entry.get(KEY_METAL, "")) != ""


## Resolved form traits for a party entry ({slot: trait_id}), or {} when
## the entry is not an assimilated metal plant. This is what the armor
## accumulator reads.
static func form_traits_of(entry: Dictionary) -> Dictionary:
	if str(entry.get("creature_id", "")) != SPECIES_ID:
		return {}
	var metal := str(entry.get(KEY_METAL, ""))
	if metal == "":
		return {}
	var form := resolve_form(SPECIES_ID, metal, str(entry.get(KEY_HOST, "")))
	return (form.get("traits", {}) as Dictionary).duplicate(true)


## Growth-time assimilation event: the plant assimilates a metal. Records
## growth-only keys on the entry (never heritable). Returns
## {"ok": bool, "form_id": String}. Re-assimilating the same metal is a
## no-op; unknown metals are refused.
static func assimilate(entry: Dictionary, metal_id: String, host: String = "") -> Dictionary:
	if str(entry.get("creature_id", "")) != SPECIES_ID:
		return {"ok": false, "form_id": ""}
	var form := resolve_form(SPECIES_ID, metal_id, host)
	if form.is_empty():
		return {"ok": false, "form_id": ""}
	entry[KEY_METAL] = metal_id
	entry[KEY_HOST] = host
	return {"ok": true, "form_id": str(form.get("form_id", ""))}


## Metal ids currently in the form table.
static func metal_ids() -> Array:
	return FORM_TABLE.keys()
