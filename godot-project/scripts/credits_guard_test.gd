extends SceneTree
## Credits debit regression: negative prices cannot mint money while
## legitimately free actions remain accepted.
## godot --headless --path godot-project --script res://scripts/credits_guard_test.gd

const GameStateScript := preload("res://scripts/game_state.gd")
var _checks := 0
var _fails := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var gs := GameStateScript.new()
	gs.new_game()
	var start := gs.get_soul_credits()
	_check(start == GameStateScript.STARTING_CREDITS, "starter balance intact")
	_check(not gs.spend_soul_credits(-1), "negative one credit cost refused")
	_check(not gs.spend_soul_credits(-2147483648), "large negative cost refused")
	_check(gs.get_soul_credits() == start, "invalid costs never mint credits")
	_check(gs.spend_soul_credits(0), "free transactions stay available")
	_check(gs.get_soul_credits() == start, "free transaction does not debit")
	_check(gs.spend_soul_credits(95), "positive price debits normally")
	_check(gs.get_soul_credits() == start - 95, "positive price subtracts once")
	_check(not gs.spend_soul_credits(start + 1), "unaffordable price is refused")
	_check(gs.get_soul_credits() == start - 95,
		"insufficient credits do not corrupt balance")
	gs.add_soul_credits(95)
	_check(gs.get_soul_credits() == start, "refunds still credit normally")
	var json := JSON.stringify(gs.state)
	var saved = JSON.parse_string(json)
	_check(saved is Dictionary and
		int((saved as Dictionary).get("soul_credits", -1)) == start,
		"save serialization preserves the valid credit balance")
	if _fails == 0:
		print("[CREDITS GUARD] PASS %d checks" % _checks)
	else:
		push_error("[CREDITS GUARD] FAIL %d/%d checks" % [_fails, _checks])
	quit(1 if _fails > 0 else 0)

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		push_error("[CREDITS GUARD] " + message)
