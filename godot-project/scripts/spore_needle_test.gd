extends SceneTree
## Spore Needle system — headless test.
##
## Covers the locked canon (story bot, doc 03b §§5–10):
##   A. Firing gate: only Forms 5/6 fire needles (can_fire); wrong form,
##      null state, and non-creature targets refuse cleanly.
##   B. Infection: fire_needle() tags a creature target (infected + lean);
##      needle lean alternates Necro/Eterni when unnamed; warded targets
##      fail the needle (§12 seam); stats track needles/infections.
##   C. Battle seam: infect_unit() tags a BattleUnit; battle_snapshot()
##      carries infected/lean/traits; on_creature_death() on a fainted
##      infected foe grows the plant.
##   D. Death -> plant: an infected host's death sprouts a fruit plant;
##      fruit_traits = random 1–3 sample of the host's expressed traits;
##      tree_lean = the needle's lean; uninfected deaths grow nothing.
##      Field death path: the died-signal watch resolves the stored
##      infection without touching other death listeners.
##   E. Harvest -> feeding loop: harvest_plant() yields a fruit through
##      FeedingLoop (carried, lean == tree lean, host_traits attached);
##      double harvest refused; unknown plant refused.
##   F. Achievement: notify_spore_harvest fires exactly on the FIRST
##      harvest of a spore-spawned plant (idempotent).
##   G. Save/load round-trip through JSON; malformed payloads refused.
##
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/spore_needle_test.gd
## (Autoloads are not loaded under -s, so scripts are instantiated via load().)

const SporeNeedle = preload("res://scripts/spore_needle.gd")
const FeedingLoop = preload("res://scripts/feeding_loop.gd")
const BattleUnitScript = preload("res://scripts/battle_unit.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const AchievementsScript := preload("res://scripts/achievements.gd")

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


func _make_gs_with_ach() -> Node:
	var gs = _make_gs()
	var ach = AchievementsScript.new()
	ach.game_state = gs
	gs.achievements = ach
	return gs


func _snapling_host(lean := "") -> Dictionary:
	return {
		"creature_id": "snapling",
		"name": "Snapling",
		"traits": {
			"root": "walking_roots", "stem": "fleshy_stalk",
			"bloom": "snapping_maw", "leafset": "needle_spray",
			"appendage": "root_claws", "armor": "spike_quills",
			"accent": "bare", "eyes": "bare", "face": "bare",
		},
		"infected": true,
		"lean": lean,
	}


## Field creature double: a Node with a died signal and a creature snapshot.
class FakeCreature extends Node:
	signal died(node)
	var _snap: Dictionary
	func _init(snap: Dictionary) -> void:
		_snap = snap
	func spore_host_snapshot() -> Dictionary:
		return _snap.duplicate(true)


func _make_creature_node(snap: Dictionary) -> FakeCreature:
	var fc := FakeCreature.new(snap)
	root.add_child(fc)
	return fc


func _init() -> void:
	print("[spore_needle_test] starting")
	_run.call_deferred()


func _run() -> void:
	_test_firing_gate()
	_test_infection()
	_test_battle_seam()
	_test_death_to_plant()
	_test_field_death_watch()
	_test_harvest()
	_test_achievement()
	_test_save_load()
	var total := _passes + _failures
	print("[TEST] spore_needle: %d passed, %d failed (of %d)" % [_passes, _failures, total])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


func _test_firing_gate() -> void:
	var gs := _make_gs()
	_check("form 1 cannot fire", not SporeNeedle.can_fire(gs))
	gs.set_form(5)
	_check("form 5 can fire", SporeNeedle.can_fire(gs))
	gs.set_form(6)
	_check("form 6 can fire", SporeNeedle.can_fire(gs))
	gs.set_form(3)
	_check("form 3 cannot fire", not SporeNeedle.can_fire(gs))
	_check("null gs cannot fire", not SporeNeedle.can_fire(null))
	# Wrong form refuses the shot.
	var r: Dictionary = SporeNeedle.fire_needle(gs, null)
	_check("wrong form: ok false", not bool(r.get("ok", true)))
	_check("wrong form: reason", str(r.get("reason", "")) == "not_spore_form")
	_check("wrong form: [WIRING] msg", str(r.get("msg", "")).begins_with("[WIRING]"))
	# Non-creature target refuses.
	gs.set_form(5)
	var prop := RefCounted.new()
	r = SporeNeedle.fire_needle(gs, prop)
	_check("non-creature: ok false", not bool(r.get("ok", true)))
	_check("non-creature: reason", str(r.get("reason", "")) == "no_creature")


func _test_infection() -> void:
	var gs := _make_gs()
	gs.set_form(5)
	SporeNeedle.set_seed(7)
	var fc := _make_creature_node(_snapling_host())
	var r: Dictionary = SporeNeedle.fire_needle(gs, fc)
	_check("fire ok", bool(r.get("ok", false)))
	_check("fire infected", bool(r.get("infected", false)))
	_check("first unnamed lean is necrolean", str(r.get("lean", "")) == "necrolean")
	_check("[WIRING] infect msg", str(r.get("msg", "")).begins_with("[WIRING]"))
	var fc2 := _make_creature_node(_snapling_host())
	r = SporeNeedle.fire_needle(gs, fc2)
	_check("lean alternates to eternilean", str(r.get("lean", "")) == "eternilean")
	var fc3 := _make_creature_node(_snapling_host())
	r = SporeNeedle.fire_needle(gs, fc3, "eternilean")
	_check("named lean honored", str(r.get("lean", "")) == "eternilean")
	var st: Dictionary = SporeNeedle.stats(gs)
	_check("needles_fired == 3", int(st.get("needles_fired", 0)) == 3)
	_check("infections == 3", int(st.get("infections", 0)) == 3)
	# Infection marker is stored on the target.
	var marker: Dictionary = fc.get_meta("spore_host", {})
	_check("meta infected", bool(marker.get("infected", false)))
	_check("meta lean", str(marker.get("lean", "")) == "necrolean")
	# Warded target fails the needle (§12 seam).
	var warded := _make_creature_node(_snapling_host())
	warded.set_meta("spore_warded", true)
	r = SporeNeedle.fire_needle(gs, warded)
	_check("warded: ok false", not bool(r.get("ok", true)))
	_check("warded: reason", str(r.get("reason", "")) == "warded")
	_check("warded: no stat bump", int(SporeNeedle.stats(gs).get("infections", 0)) == 3)


func _test_battle_seam() -> void:
	var gs := _make_gs()
	var unit = BattleUnitScript.new("snapling", 5)
	_check("unit starts uninfected", not bool(unit.spore_infected))
	_check("infect_unit ok", SporeNeedle.infect_unit(unit, "eternilean"))
	var snap: Dictionary = SporeNeedle.battle_snapshot(unit)
	_check("snapshot infected", bool(snap.get("infected", false)))
	_check("snapshot lean", str(snap.get("lean", "")) == "eternilean")
	_check("snapshot creature", str(snap.get("creature_id", "")) == "snapling")
	_check("snapshot has traits", not (snap.get("traits", {}) as Dictionary).is_empty())
	_check("infect_unit null-safe", not SporeNeedle.infect_unit(null))
	# A fainted infected foe's death grows the plant.
	var res: Dictionary = SporeNeedle.on_creature_death(gs, snap)
	_check("infected faint grows", bool(res.get("grew", false)))
	_check("plant has id", str((res.get("plant", {}) as Dictionary).get("plant_id", "")) != "")
	# Uninfected faint grows nothing.
	var clean = BattleUnitScript.new("snapling", 5)
	res = SporeNeedle.on_creature_death(gs, SporeNeedle.battle_snapshot(clean))
	_check("uninfected faint grows nothing", not bool(res.get("grew", true)))
	# Null state is safe.
	res = SporeNeedle.on_creature_death(null, snap)
	_check("null gs safe", not bool(res.get("grew", true)))


func _test_death_to_plant() -> void:
	var gs := _make_gs()
	# Deterministic sampling: same host -> identical trait sample.
	var p1: Dictionary = SporeNeedle.grow_plant(gs, _snapling_host("necrolean"))
	var t1: Array = p1.get("fruit_traits", [])
	_check("sample size 1-3", t1.size() >= 1 and t1.size() <= 3)
	_check("sampled traits are host traits", _all_in(t1, _snapling_host()["traits"].values()))
	_check("no bare sampled", not t1.has("bare"))
	_check("tree lean from needle", str(p1.get("tree_lean", "")) == "necrolean")
	_check("plant not harvested", not bool(p1.get("harvested", true)))
	var p2: Dictionary = SporeNeedle.grow_plant(gs, _snapling_host("necrolean"))
	_check("plant ids unique", str(p1.get("plant_id", "")) != str(p2.get("plant_id", "")))
	# Determinism: same rng seed + same host traits -> identical sample
	# (grow_plant seeds per plant from host+plant_id, so each plant is
	# stable across save replays while differing from its siblings).
	var ra := RandomNumberGenerator.new()
	ra.seed = 1234
	var rb := RandomNumberGenerator.new()
	rb.seed = 1234
	var s1: Array = SporeNeedle._sample_traits(_snapling_host()["traits"], ra)
	var s2: Array = SporeNeedle._sample_traits(_snapling_host()["traits"], rb)
	_check("sampling deterministic", _arr_eq(s1, s2) and s1.size() >= 1)
	_check("plants_grown == 2", int(SporeNeedle.stats(gs).get("plants_grown", 0)) == 2)
	# Edge: single expressed trait -> exactly one sampled.
	var one := _snapling_host()
	one["traits"] = {"root": "walking_roots", "stem": "bare", "bloom": "bare",
		"leafset": "bare", "appendage": "bare", "armor": "bare",
		"accent": "bare", "eyes": "bare", "face": "bare"}
	var p3: Dictionary = SporeNeedle.grow_plant(gs, one)
	_check("single trait -> one sample", (p3.get("fruit_traits", []) as Array) == ["walking_roots"])
	# Edge: no expressed traits -> empty sample, plant still grows.
	var bare := _snapling_host()
	bare["traits"] = {"root": "bare", "stem": "bare"}
	var p4: Dictionary = SporeNeedle.grow_plant(gs, bare)
	_check("traitless host still grows", str(p4.get("plant_id", "")) != "")
	_check("traitless sample empty", (p4.get("fruit_traits", []) as Array).is_empty())


func _test_field_death_watch() -> void:
	var gs := _make_gs()
	gs.set_form(6)
	SporeNeedle.set_seed(3)
	var fc := _make_creature_node(_snapling_host())
	var r: Dictionary = SporeNeedle.fire_needle(gs, fc, "eternilean")
	_check("field fire ok", bool(r.get("ok", false)))
	_check("no plant before death", SporeNeedle.plants(gs).is_empty())
	fc.died.emit(fc)
	var grown: Array = SporeNeedle.plants(gs)
	_check("died signal grew a plant", grown.size() == 1)
	var plant: Dictionary = grown[0]
	_check("field plant host", str(plant.get("host_creature_id", "")) == "snapling")
	_check("field plant lean", str(plant.get("tree_lean", "")) == "eternilean")
	_check("field plant traits sampled", (plant.get("fruit_traits", []) as Array).size() >= 1)
	# A watched node that was never infected grows nothing on death.
	var clean := _make_creature_node(_snapling_host())
	clean.died.emit(clean)
	_check("uninfected death grows nothing", SporeNeedle.plants(gs).size() == 1)


func _test_harvest() -> void:
	var gs := _make_gs()
	gs.set_form(5)
	var fc := _make_creature_node(_snapling_host())
	SporeNeedle.fire_needle(gs, fc, "necrolean")
	fc.died.emit(fc)
	var plant: Dictionary = SporeNeedle.plants(gs)[0]
	var pid := str(plant.get("plant_id", ""))
	var r: Dictionary = SporeNeedle.harvest_plant(gs, "nope")
	_check("unknown plant refused", not bool(r.get("ok", true)))
	r = SporeNeedle.harvest_plant(gs, pid)
	_check("harvest ok", bool(r.get("ok", false)))
	_check("harvest [WIRING] msg", str(r.get("msg", "")).begins_with("[WIRING]"))
	var fid := str(r.get("fruit_id", ""))
	_check("fruit_id assigned", fid != "")
	# The fruit feeds the feeding loop: carried, lean == tree lean.
	var carried: Array = FeedingLoop.carried(gs)
	var found := {}
	for f in carried:
		if str((f as Dictionary).get("fruit_id", "")) == fid:
			found = f
	_check("fruit carried", not found.is_empty())
	_check("fruit lean is tree lean", str(found.get("lean", "")) == "necrolean")
	_check("fruit host_traits match plant",
		_arr_eq(found.get("host_traits", []), plant.get("fruit_traits", [])))
	_check("fruit spore_plant_id", str(found.get("spore_plant_id", "")) == pid)
	_check("fruit power hidden until eaten", bool(found.get("power_hidden", false)))
	# The harvested fruit is edible through the normal loop.
	var eat: Dictionary = FeedingLoop.eat(gs, fid)
	_check("harvested fruit edible", bool(eat.get("ok", false)))
	# Double harvest refused.
	r = SporeNeedle.harvest_plant(gs, pid)
	_check("double harvest refused", not bool(r.get("ok", true)))
	_check("double harvest reason", str(r.get("reason", "")) == "already_harvested")
	_check("plants_harvested == 1", int(SporeNeedle.stats(gs).get("plants_harvested", 0)) == 1)


func _test_achievement() -> void:
	var gs := _make_gs_with_ach()
	gs.set_form(5)
	# Two plants; the FIRST harvest fires spore_harvest, the second does not re-fire.
	for i in 2:
		var fc := _make_creature_node(_snapling_host())
		SporeNeedle.fire_needle(gs, fc, "necrolean")
		fc.died.emit(fc)
	var ids: Array = []
	for p in SporeNeedle.plants(gs):
		ids.append(str((p as Dictionary).get("plant_id", "")))
	_check("two plants", ids.size() == 2)
	var ach = gs.achievements
	_check("not unlocked before harvest", not ach.is_unlocked("spore_harvest"))
	var r1: Dictionary = SporeNeedle.harvest_plant(gs, ids[0])
	_check("first harvest flagged", bool(r1.get("first_harvest", false)))
	_check("spore_harvest unlocked", ach.is_unlocked("spore_harvest"))
	var r2: Dictionary = SporeNeedle.harvest_plant(gs, ids[1])
	_check("second harvest not first", not bool(r2.get("first_harvest", true)))
	_check("still unlocked once", ach.is_unlocked("spore_harvest"))
	_check("unlock count sane", ach.unlock_count() >= 1)


func _test_save_load() -> void:
	var gs := _make_gs()
	gs.set_form(5)
	var fc := _make_creature_node(_snapling_host())
	SporeNeedle.fire_needle(gs, fc, "eternilean")
	fc.died.emit(fc)
	var saved: Dictionary = SporeNeedle.save_data(gs)
	# JSON round-trip (what the save system actually persists).
	var blob := JSON.stringify(saved)
	var back = JSON.parse_string(blob)
	var gs2 := _make_gs()
	_check("load ok", SporeNeedle.load_data(gs2, back))
	_check("plant survived", SporeNeedle.plants(gs2).size() == 1)
	var p: Dictionary = SporeNeedle.plants(gs2)[0]
	_check("lean survived", str(p.get("tree_lean", "")) == "eternilean")
	_check("traits survived", (p.get("fruit_traits", []) as Array).size() >= 1)
	_check("stats survived", int(SporeNeedle.stats(gs2).get("plants_grown", 0)) == 1)
	_check("malformed refused", not SporeNeedle.load_data(gs2, {}))
	_check("malformed refused 2", not SporeNeedle.load_data(gs2, {"plants": {}}))
	# Harvest works after a load.
	var r: Dictionary = SporeNeedle.harvest_plant(gs2, str(p.get("plant_id", "")))
	_check("harvest after load", bool(r.get("ok", false)))


func _all_in(items: Array, pool) -> bool:
	var p := Array(pool)
	for it in items:
		if not p.has(it):
			return false
	return true


func _arr_eq(a, b) -> bool:
	var x := Array(a).duplicate()
	var y := Array(b).duplicate()
	x.sort()
	y.sort()
	return x == y
