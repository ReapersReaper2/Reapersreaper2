extends SceneTree
## Grimley's Still — headless test.
##
## Covers: save block defaults, vial buy/craft, mote ledger (mint/spend),
## validation (egg, armor plant, Wrongness, heritage, bare slot, no vial,
## trust debt, pending, cooldown), the extraction flow (start -> night
## boundary -> mote + permanent trait loss + trust debt + bond hit),
## first-use scene verbatim lines, room hook stub, deep-garden variant flag.

const Still = preload("res://scripts/still.gd")
const Party = preload("res://scripts/party.gd")
const GameStateScript := preload("res://scripts/game_state.gd")

var _failures := 0
var _passes := 0


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("  PASS: ", name)
	else:
		_failures += 1
		print("  FAILED: ", name)


func _make_gs() -> Node:
	var gs = GameStateScript.new()
	gs.save_system = null
	gs.new_game()
	return gs


func _make_still_gs() -> Node:
	var gs = _make_gs()
	gs.set_flag(Still.UNLOCK_FLAG, true)
	return gs


func _add_test_creature(gs) -> Dictionary:
	Party.add_creature(gs, "snapling", 5)
	return Party.get_entry(gs, Party.size(gs) - 1)


func _init() -> void:
	print("[still_test] starting")
	_run.call_deferred()


func _run() -> void:
	_test_state_defaults()
	_test_vials()
	_test_mote_ledger()
	_test_validation()
	_test_extraction_flow()
	_test_cooldown()
	_test_trust_debt()
	_test_first_use_scene()
	_test_room_hook()
	_test_deep_garden()
	_test_exclusion_markers_cleared()
	_test_items_json_still_materials()
	_test_items_json_empty_mote_vial()
	var total := _passes + _failures
	print("[TEST] still: %d passed, %d failed (of %d)" % [_passes, _failures, total])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


func _test_state_defaults() -> void:
	var gs = _make_gs()
	_check("locked before hearthollow", not Still.is_unlocked(gs))
	_check("nights start 0", Still.nights(gs) == 0)
	_check("no motes", Still.mote_balance(gs) == 0)
	_check("no vials", Still.empty_vials(gs) == 0)
	_check("deep garden not live", not Still.can_use_deep_garden(gs))


func _test_vials() -> void:
	var gs = _make_still_gs()
	var before: int = gs.get_soul_credits()
	var r: Dictionary = Still.buy_vial(gs)
	_check("buy vial ok", bool(r["ok"]))
	_check("buy vial costs 50", gs.get_soul_credits() == before - Still.VIAL_COST)
	_check("vial in inventory", Still.empty_vials(gs) == 1)
	gs.state["soul_credits"] = 10
	r = Still.buy_vial(gs)
	_check("broke vial fails", not bool(r["ok"]))
	_check("broke vial no write", Still.empty_vials(gs) == 1)
	# Craft path ([TUNING] recipe).
	gs.add_item("glass_shard", 1)
	gs.add_item("grave_petals", 2)
	r = Still.craft_vial(gs)
	_check("craft vial ok", bool(r["ok"]))
	_check("craft consumes glass", gs.get_item_count("glass_shard") == 0)
	_check("craft consumes petals", gs.get_item_count("grave_petals") == 0)
	_check("crafted vial in inventory", Still.empty_vials(gs) == 2)
	r = Still.craft_vial(gs)
	_check("craft without mats fails", not bool(r["ok"]))


func _test_mote_ledger() -> void:
	var gs = _make_still_gs()
	var m: Dictionary = Still.grant_mote(gs, "taproot_cluster", "Testy", "still")
	_check("mote minted", str(m.get("mote_id", "")) == "mote_1")
	_check("mote named after source", str(m.get("name", "")) == "Mote of Testy")
	_check("mote carries trait", str(m.get("trait_id", "")) == "taproot_cluster")
	_check("mote provenance", str(m.get("source", "")) == "still")
	_check("balance 1", Still.mote_balance(gs) == 1)
	var m2: Dictionary = Still.grant_mote(gs, "walking_roots", "Testy", "graft")
	_check("second mote id", str(m2.get("mote_id", "")) == "mote_2")
	_check("spend mote", Still.spend_mote(gs, "mote_1"))
	_check("balance 1 after spend", Still.mote_balance(gs) == 1)
	_check("spend unknown fails", not Still.spend_mote(gs, "mote_99"))


func _test_validation() -> void:
	var gs = _make_still_gs()
	gs.state["soul_credits"] = 10000
	Still.buy_vial(gs)
	var entry := _add_test_creature(gs)
	# Happy-path validation: snapling root slot holds walking_roots.
	var ok: Dictionary = Still.can_extract(gs, entry, "root")
	_check("valid extraction ok", bool(ok["ok"]))
	_check("valid trait id", str(ok.get("trait_id", "")) == "walking_roots")
	# Bare slot is not extractable.
	var bare: Dictionary = Still.can_extract(gs, entry, "accent")
	_check("bare slot rejected", not bool(bare["ok"]))
	# Unknown slot rejected.
	var noslot: Dictionary = Still.can_extract(gs, entry, "nope")
	_check("unknown slot rejected", not bool(noslot["ok"]))
	# Egg dicts are rejected defensively.
	var eggish := entry.duplicate()
	eggish["egg_id"] = "egg_1"
	var egg: Dictionary = Still.can_extract(gs, eggish, "root")
	_check("egg rejected", not bool(egg["ok"]))
	# Armor plant: not a creature. Grimley physically stops you.
	var ap := {"creature_id": "armor_plant", "level": 5, "nickname": ""}
	var apc: Dictionary = Still.can_extract(gs, ap, "root")
	_check("armor plant refused", not bool(apc["ok"]))
	_check("armor plant refusal line", str(apc["msg"]).contains(Still.ARMOR_PLANT_REFUSAL))
	_check("armor plant stop beat", str(apc["msg"]).contains(Still.ARMOR_PLANT_BEAT))
	# Wrongness: the Still refuses, the glass cracks.
	var w := Party.make_entry("snapling", 5)
	w["traits_override"] = {"root": "wrongness", "stem": "fleshy_stalk"}
	var wr: Dictionary = Still.can_extract(gs, w, "root")
	_check("wrongness refused", not bool(wr["ok"]))
	_check("wrongness refusal line", str(wr["msg"]).contains(Still.WRONGNESS_REFUSAL))
	_check("glass cracks beat", str(wr["msg"]).contains(Still.WRONGNESS_BEAT))
	# Heritage: no tagged trait exists in data yet — the check is data-gated.
	_check("heritage check data-gated", not Still._trait_is_heritage("walking_roots"))
	# Trust debt blocks a second extraction until rested.
	Still.start_extraction(gs, entry, "root")
	var debt: Dictionary = Still.can_extract(gs, entry, "stem")
	_check("pending blocks re-extract", not bool(debt["ok"]))
	# No vial blocks.
	var gs2 = _make_still_gs()
	var e2 := _add_test_creature(gs2)
	var nov: Dictionary = Still.can_extract(gs2, e2, "root")
	_check("no vial blocks", not bool(nov["ok"]))
	# Locked still blocks.
	var gs3 = _make_gs()
	var lck: Dictionary = Still.can_extract(gs3, e2, "root")
	_check("locked still blocks", not bool(lck["ok"]))


func _test_extraction_flow() -> void:
	var gs = _make_still_gs()
	gs.state["soul_credits"] = 10000
	Still.buy_vial(gs)
	var entry := _add_test_creature(gs)
	entry["nickname"] = "Thorn"
	var start: Dictionary = Still.start_extraction(gs, entry, "root")
	_check("start ok", bool(start["ok"]))
	_check("start consumes vial", Still.empty_vials(gs) == 0)
	_check("first use flags scene", bool(start.get("first_use", false)))
	_check("pending staged", entry.has("still_pending"))
	# The night boundary completes it.
	Still.on_day_advance(gs)
	_check("night ticked", Still.nights(gs) == 1)
	_check("pending cleared", not entry.has("still_pending"))
	_check("trait gone permanently", str(Still.Breeding.effective_traits(entry).get("root", "")) == "bare")
	_check("mote minted", Still.mote_balance(gs) == 1)
	var m: Dictionary = Still.motes(gs)[0]
	_check("mote is the extracted trait", str(m.get("trait_id", "")) == "walking_roots")
	_check("mote named after creature", str(m.get("name", "")) == "Mote of Thorn")
	_check("trust debt 3", Still.trust_debt(entry) == Still.TRUST_DEBT_NIGHTS)
	_check("bond dropped a tier", Still.bond_tier(entry) == Still.BOND_TIER_DEFAULT - 1)
	_check("creature cannot act", not Still.can_act(entry))
	# Second extraction flags no scene.
	Still.buy_vial(gs)
	var start2: Dictionary = Still.start_extraction(gs, entry, "stem")
	_check("second start blocked by trust debt", not bool(start2["ok"]))


func _test_cooldown() -> void:
	var gs = _make_still_gs()
	gs.state["soul_credits"] = 10000
	Still.buy_vial(gs)
	Still.buy_vial(gs)
	var e1 := _add_test_creature(gs)
	var e2 := _add_test_creature(gs)
	_check("first start ok", bool(Still.start_extraction(gs, e1, "root")["ok"]))
	# One creature per night: the second start waits for the boundary.
	var r: Dictionary = Still.start_extraction(gs, e2, "root")
	_check("same-night second start blocked", not bool(r["ok"]))
	Still.on_day_advance(gs)
	_check("next night start ok", bool(Still.start_extraction(gs, e2, "root")["ok"]))


func _test_trust_debt() -> void:
	var gs = _make_still_gs()
	gs.state["soul_credits"] = 10000
	Still.buy_vial(gs)
	var entry := _add_test_creature(gs)
	Still.start_extraction(gs, entry, "root")
	Still.on_day_advance(gs)  # extraction completes; debt = 3
	_check("debt 3 after extraction", Still.trust_debt(entry) == 3)
	Still.on_day_advance(gs)
	_check("debt 2", Still.trust_debt(entry) == 2)
	_check("still cannot act", not Still.can_act(entry))
	Still.on_day_advance(gs)
	Still.on_day_advance(gs)
	_check("debt cleared", Still.trust_debt(entry) == 0)
	_check("can act again", Still.can_act(entry))


func _texts() -> Array:
	var out: Array = []
	for e in Still.FIRST_USE_SCENE:
		out.append(str((e as Dictionary).get("text", "")))
	return out


func _test_first_use_scene() -> void:
	var texts := _texts()
	# The story bot's exact strings — copied verbatim, never reworded.
	for line in [
		"Last chance. Once it's out, it's out.",
		"...Yeah. That's what they all say.",
		"It'll rest. Give it three days. And little reaper — don't waste it. It cost more than you think.",
	]:
		_check("grimley line verbatim: " + line.left(20), texts.has(line))
	_check("trust-debt aside verbatim",
		Still.GRIMLEY_ASIDE == "It'll forgive you. Eventually. They always do. That's the worst part.")
	_check("scene has mollosar beat", texts.has("..."))


func _test_room_hook() -> void:
	var gs = _make_still_gs()
	var h: Dictionary = Still.room_hook(gs)
	_check("hook unlocked", bool(h.get("unlocked", false)))
	_check("hook first_use pending", bool(h.get("first_use", false)))
	_check("hook carries scene", (h.get("scene", []) as Array).size() == Still.FIRST_USE_SCENE.size())
	_check("hook reports vials", int(h.get("empty_vials", -1)) == 0)
	var gs2 = _make_gs()
	_check("hook locked before hearthollow", not bool(Still.room_hook(gs2).get("unlocked", true)))


func _test_deep_garden() -> void:
	var gs = _make_still_gs()
	gs.state["soul_credits"] = 10000
	Still.buy_vial(gs)
	var entry := _add_test_creature(gs)
	var r: Dictionary = Still.can_extract(gs, entry, "root", "deep_garden")
	_check("deep garden gated by flag", not bool(r["ok"]))
	gs.set_flag(Still.DEEP_GARDEN_FLAG, true)
	_check("deep garden variant live with flag",
		bool(Still.can_extract(gs, entry, "root", "deep_garden")["ok"]))
	var start: Dictionary = Still.start_extraction(gs, entry, "root", "deep_garden")
	_check("deep garden start ok", bool(start["ok"]))
	Still.on_day_advance(gs)
	_check("deep garden same trust debt", Still.trust_debt(entry) == Still.TRUST_DEBT_NIGHTS)
	_check("deep garden mote minted", Still.mote_balance(gs) == 1)


## Story-lane canon lines swapped in 2026-10-05: no [WIRING] may remain on
## the Still's exclusion refusals, and the story bot's lines are verbatim.
func _test_exclusion_markers_cleared() -> void:
	var lines := [
		Still.WRONGNESS_REFUSAL, Still.WRONGNESS_BEAT,
		Still.HERITAGE_REFUSAL, Still.HERITAGE_BEAT,
		Still.ARMOR_PLANT_REFUSAL, Still.ARMOR_PLANT_BEAT,
	]
	for i in lines.size():
		var ln := str(lines[i])
		_check("exclusion line %d non-empty" % i, ln != "")
		_check("exclusion line %d no [WIRING]" % i, not ln.contains("[WIRING]"))
	_check("heritage line verbatim",
		Still.HERITAGE_REFUSAL == "\"That one is in the blood. Seven generations deep. The Still takes what is learned, not what is inherited.\"")
	_check("heritage beat verbatim", Still.HERITAGE_BEAT == "[Grimley holds your hand back.]")
	_check("armor plant line verbatim",
		Still.ARMOR_PLANT_REFUSAL == "\"Don't. That is not a creature. Put it down before it decides for you.\"")
	_check("armor plant beat verbatim", Still.ARMOR_PLANT_BEAT == "[Grimley steps in, physical stop.]")


## glass_shard / grave_petals authored 2026-10-05 (story-bot request):
## they exist in items.json, parse, and read as crafting materials.
func _test_items_json_still_materials() -> void:
	var f := FileAccess.open("res://data/items.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var items: Dictionary = data.get("items", {})
	for iid in ["glass_shard", "grave_petals"]:
		var rec: Dictionary = items.get(iid, {})
		_check(iid + " in items.json", not rec.is_empty())
		_check(iid + " kind is material", str(rec.get("kind", "")) == "material")
		_check(iid + " price unset", int(rec.get("price", -1)) == 0)
	_check("glass_shard name", str((items.get("glass_shard", {}) as Dictionary).get("name", "")) == "Glass Shard")
	_check("grave_petals name", str((items.get("grave_petals", {}) as Dictionary).get("name", "")) == "Grave Petals")


## empty_mote_vial authored 2026-10-05 (story-bot call, 03:36 email):
## it lives in items.json now, no longer count-based-only. Wiring checks
## pin presence, kind, and price == Still.VIAL_COST; the story bot re-cuts
## the desc freely ([WIRING]).
func _test_items_json_empty_mote_vial() -> void:
	var f := FileAccess.open("res://data/items.json", FileAccess.READ)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var items: Dictionary = data.get("items", {})
	var rec: Dictionary = items.get("empty_mote_vial", {})
	_check("empty_mote_vial in items.json", not rec.is_empty())
	_check("empty_mote_vial kind is material", str(rec.get("kind", "")) == "material")
	_check("empty_mote_vial name", str(rec.get("name", "")) == "Empty Mote Vial")
	_check("empty_mote_vial price == VIAL_COST", int(rec.get("price", -1)) == Still.VIAL_COST)
	_check("empty_mote_vial desc is wiring-marked", "[WIRING]" in str(rec.get("desc", "")))
	_check("empty_mote_vial == EMPTY_VIAL_ITEM", str(rec.get("name", "")) == "Empty Mote Vial" and Still.EMPTY_VIAL_ITEM == "empty_mote_vial")
