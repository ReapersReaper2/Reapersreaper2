extends SceneTree
## Headless battle scene test: setup, turn order, damage, WILT, faint/win,
## flee (wild ok / boss blocked), blackout->shrine, Bellmaw trigger, no errors.
## Run: Godot --headless --path <project> -s res://scripts/battle_scene_test.gd

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
	var b = (load("res://scripts/battle.gd")).new()
	b.fast_mode = true
	b.game_state = gs
	b.battle_config = cfg
	b.scene_changer = _nav.append
	root.add_child(b)
	return b


func _wild_cfg() -> Dictionary:
	return {
		"player_creature_id": "snapling", "player_level": 5,
		"enemy_creature_id": "bellowscap", "enemy_level": 1,
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
	print("[battle_scene_test]")
	var gs = _make_gs()

	# --- 1. setup loads both units ---
	var b = _make_battle(gs, _wild_cfg())
	await _frames(3)
	_check("units load", b._player != null and b._enemy != null)
	_check("unit stats sane", b._player.max_hp > 0 and b._enemy.max_hp > 0)
	_check("player faster than bellowscap", b._player.speed >= b._enemy.speed)
	_check("command state", b._state == 1)  # State.COMMAND
	_check("5 menu buttons", b._menu.get_child_count() == 5)
	_check("catch enabled (wild)", not (b._menu.get_child(1) as Button).disabled)
	_check("switch greyed", (b._menu.get_child(2) as Button).disabled)
	_check("item enabled (battle items live)", not (b._menu.get_child(3) as Button).disabled)
	_check("flee enabled", not (b._menu.get_child(4) as Button).disabled)
	b.queue_free()

	# --- 2. player-first turn order: one-shot enemy, player untouched ---
	b = _make_battle(gs, _wild_cfg())
	await _frames(3)
	b._enemy.hp = 1
	var php: int = b._player.hp
	b.choose_fight()
	_check("ability menu", b._state == 2)  # State.ABILITIES
	b._on_ability(str((b._player.ability_ids as Array)[0]))
	await _frames(10)
	_check("enemy fainted", b._enemy.fainted)
	_check("player untouched (acted first)", b._player.hp == php)
	_check("win navigates to return room", _nav.has("res://scenes/room_c1.tscn"))
	_check("no victory flag on wild", not gs.get_flag("wild_flag_xyz"))
	b.queue_free()

	# --- 3. damage + wilt tick at turn end ---
	_nav.clear()
	b = _make_battle(gs, _wild_cfg())
	await _frames(3)
	b._player.teach_ability("spore_cloud")
	var ehp: int = b._enemy.hp
	b.choose_fight()
	b._on_ability("spore_cloud")
	await _frames(10)
	_check("ability damaged enemy", b._enemy.hp < ehp)
	_check("wilt applied", int(b._enemy.statuses.get("wilt", 0)) > 0)
	_check("battle continues", b._state == 1)
	b.queue_free()

	# --- 4. flee works vs wild ---
	_nav.clear()
	b = _make_battle(gs, _wild_cfg())
	await _frames(3)
	b.try_flee()
	await _frames(5)
	_check("flee navigates home", _nav.has("res://scenes/room_c1.tscn"))
	_check("flee sets no flag", not gs.get_flag("bellmaw_defeated"))
	b.queue_free()

	# --- 5. flee fails vs boss ---
	_nav.clear()
	b = _make_battle(gs, _boss_cfg())
	await _frames(3)
	b.try_flee()
	await _frames(5)
	_check("boss flee blocked", _nav.is_empty())
	_check("still in command after blocked flee", b._state == 1)
	b.queue_free()

	# --- 6. boss win sets victory flag ---
	_nav.clear()
	b = _make_battle(gs, _boss_cfg())
	await _frames(3)
	b._enemy.hp = 1
	b.choose_fight()
	b._on_ability(str((b._player.ability_ids as Array)[0]))
	await _frames(10)
	_check("boss defeated", b._enemy.fainted)
	_check("victory flag set", gs.get_flag("bellmaw_defeated"))
	_check("boss win returns to room", _nav.has("res://scenes/room_c1.tscn"))
	b.queue_free()

	# --- 7. blackout -> last shrine ---
	_nav.clear()
	gs.set_last_shrine("p3", -760.0, 260.0)
	b = _make_battle(gs, _wild_cfg())
	await _frames(3)
	await b._lose()
	_check("blackout goes to shrine room", _nav.has("res://scenes/room_p3.tscn"))
	var pos: Dictionary = gs.get_position()
	_check("position set to shrine", str(pos.get("room")) == "p3" and float(pos.get("x")) == -760.0)
	b.queue_free()

	# --- 8. battle_manager API ---
	_nav.clear()
	var bm = (load("res://scripts/battle_manager.gd")).new()
	bm.scene_changer = _nav.append
	root.add_child(bm)
	_check("wild start ok", bm.start_wild_battle("bellowscap", 3, "c1", Vector2(1, 2)))
	_check("pending stored", str(bm.pending.get("enemy_creature_id")) == "bellowscap" and not bool(bm.pending.get("is_boss")))
	_check("double start refused", not bm.start_wild_battle("siltmaw", 2, "c1", Vector2.ZERO))
	_check("manager navs to battle scene", _nav.has("res://scenes/battle.tscn"))
	bm.clear_pending()
	_nav.clear()
	_check("boss start ok", bm.start_boss_battle("bellmaw", 12, "c1", Vector2(1900, 0), "bellmaw_defeated"))
	_check("boss pending", bool(bm.pending.get("is_boss")) and str(bm.pending.get("victory_flag")) == "bellmaw_defeated")
	bm.queue_free()

	# --- 9. Bellmaw trigger in room_c1 (uses the real autoloads) ---
	var ags = root.get_node_or_null("GameState")
	var abm = root.get_node_or_null("BattleManager")
	_check("autoloads present", ags != null and abm != null)
	abm.scene_changer = _nav.append
	abm.clear_pending()
	ags.clear_flag("bellmaw_defeated")
	var c1 = (load("res://scenes/room_c1.tscn")).instantiate()
	root.add_child(c1)
	await _frames(3)
	var trig = c1.get_node_or_null("BellmawTrigger")
	_check("bellmaw trigger node exists", trig != null)
	_check("trigger id bellmaw", trig != null and str(trig.get_meta("trigger_id", "")) == "bellmaw")
	_nav.clear()
	c1._on_room_trigger("bellmaw", trig)
	await _frames(2)
	_check("trigger starts boss battle", _nav.has("res://scenes/battle.tscn"))
	_check("trigger pending is bellmaw boss", str(abm.pending.get("enemy_creature_id")) == "bellmaw" and bool(abm.pending.get("is_boss")))
	# Defeated -> no re-trigger.
	abm.clear_pending()
	_nav.clear()
	ags.set_flag("bellmaw_defeated")
	c1._on_room_trigger("bellmaw", trig)
	await _frames(2)
	_check("defeated bellmaw does not re-trigger", _nav.is_empty())
	ags.clear_flag("bellmaw_defeated")
	abm.clear_pending()
	c1.queue_free()

	print("[battle_scene_test] failures: ", _failures.size())
	if _failures.is_empty():
		print("ALL BATTLE SCENE TESTS PASSED")
	else:
		printerr("FAILURES: ", _failures)
	quit(1 if not _failures.is_empty() else 0)
