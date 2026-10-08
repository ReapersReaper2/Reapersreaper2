extends SceneTree
## Headless Daily Hunt fight-wiring test: hunt battles spawn the right
## target at the right level, victory completes the hunt (score + reward),
## defeat fails it (retryable), and the battle-touching modifiers change
## the formulas. bloom_double / invisible_foes are documented-future.
##
## Run: Godot --headless --path <project> -s res://scripts/daily_hunt_fight_test.gd

const GameStateScript = preload("res://scripts/game_state.gd")
const DailyHuntsScript = preload("res://scripts/daily_hunts.gd")
const BattleManagerScript = preload("res://scripts/battle_manager.gd")
const BattleScript = preload("res://scripts/battle.gd")
const BattleUnit = preload("res://scripts/battle_unit.gd")

const DATE := "2026-10-05"

var _gs = null
var _passed := 0
var _failed := 0
var _ran := false
var _scene_changes: Array = []


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] daily_hunt_fight: ", label)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _on_scene_change(path: String) -> void:
	_scene_changes.append(path)


func _setup() -> void:
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		_gs = GameStateScript.new()
		_gs.name = "GameState"
		root.add_child(_gs)
		_gs._ready()
	_gs.new_game()


func _make_bm():
	var bm = BattleManagerScript.new()
	root.add_child(bm)
	bm._ready()
	bm.scene_changer = Callable(self, "_on_scene_change")
	bm.game_state = _gs
	return bm


## Bare battle node with config + units, minus the UI/scene flow.
func _make_battle(cfg: Dictionary):
	var b = BattleScript.new()
	b.battle_config = cfg
	b.game_state = _gs
	b.battle_manager = {}
	b.fast_mode = true
	b._msg = Label.new()
	b._menu = VBoxContainer.new()
	b._read_config()
	b._player = BattleUnit.new(str(cfg.get("player_creature_id", "snapling")), int(cfg.get("player_level", 5)))
	b._enemy = BattleUnit.new(str(cfg.get("enemy_creature_id", "siltmaw")), int(cfg.get("enemy_level", 7)))
	return b


func _run() -> void:
	_setup()
	_test_target_mapping()
	_test_manager_spawns()
	_test_unit_modifiers()
	await _test_hunt_init_and_mods()
	await _test_victory_completes()
	await _test_defeat_fails()
	_test_no_items_gate()
	print("[daily_hunt_fight_test] done: ", _passed, " passed, ", _failed, " failed")
	quit()


func _test_target_mapping() -> void:
	_check(DailyHuntsScript.battle_creature_id("boss:shika") == "shika_alpha", "map: boss:shika -> shika_alpha")
	_check(DailyHuntsScript.battle_creature_id("boss:tentacle") == "tentacle", "map: boss:tentacle -> tentacle")
	_check(DailyHuntsScript.battle_creature_id("boss:bellmaw") == "bellmaw", "map: boss:bellmaw -> bellmaw")
	_check(DailyHuntsScript.battle_creature_id("boss:harrow") == "harrow", "map: boss:harrow -> harrow")
	_check(DailyHuntsScript.battle_creature_id("siltmaw") == "siltmaw", "map: wild ids pass through")


func _test_manager_spawns() -> void:
	var bm = _make_bm()
	# Wild hunt: pending carries the flag, seamless path falls back to the
	# scene changer headless (no current scene).
	_scene_changes.clear()
	_check(bm.start_daily_hunt_battle("siltmaw", 7, false, "h1", Vector2.ZERO), "mgr: wild hunt start ok")
	_check(bool(bm.pending.get("daily_hunt", false)), "mgr: wild pending flagged daily_hunt")
	_check(str(bm.pending.get("enemy_creature_id")) == "siltmaw", "mgr: wild target id kept")
	_check(int(bm.pending.get("enemy_level")) == 7, "mgr: wild level kept")
	_check(not bool(bm.pending.get("is_boss", true)), "mgr: wild not marked boss")
	_check(_scene_changes.size() == 1, "mgr: wild launch attempted (headless fallback)")
	# Double-start refused while a battle is pending.
	_check(not bm.start_daily_hunt_battle("gravebind", 5, false, "h1", Vector2.ZERO), "mgr: second start refused mid-battle")
	bm.clear_pending()
	# Boss hunt: staged arena path.
	_scene_changes.clear()
	_check(bm.start_daily_hunt_battle("shika_alpha", 22, true, "h1", Vector2.ZERO), "mgr: boss hunt start ok")
	_check(bool(bm.pending.get("daily_hunt", false)), "mgr: boss pending flagged daily_hunt")
	_check(bool(bm.pending.get("is_boss", false)), "mgr: boss marked boss")
	_check(_scene_changes == ["res://scenes/battle.tscn"], "mgr: boss hunt uses staged battle.tscn")
	bm.clear_pending()
	bm.queue_free()


func _test_unit_modifiers() -> void:
	var plain := BattleUnit.new("snapling", 1)
	_check(plain.mod_incoming_mult == 1.0 and plain.mod_outgoing_mult == 1.0 and not plain.mod_no_armor,
		"unit: default mod mults are neutral")
	# Frail: incoming x2. snapling lvl1 def 7 -> round(20*2 - 7*0.6) = round(35.8) = 36.
	var frail := BattleUnit.new("snapling", 1)
	frail.mod_incoming_mult = 2.0
	_check(frail.take_damage(20.0, null) == 36, "unit: frail doubles incoming (got 36)")
	# No Armor: guard soaks nothing -> round(20 - 0) = 20.
	var bare := BattleUnit.new("snapling", 1)
	bare.mod_no_armor = true
	_check(bare.take_damage(20.0, null) == 20, "unit: no_armor ignores guard (got 20)")
	# Heavy Hits outgoing: snapling atk 15, snap_bite 1.2 -> raw 15*1.2*1.5 = 27
	# vs bellowscap def 10 -> round(27 - 6) = 21.
	var heavy := BattleUnit.new("snapling", 1)
	heavy.mod_outgoing_mult = 1.5
	var cap := BattleUnit.new("bellowscap", 1)
	var dealt: int = heavy.use_ability("snap_bite", cap, {"no_specials": true})
	_check(dealt == 21, "unit: heavy_hits outgoing x1.5 (got 21, want %d)" % dealt)


func _test_hunt_init_and_mods() -> void:
	var hunt: Dictionary = DailyHuntsScript.hunt_for(DATE)
	var creature := DailyHuntsScript.battle_creature_id(str(hunt["target_id"]))
	DailyHuntsScript.start_hunt(_gs, DATE)
	# Force two battle-touching modifiers regardless of today's roll.
	_gs.set_stat("daily_mod_no_armor", true)
	_gs.set_stat("daily_mod_slow_start", true)
	var b = _make_battle({
		"player_creature_id": "snapling", "player_level": 5,
		"enemy_creature_id": creature, "enemy_level": int(hunt["level"]),
		"is_boss": bool(hunt["is_boss"]), "daily_hunt": true,
	})
	b._init_daily_hunt()
	_check(b._hunt_active, "battle: hunt active when flag + hunt present")
	_check(b._player.mod_no_armor, "battle: no_armor applied to player unit")
	_check(bool(b._daily_mods.get("slow_start", false)), "battle: slow_start flag read")
	# Slow Start: player forced last on turns 1-3, free on turn 4.
	b._hunt_turns = 2
	_check(b._hunt_forces_last(), "battle: slow_start forces last on turn 2")
	b._hunt_turns = 4
	_check(not b._hunt_forces_last(), "battle: slow_start releases on turn 4")
	# No daily_hunt flag -> inactive even with a hunt running.
	var b2 = _make_battle({
		"player_creature_id": "snapling", "player_level": 5,
		"enemy_creature_id": "siltmaw", "enemy_level": 7,
	})
	b2._init_daily_hunt()
	_check(not b2._hunt_active, "battle: no flag -> hunt not tracked")
	DailyHuntsScript.abandon_hunt(_gs)


func _test_victory_completes() -> void:
	var hunt: Dictionary = DailyHuntsScript.hunt_for(DATE)
	var creature := DailyHuntsScript.battle_creature_id(str(hunt["target_id"]))
	DailyHuntsScript.start_hunt(_gs, DATE)
	var before_credits: int = _gs.get_soul_credits()
	var b = _make_battle({
		"player_creature_id": "snapling", "player_level": 30,
		"enemy_creature_id": creature, "enemy_level": int(hunt["level"]),
		"is_boss": bool(hunt["is_boss"]), "daily_hunt": true,
	})
	b._init_daily_hunt()
	_check(b._hunt_active, "victory: hunt tracking on before win")
	b._hunt_damage = 40
	b._hunt_start_msec = Time.get_ticks_msec() - 5000
	await b._complete_daily_hunt()
	_check(not DailyHuntsScript.is_active(_gs), "victory: hunt resolved (no longer active)")
	var best: Dictionary = DailyHuntsScript.best_for(DATE, _gs)
	_check(int(best.get("score", 0)) > 0, "victory: score recorded in local best")
	_check(int(best.get("damage", -1)) == 40, "victory: damage taken recorded")
	_check(_gs.get_soul_credits() == before_credits + int(hunt["reward"]),
		"victory: soul credit reward paid")
	_check(DailyHuntsScript.hall_of_fame(_gs).size() == 1, "victory: hall of fame entry added")
	_check(not b._hunt_active, "victory: battle hunt state cleared")


func _test_defeat_fails() -> void:
	var ddate := "2026-10-06"
	DailyHuntsScript.start_hunt(_gs, ddate)
	var b = _make_battle({
		"player_creature_id": "snapling", "player_level": 5,
		"enemy_creature_id": "siltmaw", "enemy_level": 7, "daily_hunt": true,
	})
	b._init_daily_hunt()
	_check(b._hunt_active, "defeat: hunt tracking on before loss")
	await b._fail_daily_hunt()
	_check(not DailyHuntsScript.is_active(_gs), "defeat: hunt failed (not active)")
	_check(not b._hunt_active, "defeat: battle hunt state cleared")
	_check(not DailyHuntsScript.has_modifier(_gs, "no_armor") and not DailyHuntsScript.has_modifier(_gs, "frail"),
		"defeat: modifier flags cleared")
	# Failed hunt leaves no score behind — it can be retried fresh.
	_check(DailyHuntsScript.best_for(ddate, _gs).is_empty(), "defeat: no best recorded for failed hunt")


func _test_no_items_gate() -> void:
	DailyHuntsScript.start_hunt(_gs, DATE)
	var b = _make_battle({
		"player_creature_id": "snapling", "player_level": 5,
		"enemy_creature_id": "siltmaw", "enemy_level": 7, "daily_hunt": true,
	})
	b._init_daily_hunt()
	# COMMAND = 1 in battle.gd's State enum.
	b._state = 1
	b._hunt_active = true
	b._daily_mods = {"no_items": true}
	b.choose_item()
	_check(b._state == 1, "no_items: item menu stays closed when modifier active")
	b._daily_mods = {}
	b.choose_item()
	_check(b._state != 1, "no_items: item menu opens without the modifier")
	DailyHuntsScript.abandon_hunt(_gs)
