extends SceneTree
## Headless trainer battle test: sequential send-out, mid-battle switch
## (costs a turn), forced switch on faint, no flee/catch, credit reward,
## one-time victory flag, post-battle dialogue hooks, BattleManager API.
## Run: Godot --headless --path <project> -s res://scripts/trainer_test.gd

const PartyScript := preload("res://scripts/party.gd")
const TrainerData := preload("res://scripts/trainer_data.gd")

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
	PartyScript.new_game_party(gs)  # snapling lv5
	PartyScript.add_creature(gs, "bellowscap", 4)
	return gs


func _make_battle(gs, cfg: Dictionary):
	var b = (load("res://scripts/battle.gd")).new()
	b.fast_mode = true
	b.game_state = gs
	b.battle_config = cfg
	b.scene_changer = _nav.append
	root.add_child(b)
	return b


func _trainer_cfg() -> Dictionary:
	return {
		"player_creature_id": "snapling", "player_level": 5,
		"player_hp": -1, "player_party_index": 0,
		"enemy_creature_id": "siltmaw", "enemy_level": 3,
		"is_boss": false, "is_trainer": true,
		"trainer_id": "p3_scavenger", "trainer_name": "SHORE SCAVENGER",
		"enemy_roster": [
			{"creature_id": "siltmaw", "level": 3},
			{"creature_id": "bellowscap", "level": 4},
		],
		"reward_credits": 60,
		"post_dialogue": ["Won."],
		"victory_flag": "trainer_p3_scavenger_defeated",
		"return_room": "p3", "return_pos": Vector2(950, 120),
	}


func _first_ability(b) -> String:
	return str((b._player.ability_ids as Array)[0])


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
	print("[trainer_test]")
	var gs = _make_gs()

	# --- 1. trainer setup ---
	var b = _make_battle(gs, _trainer_cfg())
	await _frames(3)
	_check("trainer mode on", b._is_trainer)
	_check("first foe is roster[0]", b._enemy.creature_id == "siltmaw")
	_check("command state", b._state == 1)  # State.COMMAND
	_check("5 menu buttons", b._menu.get_child_count() == 5)
	_check("catch disabled (trainer)", (b._menu.get_child(1) as Button).disabled)
	_check("switch enabled (2 conscious)", not (b._menu.get_child(2) as Button).disabled)
	b.queue_free()

	# --- 2. sequential send-out: faint foe 1 -> foe 2 enters, battle continues ---
	_nav.clear()
	b = _make_battle(gs, _trainer_cfg())
	await _frames(3)
	b._enemy.hp = 1
	b.choose_fight()
	b._on_ability(_first_ability(b))
	await _frames(12)
	_check("roster advanced", b._roster_idx == 1)
	_check("second foe sent out", b._enemy.creature_id == "bellowscap" and not b._enemy.fainted)
	_check("battle continues", b._state == 1)
	_check("no room change mid-roster", _nav.is_empty())
	b.queue_free()

	# --- 3. full win: credits, flag, post dialogue, return ---
	_nav.clear()
	var credits_before: int = gs.get_soul_credits()
	b = _make_battle(gs, _trainer_cfg())
	await _frames(3)
	b._enemy.hp = 1
	b.choose_fight()
	b._on_ability(_first_ability(b))
	await _frames(12)
	b._enemy.hp = 1
	b.choose_fight()
	b._on_ability(_first_ability(b))
	await _frames(12)
	_check("trainer defeated", b._state == 7)  # State.END
	_check("victory flag set", gs.get_flag("trainer_p3_scavenger_defeated"))
	_check("credits rewarded", gs.get_soul_credits() == credits_before + 60)
	_check("post dialogue shown", b._msg.text == "Won.")
	_check("win returns to room", _nav.has("res://scenes/room_p3.tscn"))
	b.queue_free()

	# --- 4. voluntary switch costs the turn (enemy acts + end-of-turn ticks) ---
	_nav.clear()
	b = _make_battle(gs, _trainer_cfg())
	await _frames(3)
	b._enemy.apply_status("wilt", 3)
	var wilt_before: int = int(b._enemy.statuses.get("wilt", 0))
	b.choose_switch()
	await _frames(2)  # let queue_free() clear the old command menu
	_check("switch menu state", b._state == 5)  # State.SWITCH
	_check("one candidate listed", b._menu.get_child_count() == 2)  # 1 candidate + BACK
	b._on_switch_pick(1)
	await _frames(12)
	_check("active battler swapped", b._player.creature_id == "bellowscap")
	_check("party index updated", int(b._cfg.get("player_party_index")) == 1)
	_check("turn consumed (wilt ticked)", int(b._enemy.statuses.get("wilt", 0)) < wilt_before)
	_check("back at commands", b._state == 1)
	b.queue_free()

	# --- 5. player faint forces a switch (no blackout while conscious left) ---
	_nav.clear()
	b = _make_battle(gs, _trainer_cfg())
	await _frames(3)
	b._player.hp = 1
	b.choose_fight()
	b._on_ability(_first_ability(b))
	await _frames(12)
	_check("forced switch menu", b._state == 5 and b._forced_switch)
	_check("no blackout", _nav.is_empty())
	b._on_switch_pick(1)
	await _frames(8)
	_check("replacement sent", b._player.creature_id == "bellowscap" and not b._player.fainted)
	_check("battle continues after forced switch", b._state == 1)
	b.queue_free()

	# --- 6. no flee / no catch in trainer battles ---
	_nav.clear()
	b = _make_battle(gs, _trainer_cfg())
	await _frames(3)
	b.try_flee()
	await _frames(5)
	_check("trainer flee blocked", _nav.is_empty())
	_check("still in command after blocked flee", b._state == 1)
	_check("catch blocked", not b._can_catch())
	b.queue_free()

	# --- 7. BattleManager trainer API ---
	_nav.clear()
	var bm = (load("res://scripts/battle_manager.gd")).new()
	bm.game_state = gs
	bm.scene_changer = _nav.append
	root.add_child(bm)
	_check("trainer start ok", bm.start_trainer_battle("p3_scavenger", "p3", Vector2(950, 120)))
	_check("pending is trainer", bool(bm.pending.get("is_trainer")))
	_check("roster size 2", (bm.pending.get("enemy_roster", []) as Array).size() == 2)
	_check("victory flag", str(bm.pending.get("victory_flag")) == "trainer_p3_scavenger_defeated")
	_check("double start refused", not bm.start_trainer_battle("c1_tidehunter", "c1", Vector2.ZERO))
	bm.clear_pending()
	_nav.clear()
	_check("unknown trainer refused", not bm.start_trainer_battle("nope", "p3", Vector2.ZERO))
	_check("trainer data loads", not (TrainerData.get_trainer("c1_tidehunter") as Dictionary).is_empty())
	_check("tidehunter roster 3", ((TrainerData.get_trainer("c1_tidehunter") as Dictionary).get("roster", []) as Array).size() == 3)
	_check("defeat flag name", TrainerData.defeat_flag("p3_scavenger") == "trainer_p3_scavenger_defeated")
	bm.queue_free()

	# --- 8. defeated trainer can't re-battle (flag gates the NPC) ---
	gs.set_flag("trainer_p3_scavenger_defeated")
	_check("flag persists", bool(gs.get_flag("trainer_p3_scavenger_defeated")))

	if _failures.is_empty():
		print("[trainer_test] ALL PASS")
	else:
		print("[trainer_test] FAILURES: ", _failures)
		quit(1)
		return
	quit(0)
