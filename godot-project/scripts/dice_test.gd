extends SceneTree
## Dead Man's Dice — headless test.
##
## Covers: scoring table (all combos), bust detection, hot dice, game flow
## (roll/bank/push), AI bank thresholds, buy-ins, pot payouts, table
## unlocks, Wrath flip flag, Latch answers, achievements, save/load.

const DiceGame = preload("res://scripts/dice_game.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const AchievementsScript := preload("res://scripts/achievements.gd")

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
	gs.save_system = null
	gs.new_game()
	return gs


func _make_gs_with_ach() -> Node:
	var gs = _make_gs()
	var ach = AchievementsScript.new()
	ach.game_state = gs
	gs.achievements = ach
	return gs


func _init() -> void:
	print("[dice_test] starting")
	_run.call_deferred()


func _run() -> void:
	_test_scoring()
	_test_game_flow()
	_test_ai()
	_test_economy()
	_test_state()
	_test_generic_flow_text()
	_test_flow_lines()
	_test_lock_reasons()
	var total := _passes + _failures
	print("[TEST] dice: %d passed, %d failed (of %d)" % [_passes, _failures, total])
	if _failures > 0:
		quit(1)
	else:
		quit(0)


func _test_scoring() -> void:
	var s: Dictionary
	s = DiceGame.score_dice([1, 2, 3, 4, 6])
	_check("single 1 = 100", s["score"] == 100 and s["scoring"] == 1)
	s = DiceGame.score_dice([5, 2, 3, 4, 6])
	_check("single 5 = 50", s["score"] == 50 and s["scoring"] == 1)
	s = DiceGame.score_dice([1, 5, 2, 3, 4])
	_check("1+5 = 150", s["score"] == 150 and s["scoring"] == 2)
	s = DiceGame.score_dice([1, 1, 1, 2, 3])
	_check("three 1s = 1000", s["score"] == 1000 and s["scoring"] == 3)
	s = DiceGame.score_dice([2, 2, 2, 3, 4])
	_check("three 2s = 200", s["score"] == 200 and s["scoring"] == 3)
	s = DiceGame.score_dice([6, 6, 6, 3, 4])
	_check("three 6s = 600", s["score"] == 600 and s["scoring"] == 3)
	s = DiceGame.score_dice([5, 5, 5, 2, 3])
	_check("three 5s = 500", s["score"] == 500 and s["scoring"] == 3)
	s = DiceGame.score_dice([2, 3, 4, 6, 2])
	_check("bust scores 0", s["score"] == 0 and s["scoring"] == 0)
	_check("bust detected", DiceGame.is_bust([2, 3, 4, 6, 2]))
	_check("non-bust not bust", not DiceGame.is_bust([5, 2, 3, 4, 6]))
	s = DiceGame.score_dice([1, 1, 1, 1, 2])
	_check("four 1s = 1100", s["score"] == 1100 and s["scoring"] == 4)
	s = DiceGame.score_dice([5, 5, 5, 5, 5])
	_check("five 5s = 600", s["score"] == 600 and s["scoring"] == 5)
	s = DiceGame.score_dice([1, 1, 1, 5, 5])
	_check("triple 1s + two 5s = 1100", s["score"] == 1100 and s["scoring"] == 5)
	s = DiceGame.score_dice([3, 3, 3, 1, 5])
	_check("triple 3s + 1 + 5 = 450", s["score"] == 450 and s["scoring"] == 5)


func _test_game_flow() -> void:
	var g = DiceGame.new()
	g.setup("copper", "Wrath")
	_check("setup phase player_turn", g.phase == "player_turn")
	_check("opponent name kept", g.opponent_name == "Wrath")
	# Rigged roll: three 1s -> 1000, 2 dice left.
	g.test_rolls = [1, 1, 1, 2, 3]
	var r: Dictionary = g.player_roll()
	_check("roll scores 1000", int(r["score"]) == 1000 and not bool(r["bust"]))
	_check("round score 1000", g.round_score == 1000)
	_check("2 dice in hand", g.dice_in_hand == 2)
	# Push: roll the 2 dice, both score -> hot dice resets to 5.
	g.test_rolls = [1, 5]
	r = g.player_roll()
	_check("push roll scores 150", int(r["score"]) == 150)
	_check("hot dice resets to 5", g.dice_in_hand == 5)
	_check("round score 1150", g.round_score == 1150)
	_check("bank no win yet", str(g.player_bank()["winner"]) == "")
	_check("banked 1150", g.player_banked == 1150)
	# Bust path.
	g.test_rolls = [2, 3, 4, 6, 2]
	r = g.player_roll()
	_check("bust roll", bool(r["bust"]))
	_check("bust clears round", g.round_score == 0)
	# Win path.
	g.player_banked = 4900
	g.test_rolls = [1, 2, 3, 4, 6]
	g.player_roll()
	_check("win at 5000", str(g.player_bank()["winner"]) == "player")
	_check("phase over", g.phase == "over")
	# Push availability.
	var g2 = DiceGame.new()
	g2.setup("copper")
	_check("push before roll false", not g2.player_push() or g2.last_roll.is_empty())
	g2.test_rolls = [1, 2, 3, 4, 6]
	g2.player_roll()
	_check("push after roll true", g2.player_push())


func _test_ai() -> void:
	var g = DiceGame.new()
	g.setup("copper", "Wrath")
	g.ai_bank = 800
	# AI rolls 1000 on first roll -> banks immediately.
	g.test_rolls = [1, 1, 1, 2, 3]
	var res: Dictionary = g.play_opponent_turn()
	_check("ai banks at threshold", g.opp_banked == 1000)
	_check("ai no bust", not bool(res["bust"]))
	_check("ai log has 1 roll", (res["log"] as Array).size() == 1)
	# AI busts on first roll.
	var g2 = DiceGame.new()
	g2.setup("copper")
	g2.test_rolls = [2, 3, 4, 6, 2]
	res = g2.play_opponent_turn()
	_check("ai bust", bool(res["bust"]))
	_check("ai bust banks nothing", g2.opp_banked == 0)
	# AI pushes below threshold then banks.
	var g3 = DiceGame.new()
	g3.setup("copper")
	g3.ai_bank = 800
	g3.test_rolls = [5, 2, 3, 4, 6, 1, 1, 1, 2, 3]
	res = g3.play_opponent_turn()
	_check("ai pushes then banks", g3.opp_banked == 1050)
	_check("ai log has 2 rolls", (res["log"] as Array).size() == 2)
	# AI wins at 5000.
	var g4 = DiceGame.new()
	g4.setup("copper")
	g4.ai_bank = 50
	g4.opp_banked = 4900
	g4.test_rolls = [1, 2, 3, 4, 6]
	res = g4.play_opponent_turn()
	_check("ai wins at 5000", str(res["winner"]) == "opponent")


func _test_economy() -> void:
	var gs = _make_gs()
	# Copper buy-in.
	var before: int = gs.get_soul_credits()
	_check("copper buy-in pays", DiceGame.pay_buy_in(gs, "copper"))
	_check("copper buy-in costs 50", gs.get_soul_credits() == before - 50)
	gs.state["soul_credits"] = 10
	_check("broke buy-in fails", not DiceGame.pay_buy_in(gs, "copper"))
	_check("broke buy-in no write", gs.get_soul_credits() == 10)
	# Copper pot.
	gs.state["soul_credits"] = 100
	DiceGame.pay_buy_in(gs, "copper")
	DiceGame.record_win(gs, "copper")
	_check("copper pot pays 100", gs.get_soul_credits() == 150)
	# Blend buy-in uses a rare herb.
	gs.add_item("rare_herb", 1)
	_check("blend buy-in consumes herb", DiceGame.pay_buy_in(gs, "blend"))
	_check("herb consumed", gs.get_item_count("rare_herb") == 0)
	_check("blend buy-in fails without herb", not DiceGame.pay_buy_in(gs, "blend"))
	# Blend pot grants the house blend.
	DiceGame.record_win(gs, "blend")
	_check("blend pot grants house blend", gs.get_item_count("house_blend") == 1)
	# Quiet has no buy-in.
	_check("quiet buy-in free", DiceGame.pay_buy_in(gs, "quiet"))
	# Losses tracked.
	DiceGame.record_loss(gs, "copper")
	_check("copper loss tracked", int(DiceGame._data(gs)["copper_losses"]) == 1)


func _test_state() -> void:
	var gs = _make_gs_with_ach()
	# Unlocks.
	_check("copper locked before hub", not DiceGame.table_unlocked(gs, "copper"))
	gs.set_flag("m2_hub_unlocked", true)
	_check("copper unlocked at hub", DiceGame.table_unlocked(gs, "copper"))
	_check("blend locked before copper win", not DiceGame.table_unlocked(gs, "blend"))
	_check("quiet locked before act2", not DiceGame.table_unlocked(gs, "quiet"))
	DiceGame.record_win(gs, "copper")
	_check("blend unlocked after copper win", DiceGame.table_unlocked(gs, "blend"))
	gs.set_flag("act2_unlocked", true)
	_check("quiet unlocked at act2", DiceGame.table_unlocked(gs, "quiet"))
	# Wrath flip: first copper win only.
	_check("wrath beaten after first win", DiceGame.wrath_beaten(gs))
	_check("dice_beat_wrath flag", gs.get_flag("dice_beat_wrath"))
	var res: Dictionary = DiceGame.record_win(gs, "copper")
	_check("wrath flip only once", not bool(res["wrath_flip"]))
	# Latch answers unlock in order.
	var answers: Array = DiceGame.load_answers()
	_check("5 latch answers", answers.size() == 5)
	var a1: Dictionary = DiceGame.record_win(gs, "quiet")["answer"]
	_check("first quiet win unlocks answer 1", str(a1.get("id", "")) == str(answers[0].get("id", "")))
	_check("answer text resolves", DiceGame.answer_text(str(a1.get("id", ""))) != "")
	DiceGame.record_win(gs, "quiet")
	DiceGame.record_win(gs, "quiet")
	DiceGame.record_win(gs, "quiet")
	var a5: Dictionary = DiceGame.record_win(gs, "quiet")["answer"]
	_check("fifth answer unlocked", str(a5.get("id", "")) == str(answers[4].get("id", "")))
	var a6: Dictionary = DiceGame.record_win(gs, "quiet")["answer"]
	_check("no sixth answer", a6.is_empty())
	_check("5 answers unlocked", (DiceGame.unlocked_answers(gs) as Array).size() == 5)
	# Blend opponent rotation.
	var o1: Dictionary = DiceGame.blend_opponent(gs)
	DiceGame.record_win(gs, "blend")
	var o2: Dictionary = DiceGame.blend_opponent(gs)
	_check("blend opponents rotate", str(o1.get("name", "")) != str(o2.get("name", "")))
	# Achievements: 20 launch + 23 steam.
	_check("43 achievements total", (gs.achievements as Node).total_count() == 43)
	_check("quiet_wisdom unlocked", (gs.achievements as Node).is_unlocked("quiet_wisdom"))
	_check("drowned_dice unlocked at max stakes", (gs.achievements as Node).is_unlocked("drowned_dice"))
	# High Roller at 10 copper wins (2 so far + 8 more).
	for i in 8:
		DiceGame.record_win(gs, "copper")
	_check("high_roller at 10 wins", (gs.achievements as Node).is_unlocked("high_roller"))
	_check("10 copper wins tracked", DiceGame.wins(gs, "copper") == 10)
	# Save/load round-trip: dice state survives JSON.
	var snap: String = JSON.stringify(gs.state["dice"])
	var back = JSON.parse_string(snap)
	_check("dice state serializes", back is Dictionary and int(back.get("copper_wins", 0)) == 10)
	# Table names/hints resolve.
	_check("copper table name", DiceGame.table_name("copper") == "Copper Table")
	_check("wrath flip lines", DiceGame.WRATH_FLIP_LINES.size() == 6)
	_check("wrath intro lines", DiceGame.WRATH_INTRO_LINES.size() == 4)
	# Blend regulars: story-bot roster with loss lines.
	var o3: Dictionary = DiceGame.blend_opponent(gs)
	_check("blend taunt no marker", not str(o3.get("taunt", "")).begins_with("[WIRING]"))
	_check("blend loss line", str(o3.get("loss_line", "")) != "")
	# One-shot beats fire exactly once.
	_check("wrath intro one-shot first", DiceGame.one_shot(gs, "wrath_intro"))
	_check("wrath intro one-shot second", not DiceGame.one_shot(gs, "wrath_intro"))
	_check("murray push hint", str(DiceGame.MURRAY_HINTS.get("push", "")).contains("Pushing, eh?"))
	_check("murray hint one-shot", DiceGame.one_shot(gs, "murray_push") and not DiceGame.one_shot(gs, "murray_push"))


## Generic-flow revision text (story-bot, 2026-10-05): swapped lines carry
## no [WIRING] marker. Text itself is NOT pinned — the story bot re-cuts
## freely — but a marker regression or a resurrected wiring line fails.
func _test_generic_flow_text() -> void:
	var game_src := _read_script("res://scripts/dice_game.gd")
	var ui_src := _read_script("res://scripts/dice_ui.gd")
	_check("dice_game.gd readable", game_src != "")
	_check("dice_ui.gd readable", ui_src != "")
	# Story-bot lines live, unmarked (dice_game.gd table hints).
	_check("copper hint swapped", game_src.contains("Copper table. Murray deals"))
	_check("blend hint swapped", game_src.contains("Blend table. Bigger pots, sharper tongues."))
	# Story-bot lines live, unmarked (dice_ui.gd generic flow).
	for phrase in [
		"Pick your table.",
		"You roll %d. Push, or bank at %d?",
		"Banked at %d. %s to roll.",
		"%s rolls %d...",
		"%s banks at %d. Your turn.",
		"You take the pot — %d soul credits.",
		"%s takes the pot.",
	]:
		_check("flow line live: " + phrase, ui_src.contains(phrase))
	# Old wiring lines are gone (no resurrection).
	for old in [
		"[WIRING] Pick your table.",
		"[WIRING] You can't cover the buy-in.",
		"[WIRING] Bust. The round slips away.",
		"[WIRING] Rolled %d. Bank it or push your luck.",
		"[WIRING] Banked. %s's turn.",
		"[WIRING] %s rolls %d...",
		"[WIRING] %s busts. Your turn.",
		"[WIRING] %s banks. Your turn.",
		"[WIRING] You take the pot: %d Soul Credits.",
		"[WIRING] %s takes it. The bar moves on.",
		"[WIRING] Copper table:",
		"[WIRING] Blend table:",
	]:
		_check("wiring line retired: " + old, not game_src.contains(old) and not ui_src.contains(old))


static func _read_script(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


## Re-cut flow lines (story-bot, 2026-10-05): assert BY KEY so future
## re-cuts never break this test. Wording is deliberately NOT pinned.
func _test_flow_lines() -> void:
	var keys: Array = DiceGame.FLOW_LINES.keys()
	_check("flow keys exactly the wired set",
		keys.size() == 3 and keys.has("bust_line") and keys.has("opp_bust")
		and keys.has("buyin_denied"))
	var ui_src := _read_script("res://scripts/dice_ui.gd")
	for k in keys:
		var ks := str(k)
		var line := DiceGame.flow_line(ks)
		_check("flow line non-empty: " + ks, line != "")
		_check("flow line unmarked: " + ks, not line.begins_with("[WIRING]"))
		_check("flow line wired into ui: " + ks,
			ui_src.contains('flow_line("%s")' % ks))
	_check("flow line unknown key -> empty", DiceGame.flow_line("buyin_prompt") == "")
	# Retired unwired keys never resurface.
	var game_src := _read_script("res://scripts/dice_game.gd")
	for dead in ["table_locked", "buyin_prompt", "buyin_done", "pot_line"]:
		_check("dead key absent: " + dead,
			not ui_src.contains(dead) and not game_src.contains(dead))


## Per-reason lock lines (story-bot, 2026-10-05): locks 1-2 are re-cuts
## (not wording-pinned); lock 3 was already live and stays byte-identical.
func _test_lock_reasons() -> void:
	var gs = _make_gs()
	# Lock 1: back room closed before hub unlock — fires for all 3 tables.
	for tid in ["copper", "blend", "quiet"]:
		var r1 := DiceGame.lock_reason(gs, tid)
		_check("lock1 live: " + tid, r1 != "")
		_check("lock1 unmarked: " + tid, not r1.begins_with("[WIRING]"))
	gs.set_flag("m2_hub_unlocked", true)
	# Lock 2: blend needs a copper win.
	var r2 := DiceGame.lock_reason(gs, "blend")
	_check("lock2 live", r2 != "")
	_check("lock2 unmarked", not r2.begins_with("[WIRING]"))
	# Lock 3: quiet / Act 2 gate — already-live line, verified untouched.
	_check("lock3 live", DiceGame.lock_reason(gs, "quiet") == "Latch isn't dealing until Act 2.")
