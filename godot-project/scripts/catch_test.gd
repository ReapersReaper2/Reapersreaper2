extends SceneTree
## Headless creature-catch test for Reaper's Reaper tactical battles.
## Run: Godot --headless --path <project> -s res://scripts/catch_test.gd
##
## Canon note: the roster doc (03) describes per-creature catch methods
## (chase, timing touch, lure/trap) but no single battle-catch mechanic, so
## wiring uses the simplest classic: weaken + throw a Soul Snare with a
## catch-rate formula. All numbers below are tuning placeholders, not canon.
##
## Hand-computed reference values (battle.gd::catch_rate_for):
##   rate = base * (1.5 - hp/max_hp) + 0.15 (wilted), clamped [0.01, 0.95].
##   snapling base 0.45, full HP 30/30: 0.45 * 0.5 = 0.225
##   snapling base 0.45, 1 HP of 30:    0.45 * (1.5 - 1/30) = 0.45 * 1.46667 = 0.66
##   same + WILT: 0.66 + 0.15 = 0.81
##   bellmaw base 0.05, full HP: 0.05 * 0.5 = 0.025
##   clamp high: base 0.9, hp 0, wilted: 0.9*1.5 + 0.15 = 1.5 -> 0.95
##   clamp low:  base 0.001, full HP: 0.001*0.5 = 0.0005 -> 0.01

const BattleScript = preload("res://scripts/battle.gd")

var _failures: Array[String] = []
var _ran := false
var _nav: Array = []


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failures.append(name)
		print("  FAIL: ", name)


func _make_gs():
	var ss = (load("res://scripts/save_system.gd")).new()
	root.add_child(ss)
	var ach = (load("res://scripts/achievements.gd")).new()
	root.add_child(ach)
	var gs = (load("res://scripts/game_state.gd")).new()
	gs.save_system = ss
	gs.achievements = ach
	root.add_child(gs)
	gs._ready()
	ach.game_state = gs
	return gs


func _make_battle(gs, cfg: Dictionary):
	var b = BattleScript.new()
	b.fast_mode = true
	b.game_state = gs
	b.battle_config = cfg
	b.scene_changer = _nav.append
	root.add_child(b)
	return b


func _wild_cfg() -> Dictionary:
	return {
		"player_creature_id": "snapling", "player_level": 5,
		"enemy_creature_id": "bellowscap", "enemy_level": 3,
		"is_boss": false, "victory_flag": "",
		"return_room": "c1", "return_pos": Vector2(1900, 0),
	}


func _boss_cfg() -> Dictionary:
	var c := _wild_cfg()
	c["enemy_creature_id"] = "bellmaw"
	c["enemy_level"] = 12
	c["is_boss"] = true
	c["victory_flag"] = "bellmaw_defeated"
	return c


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _run() -> void:
	print("[catch_test]")
	var B = BattleScript

	# --- 1. catch-rate math (pure, deterministic) ---
	_check("full HP halves base", is_equal_approx(B.catch_rate_for(0.45, 30, 30, false), 0.225))
	_check("1 HP nears 1.5x base", is_equal_approx(B.catch_rate_for(0.45, 1, 30, false), 0.66))
	_check("WILT adds 0.15", is_equal_approx(B.catch_rate_for(0.45, 1, 30, true), 0.81))
	_check("bellmaw full HP 0.025", is_equal_approx(B.catch_rate_for(0.05, 100, 100, false), 0.025))
	_check("clamp high 0.95", is_equal_approx(B.catch_rate_for(0.9, 0, 30, true), 0.95))
	_check("clamp low 0.01", is_equal_approx(B.catch_rate_for(0.001, 30, 30, false), 0.01))
	_check("zero max_hp safe", B.catch_rate_for(0.45, 0, 0, false) >= 0.01)

	# --- 2. creature data carries catch_rate; items.json loads ---
	var CreatureData = load("res://scripts/creature_data.gd")
	_check("snapling catch_rate 0.45", is_equal_approx(float(CreatureData.get_creature("snapling").get("catch_rate", -1.0)), 0.45))
	_check("bellmaw catch_rate 0.05", is_equal_approx(float(CreatureData.get_creature("bellmaw").get("catch_rate", -1.0)), 0.05))
	_check("soul_snare item exists", str(CreatureData.get_item("soul_snare").get("name", "")) == "Soul Snare")

	# --- 3. inventory: new game grants 5 snares; use/add work ---
	var gs = _make_gs()
	_check("new game grants 5 snares", gs.get_item_count("soul_snare") == 5)
	_check("use_item consumes", gs.use_item("soul_snare") and gs.get_item_count("soul_snare") == 4)
	gs.add_item("soul_snare", 2)
	_check("add_item works", gs.get_item_count("soul_snare") == 6)
	for i in 6:
		gs.use_item("soul_snare")
	_check("use_item fails at zero", not gs.use_item("soul_snare"))
	_check("count stays zero", gs.get_item_count("soul_snare") == 0)
	gs.add_item("soul_snare", 5)

	# --- 4. CATCH gating ---
	var b = _make_battle(gs, _wild_cfg())
	await _frames(3)
	_check("wild battle can catch", b._can_catch())
	_check("catch button enabled (wild)", not (b._menu.get_child(1) as Button).disabled)
	b.queue_free()

	var bb = _make_battle(gs, _boss_cfg())
	await _frames(3)
	_check("boss uncatchable", not bb._can_catch())
	_check("catch button disabled (boss)", (bb._menu.get_child(1) as Button).disabled)
	bb.queue_free()

	# Drain snares -> CATCH disabled.
	for i in 5:
		gs.use_item("soul_snare")
	var bn = _make_battle(gs, _wild_cfg())
	await _frames(3)
	_check("no snares -> cannot catch", not bn._can_catch())
	bn.queue_free()
	gs.add_item("soul_snare", 5)

	# Fill the party (1 starter + 5) -> CATCH still offered: a full party
	# routes the catch to the Soul Vault instead of refusing.
	var P = load("res://scripts/party.gd")
	var S = load("res://scripts/storage.gd")
	for cid in ["siltmaw", "gravebind", "thornchoir", "bellowscap", "snapling"]:
		P.add_creature(gs, cid, 3)
	_check("party full at 6", P.size(gs) == 6)
	var bf = _make_battle(gs, _wild_cfg())
	await _frames(3)
	_check("party full -> can still catch (vault)", bf._can_catch())
	_check("catch button enabled (party full)", not (bf._menu.get_child(1) as Button).disabled)
	bf.queue_free()

	# Fill the vault too -> CATCH refused, no snare consumed.
	while not S.is_full(gs):
		S.deposit_entry(gs, P.make_entry("snapling", 2))
	_check("vault full", S.is_full(gs))
	var bfull = _make_battle(gs, _wild_cfg())
	await _frames(3)
	_check("vault full -> cannot catch", not bfull._can_catch())
	_check("catch button disabled (vault full)", (bfull._menu.get_child(1) as Button).disabled)
	_check("snare not consumed by refusal", gs.get_item_count("soul_snare") == 5)
	bfull.queue_free()

	# --- 5. try_catch consumes exactly one snare, battle stays sane ---
	# (Outcome is a random roll; assert the deterministic parts: one snare
	# gone, and the battle either ended caught or is back at COMMAND.)
	var gs2 = _make_gs()
	var bc = _make_battle(gs2, _wild_cfg())
	await _frames(3)
	var before: int = gs2.get_item_count("soul_snare")
	bc.try_catch()
	await _frames(12)
	_check("throw consumes one snare", gs2.get_item_count("soul_snare") == before - 1)
	var caught: bool = bc._state == BattleScript.State.END  # after a successful catch
	var still_fighting: bool = bc._state == BattleScript.State.COMMAND  # after a break-free
	_check("sane post-throw state", caught or still_fighting)
	if caught:
		_check("caught creature joins party", P.size(gs2) == 2)
		var e: Dictionary = P.get_entry(gs2, 1)
		_check("caught id/level right", str(e.get("creature_id", "")) == "bellowscap" and int(e.get("level", 0)) == 3)
		_check("navigated back to room", _nav.size() > 0)
	bc.queue_free()

	# --- 6. _catch_success resolution is deterministic ---
	var gs3 = _make_gs()
	var bs = _make_battle(gs3, _wild_cfg())
	await _frames(3)
	await bs._catch_success("Bellowscap")
	_check("success adds to party", P.size(gs3) == 2)
	var e2: Dictionary = P.get_entry(gs3, 1)
	_check("success id/level right", str(e2.get("creature_id", "")) == "bellowscap" and int(e2.get("level", 0)) == 3)
	_check("success navigates home", _nav.size() > 0)
	bs.queue_free()

	# --- 7. Full-party catch routes to the Soul Vault ---
	var gs4 = _make_gs()
	for cid in ["siltmaw", "gravebind", "thornchoir", "bellowscap", "snapling"]:
		P.add_creature(gs4, cid, 3)
	_check("gs4 party full", P.size(gs4) == 6)
	var bv = _make_battle(gs4, _wild_cfg())
	await _frames(3)
	await bv._catch_success("Bellowscap")
	_check("party still 6", P.size(gs4) == 6)
	_check("catch went to vault", S.total_stored(gs4) == 1)
	var ve: Dictionary = S.get_entry(gs4, 0, 0)
	_check("vault id/level right", str(ve.get("creature_id", "")) == "bellowscap" and int(ve.get("level", 0)) == 3)
	bv.queue_free()

	print("[catch_test] failures: ", _failures.size())
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if not _failures.is_empty() else 0)
