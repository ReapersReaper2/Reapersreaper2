extends SceneTree
## Headless breeding/rearing test: the M+F gate, same-sex refusal, egg
## creation + parent records, incubation, hatching, growth stages (feed and
## party ticks), inheritance (stats in parental range, parts from parents
## ONLY — no fusion), ACNH-style gene Punnett squares, Journey Gift bonus,
## and derived-stat consistency with BattleUnit.
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/breeding_test.gd
## Uses throwaway slot 97 so real saves are never touched.
## (Autoloads are not loaded under -s, so scripts are instantiated via load().)

const Breeding = preload("res://scripts/breeding.gd")
const BattleUnit = preload("res://scripts/battle_unit.gd")
const CreatureData = preload("res://scripts/creature_data.gd")

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
	var party_script = load("res://scripts/party.gd")
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
	return [gs, party_script]


## Party entry with a forced sex (Party._make_entry assigns random sex).
func _mk(Party, species: String, level: int, sex: String) -> Dictionary:
	var e: Dictionary = Party.make_entry(species, level)
	e["sex"] = sex
	return e


func _init() -> void:
	print("[TEST] breeding: standard breeding/rearing")
	Breeding.set_seed(12345)
	var parts: Array = _make_gs()
	var gs = parts[0]
	var Party = parts[1]

	# --- gate: male + female accepted ---
	gs.state["party"] = [_mk(Party, "snapling", 5, "M"), _mk(Party, "siltmaw", 5, "F")]
	var ok := Breeding.can_breed(gs, 0, 1)
	_check("M+F pair accepted", bool(ok.get("ok", false)))
	# reversed order also fine (sire/dam resolved by sex, not index)
	ok = Breeding.can_breed(gs, 1, 0)
	_check("F+M index order accepted", bool(ok.get("ok", false)))

	# --- gate: refusals ---
	gs.state["party"] = [_mk(Party, "snapling", 5, "M"), _mk(Party, "siltmaw", 5, "M")]
	ok = Breeding.can_breed(gs, 0, 1)
	_check("M+M refused", not bool(ok.get("ok", true)))
	_check("M+M message names the rule", "male and one female" in str(ok.get("msg", "")))
	gs.state["party"] = [_mk(Party, "snapling", 5, "F"), _mk(Party, "siltmaw", 5, "F")]
	ok = Breeding.can_breed(gs, 0, 1)
	_check("F+F refused", not bool(ok.get("ok", true)))
	gs.state["party"] = [_mk(Party, "snapling", 5, "M"), _mk(Party, "siltmaw", 5, "F")]
	ok = Breeding.can_breed(gs, 0, 0)
	_check("same creature refused", not bool(ok.get("ok", true)))
	ok = Breeding.can_breed(gs, 0, 9)
	_check("bad index refused", not bool(ok.get("ok", true)))
	# juveniles can't breed
	var young := _mk(Party, "snapling", 1, "M")
	young["growth_stage"] = Breeding.STAGE_JUVENILE
	gs.state["party"] = [young, _mk(Party, "siltmaw", 5, "F")]
	ok = Breeding.can_breed(gs, 0, 1)
	_check("juvenile parent refused", not bool(ok.get("ok", true)))

	# --- egg creation with parent records ---
	gs.state["party"] = [_mk(Party, "snapling", 5, "M"), _mk(Party, "siltmaw", 5, "F")]
	gs.state.erase("nursery")
	var res := Breeding.breed(gs, 0, 1)
	_check("breed ok", bool(res.get("ok", false)))
	var egg: Dictionary = res.get("egg", {})
	_check("egg recorded in nursery", (gs.state.get("nursery", []) as Array).size() == 1)
	_check("egg has sire snapshot", str(egg.get("sire", {}).get("creature_id", "")) == "snapling")
	_check("egg has dam snapshot", str(egg.get("dam", {}).get("creature_id", "")) == "siltmaw")
	_check("egg starts unhatched", int(egg.get("steps_done", -1)) == 0)
	_check("egg needs incubation", int(egg.get("steps_total", 0)) == Breeding.EGG_STEPS)
	# same-sex breed produces nothing
	gs.state["party"] = [_mk(Party, "snapling", 5, "M"), _mk(Party, "siltmaw", 5, "M")]
	res = Breeding.breed(gs, 0, 1)
	_check("same-sex breed fails", not bool(res.get("ok", true)))

	# --- incubation + hatching ---
	gs.state["party"] = [_mk(Party, "snapling", 5, "M"), _mk(Party, "siltmaw", 5, "F")]
	gs.state.erase("nursery")
	Breeding.breed(gs, 0, 1)
	var early := Breeding.hatch_egg(gs, 0)
	_check("early hatch refused", not bool(early.get("ok", true)))
	var ready := Breeding.advance_eggs(gs, Breeding.EGG_STEPS)
	_check("egg ready after full incubation", ready == 1)
	var hatched := Breeding.hatch_egg(gs, 0)
	_check("hatch ok", bool(hatched.get("ok", false)))
	var kid: Dictionary = hatched.get("entry", {})
	_check("nursery empty after hatch", (gs.state.get("nursery", []) as Array).is_empty())
	_check("hatchling joins party", (Party._party(gs) as Array).size() == 3)
	_check("offspring is a hatchling", str(kid.get("growth_stage", "")) == Breeding.STAGE_HATCHLING)
	_check("offspring has journey gift", bool(kid.get("journey_gift", false)))
	_check("species follows the dam", str(kid.get("creature_id", "")) == "siltmaw")
	_check("parent records kept", str((kid.get("parents", {}) as Dictionary).get("dam_id", "")) == "siltmaw")

	# --- growth stages via feeding ---
	var fr := Breeding.feed(gs, 2)
	_check("feed ok", bool(fr.get("ok", false)))
	_check("feed adds growth", int((Party.get_entry(gs, 2) as Dictionary).get("growth_points", 0)) == Breeding.FEED_GROWTH)
	# feed to juvenile
	while str((Party.get_entry(gs, 2) as Dictionary).get("growth_stage", "")) == Breeding.STAGE_HATCHLING:
		Breeding.feed(gs, 2)
	_check("reaches juvenile", str((Party.get_entry(gs, 2) as Dictionary).get("growth_stage", "")) == Breeding.STAGE_JUVENILE)
	# party tick grows the young
	var before := int((Party.get_entry(gs, 2) as Dictionary).get("growth_points", 0))
	var ticked := Breeding.tick_party_growth(gs)
	_check("party tick grows young", ticked == 1)
	_check("tick adds points", int((Party.get_entry(gs, 2) as Dictionary).get("growth_points", 0)) == before + Breeding.PARTY_TICK_GROWTH)
	# feed to adult; adults refuse feed
	var guard := 0
	while str((Party.get_entry(gs, 2) as Dictionary).get("growth_stage", "")) != Breeding.STAGE_ADULT and guard < 20:
		Breeding.feed(gs, 2)
		guard += 1
	_check("reaches adult", str((Party.get_entry(gs, 2) as Dictionary).get("growth_stage", "")) == Breeding.STAGE_ADULT)
	fr = Breeding.feed(gs, 2)
	_check("adult refuses feed", not bool(fr.get("ok", true)))
	# the ex-hatchling can now breed (it is an adult) — pair it with the
	# opposite-sex parent (offspring sex is RNG-determined)
	var kid_sex := str((Party.get_entry(gs, 2) as Dictionary).get("sex", ""))
	var partner := 1 if kid_sex == "M" else 0  # 0 = snapling M, 1 = siltmaw F
	_check("grown offspring can breed", bool(Breeding.can_breed(gs, 2, partner).get("ok", false)))

	# --- inheritance: stats inside the parental range ---
	# snapling base: vigor 30 / might 6 / guard 3 / speed 9
	# siltmaw  base: vigor 45 / might 8 / guard 5 / speed 3
	Breeding.set_seed(777)
	gs.state.erase("nursery")
	Breeding.breed(gs, 0, 1)
	Breeding.advance_eggs(gs, Breeding.EGG_STEPS)
	# party is full-ish? size is 3, fine — hatch another
	var h2 := Breeding.hatch_egg(gs, 0)
	var k2: Dictionary = h2.get("entry", {})
	var kb: Dictionary = k2.get("base_override", {})
	_check("vigor in parental range", int(kb.get("vigor", 0)) >= 30 and int(kb.get("vigor", 0)) <= 45)
	_check("might in parental range", int(kb.get("might", 0)) >= 6 and int(kb.get("might", 0)) <= 8)
	_check("guard in parental range", int(kb.get("guard", 0)) >= 3 and int(kb.get("guard", 0)) <= 5)
	_check("speed in parental range", int(kb.get("speed", 0)) >= 3 and int(kb.get("speed", 0)) <= 9)

	# --- inheritance: parts from parents ONLY (no fusion), over many rolls ---
	CreatureData.ensure_loaded()
	var sire_traits: Dictionary = (gs.state["party"] as Array)[0].get("traits", {})
	# note: party[0] is a plain snapling entry -> traits from data
	sire_traits = CreatureData.get_creature("snapling").get("traits", {})
	var dam_traits: Dictionary = CreatureData.get_creature("siltmaw").get("traits", {})
	var fused := false
	for s in range(12):
		Breeding.set_seed(1000 + s)
		gs.state.erase("nursery")
		Breeding.breed(gs, 0, 1)
		Breeding.advance_eggs(gs, Breeding.EGG_STEPS)
		# make room: drop the last party member if full
		while (Party._party(gs) as Array).size() >= 6:
			(Party._party(gs) as Array).remove_at((Party._party(gs) as Array).size() - 1)
		var hh := Breeding.hatch_egg(gs, 0)
		if not bool(hh.get("ok", false)):
			continue
		var kk: Dictionary = hh.get("entry", {})
		var kt: Dictionary = kk.get("traits_override", {})
		for slot in Breeding.SLOTS:
			var t := str(kt.get(slot, ""))
			# 9-slot model: slots absent from a parent's data traits are bare.
			if t != str(sire_traits.get(slot, "bare")) and t != str(dam_traits.get(slot, "bare")):
				fused = true
		# genes: each allele must come from one of that parent's alleles
		var kg: Dictionary = kk.get("genes_override", {})
		var sg: Dictionary = CreatureData.get_creature("snapling").get("genes", {})
		var dg: Dictionary = CreatureData.get_creature("siltmaw").get("genes", {})
		for pair in ["hue", "bloom_tint", "pattern"]:
			var al: Array = kg.get(pair, [])
			var sa: Array = sg.get(pair, [])
			var da: Array = dg.get(pair, [])
			if not (str(al[0]) in [str(sa[0]), str(sa[1])] and str(al[1]) in [str(da[0]), str(da[1])]):
				fused = true
	_check("12 offspring: every part is one parent's part (no fusion)", not fused)
	_check("expressed traits slot-bounded", Breeding.expressed_trait_count(k2) >= 0 and Breeding.expressed_trait_count(k2) <= 9)

	# --- journey gift: small flat bonus over an ungifted twin ---
	var plain := k2.duplicate(true)
	plain.erase("journey_gift")
	var st_gift := Breeding.derived_stats(k2, 5)
	var st_plain := Breeding.derived_stats(plain, 5)
	_check("gift boosts vigor", st_gift["max_hp"] == st_plain["max_hp"] + 3)
	_check("gift boosts attack", st_gift["attack"] == st_plain["attack"] + 1)
	_check("gift boosts defense", st_gift["defense"] == st_plain["defense"] + 1)
	_check("gift boosts speed", st_gift["speed"] == st_plain["speed"] + 1)

	# --- derived stats match BattleUnit for wild (non-override) entries ---
	var wild := _mk(Party, "snapling", 5, "M")
	var ds := Breeding.derived_stats(wild, 5)
	var bu = BattleUnit.new("snapling", 5)
	_check("derived max_hp matches BattleUnit", ds["max_hp"] == bu.max_hp)
	_check("derived attack matches BattleUnit", ds["attack"] == bu.attack)
	_check("derived defense matches BattleUnit", ds["defense"] == bu.defense)
	_check("derived speed matches BattleUnit", ds["speed"] == bu.speed)

	# --- day boundary hook ---
	gs.state.erase("nursery")
	Breeding.breed(gs, 0, 1)
	Breeding.on_day_advance(gs)
	var egg2: Dictionary = (gs.state.get("nursery", []) as Array)[0]
	_check("day advance incubates eggs", int(egg2.get("steps_done", 0)) == Breeding.EGG_STEPS_PER_DAY)

	print("[TEST] breeding: %d passed, %d failed (of %d)" % [_count - _failures.size(), _failures.size(), _count])
	if not _failures.is_empty():
		printerr("FAILURES: ", _failures)
		quit(1)
	quit()
