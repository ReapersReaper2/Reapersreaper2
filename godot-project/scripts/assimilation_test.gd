extends SceneTree
## Headless test: assimilation form table + planting prompt flow + slot ids.
##
## Covers (locked design, Sweet Potato Creature):
##   A. Assimilation: one SpeciesID ("armor_plant") for the metal plant;
##      form table keyed by metal id with per-host overrides; resolve_form()
##      per metal/host; the armor accumulator reads RESOLVED form traits
##      (guard math incl. form guard_bonus); assimilation is growth-only and
##      NOT heritable (breeding.gd unchanged — snapshots never carry
##      assimilation keys; only the metal line breeds true).
##   B. Planting prompt: planting_prompt_slot() returns the story-bot-owned
##      beat slot id ONLY at lesser form + equipped Widowblade — never at
##      either alone, never at neither; plant() sets FLAG_PLANTED once
##      (idempotent), delegating to the same gate.
##   C. Slot-id verification: the story bot's 00:14 hook set
##      (wrath_oldone_entrance, wrath_blue_volley_01..03,
##      wrath_lesser_trigger, wrath_fight_end) matches the BARK_* consts in
##      wrath_ally.gd; widowblade_planting_beat parses through
##      DialogueParser from a beat-structure fixture (dialogue + trigger +
##      direction lines, per the story bot's doc conventions). The fixture
##      is STRUCTURE ONLY — real lines live in the story bot's docs; nothing
##      is authored here.
##   D. The story bot's third seeded metal dragon_gold (00:49 EDT spec):
##      resolves via resolve_form on armor_plant with form_id
##      assim_dragon_gold; hand-computed guard total matches; all trait ids
##      exist in data/traits.json; NO Widowblade dark leaf-metal row exists
##      in FORM_TABLE (story-only, never a player seed).
##   E. The REAL widowblade_planting_beat section now transcribed into
##      data/dialogue_06b.md parses through DialogueParser with the slot id
##      on the heading, WRATH/MOLLOSAR/LUNA dialogue, direction/narration,
##      and trigger entries present, and the story-bot-authored sentences
##      surviving verbatim.
##
## NOTE on the story bot's email typo: they typed "wrath_blue_folley_01..03".
## Treated as their typo for "volley" — the code's "volley" ids are what the
## hook set lists otherwise, and the test pins them.
##
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/assimilation_test.gd
## (Autoloads are not loaded under -s, so scripts are instantiated via load().)

const Assimilation = preload("res://scripts/assimilation.gd")
const ArmorAccumulator = preload("res://scripts/armor_accumulator.gd")
const Breeding = preload("res://scripts/breeding.gd")
const WrathAlly = preload("res://scripts/wrath_ally.gd")
const OldOneGate = preload("res://scripts/old_one_gate.gd")
const CreatureData = preload("res://scripts/creature_data.gd")
const GameStateScript := preload("res://scripts/game_state.gd")

var _failures := 0
var _passes := 0


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
	else:
		_failures += 1
		print("  FAILED: ", name)


func _make_gs() -> Node:
	var gs = GameStateScript.new()
	gs.save_system = null
	gs.new_game()
	return gs


func _equip(gs: Node, weapon_id: String) -> void:
	(gs.state["player"] as Dictionary)["weapon"] = weapon_id


func _fire_lesser_form(gs: Node) -> void:
	for i in WrathAlly.LESSER_FORM_THRESHOLD:
		gs.bump_counter(WrathAlly.FIRE_METER)
	WrathAlly.check_lesser_form(gs)


func _nine_traits(part_id: String) -> Dictionary:
	var t := {}
	for slot in Breeding.SLOTS:
		t[slot] = part_id
	return t


func _init() -> void:
	print("[assimilation_test] starting")
	_run.call_deferred()


func _run() -> void:
	_test_species_id()
	_test_form_resolution()
	_test_assimilate_event()
	_test_accumulator_reads_form()
	_test_growth_not_heritable()
	_test_planting_prompt_gate()
	_test_plant_idempotent()
	_test_slot_ids()
	_test_plant_beat_parses()
	_test_dragon_gold()
	_test_real_plant_beat_section()
	var total := _passes + _failures
	print("[TEST] assimilation: %d passed, %d failed (of %d)" % [_passes, _failures, total])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


func _test_species_id() -> void:
	_check("SPECIES_ID is armor_plant", Assimilation.SPECIES_ID == "armor_plant")
	_check("matches Breeding.ARMOR_PLANT_ID (breeding unchanged)",
		Assimilation.SPECIES_ID == Breeding.ARMOR_PLANT_ID)
	_check("table carries iron_beam", Assimilation.metal_ids().has("iron_beam"))
	_check("table carries silvered_ore", Assimilation.metal_ids().has("silvered_ore"))


func _test_form_resolution() -> void:
	var f := Assimilation.resolve_form("armor_plant", "iron_beam", "")
	_check("iron_beam resolves", str(f.get("form_id", "")) == "assim_iron_beam")
	_check("iron_beam armor trait", str((f.get("traits", {}) as Dictionary).get("armor", "")) == "ironwood_plates")
	_check("iron_beam stem trait", str((f.get("traits", {}) as Dictionary).get("stem", "")) == "ironwood_trunk")
	# Per-host override: mollosar gets the host record merged in.
	var fh := Assimilation.resolve_form("armor_plant", "iron_beam", "mollosar")
	_check("host override form_id", str(fh.get("form_id", "")) == "assim_iron_beam_mollosar")
	var fht: Dictionary = fh.get("traits", {})
	_check("host override adds appendage", str(fht.get("appendage", "")) == "bark_plates")
	_check("host override keeps armor", str(fht.get("armor", "")) == "ironwood_plates")
	_check("host override guard_bonus", int(fh.get("guard_bonus", 0)) == 2)
	# A host with no override gets the base form, not {}.
	var fb := Assimilation.resolve_form("armor_plant", "iron_beam", "tucker")
	_check("unknown host gets base form", str(fb.get("form_id", "")) == "assim_iron_beam")
	_check("unknown host has no appendage", not (fb.get("traits", {}) as Dictionary).has("appendage"))
	_check("base guard_bonus", int(fb.get("guard_bonus", 0)) == 1)
	# Silvered ore row has no host overrides.
	var fs := Assimilation.resolve_form("armor_plant", "silvered_ore", "mollosar")
	_check("silvered_ore resolves", str(fs.get("form_id", "")) == "assim_silvered_ore")
	_check("silvered_ore armor trait", str((fs.get("traits", {}) as Dictionary).get("armor", "")) == "soot_plates")
	# Rejections.
	_check("unknown metal resolves to {}", Assimilation.resolve_form("armor_plant", "unobtainium", "").is_empty())
	_check("empty metal resolves to {}", Assimilation.resolve_form("armor_plant", "", "").is_empty())
	_check("other species never resolves", Assimilation.resolve_form("snapling", "iron_beam", "").is_empty())


func _test_assimilate_event() -> void:
	var e := {"creature_id": "armor_plant", "traits_override": _nine_traits("walking_roots")}
	_check("not assimilated before event", not Assimilation.is_assimilated(e))
	var r := Assimilation.assimilate(e, "iron_beam", "mollosar")
	_check("assimilate ok", bool(r.get("ok", false)))
	_check("assimilate returns form_id", str(r.get("form_id", "")) == "assim_iron_beam_mollosar")
	_check("assimilated after event", Assimilation.is_assimilated(e))
	_check("growth key recorded", str(e.get("assimilated_metal", "")) == "iron_beam")
	_check("host key recorded", str(e.get("assimilation_host", "")) == "mollosar")
	var t := Assimilation.form_traits_of(e)
	_check("form traits resolve on entry", str(t.get("appendage", "")) == "bark_plates")
	# Re-assimilating the same metal is a no-op (idempotent).
	var r2 := Assimilation.assimilate(e, "iron_beam", "mollosar")
	_check("re-assimilate same metal ok", bool(r2.get("ok", false)))
	_check("re-assimilate keeps form", str(e.get("assimilated_metal", "")) == "iron_beam")
	# Unknown metal refused; entry untouched.
	var r3 := Assimilation.assimilate(e, "unobtainium", "")
	_check("unknown metal refused", not bool(r3.get("ok", true)))
	_check("refusal keeps prior metal", str(e.get("assimilated_metal", "")) == "iron_beam")
	# Non-plant entries cannot assimilate.
	var s := {"creature_id": "snapling"}
	_check("non-plant refused", not bool(Assimilation.assimilate(s, "iron_beam", "").get("ok", true)))
	_check("non-plant form traits {}", Assimilation.form_traits_of(s).is_empty())
	# Unassimilated plant: no form traits.
	var u := {"creature_id": "armor_plant"}
	_check("unassimilated plant form traits {}", Assimilation.form_traits_of(u).is_empty())


func _test_accumulator_reads_form() -> void:
	CreatureData.ensure_loaded()
	# Plant assimilated with iron_beam: form armor=ironwood_plates(4),
	# stem=ironwood_trunk(2), guard_bonus 1. Non-form slots fall back to the
	# donor map: root from a snapling taproot_cluster (guard 2).
	var donors := {}
	for slot in Breeding.SLOTS:
		donors[slot] = {"species": "armor_plant", "part_id": "walking_roots"}
	donors["root"] = {"species": "snapling", "part_id": "taproot_cluster"}
	var e := {
		"creature_id": "armor_plant",
		"part_donors": donors,
		"assimilated_metal": "iron_beam",
		"assimilation_host": "",
	}
	var acc: Dictionary = ArmorAccumulator.accumulate(e)
	_check("accumulator total with form (4 armor + 2 stem + 2 root donor + 1 bonus)",
		int(acc.get("total_guard", -1)) == 9)
	_check("form traits outrank donor map for armor",
		str(ArmorAccumulator.donor_of(e, "armor").get("part_id", "")) == "ironwood_plates")
	_check("form donor species is the plant",
		str(ArmorAccumulator.donor_of(e, "armor").get("species", "")) == "armor_plant")
	_check("non-form slot still uses donor map",
		str(ArmorAccumulator.donor_of(e, "root").get("part_id", "")) == "taproot_cluster")
	var by_donor: Dictionary = acc.get("by_donor", {})
	_check("by_donor plant line = 4+2+1", int(by_donor.get("armor_plant", -1)) == 7)
	_check("by_donor snapling line = 2", int(by_donor.get("snapling", -1)) == 2)
	var by_slot: Dictionary = acc.get("by_slot", {})
	_check("by_slot armor = 4", int(by_slot.get("armor", -1)) == 4)
	_check("by_slot stem = 2", int(by_slot.get("stem", -1)) == 2)
	# Host override row changes the math: mollosar gains appendage bark_plates(3), bonus 2.
	e["assimilation_host"] = "mollosar"
	var acc2: Dictionary = ArmorAccumulator.accumulate(e)
	_check("host form total (4+2+3+2 bonus+2 donor)", int(acc2.get("total_guard", -1)) == 13)
	_check("host form appendage read", str(ArmorAccumulator.donor_of(e, "appendage").get("part_id", "")) == "bark_plates")
	var by_slot2: Dictionary = acc2.get("by_slot", {})
	_check("host form by_slot appendage = 3", int(by_slot2.get("appendage", -1)) == 3)


func _test_growth_not_heritable() -> void:
	# An assimilated parent's growth record must never reach the offspring:
	# breeding._snapshot() copies creature_id / traits / genes / base only.
	var parent := {
		"creature_id": "armor_plant",
		"traits": _nine_traits("walking_roots"),
		"genes": {"hue": ["a", "b"]},
		"base": {"vigor": 5, "might": 5, "guard": 5, "speed": 5},
		"assimilated_metal": "iron_beam",
		"assimilation_host": "mollosar",
	}
	var snap: Dictionary = Breeding._snapshot(parent)
	_check("snapshot has creature_id", str(snap.get("creature_id", "")) == "armor_plant")
	_check("snapshot drops assimilated_metal", not snap.has("assimilated_metal"))
	_check("snapshot drops assimilation_host", not snap.has("assimilation_host"))
	_check("snapshot keys are exactly the heritable four",
		(snap.keys() as Array).all(func(k): return k in ["creature_id", "traits", "genes", "base"])
		and snap.keys().size() == 4)
	# Inheritance rolls carry no assimilation state either.
	var dam := {"creature_id": "armor_plant", "traits": _nine_traits("walking_roots")}
	var sire := {"creature_id": "snapling", "traits": _nine_traits("walking_roots")}
	var res: Dictionary = Breeding._inherit_traits(sire, dam)
	_check("inheritance yields traits+donors only",
		(res.keys() as Array).all(func(k): return k in ["traits", "donors"]) and res.keys().size() == 2)
	# A plain offspring entry is never "assimilated".
	_check("offspring entry is not assimilated", not Assimilation.is_assimilated({"creature_id": "armor_plant"}))
	# The metal line breeds true: offspring of a plant dam keep the plant id.
	_check("metal line breeds true (dam species wins)", str(dam.get("creature_id", "")) == "armor_plant")


func _test_planting_prompt_gate() -> void:
	# Neither condition: prompt closed.
	var g1 = _make_gs()
	_check("prompt closed with neither", WrathAlly.planting_prompt_slot(g1) == "")
	# Lesser form alone (blade not equipped): closed.
	var g2 = _make_gs()
	_fire_lesser_form(g2)
	_check("prompt closed at lesser form alone", WrathAlly.planting_prompt_slot(g2) == "")
	# Inventory-only blade + lesser form: still closed (must be EQUIPPED).
	g2.add_item("widowblade", 1)
	_check("prompt closed with blade in bag", WrathAlly.planting_prompt_slot(g2) == "")
	# Equipped alone (no lesser form): closed.
	var g3 = _make_gs()
	_equip(g3, "widowblade")
	_check("prompt closed when equipped alone", WrathAlly.planting_prompt_slot(g3) == "")
	# Lesser form + equipped: prompt opens with the story-bot-owned slot id.
	var g4 = _make_gs()
	_fire_lesser_form(g4)
	_equip(g4, "widowblade")
	_check("prompt opens at lesser form + equipped",
		WrathAlly.planting_prompt_slot(g4) == "widowblade_planting_beat")
	_check("prompt slot is the story-bot-owned id",
		WrathAlly.planting_prompt_slot(g4) == WrathAlly.PLANT_BEAT_SLOT)
	_check("PLANT_BEAT_SLOT pins the id",
		WrathAlly.PLANT_BEAT_SLOT == "widowblade_planting_beat")
	# The prompt gate agrees exactly with the plant gate (no drift).
	_check("prompt and can_plant agree",
		bool(OldOneGate.can_plant(g4).get("ok", false))
		and not bool(OldOneGate.can_plant(g2).get("ok", true)))


func _test_plant_idempotent() -> void:
	var gs = _make_gs()
	_fire_lesser_form(gs)
	_equip(gs, "widowblade")
	_check("FLAG_PLANTED starts unset", not gs.get_flag("widowblade_planted", false))
	var p1 := WrathAlly.plant(gs)
	_check("plant ok", bool(p1.get("ok", false)))
	_check("FLAG_PLANTED set (widowblade_planted)", gs.get_flag("widowblade_planted", false))
	_check("plant reports flag id", str(p1.get("flag", "")) == "widowblade_planted")
	_check("plant first true", bool(p1.get("first", false)))
	var p2 := WrathAlly.plant(gs)
	_check("plant idempotent (still ok)", bool(p2.get("ok", false)))
	_check("plant idempotent (first false)", not bool(p2.get("first", true)))
	_check("flag stays set", gs.get_flag("widowblade_planted", false))


func _test_slot_ids() -> void:
	# The story bot's 00:14 hook set, verified against the code's slot refs.
	# NOTE: the email literally typed "wrath_blue_folley_01..03" — treated
	# as their typo for "volley"; the code's "volley" ids are pinned here.
	var expected_volleys := ["wrath_blue_volley_01", "wrath_blue_volley_02", "wrath_blue_volley_03"]
	_check("entrance slot id", WrathAlly.BARK_ENTRANCE == "wrath_oldone_entrance")
	_check("volley slot ids", (WrathAlly.BARK_VOLLEYS as Array) == expected_volleys)
	_check("lesser trigger slot id", WrathAlly.BARK_LESSER_TRIGGER == "wrath_lesser_trigger")
	_check("fight end slot id", WrathAlly.BARK_FIGHT_END == "wrath_fight_end")
	_check("all six hook slots unique",
		([WrathAlly.BARK_ENTRANCE, WrathAlly.BARK_LESSER_TRIGGER, WrathAlly.BARK_FIGHT_END]
			+ (WrathAlly.BARK_VOLLEYS as Array)).size() == 6)


func _test_plant_beat_parses() -> void:
	# Beat-structure fixture for the story-bot-owned slot
	# widowblade_planting_beat: dialogue lines + trigger line + direction
	# lines, per the story bot's doc conventions. FIXTURE ONLY — the real
	# lines live in the story bot's dialogue docs; nothing is authored here.
	var fixture := """### widowblade_planting_beat

**WRATH:** [STORY-BOT LINE — fixture placeholder only, not canon]

*[STAGE DIRECTION — fixture placeholder only, not canon.]*

[TRIGGER: planting beat opens — slot widowblade_planting_beat]
"""
	var parser = load("res://scripts/dialogue_parser.gd")
	var entries: Array = parser.parse(fixture)
	var has_dialogue := false
	var has_trigger := false
	var has_direction := false
	var slot_named := false
	var heading_named := false
	for e in entries:
		var t := str(e.get("type", ""))
		var text := str(e.get("text", ""))
		match t:
			"dialogue":
				has_dialogue = true
				if text == "":
					_failures += 1
					print("  FAILED: fixture dialogue has empty text")
			"trigger":
				has_trigger = true
			"direction":
				has_direction = true
			"scene_heading":
				if text.find(WrathAlly.PLANT_BEAT_SLOT) >= 0:
					heading_named = true
		if text.find(WrathAlly.PLANT_BEAT_SLOT) >= 0:
			slot_named = true
	_check("beat parses to entries", entries.size() >= 3)
	_check("beat has dialogue lines", has_dialogue)
	_check("beat has a trigger line", has_trigger)
	_check("beat has direction/narration lines", has_direction)
	_check("beat names the slot id", slot_named)
	_check("beat heading keys on the slot id", heading_named)


func _load_traits_json() -> Dictionary:
	var f := FileAccess.open("res://data/traits.json", FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return (parsed as Dictionary).get("traits", {})
	return {}


func _test_dragon_gold() -> void:
	# Story-bot spec (00:49 EDT): third seeded metal — dragon_gold.
	var form: Dictionary = Assimilation.resolve_form("armor_plant", "dragon_gold")
	_check("dragon_gold resolves on armor_plant", not form.is_empty())
	if form.is_empty():
		return
	_check("dragon_gold form_id is assim_dragon_gold",
		str(form.get("form_id", "")) == "assim_dragon_gold")
	_check("dragon_gold metal pins dragon_gold",
		str(form.get("metal", "")) == "dragon_gold")
	var traits: Dictionary = form.get("traits", {})
	_check("dragon_gold armor trait is soot_plates",
		str(traits.get("armor", "")) == "soot_plates")
	_check("dragon_gold bloom trait is ember_crown",
		str(traits.get("bloom", "")) == "ember_crown")
	_check("dragon_gold stem trait is gnarled_trunk",
		str(traits.get("stem", "")) == "gnarled_trunk")
	# Every trait id in the row must already exist in data/traits.json.
	var traits_json := _load_traits_json()
	_check("traits.json loaded", not traits_json.is_empty())
	for tid_v in traits.values():
		var tid := str(tid_v)
		_check("trait id in traits.json: " + tid, traits_json.has(tid))
	# Hand-computed guard total: guard_bonus 2 + soot_plates 2 + ember_crown 0
	# + gnarled_trunk 2 = 6.
	var total := int(form.get("guard_bonus", 0))
	for tid_v in traits.values():
		var row: Dictionary = traits_json.get(str(tid_v), {})
		total += int(row.get("guard_mod", 0))
	_check("dragon_gold hand-computed guard total is 6", total == 6)
	# The Widowblade's dark leaf-metal stays story-only: it must never seed
	# as a player discovery row in FORM_TABLE.
	_check("no 'widowblade' key in FORM_TABLE",
		not (Assimilation.FORM_TABLE as Dictionary).has("widowblade"))
	var story_only_leak := false
	for key_v in (Assimilation.FORM_TABLE as Dictionary).keys():
		var ks := str(key_v).to_lower()
		if ks.contains("widow") or ks.contains("leaf"):
			story_only_leak = true
	_check("no widow/leaf metal rows in FORM_TABLE", not story_only_leak)
	_check("FORM_TABLE holds exactly iron_beam, silvered_ore, dragon_gold",
		(Assimilation.FORM_TABLE as Dictionary).keys() == ["iron_beam", "silvered_ore", "dragon_gold"])
	# Discovery still works end-to-end: growth-time assimilation of the metal
	# yields the dragon_gold form id on the party entry.
	var entry := {"creature_id": "armor_plant"}
	var res: Dictionary = Assimilation.assimilate(entry, "dragon_gold")
	_check("assimilate dragon_gold ok", bool(res.get("ok", false)))
	_check("assimilate dragon_gold form_id",
		str(res.get("form_id", "")) == "assim_dragon_gold")
	_check("assimilate dragon_gold traits resolve",
		(Assimilation.form_traits_of(entry) as Dictionary).get("bloom", "") == "ember_crown")


func _test_real_plant_beat_section() -> void:
	# The REAL widowblade_planting_beat beat, now transcribed verbatim from
	# the story bot's lines into data/dialogue_06b.md (see that file's
	# attribution comment): parses through DialogueParser with the slot id
	# on the heading and dialogue + direction + trigger entries present.
	var parser = load("res://scripts/dialogue_parser.gd")
	var entries: Array = parser.parse_file("res://data/dialogue_06b.md")
	_check("dialogue_06b.md parses non-empty", not entries.is_empty())
	var sections: Array = parser.get_scenes(entries)
	var idx := -1
	for i in sections.size():
		if str((sections[i] as Dictionary).get("heading", "")) == WrathAlly.PLANT_BEAT_SLOT:
			idx = i
			break
	_check("real beat section found in dialogue_06b.md", idx >= 0)
	if idx < 0:
		return
	_check("real beat heading keys on the slot id exactly",
		str((sections[idx] as Dictionary).get("heading", "")) == "widowblade_planting_beat")
	var body: Array = parser.entries_from_scene(entries, idx)
	var speakers := {}
	var has_trigger := false
	var has_direction := false
	var text_blob := ""
	for e_v in body:
		var e := e_v as Dictionary
		var t := str(e.get("type", ""))
		text_blob += str(e.get("text", "")) + "\n"
		if t == "dialogue":
			speakers[str(e.get("character", ""))] = true
		elif t == "trigger":
			has_trigger = true
		elif t == "direction":
			has_direction = true
	_check("real beat has WRATH dialogue line", speakers.has("WRATH"))
	_check("real beat has MOLLOSAR dialogue line", speakers.has("MOLLOSAR"))
	_check("real beat has LUNA dialogue line", speakers.has("LUNA"))
	_check("real beat has a trigger line", has_trigger)
	_check("real beat has direction/narration lines", has_direction)
	# Verbatim pin: the story-bot-authored sentences survive transcription
	# word-for-word (structural markers aside: **CHAR:**, *[...]*, [TRIGGER:]).
	var verbatim := [
		"Blue fire holds him small. I cannot hold him long.",
		"You grew inside him once. Grow again.",
		"It knows this place. It wants to stay.",
		"PLANT THE WIDOWBLADE \u2014 prompt fires only at lesser form, blade equipped",
		"The blade roots in the Old One skull. The Trees still. The cycle closes over him. A new tree will decide what kind of ruler sleeps beneath it.",
		"the scythe reaps, the sword plants, neither wins it alone",
		"lesser-form flag AND Widowblade equipped, no other trigger",
	]
	for v in verbatim:
		_check("real beat keeps verbatim line: \"" + v.left(28) + "...\"", text_blob.find(v) >= 0)
