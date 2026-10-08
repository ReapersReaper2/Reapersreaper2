extends RefCounted
## Armor accumulator for Reaper's Reaper.
##
## Reads DonorSpecies + Slot per grown part DIRECTLY from the creature
## instance record (the party entry's "part_donors" map:
##   {slot: {"species": donor_species_id, "part_id": trait_id}}).
## Entries without "part_donors" (wild-caught/legacy) are treated as
## self-donated: the entry's own species is the DonorSpecies for every slot.
## An assimilated metal plant's RESOLVED form traits (scripts/assimilation.gd)
## take precedence for slots the form defines, and the form's guard_bonus is
## folded into the total and the plant's donor line.
##
## accumulate() returns:
##   {"total_guard": int,                          # summed guard_mod
##    "by_donor": {species_id: guard, ...},        # armor per donor species
##    "by_slot": {slot: guard, ...}}               # armor per slot
## Only grown (non-"bare") parts contribute.
##
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (autoloads don't load there).
##   const ArmorAccumulator = preload("res://scripts/armor_accumulator.gd")

const CreatureData = preload("res://scripts/creature_data.gd")
const Breeding = preload("res://scripts/breeding.gd")
const Assimilation = preload("res://scripts/assimilation.gd")


## Donor record for one slot: {"species": species_id, "part_id": trait_id}.
## An assimilated metal plant's RESOLVED form traits take precedence for
## slots the form defines (locked design: the armor accumulator reads form
## traits). Falls back to {own species, effective trait} when the entry
## carries no provenance for the slot.
static func donor_of(entry: Dictionary, slot: String) -> Dictionary:
	var form_traits := Assimilation.form_traits_of(entry)
	if form_traits.has(slot):
		return {"species": Assimilation.SPECIES_ID, "part_id": str(form_traits[slot])}
	var donors: Dictionary = entry.get("part_donors", {})
	if donors.has(slot):
		var d: Dictionary = donors[slot]
		return {"species": str(d.get("species", "")), "part_id": str(d.get("part_id", "bare"))}
	var traits := Breeding.effective_traits(entry)
	return {
		"species": str(entry.get("creature_id", "")),
		"part_id": str(traits.get(slot, "bare")),
	}


## Sum guard contributions of all grown parts, keyed by donor species and
## by slot. Reads DonorSpecies + Slot from the instance record only.
## An assimilated metal plant also adds its RESOLVED form's guard_bonus
## (from the assimilation form table) to the total and its donor line.
static func accumulate(entry: Dictionary) -> Dictionary:
	CreatureData.ensure_loaded()
	var total := 0
	var by_donor := {}
	var by_slot := {}
	for slot in Breeding.SLOTS:
		var donor := donor_of(entry, slot)
		var part_id := str(donor["part_id"])
		if part_id == "bare":
			continue
		var guard := int(CreatureData.get_trait(part_id).get("guard_mod", 0))
		if guard == 0:
			continue
		total += guard
		var sp := str(donor["species"])
		by_donor[sp] = int(by_donor.get(sp, 0)) + guard
		by_slot[slot] = int(by_slot.get(slot, 0)) + guard
	var form_traits := Assimilation.form_traits_of(entry)
	if not form_traits.is_empty():
		var form := Assimilation.resolve_form(
			str(entry.get("creature_id", "")),
			str(entry.get(Assimilation.KEY_METAL, "")),
			str(entry.get(Assimilation.KEY_HOST, "")))
		var bonus := int(form.get("guard_bonus", 0))
		if bonus != 0:
			total += bonus
			var sp2 := Assimilation.SPECIES_ID
			by_donor[sp2] = int(by_donor.get(sp2, 0)) + bonus
	return {"total_guard": total, "by_donor": by_donor, "by_slot": by_slot}
