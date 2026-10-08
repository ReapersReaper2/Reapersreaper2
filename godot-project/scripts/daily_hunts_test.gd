extends SceneTree
## Headless Daily Hunts verification: deterministic date-seeded generation,
## modifier pool, active-hunt lifecycle, local bests, Hall of Fame.
##
## Run: Godot --headless --path <project> -s res://scripts/daily_hunts_test.gd

const GameStateScript = preload("res://scripts/game_state.gd")
const DailyHuntsScript = preload("res://scripts/daily_hunts.gd")
const BountyBoardScript = preload("res://scripts/bounty_board.gd")

var _gs = null
var _passed := 0
var _failed := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] daily_hunts: ", label)


func _initialize() -> void:
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		_gs = GameStateScript.new()
		_gs.name = "GameState"
		root.add_child(_gs)
		_gs._ready()
	_gs.new_game()
	_run()
	_report()
	quit()


func _report() -> void:
	print("[daily_hunts_test] done: ", _passed, " passed, ", _failed, " failed")


func _run() -> void:
	_test_determinism()
	_test_modifiers()
	_test_lifecycle()
	_test_records()


func _test_determinism() -> void:
	# Same date = same hunt, byte-for-byte.
	var a: Dictionary = DailyHuntsScript.hunt_for("2026-10-05")
	var b: Dictionary = DailyHuntsScript.hunt_for("2026-10-05")
	_check(a["target_id"] == b["target_id"], "determinism: same date same target")
	_check(a["level"] == b["level"], "determinism: same date same level")
	_check(a["modifiers"] == b["modifiers"], "determinism: same date same modifiers")
	_check(a["reward"] == b["reward"], "determinism: same date same reward")
	# Different dates = (almost surely) different hunts. Check a spread.
	var seen_targets := {}
	var seen_mods := {}
	for day in range(1, 15):
		var h: Dictionary = DailyHuntsScript.hunt_for("2026-10-%02d" % day)
		seen_targets[h["target_id"]] = true
		for m in h["modifiers"]:
			seen_mods[m] = true
	_check(seen_targets.size() > 3, "variety: multiple targets across 14 days (got %d)" % seen_targets.size())
	_check(seen_mods.size() > 3, "variety: multiple modifiers across 14 days (got %d)" % seen_mods.size())
	# Hunt shape.
	_check(a.has("date") and a.has("target_name") and a.has("is_boss"), "shape: hunt has expected keys")
	_check(int(a["level"]) >= 5 and int(a["level"]) <= 30 or bool(a["is_boss"]), "shape: level in sane range")
	# FNV-1a is stable: known vector.
	_check(DailyHuntsScript.fnv1a("test") == 2949673445, "fnv1a: stable known vector")
	# Date formatting.
	_check(DailyHuntsScript.date_string(2026, 1, 5) == "2026-01-05", "date_string: zero-padded")


func _test_modifiers() -> void:
	_check(DailyHuntsScript.MODIFIER_IDS.size() == 8, "modifiers: pool has 8")
	for mid in DailyHuntsScript.MODIFIER_IDS:
		_check(not DailyHuntsScript.modifier_name(mid).is_empty(), "modifiers: name for " + mid)
		_check(not DailyHuntsScript.modifier_desc(mid).is_empty(), "modifiers: desc for " + mid)
	# 1-2 modifiers per hunt, distinct.
	for day in range(1, 8):
		var mods: Array = DailyHuntsScript.hunt_for("2026-11-%02d" % day)["modifiers"]
		_check(mods.size() >= 1 and mods.size() <= 2, "modifiers: 1-2 per hunt")
		var uniq := {}
		for m in mods:
			uniq[m] = true
		_check(uniq.size() == mods.size(), "modifiers: distinct within a hunt")
	# Spec examples exist in the pool.
	_check("no_armor" in DailyHuntsScript.MODIFIER_IDS, "modifiers: no_armor in pool")
	_check("bloom_double" in DailyHuntsScript.MODIFIER_IDS, "modifiers: bloom_double in pool")
	_check("invisible_foes" in DailyHuntsScript.MODIFIER_IDS, "modifiers: invisible_foes in pool")


func _test_lifecycle() -> void:
	_check(not DailyHuntsScript.is_active(_gs), "lifecycle: starts inactive")
	var hunt: Dictionary = DailyHuntsScript.start_hunt(_gs, "2026-10-05")
	_check(DailyHuntsScript.is_active(_gs), "lifecycle: active after start")
	_check(not hunt.is_empty(), "lifecycle: start returns hunt")
	# Modifier flags set for this hunt's modifiers, clear for others.
	for m in hunt["modifiers"]:
		_check(DailyHuntsScript.has_modifier(_gs, m), "lifecycle: modifier flag set: " + m)
	var other: String = "no_armor" if "no_armor" not in hunt["modifiers"] else "rich"
	if other not in hunt["modifiers"]:
		_check(not DailyHuntsScript.has_modifier(_gs, other), "lifecycle: non-picked modifier flag clear")
	# Complete: score > 0, best recorded, flags cleared.
	var res: Dictionary = DailyHuntsScript.complete_hunt(_gs, 120.0, 10)
	_check(not res.is_empty(), "lifecycle: complete returns result")
	_check(int(res["score"]) > 0, "lifecycle: score positive")
	_check(bool(res["is_best"]), "lifecycle: first clear is best")
	_check(not DailyHuntsScript.is_active(_gs), "lifecycle: inactive after complete")
	_check(not DailyHuntsScript.has_modifier(_gs, hunt["modifiers"][0]), "lifecycle: modifier flags cleared")
	# Completing with no active hunt is a safe no-op.
	var noop: Dictionary = DailyHuntsScript.complete_hunt(_gs, 60.0, 0)
	_check(noop.is_empty(), "lifecycle: complete with no active hunt is no-op")
	# Abandon clears state too.
	DailyHuntsScript.start_hunt(_gs, "2026-10-06")
	DailyHuntsScript.abandon_hunt(_gs)
	_check(not DailyHuntsScript.is_active(_gs), "lifecycle: abandon clears active")


func _test_records() -> void:
	# Best persists per date.
	DailyHuntsScript.start_hunt(_gs, "2026-10-07")
	var r1: Dictionary = DailyHuntsScript.complete_hunt(_gs, 300.0, 50)
	var best: Dictionary = DailyHuntsScript.best_for("2026-10-07", _gs)
	_check(not best.is_empty(), "records: best recorded")
	_check(int(best["score"]) == int(r1["score"]), "records: best matches clear score")
	# A worse clear does not overwrite.
	DailyHuntsScript.start_hunt(_gs, "2026-10-07")
	var r2: Dictionary = DailyHuntsScript.complete_hunt(_gs, 900.0, 200)
	_check(not bool(r2["is_best"]), "records: worse clear is not best")
	_check(int(DailyHuntsScript.best_for("2026-10-07", _gs)["score"]) == int(r1["score"]), "records: best kept")
	# A better clear overwrites.
	DailyHuntsScript.start_hunt(_gs, "2026-10-07")
	var r3: Dictionary = DailyHuntsScript.complete_hunt(_gs, 30.0, 0)
	_check(bool(r3["is_best"]), "records: better clear is best")
	_check(int(DailyHuntsScript.best_for("2026-10-07", _gs)["score"]) == int(r3["score"]), "records: best updated")
	# Hall of Fame: entries sorted desc, capped, one per date.
	var hof: Array = DailyHuntsScript.hall_of_fame(_gs)
	_check(hof.size() >= 2, "records: hof has entries")
	var sorted_ok := true
	for i in range(hof.size() - 1):
		if int(hof[i]["score"]) < int(hof[i + 1]["score"]):
			sorted_ok = false
	_check(sorted_ok, "records: hof sorted desc")
	var dates := {}
	for e in hof:
		_check(e.has("date") and e.has("target_name") and e.has("score"), "records: hof entry shape")
		dates[e["date"]] = true
	_check(dates.size() == hof.size(), "records: hof one entry per date")
	# Score formula sanity: faster/cleaner = higher.
	var s1: int = DailyHuntsScript.score_hunt(60.0, 0, 10)
	var s2: int = DailyHuntsScript.score_hunt(600.0, 100, 10)
	_check(s1 > s2, "records: faster/cleaner scores higher")
	_check(DailyHuntsScript.score_hunt(99999.0, 99999, 1) == 0, "records: score floors at 0")
	# Bounty board integration: the script wires the daily-hunt section.
	_check(BountyBoardScript != null, "board: bounty_board.gd preloads (wires TODAY'S HUNT section)")
	var _bb = BountyBoardScript.new()
	_check(_bb.has_method("_fill_daily_hunt"), "board: has _fill_daily_hunt")
	_check(_bb.has_method("_on_daily_hunt_pressed"), "board: has _on_daily_hunt_pressed")
	_bb.free()
