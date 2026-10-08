extends RefCounted
## Grimley's Still — trait extraction (wiring, per story-bot spec 2026-10-05,
## /tmp/still-extraction.md).
##
## Model: 1 living creature (not an egg) + 1 empty mote vial + one in-game
## night cycle -> 1 trait mote (trait ledger, named after the source
## creature) + the creature alive minus the trait (permanent loss).
##
## Costs: trait gone permanently; trust debt 3 nights (no breed/fight/
## handle), Bond -1 tier, per-creature; vial 50 Soul Credits (Grimley) or
## crafted glass + Grave Petals. One creature per night (cooldown).
##
## Hard exclusions: Wrongness (Strange Animal) — the Still refuses, the
## glass cracks; heritage traits (7-generation) — locked; armor plant —
## not a creature, Grimley physically stops you.
##
## Mote = the universal trait currency (shared with Graft fusion and fairy
## motes). This module owns the mint/spend seam; the other two systems call
## into it rather than running their own mote books.
##
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (autoloads don't load there).
##   const Still = preload("res://scripts/still.gd")
##
## Mutable state lives in GameState and is passed in as `gs` — the module
## itself holds no mutable state (same pattern as party.gd).
##
## DESIGN DECISIONS (wiring — flagged, not hidden):
##   - Time source: there is no in-game clock yet. The Still counts nights
##     in state["still"]["nights"], advanced by on_day_advance(), which the
##     shrine rest wires next to Breeding.on_day_advance (the established
##     day-boundary pattern). Extraction starts on night N and completes on
##     the next boundary tick — "takes one in-game night cycle".
##   - There was no trait ledger in the codebase (verified 2026-10-05):
##     fabricator keeps learned traits, breeding keeps traits on entries.
##     state["still"]["motes"] IS the trait ledger of record for motes.
##     The mote dict's "name" field ("Mote of <source>") is a wiring choice
##     — flagged for the story bot to rename (see FIELD MAPPING below).
##   - No bond system exists yet. bond_tier defaults to 2 [TUNING]; the
##     Still is the first writer of entry["bond_tier"].
##   - Wrongness detection is defensive (trait id/name containing
##     "wrongness", or an entry-level "wrongness" flag) — no Wrongness
##     trait id exists in data/traits.json yet. Flagged.
##   - Heritage check = "heritage" in the trait's tags (none exist in data
##     yet). Flagged: data dependency on the story bot.
##   - Vial crafting recipe {"glass_shard": 1, "grave_petals": 2} is
##     [TUNING]; all three items (glass_shard, grave_petals, empty_mote_vial)
##     live in data/items.json as of 2026-10-05 (story-bot call, 03:36 email).
##     buy_vial() works today via Soul Credits (price = VIAL_COST, [TUNING]).
##   - Eggs never reach the Still: eggs live in state["nursery"], not on
##     party/storage entries. can_extract() also rejects entry dicts that
##     carry an "egg_id" key, defensively.
##   - Extraction permanence DECIDED by the story bot (2026-10-05 03:19
##     email): the specimen stays ALIVE; only the trait is permanently
##     lost (slot -> "bare"), with trust debt 3 nights and Bond -1 tier.
##     Locked by the first-use scene ("It'll rest. Give it three days."
##     / "It'll forgive you. Eventually."). Whole-creature loss is NOT
##     modeled — the story bot's earlier "give up the specimen" phrasing
##     was corrected to the trait-and-trust trade, not the life.
##   - Deep Garden second Still (post-game): faster cadence (one per day),
##     same trust debt. Flagged variant, not live (needs the post-game
##     flag "deep_garden_still" + its room).
##   - Spec vs email discrepancy RESOLVED by the story bot (2026-10-05
##     03:19 email): the Still is one machine, in the Hearthollow
##     workroom, available when Hearthollow opens. The "home base after
##     Act 1" and "Ch8 workroom" phrasings describe the same unlock, and
##     the Still does not travel. The hearthollow_unlocked flag and the
##     Ch8 workroom hook stub already model exactly that — no change.
##
## [HOOK: HEARTHOLLOW WORKROOM — Ch8, does not exist yet]
## When the Hearthollow workroom room script lands, its Still interactable
## calls Still.room_hook(gs) and pages Still.first_use_scene() on the first
## visit. After the first use, the Still is menu-driven (no scene).

const CreatureData = preload("res://scripts/creature_data.gd")
const Breeding = preload("res://scripts/breeding.gd")
const Party = preload("res://scripts/party.gd")
const Storage = preload("res://scripts/storage.gd")

## --- Tuning (wiring placeholders, story bot can retune) -----------------
const TRUST_DEBT_NIGHTS := 3   # spec: 3 in-game days of rest
const BOND_TIER_DROP := 1      # spec: Bond -1 tier
const BOND_TIER_DEFAULT := 2   # [TUNING] no bond system exists yet
const BOND_TIER_MIN := 0
const VIAL_COST := 50          # Soul Credits per empty vial (Grimley)
const EMPTY_VIAL_ITEM := "empty_mote_vial"
## [TUNING] vial craft recipe; items authored in data/items.json 2026-10-05
## (prices still unset — story bot, no economy call).
const VIAL_RECIPE := {"glass_shard": 1, "grave_petals": 2}

const ARMOR_PLANT_ID := "armor_plant"  # == Breeding.ARMOR_PLANT_ID
const WRONGNESS_TRAIT_ID := "wrongness"
const HERITAGE_TAG := "heritage"

## Save flags.
const UNLOCK_FLAG := "hearthollow_unlocked"   # Still is usable from here
const DEEP_GARDEN_FLAG := "deep_garden_still" # post-game second Still

## --- Grimley lines ------------------------------------------------------
## Story-bot verbatim (spec doc 2026-10-05). Re-cut freely — never reworded
## by wiring.
const WRONGNESS_REFUSAL := "Some things don't come out. They are the thing."
const WRONGNESS_BEAT := "[The glass cracks. Grimley steps back. He won't try twice.]"
## Heritage refusal — story-lane canon (Sweet Potato Creature, 2026-10-05).
## Re-cut by story bot only; wiring must not paraphrase.
const HERITAGE_BEAT := "[Grimley holds your hand back.]"
const HERITAGE_REFUSAL := "\"That one is in the blood. Seven generations deep. The Still takes what is learned, not what is inherited.\""
## Armor-plant refusal — story-lane canon (Sweet Potato Creature, 2026-10-05).
## Re-cut by story bot only; wiring must not paraphrase.
const ARMOR_PLANT_BEAT := "[Grimley steps in, physical stop.]"
const ARMOR_PLANT_REFUSAL := "\"Don't. That is not a creature. Put it down before it decides for you.\""
const GRIMLEY_ASIDE := "It'll forgive you. Eventually. They always do. That's the worst part."

## First-use scene — story-bot verbatim (spec doc 2026-10-05). Paged once
## by the Hearthollow workroom interact; afterwards the Still is a menu.
const FIRST_USE_SCENE := [
	{"type": "direction", "text": "[Grimley loads the creature. It doesn't struggle — it trusts him. That's what makes it hard to watch.]"},
	{"type": "dialogue", "character": "GRIMLEY", "text": "Last chance. Once it's out, it's out."},
	{"type": "dialogue", "character": "MOLLOSAR", "text": "..."},
	{"type": "direction", "text": "[quietly]"},
	{"type": "dialogue", "character": "GRIMLEY", "text": "...Yeah. That's what they all say."},
	{"type": "direction", "text": "[He pulls the lever.]"},
	{"type": "direction", "text": "[The trait draws out as light, condenses into the mote. The creature shudders — then settles. It looks at Mollosar. It doesn't look away. That's worse.]"},
	{"type": "dialogue", "character": "GRIMLEY", "text": "It'll rest. Give it three days. And little reaper — don't waste it. It cost more than you think."},
]


## --- State ---------------------------------------------------------------

## The Still's save block (created lazy; old saves work).
##   {"nights": int, "last_night_used": int, "motes": [...],
##    "mote_seq": int, "first_use_done": bool}
static func _still(gs) -> Dictionary:
	var blank := {
		"nights": 0, "last_night_used": -1, "motes": [],
		"mote_seq": 0, "first_use_done": false,
	}
	if gs == null or gs.get("state") == null:
		return blank
	var st: Dictionary = gs.get("state")
	if not st.has("still") or not (st["still"] is Dictionary):
		st["still"] = blank.duplicate(true)
	var s: Dictionary = st["still"]
	for k in blank:
		if not s.has(k):
			s[k] = blank[k] if not (blank[k] is Array) else []
	return s


static func nights(gs) -> int:
	return int(_still(gs).get("nights", 0))


static func is_unlocked(gs) -> bool:
	return gs != null and bool(gs.get_flag(UNLOCK_FLAG))


static func can_use_deep_garden(gs) -> bool:
	return gs != null and bool(gs.get_flag(DEEP_GARDEN_FLAG))


## --- Mote ledger (universal trait currency) ------------------------------
## Mote dict:
##   {"mote_id": "mote_<n>", "trait_id": id, "trait_name": name,
##    "name": "Mote of <source creature name>",   <- FLAGGED: story bot to
##        rename (see header). "named after the source creature" per spec.
##    "source": "still" | "graft" | "fairy", "night": n}
## Graft fusion and fairy motes share this ledger via grant_mote/spend_mote.

static func motes(gs) -> Array:
	return _still(gs).get("motes", [])


static func mote_balance(gs) -> int:
	return motes(gs).size()


## Mint a mote into the ledger. source_name should be the source creature's
## display name (nickname or species name) — "named after the source
## creature" per spec. provenance: "still" | "graft" | "fairy".
static func grant_mote(gs, trait_id: String, source_name: String, provenance: String) -> Dictionary:
	var s := _still(gs)
	s["mote_seq"] = int(s.get("mote_seq", 0)) + 1
	var t: Dictionary = CreatureData.get_trait(trait_id)
	var mote := {
		"mote_id": "mote_%d" % int(s["mote_seq"]),
		"trait_id": trait_id,
		"trait_name": str(t.get("name", trait_id)),
		"name": "Mote of %s" % source_name,
		"source": provenance,
		"night": nights(gs),
	}
	(motes(gs) as Array).append(mote)
	return mote


## Spend (remove) a mote by id. False when the id isn't in the ledger.
static func spend_mote(gs, mote_id: String) -> bool:
	var ms: Array = motes(gs)
	for i in ms.size():
		if str((ms[i] as Dictionary).get("mote_id", "")) == mote_id:
			ms.remove_at(i)
			return true
	return false


## --- Vials ----------------------------------------------------------------

static func empty_vials(gs) -> int:
	return 0 if gs == null else gs.get_item_count(EMPTY_VIAL_ITEM)


## Buy an empty vial from Grimley for 50 Soul Credits.
static func buy_vial(gs) -> Dictionary:
	if gs == null:
		return {"ok": false, "msg": "No game state."}
	if not gs.spend_soul_credits(VIAL_COST):
		return {"ok": false, "msg": "Not enough Soul Credits for a vial."}
	gs.add_item(EMPTY_VIAL_ITEM, 1)
	return {"ok": true, "msg": "Grimley hands over an empty mote vial."}


## Craft an empty vial from glass + Grave Petals. [TUNING] recipe; item
## entries now live in data/items.json (prices unset, story-bot owned).
static func craft_vial(gs) -> Dictionary:
	if gs == null:
		return {"ok": false, "msg": "No game state."}
	for item_id in VIAL_RECIPE:
		if gs.get_item_count(item_id) < int(VIAL_RECIPE[item_id]):
			return {"ok": false, "msg": "Need glass and Grave Petals to blow a vial."}
	for item_id in VIAL_RECIPE:
		for i in int(VIAL_RECIPE[item_id]):
			gs.use_item(item_id)
	gs.add_item(EMPTY_VIAL_ITEM, 1)
	return {"ok": true, "msg": "A fresh mote vial, blown and cooled."}


## --- Creature helpers ------------------------------------------------------

## Display name: nickname, else species name, else the raw id.
static func display_name(entry: Dictionary) -> String:
	var nick := str(entry.get("nickname", ""))
	if nick != "":
		return nick
	var c: Dictionary = CreatureData.get_creature(str(entry.get("creature_id", "")))
	return str(c.get("name", entry.get("creature_id", "creature")))


static func bond_tier(entry: Dictionary) -> int:
	return int(entry.get("bond_tier", BOND_TIER_DEFAULT))


## Nights of trust debt remaining. > 0: the creature cannot breed, fight,
## or be handled.
static func trust_debt(entry: Dictionary) -> int:
	return int(entry.get("trust_debt", 0))


## Breed/fight/handle gate: false while the creature owes trust debt or an
## extraction is still condensing. Breeding, battle, and party-handling
## call this when their gates land.
static func can_act(entry: Dictionary) -> bool:
	return trust_debt(entry) <= 0 and not entry.has("still_pending")


static func _is_armor_plant(entry: Dictionary) -> bool:
	return str(entry.get("creature_id", "")) == ARMOR_PLANT_ID


## Wrongness (Strange Animal): trait id/name containing "wrongness", or an
## entry-level "wrongness" flag. Defensive — no Wrongness trait id exists
## in data/traits.json yet (flagged data dependency).
static func _trait_is_wrongness(trait_id: String) -> bool:
	if trait_id == WRONGNESS_TRAIT_ID:
		return true
	var t: Dictionary = CreatureData.get_trait(trait_id)
	if str(t.get("name", "")).to_lower().contains("wrongness"):
		return true
	return false


static func _entry_is_wrongness(entry: Dictionary) -> bool:
	if bool(entry.get("wrongness", false)):
		return true
	for slot in Breeding.effective_traits(entry):
		if _trait_is_wrongness(str(Breeding.effective_traits(entry)[slot])):
			return true
	return false


## Heritage traits (7-generation): locked to the bloodline. Identified by
## the "heritage" tag on the trait — none exist in data yet (flagged).
static func _trait_is_heritage(trait_id: String) -> bool:
	var t: Dictionary = CreatureData.get_trait(trait_id)
	return HERITAGE_TAG in t.get("tags", [])


## Slots the Still UI can offer for this creature: expressed (non-"bare")
## traits that aren't hard exclusions. Wrongness/heritage slots are greys
## the UI greys out with the refusal lines (see can_extract).
static func extractable_slots(entry: Dictionary) -> Array:
	var out: Array = []
	for slot in Breeding.effective_traits(entry):
		var tid := str(Breeding.effective_traits(entry)[slot])
		if tid == "" or tid == "bare":
			continue
		if _trait_is_wrongness(tid) or _trait_is_heritage(tid):
			continue
		out.append({"slot": str(slot), "trait_id": tid})
	return out


## --- Validation ------------------------------------------------------------

## Full validation for putting `entry`'s `slot` trait in the Still.
## Returns {"ok": bool, "msg": str, "trait_id": str}.
## variant: "still" | "deep_garden" (post-game flagged variant).
static func can_extract(gs, entry: Dictionary, slot: String, variant: String = "still") -> Dictionary:
	var fail := func(m: String) -> Dictionary: return {"ok": false, "msg": m, "trait_id": ""}
	if not is_unlocked(gs):
		return fail.call("The Still isn't available yet.")
	if entry.is_empty() or str(entry.get("creature_id", "")) == "":
		return fail.call("No creature selected.")
	if entry.has("egg_id"):
		return fail.call("Eggs don't go in the Still.")
	# Hard exclusion: the armor plant is not a creature. Grimley stops you.
	if _is_armor_plant(entry):
		return fail.call(ARMOR_PLANT_BEAT + "\n" + ARMOR_PLANT_REFUSAL)
	# Hard exclusion: Wrongness. The Still refuses; the glass cracks.
	if _entry_is_wrongness(entry):
		return fail.call(WRONGNESS_REFUSAL + "\n" + WRONGNESS_BEAT)
	var traits: Dictionary = Breeding.effective_traits(entry)
	if not traits.has(slot):
		return fail.call("That creature has no such trait.")
	var tid := str(traits[slot])
	if tid == "" or tid == "bare":
		return fail.call("Nothing left to extract there.")
	# Hard exclusion: heritage traits are locked to the bloodline.
	if _trait_is_heritage(tid):
		return fail.call(HERITAGE_BEAT + "\n" + HERITAGE_REFUSAL)
	if trust_debt(entry) > 0:
		return fail.call("%s is still resting. Give it time." % display_name(entry))
	if entry.has("still_pending"):
		return fail.call("The Still is already working on %s." % display_name(entry))
	if empty_vials(gs) < 1:
		return fail.call("You need an empty mote vial.")
	var s := _still(gs)
	if variant == "deep_garden":
		if not can_use_deep_garden(gs):
			return fail.call("The Deep Garden Still isn't yours yet.")
		# Faster cadence: one at a time, no per-night start limit. Same
		# trust debt. (Flagged post-game variant — not live.)
	else:
		# One creature per night.
		if int(s.get("last_night_used", -1)) >= nights(gs):
			return fail.call("The Still has already run tonight.")
	return {"ok": true, "msg": "", "trait_id": tid}


## Start an extraction: consumes one empty vial, stages the pending
## extraction (it completes on the next night boundary). Returns
## {"ok", "msg", "first_use"} — first_use true means the Hearthollow
## workroom should page FIRST_USE_SCENE before the menu.
static func start_extraction(gs, entry: Dictionary, slot: String, variant: String = "still") -> Dictionary:
	var check := can_extract(gs, entry, slot, variant)
	if not bool(check.get("ok", false)):
		check["first_use"] = false
		return check
	gs.use_item(EMPTY_VIAL_ITEM)
	entry["still_pending"] = {
		"trait_id": str(check["trait_id"]), "slot": slot, "variant": variant,
	}
	_still(gs)["last_night_used"] = nights(gs)
	var s := _still(gs)
	var first := not bool(s.get("first_use_done", false))
	s["first_use_done"] = true
	return {"ok": true, "msg": "Grimley loads %s into the Still." % display_name(entry),
		"trait_id": str(check["trait_id"]), "first_use": first}


## Night boundary (called from the shrine rest's day-boundary flow, next to
## Breeding.on_day_advance): complete pending extractions, tick trust debt.
static func on_day_advance(gs) -> void:
	if gs == null:
		return
	var s := _still(gs)
	s["nights"] = int(s.get("nights", 0)) + 1
	var just_completed: Array = []
	for entry in _all_entries(gs):
		var e: Dictionary = entry
		if e.has("still_pending"):
			_complete_extraction(gs, e)
			just_completed.append(e)
	# Trust debt ticks for everyone except creatures whose extraction just
	# completed — their 3 nights of rest start now.
	for entry in _all_entries(gs):
		var e: Dictionary = entry
		if int(e.get("trust_debt", 0)) > 0 and not just_completed.has(e):
			e["trust_debt"] = int(e.get("trust_debt", 0)) - 1


## Complete one pending extraction: trait leaves the creature permanently,
## the mote lands in the ledger named after the source creature, trust debt
## and the Bond hit land on the creature.
static func _complete_extraction(gs, entry: Dictionary) -> void:
	var pending: Dictionary = entry.get("still_pending", {})
	var tid := str(pending.get("trait_id", ""))
	var slot := str(pending.get("slot", ""))
	entry.erase("still_pending")
	# Permanent loss: the slot goes "bare" (breeding's empty-slot id).
	var traits: Dictionary = Breeding.effective_traits(entry).duplicate()
	if slot != "" and traits.has(slot):
		traits[slot] = "bare"
	entry["traits_override"] = traits
	grant_mote(gs, tid, display_name(entry), "still")
	entry["trust_debt"] = TRUST_DEBT_NIGHTS
	entry["bond_tier"] = maxi(BOND_TIER_MIN, bond_tier(entry) - BOND_TIER_DROP)


## Every creature entry the Still can see: party + Soul Vault boxes.
static func _all_entries(gs) -> Array:
	var out: Array = []
	for e in Party._party(gs):
		out.append(e)
	var boxes: Array = Storage._storage(gs)
	for b in boxes:
		if b is Array:
			for e in b:
				out.append(e)
	return out


## --- Room hook (stub) -------------------------------------------------------
## [HOOK: HEARTHOLLOW WORKROOM — Ch8, does not exist yet]
## The workroom's Still interactable calls this. Returns the menu state the
## room UI pages: whether the first-use scene should play, the motes, the
## cooldown, and the vial count.
static func room_hook(gs) -> Dictionary:
	return {
		"unlocked": is_unlocked(gs),
		"first_use": not bool(_still(gs).get("first_use_done", false)),
		"motes": motes(gs),
		"night": nights(gs),
		"can_run_tonight": int(_still(gs).get("last_night_used", -1)) < nights(gs),
		"empty_vials": empty_vials(gs),
		"scene": FIRST_USE_SCENE,
	}


static func first_use_scene() -> Array:
	return FIRST_USE_SCENE
