extends RefCounted
## Step driver: the single production source of "steps taken".
##
## Owns state["run"] — {run_id, started_at, steps_total} — and fans each
## step batch out to its consumers in a fixed, reviewable order (spec §5).
## ONLY StepDriver.advance() writes state["run"]["steps_total"];
## reset_run() writing 0 is run creation, not a second write path.
## Debug/test step injection goes through StepDriver.advance() too —
## never hand-bump the dict.
##
## DISAMBIGUATION: state["run"] / StepDriver.reset_run() have NOTHING to do
## with SpeedrunScript.start_run() (scripts/speedrun.gd). "Run" here means
## "this playthrough's step clock" (identity + step total persisted in the
## save payload); SpeedrunScript tracks timed speedrun attempts
## (state["stats"] speedrun_* keys). The names are unrelated.
##
## No class_name / autoload on purpose: consumers preload this script, so it
## works in headless -s test scripts too (autoloads don't load there;
## Godot 4.3 forbids class_name matching an autoload name) — same
## convention as feeding_loop.gd and breeding.gd:
##   const StepDriver = preload("res://scripts/step_driver.gd")
##
## Egg boundary (Tucker 01:06 EDT ruling, spec §5/§8 Q4): advance() must
## NEVER call Breeding.advance_eggs() and must never call on_day_advance().
## Eggs stay day-boundary in v1.

const FeedingLoop := preload("res://scripts/feeding_loop.gd")

## Pixels of player travel per step. Tuning (spec §8 Q1 — settled).
## Do NOT call 48px "one tile" in code or comments.
const PX_PER_STEP := 48.0


## Per-field malformed definitions (spec §2/C3).
static func _valid_run_id(run_id) -> bool:
	return run_id is String and not (run_id as String).is_empty()


static func _valid_started_at(v) -> bool:
	return v is int and int(v) >= 0


static func _valid_steps_total(v) -> bool:
	return v is int and int(v) >= 0


## Load-boundary int coercion (Tucker 04:21 EDT fix): Godot's
## JSON.stringify/parse_string converts every int to a float, so a save
## round-trip turns steps_total 250 into 250.0 — and the strict
## validators above would then "repair" it to 0, wiping the count.
## Coerce whole-number floats back to ints at the load boundary instead;
## the validators stay strict for genuinely-new data.
static func _coerce_nonneg_int(v, default: int) -> int:
	if v is int and int(v) >= 0:
		return int(v)
	if v is float and v >= 0.0 and v == floor(v):
		return int(v)
	return default


## Generate a run id: "run_<unix>_<8 hex>" (spec §2/C5).
## Seeded-RNG-safe: headless determinism tests seed the GLOBAL rng, so
## run ids draw from a separately-randomized generator — never the
## global stream — plus Time-derived entropy.
static func _generate_run_id() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var suffix := ""
	for i in 8:
		suffix += "%x" % rng.randi_range(0, 15)
	return "run_%d_%s" % [int(Time.get_unix_time_from_system()), suffix]


## Repair/create state["run"] to the §2 shape. Field-wise repair ONLY:
## preserves every valid field, repairs only invalid ones, and NEVER
## resets a valid steps_total because another field was malformed.
## Empty-run_id sentinel upgrade (migrated/default placeholder): generate
## a real id and set started_at to now *if it is 0*, preserving
## steps_total as-is. Idempotent.
static func ensure_run(gs) -> Dictionary:
	var s: Dictionary = gs.state
	if not s.has("run") or not (s["run"] is Dictionary):
		s["run"] = {}
	var run: Dictionary = s["run"]
	if not _valid_run_id(run.get("run_id", "")):
		run["run_id"] = _generate_run_id()
		if int(run.get("started_at", 0)) == 0:
			run["started_at"] = int(Time.get_unix_time_from_system())
	if not _valid_started_at(run.get("started_at", -1)):
		run["started_at"] = _coerce_nonneg_int(run.get("started_at", -1), int(Time.get_unix_time_from_system()))
	if not _valid_steps_total(run.get("steps_total", -1)):
		run["steps_total"] = _coerce_nonneg_int(run.get("steps_total", -1), 0)
	return run


## Fresh run: new id (generated, or injected for test determinism),
## started_at = now, steps_total = 0. Called by GameState.new_game().
## Writing 0 here is run creation — the only other write to steps_total
## anywhere is advance().
static func reset_run(gs, run_id: String = "") -> Dictionary:
	var rid := run_id
	if rid.is_empty():
		rid = _generate_run_id()
	gs.state["run"] = {
		"run_id": rid,
		"started_at": int(Time.get_unix_time_from_system()),
		"steps_total": 0,
	}
	return gs.state["run"]


## Read-only accessors (via ensure_run, so they also repair).
static func get_steps(gs) -> int:
	return int(ensure_run(gs).get("steps_total", 0))


static func get_run_id(gs) -> String:
	return str(ensure_run(gs).get("run_id", ""))


## THE advancement entry. Order:
##   (1) ensure_run — the run section always exists before anything moves.
##   (2) edge semantics (C6): n == 0 -> no-op, no fan-out, returns current
##       totals; n < 0 -> no-op with push_error, NO fan-out (consumers must
##       not fire on a rejected call); n > 0 -> steps_total += n, fan out
##       exactly once.
##   (3) fan out to consumers in fixed order (spec §5):
##       1. FeedingLoop.on_steps_taken(gs, n) -> result under "feeding".
##          Feeding is shipped and canon-locked; the 1,200-step rot
##          boundary resolves before any new consumer reacts to the
##          same step batch.
##       2. Corpse-plant on-plant step timers — RESERVED slot. The plants
##          module owns its own seam; it is NOT wired here. When the
##          first genuine R22 step consumer lands, its result goes under
##          the additive "r22" key. R15 (mortal-world check) and R14
##          (husk fade) are event-triggered, NOT step consumers — they
##          never get a slot here (Grimley boundary correction, §5).
##   (4) return {"steps_total": int, "feeding": {...}, "anomalies": [...]}.
## §9 loud-failure channel: consumer anomalies are collected into the
## "anomalies" array via _collect_consumer_anomalies (§9.5/§9.4 case 1).
## Eggs are NOT fanned out: never advance_eggs / on_day_advance (§8 Q4).
static func _collect_consumer_anomalies(result, consumer_name: String, steps_total: int, anomalies: Array) -> Dictionary:
	if not (result is Dictionary):
		push_error("step_driver: advance: consumer '%s' returned a malformed result (not a Dictionary)" % consumer_name)
		anomalies.append({
			"kind": "consumer_malformed",
			"consumer": consumer_name,
			"steps_total": steps_total,
			"detail": "result is not a Dictionary",
		})
		return {}
	var res: Dictionary = result
	if not res.has("rotted"):
		push_error("step_driver: advance: consumer '%s' result missing 'rotted' key" % consumer_name)
		anomalies.append({
			"kind": "consumer_malformed",
			"consumer": consumer_name,
			"steps_total": steps_total,
			"detail": "result missing 'rotted' key",
		})
	if res.get("anomalies") is Array:
		for record in res.get("anomalies"):
			if record is Dictionary:
				anomalies.append(record)
				push_error("step_driver: advance: consumer '%s' anomaly: %s" % [consumer_name, str(record)])
	return res


static func advance(gs, n: int) -> Dictionary:
	var run := ensure_run(gs)
	var total := int(run.get("steps_total", 0))
	var anomalies: Array = []
	if n == 0:
		return {"steps_total": total, "feeding": {}, "anomalies": anomalies}
	if n < 0:
		push_error("step_driver: advance: negative step count %d rejected (no fan-out)" % n)
		return {"steps_total": total, "feeding": {}, "anomalies": anomalies}
	run["steps_total"] = total + n
	var feeding := FeedingLoop.on_steps_taken(gs, n)
	feeding = _collect_consumer_anomalies(feeding, "feeding", int(run["steps_total"]), anomalies)
	return {"steps_total": int(run["steps_total"]), "feeding": feeding, "anomalies": anomalies}
