extends SceneTree
## Per-individual Lullmother encounter memory: director D-36/D-38/D-39.
## No attachment, automatic bond, cost, narrative, or cooldown invented.
## godot --headless --path godot-project --script res://scripts/offer_memory_test.gd

const Memory := preload("res://scripts/offer_memory.gd")
const Party := preload("res://scripts/party.gd")
const GameState := preload("res://scripts/game_state.gd")
const Breeding := preload("res://scripts/breeding.gd")

var _checks := 0
var _failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var gs = GameState.new()
	gs.new_game()
	var log := Memory.field_log(gs)
	var a := Party.make_entry("snapling", 5)
	var b := Party.make_entry("snapling", 5)
	_check(a.has("offer_memory") and b.has("offer_memory"),
		"each new creature has its own offer memory")
	_check(not Memory.can_attempt_attunement(a), "never visited is not ready")
	_check(log.is_empty(), "new run encounter log starts empty")
	_check(not Memory.record_outcome(a, "", "a-1", Memory.OUTCOME_NEUTRAL, log)["ok"],
		"no species-level fallback when individual reference is missing")
	_check(not a["offer_memory"].has("neutral_visits"),
		"invalid identity does not mutate memory")
	var one = Memory.record_outcome(a, "instance-A", "encounter-A1", Memory.OUTCOME_NEUTRAL, log)
	_check(one["ok"] and one["changed"], "neutral fed/stayed visit recorded")
	_check(int(Memory.snapshot(a).get("neutral_visits", -1)) == 1,
		"first neutral visit increments one individual's counter")
	_check(not Memory.can_attempt_attunement(a),
		"first neutral observation does not produce a bond")
	var same = Memory.record_outcome(a, "instance-A", "encounter-A1", Memory.OUTCOME_NEUTRAL, log)
	_check(same["ok"] and not same["changed"], "double tap is idempotent")
	_check(int(Memory.snapshot(a).get("neutral_visits", -1)) == 1,
		"double tap cannot become two visits")
	_check(int(Memory.snapshot(b).get("neutral_visits", 0)) == 0,
		"two individuals of same species never share progress")
	Memory.record_outcome(a, "instance-A", "encounter-A2", Memory.OUTCOME_NEUTRAL, log)
	_check(Memory.can_attempt_attunement(a),
		"second distinct neutral visit permits a later attunement attempt")
	_check(not a.has("bonded") and (a.get("mantles", []) as Array).is_empty(),
		"two visits do not auto-bond or mint a mantle")
	Memory.record_outcome(a, "instance-A", "encounter-A3", Memory.OUTCOME_NEUTRAL, log)
	_check(int(Memory.snapshot(a)["neutral_visits"]) == 2,
		"neutral readiness is capped at the two-visit threshold")

	# Refusal never writes a tended marker, even after a neutral visit.
	Memory.record_outcome(b, "instance-B", "encounter-B1", Memory.OUTCOME_NEUTRAL, log)
	var rejected := Memory.record_outcome(b, "instance-B", "encounter-B2",
		Memory.OUTCOME_WITHDREW, log)
	_check(rejected["ok"] and int(Memory.snapshot(b)["neutral_visits"]) == 1,
		"withdrawal does not count as a neutral visit")
	_check(bool(Memory.snapshot(b)["reoffer_blocked"]) and
		bool(Memory.snapshot(b)["reoffer_rule_pending"]),
		"hard refusal safely blocks reoffers pending director interval ruling")
	_check(not b.has("tended") and (b.get("mantles", []) as Array).is_empty(),
		"refusal never marks tended or grants a mantle")
	_check(log.size() == 1 and str((log[0] as Dictionary)["individual_ref"]) == "instance-B",
		"refusal enters the field log at individual scope")
	var ignored := Memory.record_outcome(b, "instance-B", "encounter-B3",
		Memory.OUTCOME_NEUTRAL, log)
	_check(not ignored["ok"] and str(ignored["reason"]) == "reoffer_pending_ruling",
		"no immediate retry bypasses the unresolved reoffer interval")
	_check(int(Memory.snapshot(b)["neutral_visits"]) == 1 and log.size() == 1,
		"blocked attempts do not change visits or journal")
	_check(Memory.reopen_after_ruling(b), "explicit ruling seam can reopen offers")
	_check(not bool(Memory.snapshot(b).get("reoffer_blocked", false)),
		"explicit reopen clears lock without resetting history")
	_check(log.size() == 1 and (Memory.snapshot(b)["outcomes"] as Array).size() == 2,
		"reopening preserves refusal history")
	_check(not Memory.reopen_after_ruling(a),
		"unblocked creature cannot be spuriously reopened")

	var corrupt := {"offer_memory": {"encounters_seen": "not-an-array"}}
	var before := JSON.stringify(corrupt)
	_check(not Memory.record_outcome(corrupt, "instance-C", "C1",
		Memory.OUTCOME_NEUTRAL, log)["ok"], "malformed memory rejected")
	_check(JSON.stringify(corrupt) == before, "malformed write is transactional")
	_check(not Memory.record_outcome(a, "instance-A", "A4", "AUTO_BOND", log)["ok"],
		"unapproved automatic bonding outcome rejected")
	_check(log.size() == 1, "invalid outcomes cannot generate journal entries")
	var snapshot := Memory.snapshot(b)
	snapshot["neutral_visits"] = 999
	_check(int(Memory.snapshot(b)["neutral_visits"]) == 1,
		"readers cannot mutate the creature's stored memory")

	_check(Party.append_entry(gs, b), "individual with memory joins saved party")
	b["offer_memory"].clear()
	_check(int(Memory.snapshot(Party.get_entry(gs, Party.size(gs) - 1))["neutral_visits"]) == 1,
		"party insertion deep copies individual history")
	var entry := Party.get_entry(gs, Party.size(gs) - 1)
	_check(not Breeding._snapshot(entry).has("offer_memory"),
		"breeding snapshots do not inherit encounter memory")
	var serialized := JSON.stringify(gs.state)
	var recovered = JSON.parse_string(serialized)
	_check(recovered is Dictionary, "save format remains JSON serializable")
	if recovered is Dictionary:
		_check((recovered as Dictionary).get("field_encounters", []).size() == 1,
			"field refusal persists across save/reload")
		_check(((((recovered as Dictionary)["party"] as Array).back() as Dictionary).get(
			"offer_memory", {}) as Dictionary).get("neutral_visits", 0) == 1,
			"individual visit count persists across save/reload")

	if _failed == 0:
		print("[OFFER MEMORY] PASS %d checks" % _checks)
	else:
		push_error("[OFFER MEMORY] FAIL %d/%d checks" % [_failed, _checks])
	quit(1 if _failed > 0 else 0)

func _check(ok: bool, detail: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		push_error("[OFFER MEMORY] " + detail)
