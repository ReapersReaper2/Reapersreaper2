extends SceneTree
## Corpse-fruit module — headless test (foe-fruit door only).
##
## Covers FRUIT-SPEC REV 4.1 + FRUIT-OBJECT-MODEL REV 2 foe-fruit rules:
##   A. Eligibility conjunction: regret tag, tier floor, corpse, mortal-world
##      check (INV-5/R15), and each §1.4 locked exclusion (R5).
##   B. R2 tiebreak: true ties resolve Necro; dominant signature wins.
##   C. Tier multipliers ×1.0/×1.5/×2.0 and the Human Body alias.
##   D. Emergence: one foe -> one plant -> one fruit; ineligible refused;
##      second emergence refused.
##   E. Rot math: steps_remaining derived; boundary 1200 rots / 1199 not;
##      no banking (harvest never resets the anchor); plants and carried
##      fruit share the timer (R3); rots logged to ledger.fruit.harvested.
##   F. Harvest: carried record self-sufficient (INV-4); plant -> husk.
##   G. Consumption slot lifecycle: 3 slots, permanent-until-evicted (R19),
##      oldest evicted on the 4th eat; eating is NEVER blocked; eaten[]
##      append-only history; fresh grant after eviction resets to 1.0.
##   H. Dilution: repeat fruit halves potency (floor 1/4), no slot consumed.
##   I. Tokens: one per consumed fruit, max 5 FIFO; trait effects persist
##      past the visual cap.
##   J. Ledger: necro_count/eterni_count tallies; harvested[] outcomes.
##   K. INV-7: lifecycle paths never write gravebloom-family keys.
##
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/fruit_traits_test.gd
## (Autoloads are not loaded under -s, so scripts are instantiated via load().)

const FruitTraits = preload("res://scripts/fruit_traits.gd")
const GameStateScript := preload("res://scripts/game_state.gd")

## Test trait table (story-side owns the real one; the module never invents rows).
const TEST_TABLE := {
	"trait_shika_claw": {"might": 4, "guard": 2},
	"trait_grave_eye": {"might": 2, "guard": 4},
	"trait_kanryu_crest": {"might": 6, "guard": 0},
	"trait_ember_tongue": {"might": 0, "guard": 6},
	"trait_thorn_choir": {"might": 3, "guard": 3},
	"trait_siltmaw_hide": {"might": 1, "guard": 5},
}

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


func _foe(foe_id: String, enc_ref: String, tier: String, lean: float = 3.0) -> Dictionary:
	return {
		"foe_id": foe_id, "enc_ref": enc_ref, "tier": tier,
		"fruit_eligibility": "eligible", "corpse_produced": true, "mortal_world": false,
	}


## Full lifecycle helper: emerge -> finish_growth -> harvest -> consume.
## Returns the consume() result.
func _full_fruit(gs: Node, foe: Dictionary, room: String, lean: String,
		trait_id: String, steps: int) -> Dictionary:
	var e := FruitTraits.emerge_plant(gs, foe, room, lean, trait_id, steps)
	if not bool(e.get("ok", false)):
		return {"ok": false, "reason": "emerge_failed:" + str(e.get("reason", ""))}
	var plant: Dictionary = e["plant"]
	FruitTraits.finish_growth(gs, str(plant["plant_id"]), steps)
	var h := FruitTraits.harvest_fruit(gs, str(plant["plant_id"]), steps)
	if not bool(h.get("ok", false)):
		return {"ok": false, "reason": "harvest_failed:" + str(h.get("reason", ""))}
	var carried: Dictionary = h["carried"]
	return FruitTraits.consume(gs, str(carried["fruit_id"]), steps, TEST_TABLE)


func _init() -> void:
	print("[fruit_traits_test] starting")
	seed(20261009)
	_run.call_deferred()


func _run() -> void:
	_test_eligibility()
	_test_lean()
	_test_tiers()
	_test_emergence()
	_test_rot()
	_test_harvest()
	_test_slots()
	_test_dilution()
	_test_tokens()
	_test_ledger()
	_test_invariants()
	var total := _passes + _failures
	print("[TEST] fruit_traits: %d passed, %d failed (of %d)" % [_passes, _failures, total])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


func _test_eligibility() -> void:
	var ok_f := _foe("shika_hunter", "ENC-029", "Skeletal Body")
	_check("eligible foe passes", bool(FruitTraits.check_eligibility(ok_f).get("ok", false)))
	# Regret tag is HARD (R1).
	var no_tag := _foe("shika_hunter", "ENC-029", "Skeletal Body")
	no_tag["fruit_eligibility"] = "ineligible"
	var r: Dictionary = FruitTraits.check_eligibility(no_tag)
	_check("no regret tag refused", not bool(r.get("ok", true)) and str(r.get("reason", "")) == "no_regret_tag")
	# Tier floor: below Skeletal Body never fruits.
	var wisp := _foe("wisp", "ENC-028", "Wisp")
	r = FruitTraits.check_eligibility(wisp)
	_check("sub-floor tier refused", not bool(r.get("ok", true)) and str(r.get("reason", "")) == "tier_below_floor")
	# Higher tiers pass.
	_check("False Flesh passes floor", bool(FruitTraits.check_eligibility(_foe("f", "ENC-027", "False Flesh")).get("ok", false)))
	_check("Full Manifestation passes floor", bool(FruitTraits.check_eligibility(_foe("f", "ENC-022", "Full Manifestation")).get("ok", false)))
	_check("Human Body alias passes floor", bool(FruitTraits.check_eligibility(_foe("f", "ENC-023", "Human Body")).get("ok", false)))
	# Corpse required.
	var sparred := _foe("shika_hunter", "ENC-029", "Skeletal Body")
	sparred["corpse_produced"] = false
	r = FruitTraits.check_eligibility(sparred)
	_check("no corpse refused", not bool(r.get("ok", true)) and str(r.get("reason", "")) == "no_corpse")
	# Mortal-world kills never enter the plant records (INV-5 / R15).
	var mortal := _foe("shika_hunter", "ENC-029", "Skeletal Body")
	mortal["mortal_world"] = true
	r = FruitTraits.check_eligibility(mortal)
	_check("mortal world refused", not bool(r.get("ok", true)) and str(r.get("reason", "")) == "mortal_world")
	# §1.4 locked exclusions (R5) — ENC-keyed.
	for enc in FruitTraits.LOCKED_EXCLUSION_ENCS:
		var ef := _foe("some_foe", str(enc), "Full Manifestation")
		r = FruitTraits.check_eligibility(ef)
		_check("exclusion %s refused" % str(enc), not bool(r.get("ok", true)) and str(r.get("reason", "")) == "locked_exclusion")
	# Foe-keyed exclusions.
	for foe_id in FruitTraits.LOCKED_EXCLUSION_FOES:
		var ff := _foe(str(foe_id), "ENC-099", "Full Manifestation")
		r = FruitTraits.check_eligibility(ff)
		_check("exclusion %s refused" % str(foe_id), not bool(r.get("ok", true)) and str(r.get("reason", "")) == "locked_exclusion")
	# Explicit is_excluded checks.
	_check("is_excluded ENC-003", FruitTraits.is_excluded("ENC-003", "whatever"))
	_check("is_excluded wrath gate foe", FruitTraits.is_excluded("ENC-099", "wrath"))
	_check("is_excluded false for clean", not FruitTraits.is_excluded("ENC-029", "shika_hunter"))


func _test_lean() -> void:
	_check("death-dominant -> necro", FruitTraits.determine_lean(3.0, 1.0) == "necro")
	_check("light-dominant -> eterni", FruitTraits.determine_lean(1.0, 3.0) == "eterni")
	_check("true tie -> necro (R2)", FruitTraits.determine_lean(2.0, 2.0) == "necro")
	_check("zero tie -> necro (R2)", FruitTraits.determine_lean(0.0, 0.0) == "necro")


func _test_tiers() -> void:
	_check("Skeletal Body x1.0", FruitTraits.tier_mult("Skeletal Body") == 1.0)
	_check("False Flesh x1.5", FruitTraits.tier_mult("False Flesh") == 1.5)
	_check("Human Body alias x1.5", FruitTraits.tier_mult("Human Body") == 1.5)
	_check("Full Manifestation x2.0", FruitTraits.tier_mult("Full Manifestation") == 2.0)
	_check("unknown tier refuses", FruitTraits.tier_mult("Wisp") == 0.0)
	_check("floor rank order", FruitTraits.tier_at_least("Full Manifestation", "Skeletal Body"))
	_check("alias at floor", FruitTraits.tier_at_least("Human Body", "Skeletal Body"))
	_check("unknown fails rank", not FruitTraits.tier_at_least("Wisp", "Skeletal Body"))


func _test_emergence() -> void:
	var gs := _make_gs()
	var e: Dictionary = FruitTraits.emerge_plant(gs, _foe("shika_hunter", "ENC-029", "Skeletal Body"), "C1_01_corpsegarden", "necro", "trait_shika_claw", 500)
	_check("emerge ok", bool(e.get("ok", false)))
	var plant: Dictionary = e["plant"]
	_check("plant id from counter", str(plant.get("plant_id", "")) == "corpseplant_1")
	_check("status growing", str(plant.get("status", "")) == "growing")
	_check("enc_ref provenance carried", str(plant.get("enc_ref", "")) == "ENC-029")
	_check("anchor is driver step", int(plant.get("planted_at_step", -1)) == 500)
	_check("Q4: no emerged_at_step while growing", not plant.has("emerged_at_step"))
	# Second emergence of the same foe: refused (one foe -> one fruit).
	var e2: Dictionary = FruitTraits.emerge_plant(gs, _foe("shika_hunter", "ENC-029", "Skeletal Body"), "C1_02_other", "necro", "trait_shika_claw", 600)
	_check("re-fruit refused", not bool(e2.get("ok", true)) and str(e2.get("reason", "")) == "already_fruited")
	# Ineligible foe: refused.
	var e3: Dictionary = FruitTraits.emerge_plant(gs, _foe("shika_hunter", "ENC-003", "Skeletal Body"), "C1_01_corpsegarden", "necro", "trait_shika_claw", 600)
	_check("excluded foe refused", not bool(e3.get("ok", true)))
	# Growth finishes: fruit sub-record written, still anchored at 500.
	var f := FruitTraits.finish_growth(gs, "corpseplant_1", 510)
	_check("finish ok", bool(f.get("ok", false)))
	_check("status harvestable", str((f["plant"] as Dictionary).get("status", "")) == "harvestable")
	_check("fruit record resolved", not ((f["plant"] as Dictionary).get("fruit", {}) as Dictionary).is_empty())
	_check("fruit id joins plant", str(((f["plant"] as Dictionary).get("fruit", {}) as Dictionary).get("fruit_id", "")) == "fruit_corpseplant_1")
	_check("timer starts at finish (1200)", FruitTraits.steps_remaining(int(((f["plant"] as Dictionary).get("fruit", {}) as Dictionary).get("emerged_at_step", 0)), 510) == 1200)
	# Double-finish is idempotent.
	var f2 := FruitTraits.finish_growth(gs, "corpseplant_1", 520)
	_check("double finish idempotent", bool(f2.get("ok", false)) and int(((f2["plant"] as Dictionary).get("fruit", {}) as Dictionary).get("emerged_at_step", 0)) == 510)


func _test_rot() -> void:
	# Boundary: 1199 steps fine, 1200th step rots (<= 0).
	_check("1199 remaining", FruitTraits.steps_remaining(0, 1199) == 1)
	_check("1200 boundary rots", FruitTraits.is_rotted(0, 1200))
	_check("1199 not rotted", not FruitTraits.is_rotted(0, 1199))
	# On-plant rot via on_steps_taken.
	var gs := _make_gs()
	var e: Dictionary = FruitTraits.emerge_plant(gs, _foe("shika_hunter", "ENC-029", "Skeletal Body"), "C1_01_x", "necro", "trait_shika_claw", 0)
	var plant: Dictionary = e["plant"]
	FruitTraits.finish_growth(gs, str(plant["plant_id"]), 0)
	var r: Dictionary = FruitTraits.on_steps_taken(gs, 1199)
	_check("no rot at 1199", (r.get("rotted", []) as Array).is_empty())
	r = FruitTraits.on_steps_taken(gs, 1)
	_check("plant rots at 1200", (r.get("rotted", []) as Array) == ["fruit_corpseplant_1"])
	var plants: Array = cropse_plants_for_test(gs)
	_check("plant flipped rotted", str((plants[0] as Dictionary).get("status", "")) == "rotted")
	_check("rot logged", _harvested_outcomes(gs) == ["rotted"])
	# Carried fruit shares the timer (R3 — runs everywhere).
	var gs2 := _make_gs()
	var e2: Dictionary = FruitTraits.emerge_plant(gs2, _foe("gloombeast", "ENC-030", "False Flesh"), "C2_01_x", "eterni", "trait_grave_eye", 0)
	FruitTraits.finish_growth(gs2, "corpseplant_1", 0)
	var h := FruitTraits.harvest_fruit(gs2, "corpseplant_1", 500)
	_check("harvest ok", bool(h.get("ok", false)))
	_check("anchor carried over, never reset (INV-4)", int((h["carried"] as Dictionary).get("emerged_at_step", -1)) == 0)
	var r2: Dictionary = FruitTraits.on_steps_taken(gs2, 1199)
	_check("carried alive at 1199", (r2.get("rotted", []) as Array).is_empty())
	r2 = FruitTraits.on_steps_taken(gs2, 1200)
	_check("carried rots at 1200 (no banking)", (r2.get("rotted", []) as Array) == ["fruit_corpseplant_1"])
	_check("carried gone after rot", (FruitTraits.carried(gs2) as Array).is_empty())
	_check("rot outcome logged for carried", _harvested_outcomes(gs2) == ["rotted"])
	# Rotted fruit cannot be eaten.
	var eat: Dictionary = FruitTraits.consume(gs2, "fruit_corpseplant_1", 1200, TEST_TABLE)
	_check("rotted fruit uneatable", not bool(eat.get("ok", true)) and str(eat.get("reason", "")) == "missing")


func _test_harvest() -> void:
	var gs := _make_gs()
	var e: Dictionary = FruitTraits.emerge_plant(gs, _foe("shika_hunter", "ENC-029", "Skeletal Body"), "C1_01_x", "necro", "trait_shika_claw", 100)
	FruitTraits.finish_growth(gs, "corpseplant_1", 100)
	var early := FruitTraits.harvest_fruit(gs, "corpseplant_1", 100)
	# Cannot harvest before finish_growth on a fresh check: force via new plant.
	_check("harvest ok", bool(early.get("ok", false)))
	var carried: Dictionary = early["carried"]
	_check("carried origin foe-fruit", str(carried.get("origin", "")) == "foe-fruit")
	_check("carried self-sufficient trait", str(carried.get("trait_id", "")) == "trait_shika_claw")
	_check("carried self-sufficient foe", str(carried.get("source_foe", "")) == "shika_hunter")
	_check("carried self-sufficient tier", str(carried.get("tier", "")) == "Skeletal Body")
	_check("carried anchor kept", int(carried.get("emerged_at_step", -1)) == 100)
	_check("plant harvested + husk", str((cropse_plants_for_test(gs)[0] as Dictionary).get("status", "")) == "harvested")
	# Double harvest refused.
	var again := FruitTraits.harvest_fruit(gs, "corpseplant_1", 101)
	_check("double harvest refused", not bool(again.get("ok", true)) and str(again.get("reason", "")) == "not_harvestable")
	# Harvesting a growing plant refused.
	var gs2 := _make_gs()
	FruitTraits.emerge_plant(gs2, _foe("other_foe", "ENC-031", "Skeletal Body"), "C1_02_x", "necro", "trait_grave_eye", 0)
	var grow_h := FruitTraits.harvest_fruit(gs2, "corpseplant_1", 1)
	_check("growing plant unharvestable", not bool(grow_h.get("ok", true)))


func _test_slots() -> void:
	var gs := _make_gs()
	var r1 := _full_fruit(gs, _foe("foe_a", "ENC-040", "Skeletal Body"), "R1", "necro", "trait_shika_claw", 0)
	_check("eat 1 ok", bool(r1.get("ok", false)))
	_check("potency mult fresh 1.0", float(r1.get("potency_mult", 0.0)) == 1.0)
	_check("tier mult x1.0 might", float(r1.get("might", -1.0)) == 4.0)
	var r2 := _full_fruit(gs, _foe("foe_b", "ENC-041", "False Flesh"), "R1", "eterni", "trait_grave_eye", 10)
	_check("eat 2 ok", bool(r2.get("ok", false)))
	_check("tier mult x1.5 might", float(r2.get("might", -1.0)) == 3.0)  ## 2 * 1.5
	var r3 := _full_fruit(gs, _foe("foe_c", "ENC-042", "Full Manifestation"), "R1", "necro", "trait_ember_tongue", 20)
	_check("eat 3 ok", bool(r3.get("ok", false)))
	_check("tier mult x2.0 guard", float(r3.get("guard", -1.0)) == 12.0)  ## 6 * 2.0
	_check("3 slots filled", (FruitTraits.active_traits(gs) as Array).size() == 3)
	# 4th eat evicts the oldest (R19) — never blocked.
	var r4 := _full_fruit(gs, _foe("foe_d", "ENC-043", "Skeletal Body"), "R1", "eterni", "trait_thorn_choir", 30)
	_check("4th eat never blocked", bool(r4.get("ok", false)))
	_check("oldest evicted", str(r4.get("evicted", "")) == "trait_shika_claw")
	_check("still 3 active", (FruitTraits.active_traits(gs) as Array).size() == 3)
	var ids: Array = []
	for t in (FruitTraits.active_traits(gs) as Array):
		ids.append(str((t as Dictionary).get("trait_id", "")))
	_check("evicted gone", not ids.has("trait_shika_claw"))
	_check("eaten history append-only 4", ((FruitTraits._player_fruit(gs).get("eaten", []) as Array)).size() == 4)
	# Re-grant after eviction is fresh (dilution reset).
	var r5 := _full_fruit(gs, _foe("foe_a2", "ENC-044", "Skeletal Body"), "R1", "necro", "trait_shika_claw", 40)
	_check("re-grant ok", bool(r5.get("ok", false)))
	_check("re-grant fresh 1.0", float(r5.get("potency_mult", 0.0)) == 1.0)
	_check("basis tier_relative", str(r5.get("basis", "")) == "tier_relative")
	_check("fruit_granted flag", bool((FruitTraits.active_traits(gs)[2] as Dictionary).get("fruit_granted", false)))
	_check("mode permanent", str((FruitTraits.active_traits(gs)[2] as Dictionary).get("mode", "")) == "permanent")


func _test_dilution() -> void:
	var gs := _make_gs()
	_full_fruit(gs, _foe("foe_x", "ENC-050", "Skeletal Body"), "R1", "necro", "trait_shika_claw", 0)
	_full_fruit(gs, _foe("foe_y", "ENC-051", "Skeletal Body"), "R1", "necro", "trait_grave_eye", 10)
	_check("2 slots before dilution", (FruitTraits.active_traits(gs) as Array).size() == 2)
	# Second fruit, same foe species (same trait_id, new foe_id) -> dilution, no slot.
	var rd := _full_fruit(gs, _foe("foe_x2", "ENC-052", "Skeletal Body"), "R1", "necro", "trait_shika_claw", 20)
	_check("dilution eat ok", bool(rd.get("ok", false)))
	_check("diluted flag", bool(rd.get("diluted", false)))
	_check("halved to 0.5", float(rd.get("potency_mult", 0.0)) == 0.5)
	_check("no slot consumed", (FruitTraits.active_traits(gs) as Array).size() == 2)
	_check("active record halved", float(((FruitTraits.active_traits(gs)[0] as Dictionary)).get("potency_mult", 0.0)) == 0.5)
	_check("diluted might", float(rd.get("might", -1.0)) == 2.0)  ## 4 * 1.0 * 0.5
	# Third repeat -> floor 0.25.
	var rd2 := _full_fruit(gs, _foe("foe_x3", "ENC-053", "Skeletal Body"), "R1", "necro", "trait_shika_claw", 30)
	_check("floored to 0.25", float(rd2.get("potency_mult", 0.0)) == 0.25)
	# Fourth repeat stays at floor.
	var rd3 := _full_fruit(gs, _foe("foe_x4", "ENC-054", "Skeletal Body"), "R1", "necro", "trait_shika_claw", 40)
	_check("floor holds", float(rd3.get("potency_mult", 0.0)) == 0.25)
	_check("eaten history counts every eat", ((FruitTraits._player_fruit(gs).get("eaten", []) as Array)).size() == 5)


func _test_tokens() -> void:
	var gs := _make_gs()
	var traits := ["trait_shika_claw", "trait_grave_eye", "trait_ember_tongue",
		"trait_thorn_choir", "trait_siltmaw_hide", "trait_kanryu_crest"]
	for i in range(6):
		_full_fruit(gs, _foe("foe_t%d" % i, "ENC-06%d" % i, "Skeletal Body"), "R1",
			"necro" if i % 2 == 0 else "eterni", str(traits[i]), i * 10)
	var tokens: Array = FruitTraits.tokens(gs)
	_check("tokens capped at 5", tokens.size() == 5)
	var ids: Array = []
	for t in tokens:
		ids.append(str((t as Dictionary).get("trait_id", "")))
	_check("FIFO: oldest replaced", not ids.has("trait_shika_claw") and ids.has("trait_kanryu_crest"))
	_check("lean coloring carried", str((tokens[0] as Dictionary).get("lean", "")) in ["necro", "eterni"])
	# Trait effects persist past the visual cap (slot accounting untouched).
	_check("active traits still 3", (FruitTraits.active_traits(gs) as Array).size() == 3)
	# describe() hides power.
	var d: Dictionary = FruitTraits.describe(tokens[0])
	_check("power hidden in describe", str(d.get("trait", "")) == "unknown")
	_check("luna_lean reads lean", FruitTraits.luna_lean(tokens[0]) == str((tokens[0] as Dictionary).get("lean", "")))


func _test_ledger() -> void:
	var gs := _make_gs()
	_full_fruit(gs, _foe("n1", "ENC-070", "Skeletal Body"), "R1", "necro", "trait_shika_claw", 0)
	_full_fruit(gs, _foe("e1", "ENC-071", "Skeletal Body"), "R1", "eterni", "trait_grave_eye", 10)
	var led := FruitTraits.ledger(gs)
	_check("necro counted", int(led.get("necro_count", 0)) == 1)
	_check("eterni counted", int(led.get("eterni_count", 0)) == 1)
	_check("harvested outcomes eaten", _harvested_outcomes(gs) == ["eaten", "eaten"])
	# Mixed ledger: one eaten, one rotted on-plant.
	var gs2 := _make_gs()
	var e: Dictionary = FruitTraits.emerge_plant(gs2, _foe("n2", "ENC-072", "Skeletal Body"), "R1", "necro", "trait_shika_claw", 0)
	FruitTraits.finish_growth(gs2, "corpseplant_1", 0)
	_full_fruit(gs2, _foe("e2", "ENC-073", "Skeletal Body"), "R1", "eterni", "trait_grave_eye", 0)
	FruitTraits.on_steps_taken(gs2, 1200)
	_check("mixed ledger", _harvested_outcomes(gs2) == ["rotted", "eaten"])


func _test_invariants() -> void:
	var gs := _make_gs()
	# Lifecycle paths never write gravebloom-family keys (INV-7 / R18).
	_full_fruit(gs, _foe("inv_foe", "ENC-080", "Skeletal Body"), "R1", "necro", "trait_shika_claw", 0)
	_check("no gravebloom_grown writes", not ((gs.state as Dictionary).get("ledger", {}) as Dictionary).has("graveblooms"))
	_check("no ledger graveblooms array", not FruitTraits.ledger(gs).has("graveblooms"))
	# record_gravebloom writes only when the defeat flow calls it.
	FruitTraits.record_gravebloom(gs, "R1", "inv_foe", true)
	var gbs: Array = ((gs.state as Dictionary).get("ledger", {}) as Dictionary).get("graveblooms", [])
	_check("record_gravebloom writes marker", gbs.size() == 1 and bool((gbs[0] as Dictionary).get("fruit_spawned", false)))
	# Save round-trip through JSON (state is the save truth).
	var gs2 := _make_gs()
	_full_fruit(gs2, _foe("s1", "ENC-081", "Full Manifestation"), "R2", "eterni", "trait_kanryu_crest", 700)
	var snap := JSON.stringify(gs2.state)
	var back = JSON.parse_string(snap)
	var gs3 := _make_gs()
	gs3.state = back
	_check("carried survives round-trip", (FruitTraits.carried(gs3) as Array).is_empty())
	_check("active survives round-trip", (FruitTraits.active_traits(gs3) as Array).size() == 1)
	_check("tokens survive round-trip", (FruitTraits.tokens(gs3) as Array).size() == 1)
	_check("eaten survives round-trip", ((FruitTraits._player_fruit(gs3).get("eaten", []) as Array)).size() == 1)
	_check("anchor survives round-trip", int(((FruitTraits._player_fruit(gs3).get("eaten", []) as Array)[0] as Dictionary).get("emerged_at_step", -1)) == 700)


## Ledger harvested[] outcomes in order.
func _harvested_outcomes(gs: Node) -> Array:
	var out: Array = []
	for row in (FruitTraits.ledger(gs).get("harvested", []) as Array):
		out.append(str((row as Dictionary).get("outcome", "")))
	return out


## Static-lazy helper: plant records of a holder.
static func cropse_plants_for_test(gs: Node) -> Array:
	return ((gs.state as Dictionary).get("plants", {}) as Dictionary).get("corpse_fruit", [])
