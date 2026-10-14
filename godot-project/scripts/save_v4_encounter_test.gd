extends SceneTree
## Persistent encounter data must never corrupt older saves or invent captures.
const Save := preload("res://scripts/save_system.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[ENCOUNTER SAVE V4] " + label)

func _run() -> void:
	var ss = Save.new()
	root.add_child(ss)
	_check(Save.SAVE_VERSION == 4, "v4 migration selected explicitly")
	var fresh: Dictionary = Save.default_save()
	var section: Dictionary = fresh.get("encounters", {})
	_check(section.get("creatures") is Dictionary and (section["creatures"] as Dictionary).is_empty(),
		"fresh encounters have no fabricated bonds or creatures")
	_check(section.get("lullmothers") is Array and (section["lullmothers"] as Array).is_empty(),
		"fresh encounters have no planted pods")
	_check(int(section.get("pod_stock", -1)) == 0 and
		not bool(section.get("seen_lurk_warning", true)),
		"no pod stock or tutorial trigger awarded on new game")

	var old: Dictionary = Save.default_save()
	old["save_version"] = 3
	old.erase("encounters")
	old["flags"]["key_story_flag"] = true
	old["player"]["form"] = 3
	old["run"]["steps_total"] = 789
	var migrated: Dictionary = ss.migrate(old)
	_check(int(migrated.get("save_version", -1)) == 4 and migrated.has("encounters"),
		"v3 save upgrades to v4 additively")
	_check(int(migrated["player"]["form"]) == 3 and
		int(migrated["run"]["steps_total"]) == 789 and
		bool(migrated["flags"]["key_story_flag"]),
		"migration preserves player progress, step counter and story flags")
	var again: String = JSON.stringify(ss.migrate(migrated.duplicate(true)))
	_check(again == JSON.stringify(migrated), "migration is idempotent")

	var planted := {
		"id": "lm_run1_0",
		"state": "rooting",
		"root_minutes_left": 12.25,
		"resolved_dusk": -1,
		"maturity": 4,
		"extra_future_field": 31,
	}
	var partial: Dictionary = Save.default_save()
	partial["save_version"] = 3
	partial["encounters"] = {
		"creatures": {"room_gd1_01": {
			"warmth": 0.72, "wariness_until_day": 5,
			"last_outcome": "interested",
		}},
		"lullmothers": [planted],
		"pod_stock": 7,
		"pod_production": {"per_day": 0.16, "unknown_depth": 8},
		"seen_lurk_warning": true,
		"unknown_encounter_field": "preserve",
	}
	var upgraded: Dictionary = ss.migrate(partial)
	_check(int(upgraded["encounters"]["pod_stock"]) == 7 and
		bool(upgraded["encounters"]["seen_lurk_warning"]),
		"existing nursery stock and teaching flag survive migration")
	_check(is_equal_approx(float(upgraded["encounters"]["creatures"]["room_gd1_01"]["warmth"]), 0.72) and
		int(upgraded["encounters"]["creatures"]["room_gd1_01"]["wariness_until_day"]) == 5,
		"creature identity, warmth and wariness stamps survive migration")
	_check(is_equal_approx(float(upgraded["encounters"]["lullmothers"][0]["root_minutes_left"]),12.25) and
		int(upgraded["encounters"]["lullmothers"][0]["maturity"]) == 4 and
		int(upgraded["encounters"]["lullmothers"][0]["resolved_dusk"]) == -1,
		"plant rooting, maturity and idempotency state survive migration")
	_check(upgraded["encounters"]["unknown_encounter_field"] == "preserve" and
		int(upgraded["encounters"]["pod_production"]["unknown_depth"]) == 8,
		"forward-compatible unknown fields are preserved verbatim")
	_check(is_equal_approx(float(upgraded["encounters"]["pod_production"]["per_day"]), 0.16),
		"non-default production accumulator is not overwritten")
	var malformed: Dictionary = Save.default_save()
	malformed["save_version"] = 3
	malformed["encounters"] = {"creatures": "broken", "lullmothers": 5,
		"pod_stock": -10, "pod_production": {"per_day": "broken"},
		"seen_lurk_warning": 100}
	var repaired: Dictionary = ss.migrate(malformed)
	_check(repaired["encounters"]["creatures"] is Dictionary and
		repaired["encounters"]["lullmothers"] is Array,
		"malformed encounter sections safely repaired")
	_check(int(repaired["encounters"]["pod_stock"]) == 0 and
		not bool(repaired["encounters"]["seen_lurk_warning"]),
		"invalid stock/flag repaired to harmless defaults")
	_check(is_equal_approx(float(repaired["encounters"]["pod_production"]["per_day"]),0.333),
		"invalid rate repaired to nonactive proposed schema default")
	var v1: Dictionary = Save.default_save()
	v1["save_version"] = 1
	v1.erase("party")
	v1.erase("run")
	v1.erase("encounters")
	var full: Dictionary = ss.migrate(v1)
	_check(int(full.get("save_version", -1)) == 4 and
		full.has("party") and full.has("run") and full.has("encounters"),
		"v1 save upgrades all the way through v2/v3/v4")
	var future: Dictionary = Save.default_save()
	future["save_version"] = 5
	_check(ss.migrate(future).is_empty(), "future save cannot be downgraded")

	if failures == 0:
		print("[ENCOUNTER SAVE V4] PASS %d checks" % checks)
	else:
		push_error("[ENCOUNTER SAVE V4] FAIL %d/%d" % [failures, checks])
	quit(1 if failures > 0 else 0)
