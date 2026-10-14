extends SceneTree
## Headless contract from ENCOUNTER-IMPL-wrath / BOT-002 Q1-Q6.
## No capture algorithm, output odds or unapproved temperament data.
const Session := preload("res://scripts/encounter_session.gd")
var failures := 0
var checks := 0
var fruit_count := 2
var consume_calls := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[ENCOUNTER SESSION] " + label)

func _consume(item_id: String) -> bool:
	consume_calls += 1
	if item_id != "sample_fruit" or fruit_count <= 0:
		return false
	fruit_count -= 1
	return true

func _run() -> void:
	var records: Dictionary = {}
	var encounter = Session.new(records)
	_check(not encounter.register("", "sun", 288, 0.7),
		"blank creature identity is rejected before persistence")
	_check(not encounter.register("id_bad", "unknown", 288, 0.7),
		"no fabricated species lean enters persistent data")
	_check(not encounter.register("id_bad", "sun", -10, 0.7),
		"invalid awareness range rejected")
	_check(encounter.register("room_gd1_01", "sun", 288, 0.7),
		"first resident gains stable persistent record")
	_check(encounter.register("room_gd1_02", "shade", 288, 0.3),
		"two species can be noticed independently")
	_check(not encounter.register("room_gd1_01", "sun", 288, 0.7),
		"duplicate node registration does not clobber player memories")
	_check(records.size() == 2 and encounter.record_of("room_gd1_01").get("met") == false,
		"registering is not the same as meeting a creature")
	_check(encounter.notice("room_gd1_01", 1) and
		encounter.state_of("room_gd1_01") == Session.ATTENDING,
		"player entering awareness transitions ambient to attending")
	_check(bool(records["room_gd1_01"]["met"]),
		"first awareness records meeting without awarding a capture")
	_check(encounter.notice("room_gd1_02", 1),
		"multiple creatures can attend simultaneously")
	_check(encounter.try_ask("room_gd1_01", 1),
		"nearest eligible resident can open asking")
	_check(not encounter.try_ask("room_gd1_02", 1) and encounter.has_active_asking(),
		"second creature cannot open a simultaneous asking")
	_check(encounter.state_of("room_gd1_02") == Session.ATTENDING,
		"second creature's attending state survives active asking")
	_check(encounter.tend("room_gd1_01", 0.10, true),
		"director-supplied tending weight updates session")
	_check(is_equal_approx(float(records["room_gd1_01"]["warmth"]), 0.1),
		"tending adjusts warmth without awarding anything")
	_check(encounter.may_guide("room_gd1_01", true, 0.10) and
		not encounter.may_guide("room_gd1_01", false, 0.10),
		"Guide only offered with explicit open, baited, nearby Lullmother")
	_check(not encounter.offer("room_gd1_02", "sample_fruit", "sun"),
		"unselected creature cannot steal a fruit offering")
	_check(encounter.offer("room_gd1_01", "sample_fruit", "sun"),
		"offer is held, not transferred")
	_check(fruit_count == 2 and consume_calls == 0,
		"inventory untouched when presenting fruit")
	_check(encounter.answer_offer("room_gd1_01", "hold", Callable(self, "_consume")),
		"creature may deliberate on a held offering")
	_check(fruit_count == 2 and encounter.has_active_asking(),
		"holding a fruit is never consumption or forced ending")
	_check(encounter.answer_offer("room_gd1_01", "decline", Callable(self, "_consume")),
		"declining closes asking peacefully")
	_check(fruit_count == 2 and consume_calls == 0 and
		encounter.state_of("room_gd1_01") == Session.NEUTRAL,
		"declined fruit stays in inventory with neutral outcome")
	_check(encounter.notice("room_gd1_01", 1) and encounter.try_ask("room_gd1_01", 1),
		"neutral resident can be approached again")
	_check(encounter.offer("room_gd1_01", "sample_fruit", "shade"),
		"offer stores capture lean independently of fruit trait lean")
	_check(encounter.answer_offer("room_gd1_01", "eat_stay", Callable(self, "_consume")),
		"table-selected eat+stay outcome becomes interested")
	_check(fruit_count == 1 and consume_calls == 1 and
		encounter.state_of("room_gd1_01") == Session.INTERESTED,
		"fruit consumed ONCE at eat moment; still no capture awarded")
	_check(encounter.may_guide("room_gd1_01", true, 0.6),
		"interested outcome may guide to an eligible nearby plant")
	_check(not records["room_gd1_01"].has("captured") and
		not records["room_gd1_01"].has("mantle"),
		"interested does not create capture, mantle or unapproved benefit")
	_check(encounter.notice("room_gd1_01", 1) and encounter.try_ask("room_gd1_01", 1),
		"follow-up asking can begin with retained warmth")
	_check(encounter.offer("room_gd1_01", "sample_fruit", "sun"),
		"second held offering accepted")
	fruit_count = 0
	_check(not encounter.answer_offer("room_gd1_01", "eat_stay", Callable(self, "_consume")) and
		encounter.has_active_asking(),
		"inventory failure leaves creature asking; no phantom consumption")
	_check(encounter.walk_away("room_gd1_01") and
		encounter.state_of("room_gd1_01") == Session.NEUTRAL,
		"walking away without answer is neutral")
	_check(encounter.held_fruit.is_empty() and not encounter.has_active_asking(),
		"walking away clears held offering and UI-only state")
	_check(encounter.notice("room_gd1_01", 2) and encounter.try_ask("room_gd1_01", 2),
		"asking can reopen on next day")
	_check(encounter.withdraw("room_gd1_01", 2, 1) and
		int(records["room_gd1_01"]["wariness_until_day"]) == -1,
		"clean withdraw is safe and clears wariness")
	_check(encounter.state_of("room_gd1_02") == Session.ATTENDING and
		encounter.try_ask("room_gd1_02", 2),
		"already-attending second creature can take focus without new area entry")
	_check(encounter.set_approaching("room_gd1_02", true) and
		encounter.withdraw("room_gd1_02", 2, 1),
		"withdrawing mid-approach is wary, not neutral")
	_check(encounter.is_wary("room_gd1_02", 2) and
		int(records["room_gd1_02"]["wariness_until_day"]) == 3,
		"director-supplied one-day wariness stamp applies")
	_check(encounter.notice("room_gd1_02", 2) and
		encounter.state_of("room_gd1_02") == Session.WARY,
		"wary creature may still attend while outcome stays cold")
	_check(encounter.try_ask("room_gd1_02", 2) and
		encounter.push_wary("room_gd1_02", 2, 3),
		"explicit pushing of a wary creature escalates to scared off")
	_check(encounter.state_of("room_gd1_02") == Session.SCARED_OFF and
		int(records["room_gd1_02"]["wariness_until_day"]) == 5,
		"scared outcome persists three-day stamp from triggering day")
	_check(not encounter.notice("room_gd1_02", 3),
		"scared resident cannot be retriggered before day-stamp expires")
	_check(encounter.notice("room_gd1_02", 5),
		"resident may return when wariness day-stamp expires")
	_check(encounter.scare("room_gd1_01", 5, 3) and
		encounter.state_of("room_gd1_01") == Session.SCARED_OFF,
		"scythe anti-trigger scares without damaging or capturing")
	_check(not encounter.try_ask("room_gd1_01", 5),
		"scared creature cannot reopen encounter immediately")
	_check(encounter.try_ask("room_gd1_02", 5), "another attending creature can ask")
	var before: String = JSON.stringify(records)
	encounter.clear_runtime()
	_check(not encounter.has_active_asking() and
		encounter.state_of("room_gd1_02") == Session.ATTENDING,
		"save/reload cancels session, returns current resident to attending")
	_check(JSON.stringify(records) == before and
		encounter.held_fruit.is_empty(),
		"session reset does not corrupt relationship records")
	_check(not encounter.try_ask("missing", 1) and
		not encounter.scare("missing", 1, 3),
		"unknown identities cannot create stray encounter records")
	var recreated = Session.new(records)
	_check(recreated.register("room_gd1_01", "sun", 288, 0.7, 6) and
		is_equal_approx(float(recreated.record_of("room_gd1_01").get("warmth")), 0.10),
		"restoring scene from saved record preserves warmth, not reset to zero")
	_check(not recreated.has_active_asking(),
		"session's asking/held fruit are never serialized")
	# Isolated offer-cancel and pause cases must not mutate the main run.
	var cancel_data: Dictionary = {}
	var leaving = Session.new(cancel_data)
	_check(leaving.register("room_gd2_01", "rot", 288, 0.5) and
		leaving.notice("room_gd2_01", 3) and leaving.try_ask("room_gd2_01", 3),
		"offer-cancel fixture begins with normal asking")
	_check(leaving.offer("room_gd2_01", "sample_fruit", "rot") and
		leaving.cancel_offer("room_gd2_01", 3, 1),
		"clean held fruit withdrawal succeeds")
	_check(leaving.has_active_asking() and leaving.held_fruit.is_empty() and
		not leaving.is_wary("room_gd2_01", 3),
		"clean offer withdrawal neither consumes nor startles the creature")
	_check(leaving.offer("room_gd2_01", "sample_fruit", "rot") and
		leaving.set_approaching("room_gd2_01", true) and
		leaving.cancel_offer("room_gd2_01", 3, 1),
		"snapping offer back mid-approach causes WARY instead of neutral")
	_check(not leaving.has_active_asking() and
		leaving.state_of("room_gd2_01") == Session.WARY and
		int(cancel_data["room_gd2_01"]["wariness_until_day"]) == 4,
		"snapped offer persists the director-supplied one-day wariness stamp")
	_check(leaving.notice("room_gd2_01", 3) and
		leaving.try_ask("room_gd2_01", 3) and leaving.cancel_for_pause(),
		"pausing from a wary asking safely closes the transient UI")
	_check(not leaving.has_active_asking() and
		leaving.state_of("room_gd2_01") == Session.NEUTRAL and
		int(cancel_data["room_gd2_01"]["wariness_until_day"]) == 4,
		"pause has no extra penalty and does not silently erase saved wariness")
	_check(not leaving.cancel_for_pause(),
		"pause again without a live asking is an idempotent no-op")

	if failures == 0:
		print("[ENCOUNTER SESSION] PASS %d checks" % checks)
	else:
		push_error("[ENCOUNTER SESSION] FAIL %d/%d" % [failures, checks])
	quit(1 if failures > 0 else 0)
