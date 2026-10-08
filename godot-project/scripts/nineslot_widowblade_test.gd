extends SceneTree
## Headless test for the 9-slot part model + Widowblade endgame wiring.
## Covers: 9-slot inheritance rolls, eyes/face slot handling, species record
## shape (silhouette + variant_slots + donor_parts), the armor accumulator's
## DonorSpecies+Slot read, shadow-pool charge rules (Driftcap refill ONLY,
## blast spend, birth from slow_focus+charge only — never from blasts), the
## Widowblade acquisition event, and the Old One gate block/pass.
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/nineslot_widowblade_test.gd
## Uses throwaway slot 97 so real saves are never touched.
## (Autoloads are not loaded under -s, so scripts are instantiated via load().)

const Breeding = preload("res://scripts/breeding.gd")
const ArmorAccumulator = preload("res://scripts/armor_accumulator.gd")
const FairyPools = preload("res://scripts/fairy_pools.gd")
const Widowblade = preload("res://scripts/widowblade.gd")
const OldOneGate = preload("res://scripts/old_one_gate.gd")
const CreatureData = preload("res://scripts/creature_data.gd")

const NINE := ["root", "stem", "bloom", "leafset", "appendage", "armor", "accent", "eyes", "face"]

var _failures: Array[String] = []
var _count := 0


func _check(name: String, cond: bool) -> void:
	_count += 1
	if cond:
		print("  PASS: ", name)
	else:
		_failures.append(name)
		print("  FAIL: ", name)


func _make_gs():
	var ss = (load("res://scripts/save_system.gd")).new()
	root.add_child(ss)
	var ach = (load("res://scripts/achievements.gd")).new()
	root.add_child(ach)
	var gs = (load("res://scripts/game_state.gd")).new()
	gs.save_system = ss
	gs.achievements = ach
	root.add_child(gs)
	# NOTE: under -s, _ready() does not auto-fire for nodes added in _init().
	gs._ready()
	ach.game_state = gs
	return gs


func _mk(Party, species: String, level: int, sex: String) -> Dictionary:
	var e: Dictionary = Party.make_entry(species, level)
	e["sex"] = sex
	return e


func _hatch_one(gs, Party) -> Dictionary:
	while (Party._party(gs) as Array).size() >= 6:
		(Party._party(gs) as Array).remove_at((Party._party(gs) as Array).size() - 1)
	var h := Breeding.hatch_egg(gs, 0)
	return h.get("entry", {})


func _init() -> void:
	print("[TEST] nineslot_widowblade: 9-slot model + Widowblade endgame")
	Breeding.set_seed(4242)
	var Party = load("res://scripts/party.gd")
	var gs = _make_gs()

	# --- SLOTS is the 9 ---
	_check("SLOTS has 9 entries", Breeding.SLOTS.size() == 9)
	_check("SLOTS matches canon order", Breeding.SLOTS == NINE)

	# --- 9-slot inheritance rolls: every part is one parent's, all 9 slots ---
	CreatureData.ensure_loaded()
	var sire_traits: Dictionary = CreatureData.get_creature("snapling").get("traits", {})
	var dam_traits: Dictionary = CreatureData.get_creature("siltmaw").get("traits", {})
	gs.state["party"] = [_mk(Party, "snapling", 5, "M"), _mk(Party, "siltmaw", 5, "F")]
	var fused := false
	var nine_seen := true
	for s in range(8):
		Breeding.set_seed(5000 + s)
		gs.state.erase("nursery")
		Breeding.breed(gs, 0, 1)
		Breeding.advance_eggs(gs, Breeding.EGG_STEPS)
		var kid := _hatch_one(gs, Party)
		var kt: Dictionary = kid.get("traits_override", {})
		if kt.keys().size() != 9:
			nine_seen = false
		for slot in Breeding.SLOTS:
			if not kt.has(slot):
				nine_seen = false
			var t := str(kt.get(slot, ""))
			if t != str(sire_traits.get(slot, "bare")) and t != str(dam_traits.get(slot, "bare")):
				fused = true
		# donor provenance: every slot names a parent species + the part id
		var donors: Dictionary = kid.get("part_donors", {})
		for slot in Breeding.SLOTS:
			var d: Dictionary = donors.get(slot, {})
			if not (str(d.get("species", "")) in ["snapling", "siltmaw"]
					and str(d.get("part_id", "")) == str(kt.get(slot, ""))):
				fused = true
	_check("offspring carry all 9 slots", nine_seen)
	_check("9-slot rolls: every part is one parent's part (no fusion)", not fused)

	# --- eyes/face slot handling (dedicated dominance rolls) ---
	# hand-built snapshots: parents differ ONLY in eyes/face (unknown trait
	# ids get default 0.5 dominance, so rolls are 50/50 across seeds).
	var saw_sire_eye := false
	var saw_dam_eye := false
	var saw_sire_face := false
	var saw_dam_face := false
	var eye_face_only := true
	var donor_match := true
	for s in range(20):
		Breeding.set_seed(9000 + s)
		var sire := {"creature_id": "sire_sp", "traits": {"eyes": "sire_eyes", "face": "sire_face"}}
		var dam := {"creature_id": "dam_sp", "traits": {"eyes": "dam_eyes", "face": "dam_face"}}
		var res: Dictionary = Breeding._inherit_traits(sire, dam)
		var tr: Dictionary = res["traits"]
		var dn: Dictionary = res["donors"]
		# untouched slots default to "bare" on both sides
		for slot in Breeding.SLOTS:
			if slot in ["eyes", "face"]:
				continue
			if str(tr.get(slot, "")) != "bare":
				eye_face_only = false
		var e := str(tr.get("eyes", ""))
		var f := str(tr.get("face", ""))
		if e == "sire_eyes":
			saw_sire_eye = true
			if str((dn["eyes"] as Dictionary).get("species", "")) != "sire_sp":
				donor_match = false
		elif e == "dam_eyes":
			saw_dam_eye = true
			if str((dn["eyes"] as Dictionary).get("species", "")) != "dam_sp":
				donor_match = false
		else:
			eye_face_only = false
		if f == "sire_face":
			saw_sire_face = true
			if str((dn["face"] as Dictionary).get("species", "")) != "sire_sp":
				donor_match = false
		elif f == "dam_face":
			saw_dam_face = true
			if str((dn["face"] as Dictionary).get("species", "")) != "dam_sp":
				donor_match = false
		else:
			eye_face_only = false
	_check("eyes roll: both parents' eyes seen across seeds", saw_sire_eye and saw_dam_eye)
	_check("face roll: both parents' faces seen across seeds", saw_sire_face and saw_dam_face)
	_check("eyes/face rolls stay inside their slots", eye_face_only)
	_check("donor species always matches the winning parent", donor_match)

	# --- species record shape ---
	var ok_shape := true
	var donor_bad := false
	for cid in CreatureData.creature_ids():
		var c: Dictionary = CreatureData.get_creature(cid)
		if str(c.get("silhouette", "")) == "":
			ok_shape = false
		var vs: Dictionary = c.get("variant_slots", {})
		if vs.keys().size() != 9:
			ok_shape = false
		for slot in Breeding.SLOTS:
			if not vs.has(slot) or not (vs[slot] is bool):
				ok_shape = false
		var dp: Array = c.get("donor_parts", [])
		for d in dp:
			var dd: Dictionary = d
			if not (dd.has("species") and dd.has("slot") and dd.has("part_id")):
				donor_bad = true
			if not Breeding.SLOTS.has(str(dd.get("slot", ""))):
				donor_bad = true
			var pid := str(dd.get("part_id", ""))
			if pid != "bare" and CreatureData.get_trait(pid).is_empty():
				donor_bad = true
	_check("every species has a non-empty silhouette", ok_shape)
	_check("every species has a 9-slot bool variant_slots map", ok_shape)
	_check("donor_parts are well-formed {species, slot, part_id}", not donor_bad)
	var snap_vs: Dictionary = CreatureData.get_creature("snapling").get("variant_slots", {})
	_check("existing species: eyes/face variant, the rest fixed",
		bool(snap_vs.get("eyes", false)) and bool(snap_vs.get("face", false))
		and not bool(snap_vs.get("root", true)) and not bool(snap_vs.get("armor", true)))

	# --- armor accumulator reads DonorSpecies + Slot from the instance ---
	# offspring of bellmaw(M) x snapling(F): donors split across species.
	gs.state["party"] = [_mk(Party, "bellmaw", 12, "M"), _mk(Party, "snapling", 5, "F")]
	Breeding.set_seed(31337)
	gs.state.erase("nursery")
	Breeding.breed(gs, 0, 1)
	Breeding.advance_eggs(gs, Breeding.EGG_STEPS)
	var akid := _hatch_one(gs, Party)
	var acc: Dictionary = ArmorAccumulator.accumulate(akid)
	# hand-computed expectation from the same donor map + trait table
	var exp_total := 0
	var exp_by_donor := {}
	for slot in Breeding.SLOTS:
		var dd: Dictionary = (akid.get("part_donors", {}) as Dictionary).get(slot, {})
		var pid := str(dd.get("part_id", "bare"))
		if pid == "bare":
			continue
		var g := int(CreatureData.get_trait(pid).get("guard_mod", 0))
		if g == 0:
			continue
		exp_total += g
		var sp := str(dd.get("species", ""))
		exp_by_donor[sp] = int(exp_by_donor.get(sp, 0)) + g
	_check("accumulator total matches donor-map math", int(acc.get("total_guard", -1)) == exp_total)
	_check("accumulator by_donor matches donor-map math",
		(acc.get("by_donor", {}) as Dictionary) == exp_by_donor)
	_check("accumulator donor keys are species ids",
		(acc.get("by_donor", {}) as Dictionary).keys().all(func(k): return k in ["bellmaw", "snapling"]))
	# legacy entry without part_donors -> self-donated fallback
	var legacy: Dictionary = Party.make_entry("thornchoir", 4)
	var lacc: Dictionary = ArmorAccumulator.accumulate(legacy)
	var lexp := 0
	for slot in Breeding.SLOTS:
		var pid2 := str((CreatureData.get_creature("thornchoir").get("traits", {}) as Dictionary).get(slot, "bare"))
		if pid2 != "bare":
			lexp += int(CreatureData.get_trait(pid2).get("guard_mod", 0))
	_check("legacy entry: accumulator self-donates", int(lacc.get("total_guard", -1)) == lexp)
	var ld: Dictionary = ArmorAccumulator.donor_of(legacy, "armor")
	_check("legacy entry: donor species is own species",
		str(ld.get("species", "")) == "thornchoir" and str(ld.get("part_id", "")) != "")

	# --- shadow pool charge rules ---
	FairyPools.set_seed(7)
	gs.state.erase("fairy_pools")
	_check("shadow charge starts at 0", FairyPools.shadow_charge(gs) == 0)
	_check("blast fails with no charge", not FairyPools.blast(gs))
	_check("charge still 0 after failed blast", FairyPools.shadow_charge(gs) == 0)
	# ONLY Driftcap contact refills
	var ch := FairyPools.driftcap_contact(gs)
	_check("Driftcap contact refills to max", ch == FairyPools.max_charge() and FairyPools.max_charge() > 0)
	_check("blast spends charge", FairyPools.blast(gs) and FairyPools.shadow_charge(gs) == FairyPools.max_charge() - 1)
	# blasts never birth: drain the pool with blasts, confirm no birth flag
	gs.state["flags"] = {}
	while FairyPools.blast(gs):
		pass
	_check("blasts drain the pool to 0", FairyPools.shadow_charge(gs) == 0)
	_check("blasts never birth a widow", not bool(gs.get_flag("widow_born", false)))
	# birth requires slow_focus
	FairyPools.driftcap_contact(gs)
	var b1 := FairyPools.try_widow_birth(gs, false)
	_check("birth refused without slow_focus", not bool(b1.get("ok", true)))
	_check("birth without focus spends nothing", FairyPools.shadow_charge(gs) == FairyPools.max_charge())
	# birth requires charge
	while FairyPools.blast(gs):
		pass
	var b2 := FairyPools.try_widow_birth(gs, true)
	_check("birth refused with no charge", not bool(b2.get("ok", true)))
	# birth with focus + charge: rare — sweep seeds until one lands, then
	# verify a success consumes exactly one charge
	FairyPools.driftcap_contact(gs)
	var born := false
	var before_ch := 0
	for s in range(400):
		FairyPools.set_seed(20000 + s)
		var pre := FairyPools.shadow_charge(gs)
		var r := FairyPools.try_widow_birth(gs, true)
		if bool(r.get("ok", false)):
			born = true
			before_ch = pre
			break
		# failed rolls must not consume charge
		if FairyPools.shadow_charge(gs) != pre:
			_failures.append("failed birth roll consumed charge (seed %d)" % (20000 + s))
			print("  FAIL: failed birth roll consumed charge")
	_check("birth lands with slow_focus + charge (rare)", born)
	if born:
		_check("successful birth consumes one charge", FairyPools.shadow_charge(gs) == before_ch - 1)
		_check("successful birth flags the event", bool(gs.get_flag("widow_born", false)))
	# light pool sanity
	_check("light pool source is armor_plant", FairyPools.pool_source("light_pool") == "armor_plant")
	_check("shadow pool source is widowblade", FairyPools.pool_source("shadow_pool") == "widowblade")
	FairyPools.add_light_energy(gs, 5)
	_check("light energy accumulates", FairyPools.light_energy(gs) == 5)
	_check("light spend works", FairyPools.spend_light_energy(gs, 2) and FairyPools.light_energy(gs) == 3)
	_check("light overspend refused", not FairyPools.spend_light_energy(gs, 99))

	# --- Widowblade acquisition event ---
	gs.state["flags"] = {}
	gs.state["inventory"] = {}
	_check("widowblade is a key-item weapon class", Widowblade.is_key_item_weapon())
	var acq := Widowblade.on_ivy_defeated(gs)
	_check("acquisition ok", bool(acq.get("ok", false)))
	_check("FLAG_IVY_DEFEATED set", bool(gs.get_flag(Widowblade.FLAG_IVY_DEFEATED, false)))
	_check("widowblade granted to inventory", gs.get_item_count(Widowblade.ITEM_ID) == 1)
	var acq2 := Widowblade.on_ivy_defeated(gs)
	_check("re-acquire is flag-idempotent", bool(gs.get_flag(Widowblade.FLAG_IVY_DEFEATED, false)))
	_check("re-acquire grants no duplicate", gs.get_item_count(Widowblade.ITEM_ID) == 1 and not bool(acq2.get("granted", true)))
	# shared charge definition: both phases read the same value
	FairyPools.driftcap_contact(gs)
	_check("wielder HUD reads the shared charge", Widowblade.shared_shadow_charge(gs) == FairyPools.shadow_charge(gs))

	# --- Old One gate ---
	gs.state["flags"] = {}
	gs.state["inventory"] = {}
	var g1 := OldOneGate.check(gs)
	_check("gate blocks with nothing", not bool(g1.get("ok", true)))
	gs.set_flag(Widowblade.FLAG_IVY_DEFEATED, true)
	var g2 := OldOneGate.check(gs)
	_check("gate blocks with flag but no blade", not bool(g2.get("ok", true)))
	gs.add_item(Widowblade.ITEM_ID, 1)
	var g3 := OldOneGate.check(gs)
	_check("gate passes with flag + blade present", bool(g3.get("ok", false)))
	gs.state["inventory"] = {}
	var player: Dictionary = gs.state.get("player", {})
	player["weapon"] = Widowblade.ITEM_ID
	gs.state["player"] = player
	var g4 := OldOneGate.check(gs)
	_check("gate passes with blade equipped", bool(g4.get("ok", false)))

	print("[TEST] nineslot_widowblade: %d passed, %d failed (of %d)" % [_count - _failures.size(), _failures.size(), _count])
	if not _failures.is_empty():
		printerr("FAILURES: ", _failures)
		quit(1)
	quit()
