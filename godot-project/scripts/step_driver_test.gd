extends SceneTree
## Step driver — headless test (spec STEP-DRIVER-SPEC REV 2 §7).
##
## Covers:
##   A. ensure_run field-wise repair (C3): a type error in one field repairs
##      only that field — a valid steps_total is never reset.
##   B. ensure_run sentinel upgrade: empty run_id -> real id, started_at set
##      iff 0, steps preserved.
##   C. reset_run: fresh id (suffix >= 8 hex), seeded-RNG-safe, injected id
##      respected (C5); new_game() issues unique ids.
##   D. advance() edge semantics (C6): n == 0 no-op, no fan-out; n < 0 no-op
##      + push_error, no fan-out. (push_error writes to stderr; not
##      assertable headless — the no-op side is asserted.)
##   E. advance() fans out to FeedingLoop exactly once, matching a direct
##      on_steps_taken call on an identical fixture; end-to-end: 1200 steps
##      through the driver rots a carried fruit (§9 acceptance).
##   F. migrate_v2_to_v3: grants run, preserves a valid run, field-wise
##      repair; SaveSystem never preloads StepDriver (source check).
##   G. Player odometer: synthetic displacement advances steps (C1);
##      wall-press ~0 (C1); teleport 0 (C1); tendril ride 0 (C2);
##      move_locked / input_locked 0 (C2); flight counts (v1, §8 Q2);
##      standing still 0; out-of-tree player records nothing.
##   H. Save/load round trip preserves run_id and steps_total (§9).
##   I. §9 anomalies channel: advance() returns "anomalies" (present and
##      empty) on all three return paths; _collect_consumer_anomalies
##      malformed check (§9.5) + consumer aggregation (§9.4 case 1).
##
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/step_driver_test.gd
## (Autoloads are not loaded under -s, so scripts are instantiated via load();
## the player-odometer tests use the /root/GameState autoload like flight_test.gd.)

const StepDriver := preload("res://scripts/step_driver.gd")
const FeedingLoop := preload("res://scripts/feeding_loop.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const SaveSystemScript := preload("res://scripts/save_system.gd")
const PlayerScript := preload("res://scripts/player.gd")

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


## "run_<unix>_<8+ hex>" (spec §2/C5).
func _is_run_id(rid: String) -> bool:
	var parts := rid.split("_")
	if parts.size() != 3:
		return false
	if parts[0] != "run":
		return false
	if not parts[1].is_valid_int():
		return false
	if parts[2].length() < 8:
		return false
	for c in parts[2]:
		if not "0123456789abcdef".contains(c):
			return false
	return true


func _make_player() -> Node:
	var player = PlayerScript.new()
	player.name = "StepOdoPlayer"
	root.add_child(player)  # _ready runs: _step_odo = 0.0
	return player


func _free_player(p: Node) -> void:
	if is_instance_valid(p):
		if p.get_parent() != null:
			p.get_parent().remove_child(p)
		p.free()  # immediate: queue_free leaves stale player-group lookups


func _init() -> void:
	print("[step_driver_test] starting")
	seed(12345)  # pin the global RNG: run ids must NOT come from this stream (C5)
	_run.call_deferred()


func _run() -> void:
	_test_ensure_run_repair()
	_test_json_float_coercion()
	_test_sentinel_upgrade()
	_test_reset_run()
	_test_advance_edges()
	_test_advance_fanout()
	_test_rot_end_to_end()
	_test_migration()
	_test_default_save_run()
	_test_odometer_synthetic()
	_test_standing_still()
	_test_wall_press()
	_test_teleport()
	_test_tendril_ride()
	_test_locks()
	_test_flight_counts()
	_test_out_of_tree_guard()
	_test_save_load_run()
	var total := _passes + _failures
	print("[TEST] step_driver: %d passed, %d failed (of %d)" % [_passes, _failures, total])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


# --- A/B: ensure_run ------------------------------------------------------

func _test_ensure_run_repair() -> void:
	var gs := _make_gs()
	# A type error in started_at must not wipe a valid steps_total (C3).
	gs.state["run"] = {"run_id": "run_9_abcdef12", "started_at": "oops", "steps_total": 42}
	var run: Dictionary = StepDriver.ensure_run(gs)
	_check("repair keeps valid run_id", str(run.get("run_id", "")) == "run_9_abcdef12")
	_check("repair fixes started_at only", (run.get("started_at", -1) is int) and int(run.get("started_at", -1)) >= 0)
	_check("repair never resets valid steps_total", int(run.get("steps_total", 0)) == 42)
	# Negative steps_total repairs to 0; missing section is created.
	gs.state["run"] = {"run_id": "run_9_abcdef12", "started_at": 5, "steps_total": -3}
	var run2: Dictionary = StepDriver.ensure_run(gs)
	_check("negative steps_total repairs to 0", int(run2.get("steps_total", -1)) == 0)
	_check("repair keeps valid run_id (2)", str(run2.get("run_id", "")) == "run_9_abcdef12")
	gs.state.erase("run")
	var run3: Dictionary = StepDriver.ensure_run(gs)
	_check("missing run section created", _is_run_id(str(run3.get("run_id", ""))))
	_check("created run starts at 0 steps", int(run3.get("steps_total", -1)) == 0)
	# Idempotent: a second call changes nothing.
	var snap := str(run3.get("run_id", ""))
	var run4: Dictionary = StepDriver.ensure_run(gs)
	_check("ensure_run idempotent", str(run4.get("run_id", "")) == snap)


func _test_json_float_coercion() -> void:
	var gs := _make_gs()
	# JSON round-trip (Tucker 04:21 EDT fix): parse_string turns every
	# int into a float. Whole-number floats coerce back, not reset.
	gs.state["run"] = {"run_id": "run_9_abcdef12", "started_at": 1791234567.0, "steps_total": 250.0}
	var run: Dictionary = StepDriver.ensure_run(gs)
	_check("float steps_total coerces to int", int(run.get("steps_total", -1)) == 250)
	_check("coerced steps_total is int", run.get("steps_total", -1) is int)
	_check("float started_at coerces to int", int(run.get("started_at", -1)) == 1791234567)
	# A fractional float is genuinely malformed -> falls back to default.
	gs.state["run"] = {"run_id": "run_9_abcdef12", "started_at": 1791234567.5, "steps_total": 42.7}
	var run2: Dictionary = StepDriver.ensure_run(gs)
	_check("fractional steps_total falls back to 0", int(run2.get("steps_total", -1)) == 0)
	_check("fractional started_at falls back to now", (run2.get("started_at", -1) is int) and int(run2.get("started_at", -1)) > 1791234567)


func _test_sentinel_upgrade() -> void:
	var gs := _make_gs()
	# Migrated/default placeholder: "" run_id, 0 started_at.
	gs.state["run"] = {"run_id": "", "started_at": 0, "steps_total": 7}
	var run: Dictionary = StepDriver.ensure_run(gs)
	_check("sentinel run_id upgraded to real id", _is_run_id(str(run.get("run_id", ""))))
	_check("sentinel started_at set to now", int(run.get("started_at", 0)) > 0)
	_check("sentinel steps preserved", int(run.get("steps_total", 0)) == 7)
	# Empty run_id but nonzero started_at: id upgraded, started_at kept.
	gs.state["run"] = {"run_id": "", "started_at": 12345, "steps_total": 9}
	var run2: Dictionary = StepDriver.ensure_run(gs)
	_check("sentinel keeps nonzero started_at", int(run2.get("started_at", 0)) == 12345)
	_check("sentinel steps preserved (2)", int(run2.get("steps_total", 0)) == 9)


# --- C: reset_run ---------------------------------------------------------

func _test_reset_run() -> void:
	var gs := _make_gs()
	var run: Dictionary = StepDriver.reset_run(gs)
	_check("reset_run id format", _is_run_id(str(run.get("run_id", ""))))
	_check("reset_run zeroes steps", int(run.get("steps_total", -1)) == 0)
	_check("reset_run started_at now", int(run.get("started_at", 0)) > 0)
	var first_id := StepDriver.get_run_id(gs)
	var run2: Dictionary = StepDriver.reset_run(gs)
	_check("reset_run issues fresh id", str(run2.get("run_id", "")) != first_id)
	_check("get_steps reads 0 after reset", StepDriver.get_steps(gs) == 0)
	# Injected id (test determinism, C5).
	var injected := StepDriver.reset_run(gs, "run_1_deadbeef01")
	_check("reset_run honors injected id", str(injected.get("run_id", "")) == "run_1_deadbeef01")
	_check("get_run_id returns injected id", StepDriver.get_run_id(gs) == "run_1_deadbeef01")
	# Seeded-RNG safety: two draws under the same global seed must differ —
	# run ids draw from a separately-randomized generator, never the
	# global stream the determinism tests seed.
	seed(12345)
	var a := str(StepDriver.reset_run(gs).get("run_id", ""))
	seed(12345)
	var b := str(StepDriver.reset_run(gs).get("run_id", ""))
	_check("run ids ignore the seeded global RNG", a != b)
	# new_game() wires reset_run: unique id per game, steps zeroed.
	var gs2 := _make_gs()
	var id_a := StepDriver.get_run_id(gs2)
	StepDriver.advance(gs2, 50)
	gs2.new_game()
	_check("new_game issues unique run_id", StepDriver.get_run_id(gs2) != id_a)
	_check("new_game zeroes steps", StepDriver.get_steps(gs2) == 0)


# --- D: advance() edges ---------------------------------------------------

func _test_advance_edges() -> void:
	var gs := _make_gs()
	var fid := FeedingLoop.carry(gs, FeedingLoop.pick_fruit("gloomcap", 3))
	_check("carried for edge tests", fid != "")
	var r0: Dictionary = StepDriver.advance(gs, 0)
	_check("advance(0) returns shape", r0.has("steps_total") and r0.has("feeding") and r0.has("anomalies"))
	_check("advance(0) returns totals", int(r0.get("steps_total", -1)) == 0)
	_check("advance(0) no fan-out", (r0.get("feeding", {}) as Dictionary).is_empty())
	_check("advance(0) anomalies present and empty", (r0.get("anomalies", null) is Array) and (r0.get("anomalies", []) as Array).is_empty())
	_check("advance(0) fruit untouched", int((FeedingLoop.carried(gs)[0] as Dictionary).get("steps_carried", -1)) == 0)
	var rn: Dictionary = StepDriver.advance(gs, -1)
	_check("advance(-1) returns totals unchanged", int(rn.get("steps_total", -1)) == 0)
	_check("advance(-1) no fan-out", (rn.get("feeding", {}) as Dictionary).is_empty())
	_check("advance(-1) anomalies present and empty", (rn.get("anomalies", null) is Array) and (rn.get("anomalies", []) as Array).is_empty())
	_check("advance(-1) fruit untouched", int((FeedingLoop.carried(gs)[0] as Dictionary).get("steps_carried", -1)) == 0)
	# push_error fires to stderr on the negative path — not assertable
	# headless; the no-op side above is the asserted half.
	var r10: Dictionary = StepDriver.advance(gs, 10)
	_check("advance(10) returns shape", r10.has("steps_total") and r10.has("feeding") and r10.has("anomalies"))
	_check("advance(10) bumps once", int(r10.get("steps_total", -1)) == 10)
	_check("advance(10) anomalies present and empty", (r10.get("anomalies", null) is Array) and (r10.get("anomalies", []) as Array).is_empty())
	_check("advance(10) get_steps agrees", StepDriver.get_steps(gs) == 10)


# --- E: fan-out -----------------------------------------------------------

func _test_advance_fanout() -> void:
	var gs1 := _make_gs()
	var gs2 := _make_gs()
	# Identical fixtures: seeded concoctions + per-save picked counter.
	var id1 := FeedingLoop.carry(gs1, FeedingLoop.pick_fruit("gloomcap", 42))
	var id2 := FeedingLoop.carry(gs2, FeedingLoop.pick_fruit("gloomcap", 42))
	_check("identical fixtures carry same id", id1 == id2)
	var via_driver: Dictionary = StepDriver.advance(gs1, 500)
	var direct: Dictionary = FeedingLoop.on_steps_taken(gs2, 500)
	var c1: Dictionary = FeedingLoop.carried(gs1)[0]
	var c2: Dictionary = FeedingLoop.carried(gs2)[0]
	_check("driver fan-out matches direct call", int(c1.get("steps_carried", -1)) == 500 and int(c1.get("steps_carried", -1)) == int(c2.get("steps_carried", -2)))
	_check("driver feeding result matches direct", str((via_driver.get("feeding", {}) as Dictionary).get("rotted", [])) == str(direct.get("rotted", [])))
	_check("driver bumps steps_total once", int(via_driver.get("steps_total", -1)) == 500)
	_check("direct feeding call never writes the clock", StepDriver.get_steps(gs2) == 0)
	# --- §9: consumer anomalies channel — helper unit tests (b)/(c) ---
	# (b) {} and non-Dict results -> consumer_malformed record, correct
	# shape (§9.3: kind, consumer, steps_total, detail).
	var mal1: Array = []
	var feed1: Dictionary = StepDriver._collect_consumer_anomalies({}, "feeding", 10, mal1)
	_check("helper {} -> feeding substituted to empty dict", feed1.is_empty())
	_check("helper {} -> one malformed record", mal1.size() == 1)
	var rec1: Dictionary = mal1[0]
	_check("helper {} -> consumer_malformed shape", str(rec1.get("kind", "")) == "consumer_malformed" and str(rec1.get("consumer", "")) == "feeding" and int(rec1.get("steps_total", -1)) == 10 and rec1.has("detail"))
	var mal2: Array = []
	var feed2: Dictionary = StepDriver._collect_consumer_anomalies("oops", "feeding", 10, mal2)
	_check("helper non-Dict -> feeding substituted to empty dict", feed2.is_empty())
	_check("helper non-Dict -> consumer_malformed shape", mal2.size() == 1 and str((mal2[0] as Dictionary).get("kind", "")) == "consumer_malformed" and (mal2[0] as Dictionary).has("detail"))
	# (c) {"rotted": [], "anomalies": [rot_missed record]} -> aggregated
	# verbatim into the shared array (§9.4 case 1).
	var rot_missed := {"kind": "rot_missed", "consumer": "feeding", "steps_total": 10, "detail": "fruit missed rot window"}
	var mal3: Array = []
	var feed3: Dictionary = StepDriver._collect_consumer_anomalies({"rotted": [], "anomalies": [rot_missed]}, "feeding", 10, mal3)
	_check("helper keeps valid feeding dict", feed3.has("rotted"))
	_check("helper aggregates consumer anomalies verbatim", mal3.size() == 1 and str((mal3[0] as Dictionary)) == str(rot_missed))


## §9 acceptance: walking a carried fruit 1200 steps rots it VIA THE
## DRIVER (advance() fan-out), not via a direct on_steps_taken call.
func _test_rot_end_to_end() -> void:
	var gs := _make_gs()
	var fid := FeedingLoop.carry(gs, FeedingLoop.pick_fruit("gloomcap", 7))
	_check("carried for rot test", fid != "")
	for i in 12:
		var r: Dictionary = StepDriver.advance(gs, 100)
		_check("advance batch %d accumulates" % i, int(r.get("steps_total", -1)) == (i + 1) * 100)
	var fruit: Dictionary = FeedingLoop.carried(gs)[0]
	_check("1200 steps via driver rots the fruit", bool(fruit.get("rotted", false)))
	_check("driver clock reads 1200", StepDriver.get_steps(gs) == 1200)
	_check("rotted stat counted via driver", int((FeedingLoop.save_data(gs)["stats"] as Dictionary).get("rotted", 0)) == 1)
	_check("rotted fruit uneatable", not bool((FeedingLoop.eat(gs, fid) as Dictionary).get("ok", true)))


# --- F: migration ---------------------------------------------------------

func _test_migration() -> void:
	var ss = SaveSystemScript.new()
	# v2 payload (no run key) gains the placeholder; version stamps 3.
	var v2: Dictionary = SaveSystemScript.default_save()
	v2.erase("run")
	v2["save_version"] = 2
	var v3: Dictionary = ss.migrate_v2_to_v3(v2)
	_check("migrate_v2_to_v3 stamps version 3", int(v3.get("save_version", 0)) == 3)
	var granted: Dictionary = v3.get("run", {})
	_check("migrate_v2_to_v3 grants run", not granted.is_empty())
	_check("granted run_id is the empty sentinel", str(granted.get("run_id", "x")) == "")
	_check("granted steps are 0", int(granted.get("steps_total", -1)) == 0)
	# A valid existing run is never overwritten.
	var v2b: Dictionary = SaveSystemScript.default_save()
	v2b["save_version"] = 2
	v2b["run"] = {"run_id": "run_1_abcd1234", "started_at": 5, "steps_total": 300}
	var v3b: Dictionary = ss.migrate_v2_to_v3(v2b)
	var kept: Dictionary = v3b["run"]
	_check("migration keeps valid run", str(kept.get("run_id", "")) == "run_1_abcd1234" and int(kept.get("steps_total", 0)) == 300)
	# Malformed run: field-wise repair, valid steps preserved.
	var v2c: Dictionary = SaveSystemScript.default_save()
	v2c["save_version"] = 2
	v2c["run"] = {"run_id": 123, "started_at": "oops", "steps_total": 42}
	var v3c: Dictionary = ss.migrate_v2_to_v3(v2c)
	var fixed: Dictionary = v3c["run"]
	_check("migration repairs malformed fields", str(fixed.get("run_id", "x")) == "" and int(fixed.get("started_at", -1)) == 0)
	_check("migration preserves valid steps on repair", int(fixed.get("steps_total", 0)) == 42)
	# Full migrate() chain picks up case 2:.
	var v2d: Dictionary = SaveSystemScript.default_save()
	v2d.erase("run")
	v2d["save_version"] = 2
	var chained: Dictionary = ss.migrate(v2d)
	_check("migrate() chain runs v2->v3", int(chained.get("save_version", 0)) == 3 and (chained.get("run", {}) as Dictionary).has("run_id"))
	# SaveSystem must never preload StepDriver (preload-cycle boundary).
	var src := FileAccess.get_file_as_string("res://scripts/save_system.gd")
	_check("SaveSystem independent of StepDriver", src.find("step_driver.gd") < 0)
	ss.free()


func _test_default_save_run() -> void:
	var d: Dictionary = SaveSystemScript.default_save()
	_check("default_save has run section", d.has("run"))
	var run: Dictionary = d.get("run", {})
	_check("default_save run placeholders", str(run.get("run_id", "x")) == "" and int(run.get("started_at", -1)) == 0 and int(run.get("steps_total", -1)) == 0)


# --- G: player odometer ---------------------------------------------------
## These drive a real ReaperPlayer fixture's _physics_process with the
## /root/GameState autoload (flight_test.gd pattern), so
## player._game_state() resolves and StepDriver.advance() fires.

func _test_odometer_synthetic() -> void:
	var gs: Node = root.get_node("GameState")
	gs.new_game()
	var player = _make_player()
	player.global_position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	# ~2.94 px/frame of real displacement (velocity re-asserted each
	# frame; _physics_process decays it): 120 frames ≈ 353 px ≈ 7 steps.
	for i in 120:
		player.velocity = Vector2(200, 0)
		player._physics_process(1.0 / 60.0)
	var steps := StepDriver.get_steps(gs)
	_check("synthetic displacement advances steps", steps >= 6 and steps <= 8)
	_check("odometer keeps remainder < PX_PER_STEP", player._step_odo >= 0.0 and player._step_odo < StepDriver.PX_PER_STEP)
	_free_player(player)


func _test_standing_still() -> void:
	var gs: Node = root.get_node("GameState")
	gs.new_game()
	var player = _make_player()
	player.global_position = Vector2(100, 100)
	player.velocity = Vector2.ZERO
	for i in 30:
		player._physics_process(1.0 / 60.0)
	_check("standing still accrues 0 steps", StepDriver.get_steps(gs) == 0)
	_free_player(player)


func _test_wall_press() -> void:
	# C1: pressing into a wall moves ~0 px — velocity * delta would count
	# phantom steps; the displacement odometer counts ~0.
	var gs: Node = root.get_node("GameState")
	gs.new_game()
	var player = _make_player()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 8.0
	shape.shape = circle
	player.add_child(shape)
	var wall := StaticBody2D.new()
	var wshape := CollisionShape2D.new()
	var seg := SegmentShape2D.new()
	seg.a = Vector2(9.0, -500.0)
	seg.b = Vector2(9.0, 500.0)
	wshape.shape = seg
	wall.add_child(wshape)
	root.add_child(wall)
	player.global_position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	Input.action_press("move_right")
	for i in 60:
		player._physics_process(1.0 / 60.0)
	Input.action_release("move_right")
	_check("wall-press accrues 0 steps", StepDriver.get_steps(gs) == 0)
	root.remove_child(wall)
	wall.free()
	_free_player(player)


func _test_teleport() -> void:
	# C1: the per-frame baseline is re-captured every frame, so a teleport
	# never appears as one giant displacement.
	var gs: Node = root.get_node("GameState")
	gs.new_game()
	var player = _make_player()
	player.velocity = Vector2.ZERO
	player.global_position = Vector2(5000, 5000)
	player._physics_process(1.0 / 60.0)
	_check("teleport accrues 0 steps", StepDriver.get_steps(gs) == 0)
	_free_player(player)


func _test_tendril_ride() -> void:
	# C2: tendril_riding zeroes every frame even while the ride moves the
	# player hundreds of pixels.
	var gs: Node = root.get_node("GameState")
	gs.new_game()
	var player = _make_player()
	player.tendril_riding = true
	player.velocity = Vector2.ZERO
	for i in 10:
		player.global_position += Vector2(60, 0)
		player._physics_process(1.0 / 60.0)
	_check("tendril ride accrues 0 steps", StepDriver.get_steps(gs) == 0)
	player.tendril_riding = false
	_free_player(player)


func _test_locks() -> void:
	# C2: move_locked / input_locked zero steps by construction — the body
	# still moves, but nothing is recorded. Baselines re-captured during
	# locked frames, so no phantom step fires on unlock.
	var gs: Node = root.get_node("GameState")
	gs.new_game()
	var player = _make_player()
	player.global_position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	player.move_locked = true
	for i in 30:
		player.velocity = Vector2(200, 0)
		player._physics_process(1.0 / 60.0)
	_check("move_locked accrues 0 steps", StepDriver.get_steps(gs) == 0)
	_check("move_locked keeps odometer at 0", player._step_odo == 0.0)
	player.move_locked = false
	player.input_locked = true
	player.global_position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	for i in 30:
		player.velocity = Vector2(200, 0)
		player._physics_process(1.0 / 60.0)
	_check("input_locked accrues 0 steps", StepDriver.get_steps(gs) == 0)
	player.input_locked = false
	player.velocity = Vector2.ZERO
	player._physics_process(1.0 / 60.0)
	_check("no phantom step after unlock", StepDriver.get_steps(gs) == 0)
	_free_player(player)


func _test_flight_counts() -> void:
	# v1 behavior (spec §8 Q2 settled): flight is NOT a no-count guard.
	var gs: Node = root.get_node("GameState")
	gs.new_game()
	var player = _make_player()
	player.flying = true
	player.global_position = Vector2.ZERO
	player.velocity = Vector2.ZERO
	for i in 120:
		player.velocity = Vector2(200, 0)
		player._physics_process(1.0 / 60.0)
	_check("flight distance counts steps (v1)", StepDriver.get_steps(gs) >= 6)
	player.flying = false
	_free_player(player)


func _test_out_of_tree_guard() -> void:
	# player._game_state() returns null outside the tree — the odometer
	# records nothing (no StepDriver call at all).
	var gs: Node = root.get_node("GameState")
	gs.new_game()
	var before := StepDriver.get_steps(gs)
	var player = PlayerScript.new()  # never added to the tree
	player.velocity = Vector2(200, 0)
	player._physics_process(1.0 / 60.0)
	_check("out-of-tree player records nothing", StepDriver.get_steps(gs) == before and player._step_odo == 0.0)
	player.free()


# --- H: save/load round trip ----------------------------------------------

func _test_save_load_run() -> void:
	# §9 acceptance: mid-run shrine save -> reload preserves run identity.
	# Uses throwaway slot 90 (save_test.gd uses 90-99, minus 90).
	var save_system_script = load("res://scripts/save_system.gd")
	var game_state_script = load("res://scripts/game_state.gd")
	var sscript = save_system_script.new()
	root.add_child(sscript)
	var gs = game_state_script.new()
	gs.save_system = sscript
	root.add_child(gs)
	# Under -s, _ready() does not auto-fire — invoke explicitly to exercise
	# the real production boot path (new_game -> reset_run).
	gs._ready()
	StepDriver.advance(gs, 250)
	var rid := StepDriver.get_run_id(gs)
	_check("save_to_slot(90)", gs.save_to_slot(90))
	StepDriver.advance(gs, 100)
	_check("load_from_slot(90)", gs.load_from_slot(90))
	_check("reload preserves run_id", StepDriver.get_run_id(gs) == rid)
	_check("reload preserves steps_total", StepDriver.get_steps(gs) == 250)
	sscript.delete_save(90)
	root.remove_child(gs)
	gs.free()
	root.remove_child(sscript)
	sscript.free()
