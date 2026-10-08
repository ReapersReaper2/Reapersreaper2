extends RefCounted
## Living Fabricator — the metal/plant grafting system (Grove, room_g1).
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Static manager; game code passes the GameState node in (merchants.gd
## pattern). Canon: the six locked grafts (story bot, 03b §20; Grove
## tutorial + Journal flavor on Drive). Grafts are permanent — no ungraft.
##
## State in state["fabricator"] (lazy — old saves work):
##   {"learned": [trait_ids], "grafts": {"weapon": trait|null,
##    "armor": [trait|null, trait|null]}}
## Slots: weapon 1, armor 2. Utility (key-form), world (bridge), and quest
## (prosthetic) traits are one-shot applications, not slots: applying them
## consumes the learned trait (feed again to regrow).
##
## All flavor text is [WIRING] wiring-written, flagged for story-bot revision.

## trait_id -> {name, slot, feed (item_id), effect, desc}.
## slot: "weapon" | "armor" | "utility" | "world" | "quest".
const TRAITS := {
	"thorn": {
		"name": "Thorn Graft", "slot": "armor", "feed": "briar_thorns",
		"effect": "retaliation",
		"desc": "[WIRING] Thorns woven into the armor bite back: attackers take 1 damage when they hit you.",
	},
	"cinder": {
		"name": "Cinder Bark", "slot": "armor", "feed": "ash_bark",
		"effect": "fire_resist",
		"desc": "[WIRING] Ash-adapted bark. Fire and ash damage reduced.",
	},
	"blade": {
		"name": "Blade Regrowth", "slot": "weapon", "feed": "broken_sword",
		"effect": "living_blade",
		"desc": "[WIRING] The plant grows the broken sword back — living metal, stronger than the original, and it remembers.",
	},
	"keyform": {
		"name": "Key-Form", "slot": "utility", "feed": "rusted_key",
		"effect": "replica_key",
		"desc": "[WIRING] Grow a one-use replica key. Opens one locked door, then it's just metal again.",
	},
	"bridge": {
		"name": "Bridge Supports", "slot": "world", "feed": "iron_beam",
		"effect": "repair_crossing",
		"desc": "[WIRING] Living-metal supports, grown to order. Repairs the broken crossing on the Ashen Peak path.",
	},
	"prosthetic": {
		"name": "Prosthetic", "slot": "quest", "feed": "silvered_ore",
		"effect": "prosthetic_arm",
		"desc": "[WIRING] A living-metal arm, grown for someone who lost one. (The story beat comes later.)",
	},
}

## Feedstock: item_id -> trait_id it teaches. Curated list only — anything
## else gets the in-fiction refusal (hum / reject / spit-back).
const FEEDSTOCK := {
	"briar_thorns": "thorn",
	"ash_bark": "cinder",
	"broken_sword": "blade",
	"rusted_key": "keyform",
	"iron_beam": "bridge",
	"silvered_ore": "prosthetic",
}

## In-fiction refusals for non-curated feeds (Grove tutorial beat: hum =
## thinking, silence = no, spat metal = ruder no). [WIRING], story-bot owns.
const REFUSALS := [
	"[WIRING] The plant hums, considering. Then, politely: no.",
	"[WIRING] Silence. The plant has opinions and this is one of them.",
	"[WIRING] The plant spits the offering back as living-metal feedstock. Rude. Final.",
]

const THORN_RETAIL := 1      # retaliation damage dealt to attackers
const CINDER_REDUCTION := 1  # fire/ash damage reduced by this much
const ARMOR_SLOTS := 2


static func trait_ids() -> Array:
	return TRAITS.keys()


static func trait_name(tid: String) -> String:
	return str(TRAITS.get(tid, {}).get("name", tid))


static func trait_desc(tid: String) -> String:
	return str(TRAITS.get(tid, {}).get("desc", ""))


static func trait_slot(tid: String) -> String:
	return str(TRAITS.get(tid, {}).get("slot", ""))


static func feedstock_for(trait_id: String) -> String:
	return str(TRAITS.get(trait_id, {}).get("feed", ""))


static func _data(gs) -> Dictionary:
	var blank := {"learned": [], "grafts": {"weapon": null, "armor": [null, null]}}
	if gs == null or gs.get("state") == null:
		return blank
	var st: Dictionary = gs.get("state")
	if not st.has("fabricator") or not (st["fabricator"] is Dictionary):
		st["fabricator"] = {"learned": [], "grafts": {"weapon": null, "armor": [null, null]}}
	var d: Dictionary = st["fabricator"]
	if not d.has("learned"):
		d["learned"] = []
	if not d.has("grafts") or not (d["grafts"] is Dictionary):
		d["grafts"] = {"weapon": null, "armor": [null, null]}
	return d


static func learned(gs) -> Array:
	return (_data(gs).get("learned", []) as Array).duplicate()


static func is_learned(gs, trait_id: String) -> bool:
	return (_data(gs).get("learned", []) as Array).has(trait_id)


## Feed an item to the plant. Consumes 1 of the item. Returns
## {"ok": bool, "trait": id|"", "msg": String}.
static func learn(gs, item_id: String) -> Dictionary:
	if gs == null:
		return {"ok": false, "trait": "", "msg": "[WIRING] No plant here."}
	var trait_id := str(FEEDSTOCK.get(item_id, ""))
	if trait_id == "":
		return {"ok": false, "trait": "", "msg": _refusal(item_id)}
	if not gs.use_item(item_id):
		return {"ok": false, "trait": "", "msg": "[WIRING] You don't have one to feed."}
	var d := _data(gs)
	var have: Array = d["learned"]
	if not have.has(trait_id):
		have.append(trait_id)
	return {"ok": true, "trait": trait_id,
		"msg": "[WIRING] The plant takes it. Something new is growing: %s." % trait_name(trait_id)}


static func _refusal(item_id: String) -> String:
	var h := 0
	for c in item_id:
		h = (h * 31 + c.unicode_at(0)) % 997
	return REFUSALS[h % REFUSALS.size()]


## Graft (or apply) a learned trait. Weapon/armor grafts are permanent;
## utility/world/quest traits are one-shot applications that consume the
## learned trait. Returns {"ok": bool, "msg": String}.
## Successful grafts fire the "first_graft" achievement beat.
## Trigger map: graft_completed counter, fire on count == 1.
static func _graft_ok(gs, msg: String) -> Dictionary:
	if gs != null and gs.has_method("unlock_achievement"):
		var n := 1
		if gs.has_method("bump_counter"):
			n = int(gs.bump_counter("graft_completed"))
		if n == 1:
			gs.unlock_achievement("first_graft")
	return {"ok": true, "msg": msg}


static func graft(gs, trait_id: String) -> Dictionary:
	if gs == null:
		return {"ok": false, "msg": "[WIRING] No plant here."}
	if not TRAITS.has(trait_id):
		return {"ok": false, "msg": "[WIRING] The plant doesn't know that shape."}
	if not is_learned(gs, trait_id):
		return {"ok": false, "msg": "[WIRING] Feed the plant %s first." % feedstock_for(trait_id)}
	var slot := trait_slot(trait_id)
	var d := _data(gs)
	var grafts: Dictionary = d["grafts"]
	match slot:
		"weapon":
			if grafts.get("weapon") != null:
				return {"ok": false, "msg": "[WIRING] The weapon is already grafted. Grafts are permanent."}
			grafts["weapon"] = trait_id
			# Steam "It Remembers" (blade_regrown; story-bot answers
			# 2026-10-04): fire on blade-regrowth graft completion. The
			# weapon slot accepts exactly one graft ever, so the first
			# completion is the only completion — no blade-state check
			# needed (matches the story-bot fallback).
			if trait_id == "blade" and gs.has_method("unlock_achievement"):
				gs.unlock_achievement("blade_regrown")
			return _graft_ok(gs, "[WIRING] The blade takes the graft. Living metal hums along its edge.")
		"armor":
			var slots: Array = grafts.get("armor", [null, null])
			for i in slots.size():
				if slots[i] == null:
					slots[i] = trait_id
					grafts["armor"] = slots
					return _graft_ok(gs, "[WIRING] The armor accepts the graft. It settles like it was always there.")
			return {"ok": false, "msg": "[WIRING] The armor is full — two grafts, no more. (\"More than that and it gets distracted.\")"}
		"utility":
			# Key-form: grow a one-use replica key.
			_consume_learned(d, trait_id)
			gs.add_item("living_key", 1)
			return _graft_ok(gs, "[WIRING] The plant grows a key. It won't last — use it on a locked door.")
		"world":
			# Bridge supports: repair the Ashen Peak crossing.
			_consume_learned(d, trait_id)
			gs.set_flag("f2_bridge_repaired", true)
			return _graft_ok(gs, "[WIRING] Living-metal supports rise over the broken crossing. The shortcut is open.")
		"quest":
			# Prosthetic: flag only — the story beat comes later.
			_consume_learned(d, trait_id)
			gs.set_flag("fabricator_prosthetic_grown", true)
			return _graft_ok(gs, "[WIRING] The plant grows an arm. It waits, patient as soil, for whoever needs it.")
	return {"ok": false, "msg": "[WIRING] Nothing happens."}


static func _consume_learned(d: Dictionary, trait_id: String) -> void:
	(d.get("learned", []) as Array).erase(trait_id)


## Effect queries for combat / world code.

static func has_graft(gs, trait_id: String) -> bool:
	var grafts: Dictionary = _data(gs).get("grafts", {})
	if grafts.get("weapon") == trait_id:
		return true
	return (grafts.get("armor", []) as Array).has(trait_id)


static func grafted_weapon(gs) -> String:
	return str(_data(gs).get("grafts", {}).get("weapon", ""))


static func grafted_armor(gs) -> Array:
	return (_data(gs).get("grafts", {}).get("armor", [null, null]) as Array).duplicate()


## Thorn retaliation: called when the player takes a hit. Returns the
## retaliation damage dealt (0 when no thorn graft).
static func thorn_retaliation(gs) -> int:
	return THORN_RETAIL if has_graft(gs, "thorn") else 0


## Cinder bark: reduce incoming fire/ash damage.
static func cinder_mitigation(gs, tags: Array) -> int:
	if has_graft(gs, "cinder") and (tags.has("fire") or tags.has("ash")):
		return CINDER_REDUCTION
	return 0
