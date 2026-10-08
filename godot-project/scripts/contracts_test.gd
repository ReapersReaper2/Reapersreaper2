extends SceneTree
## Bounty contract system — headless test.
##
## Covers: contracts.json loads, accept flow, prereq gating (flag +
## contract chain), Kanryu NOT takeable, objective progress (reap /
## catch / collect / flag), completion, turn-in pays credits + items,
## completed contracts can't be re-accepted, persistence across
## save/load, journal lists accepted contracts.

const ContractsScript := preload("res://scripts/contracts.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const JournalScript := preload("res://scripts/journal.gd")
const BountyBoardScript := preload("res://scripts/bounty_board.gd")

var _failures := 0
var _passes := 0


func _check(name: String, cond: bool) -> void:
	if cond:
		_passes += 1
		print("  PASS: ", name)
	else:
		_failures += 1
		print("  FAILED: ", name)


func _make_gs() -> Node:
	var gs = GameStateScript.new()
	gs.save_system = null  # avoid file IO; state stays in memory
	gs.new_game()
	return gs


func _init() -> void:
	print("[contracts_test] starting")
	_run.call_deferred()


func _run() -> void:
	var gs = _make_gs()

	# --- Data loads ---
	var all: Array = ContractsScript.load_contracts()
	_check("contracts.json loads (%d contracts)" % all.size(), all.size() >= 6)
	var ids := ContractsScript.contract_ids()
	for want in ["c_strays", "c_pods", "c_siltmaw", "c_bellowscap", "c_gravebind", "c_snarer", "c_puff"]:
		_check("contract %s defined" % want, want in ids)

	# --- Kanryu is NOT a contract ---
	_check("kanryu not a contract id", not ("kanryu" in ids))
	_check("kanryu accept fails", not ContractsScript.accept(gs, "kanryu"))
	_check("unknown id accept fails", not ContractsScript.accept(gs, "nope"))
	# Sealed entry still on the board data.
	var board := BountyBoardScript.load_board()
	_check("kanryu still sealed on board", bool(board.get("kanryu", {}).get("sealed", false)))

	# --- Accept flow ---
	_check("c_strays status available", ContractsScript.status(gs, "c_strays") == "available")
	_check("accept c_strays", ContractsScript.accept(gs, "c_strays"))
	_check("c_strays accepted", ContractsScript.is_accepted(gs, "c_strays"))
	_check("accepted flag set", gs.get_flag("contract_c_strays_accepted"))
	_check("status accepted after accept", ContractsScript.status(gs, "c_strays") == "accepted")
	_check("double accept fails", not ContractsScript.accept(gs, "c_strays"))

	# --- Prereq gating: flag ---
	_check("c_siltmaw locked before tutorial", ContractsScript.status(gs, "c_siltmaw") == "locked")
	_check("c_siltmaw accept fails before tutorial", not ContractsScript.accept(gs, "c_siltmaw"))
	gs.set_flag("h1_board_read")
	_check("c_siltmaw available after tutorial", ContractsScript.status(gs, "c_siltmaw") == "available")
	_check("c_siltmaw accepts now", ContractsScript.accept(gs, "c_siltmaw"))

	# --- Prereq gating: contract chain ---
	_check("c_puff locked before c_strays done", ContractsScript.status(gs, "c_puff") == "locked")
	_check("c_puff accept fails early", not ContractsScript.accept(gs, "c_puff"))

	# --- Objective progress: reap ---
	var prog: Array = ContractsScript.objectives_progress(gs, "c_strays")
	_check("c_strays has 1 objective", prog.size() == 1)
	_check("c_strays starts 0/4", int(prog[0]["current"]) == 0 and not bool(prog[0]["done"]))
	ContractsScript.record_reap(gs, "wispwillow")
	ContractsScript.record_reap(gs, "wispwillow")
	prog = ContractsScript.objectives_progress(gs, "c_strays")
	_check("c_strays 2/4 after 2 reaps", int(prog[0]["current"]) == 2)
	_check("c_strays not complete at 2/4", not ContractsScript.is_complete(gs, "c_strays"))
	ContractsScript.record_reap(gs, "siltmaw")  # wrong species: no progress
	prog = ContractsScript.objectives_progress(gs, "c_strays")
	_check("wrong species doesn't count", int(prog[0]["current"]) == 2)
	ContractsScript.record_reap(gs, "wispwillow")
	ContractsScript.record_reap(gs, "wispwillow")
	_check("c_strays complete at 4/4", ContractsScript.is_complete(gs, "c_strays"))
	_check("status ready when complete", ContractsScript.status(gs, "c_strays") == "ready")

	# --- Objective progress: catch ---
	_check("accept c_snarer", ContractsScript.accept(gs, "c_snarer"))
	ContractsScript.record_catch(gs, "siltmaw")
	prog = ContractsScript.objectives_progress(gs, "c_snarer")
	_check("c_snarer 1/2 after catch", int(prog[0]["current"]) == 1)
	ContractsScript.record_catch(gs, "floatbladder")
	_check("c_snarer complete (any x2)", ContractsScript.is_complete(gs, "c_snarer"))

	# --- Objective progress: collect ---
	_check("accept c_pods", ContractsScript.accept(gs, "c_pods"))
	ContractsScript.record_collect(gs, "creep_pod")
	_check("c_pods complete after 1 pod", ContractsScript.is_complete(gs, "c_pods"))

	# --- Turn-in pays credits + items ---
	var before: int = gs.get_soul_credits()
	var snares_before: int = gs.get_item_count("soul_snare")
	var res := ContractsScript.turn_in(gs, "c_strays")
	_check("turn_in c_strays ok", bool(res.get("ok", false)))
	_check("turn_in pays 400 credits", int(res.get("credits", 0)) == 400)
	_check("credits landed", gs.get_soul_credits() == before + 400)
	_check("turned_in recorded", ContractsScript.is_turned_in(gs, "c_strays"))
	_check("done flag set", gs.get_flag("contract_c_strays_done"))
	_check("status done after turn-in", ContractsScript.status(gs, "c_strays") == "done")
	_check("completed contract can't be re-accepted", not ContractsScript.accept(gs, "c_strays"))
	# Item rewards.
	res = ContractsScript.turn_in(gs, "c_pods")
	_check("c_pods turn-in ok", bool(res.get("ok", false)))
	_check("c_pods grants 2 snares", gs.get_item_count("soul_snare") == snares_before + 2)
	# Chain prereq now satisfied.
	_check("c_puff available after c_strays turned in", ContractsScript.status(gs, "c_puff") == "available")
	# Turn-in before completion fails.
	_check("turn_in incomplete fails", not bool(ContractsScript.turn_in(gs, "c_siltmaw").get("ok", false)))

	# --- Journal lists accepted contracts ---
	var j = JournalScript.new()
	j.game_state = gs
	root.add_child(j)
	j._ready()
	j._tab = 0
	j._refresh()
	var found := false
	for row in j._rows:
		if str((row as Dictionary).get("kind", "")) == "contract":
			found = true
	_check("journal QUESTS tab lists contracts", found)
	# Turned-in contracts drop off the journal list.
	j._refresh()
	var done_listed := false
	for row in j._rows:
		var r: Dictionary = row
		if str(r.get("kind", "")) == "contract" and str(r.get("id", "")) == "c_strays":
			done_listed = true
	_check("turned-in contract leaves journal list", not done_listed)
	j.queue_free()

	# --- Persistence across save/load ---
	var gs2 = _make_gs()
	gs2.state = gs.state.duplicate(true)  # simulate a save round-trip
	_check("accepted survives round-trip", ContractsScript.is_accepted(gs2, "c_siltmaw"))
	_check("turned_in survives round-trip", ContractsScript.is_turned_in(gs2, "c_strays"))
	_check("flags survive round-trip", gs2.get_flag("contract_c_strays_done"))
	ContractsScript.record_reap(gs2, "siltmaw")
	prog = ContractsScript.objectives_progress(gs2, "c_siltmaw")
	# 1 carried over from the pre-round-trip "wrong species" reap + 1 new.
	_check("progress counts survive round-trip", int(prog[0]["current"]) == 2)

	print("[contracts_test] %d passed, %d failed" % [_passes, _failures])
	quit(1 if _failures > 0 else 0)
