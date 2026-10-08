extends SceneTree
## Headless seamless-battle test: wild encounters play out in the overworld
## with no scene change; boss battles keep the staged battle.tscn
## transition. Run:
##   ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/seamless_battle_test.gd
##
## Covers: wild start spawns the seamless layer in the current room (no
## scene change), player stays at the same position, movement+input locked,
## wild creature visual spawned, double-start refused mid-battle, victory /
## flee / defeat all dismiss the layer and unlock the player in place,
## defeat does NOT shrine-trip ("it's a memory"), boss still transitions.

const BM_Script := preload("res://scripts/battle_manager.gd")


class TestPlayer:
	extends Node2D
	var move_locked := false
	var input_locked := false


var _failures: Array[String] = []
var _ran := false
var _scene_changes: Array = []
var _resolved: Array = []


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failures.append(name)
		print("  FAIL: ", name)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _on_scene_change(path: String) -> void:
	_scene_changes.append(path)


func _on_resolved(outcome: String) -> void:
	_resolved.append(outcome)


func _make_bm():
	var bm = BM_Script.new()
	root.add_child(bm)
	bm._ready()
	bm.scene_changer = Callable(self, "_on_scene_change")
	bm.seamless_fast_mode = true
	return bm


func _make_room_with_player(pos: Vector2) -> Array:
	var room := Node2D.new()
	room.name = "TestRoom"
	root.add_child(room)
	current_scene = room
	var player = TestPlayer.new()
	player.name = "Player"
	player.position = pos
	room.add_child(player)
	player.add_to_group("player")
	return [room, player]


func _seamless_in(room: Node) -> Node:
	return room.get_node_or_null("SeamlessBattle")


func _battle_of(seamless: Node) -> Node:
	var layer: Node = seamless.get_node_or_null("SeamlessBattleLayer")
	if layer == null:
		return null
	return layer.get_node_or_null("EmbeddedBattle")


func _run() -> void:
	print("== seamless battle: wild starts in-overworld ==")
	_scene_changes.clear()
	var bm = _make_bm()
	var parts := _make_room_with_player(Vector2(100, 200))
	var room: Node = parts[0]
	var player = parts[1]

	_check("wild start ok", bm.start_wild_battle("bellowscap", 3, "m3a", Vector2(100, 200)))
	_check("no scene change for wild battle", _scene_changes.is_empty())
	var seamless: Node = _seamless_in(room)
	_check("seamless node spawned in current room", seamless != null)
	seamless.resolved.connect(_on_resolved)
	_check("player never left the room", player.get_parent() == room)
	_check("player position unchanged at start", player.position == Vector2(100, 200))
	_check("movement locked during battle", bool(player.get("move_locked")))
	_check("input locked during battle", bool(player.get("input_locked")))
	_check("pending held for whole battle (blocks retrigger)", not bm.pending.is_empty())
	_check("second wild start refused mid-battle",
		not bm.start_wild_battle("siltmaw", 2, "m3a", Vector2.ZERO))
	var layer: Node = seamless.get_node_or_null("SeamlessBattleLayer")
	_check("battle CanvasLayer present", layer != null)
	_check("dim overlay present", layer != null and layer.get_node_or_null("Dim") != null)
	var battle: Node = _battle_of(seamless)
	_check("embedded battle present in embedded mode",
		battle != null and bool(battle.get("embedded_mode")))
	var visual: Node = seamless.get_node_or_null("WildCreatureVisual")
	_check("wild creature visual spawned in room", visual != null)
	if visual != null:
		_check("creature visual near encounter spot",
			(visual as Node2D).position.distance_to(Vector2(190, 130)) < 1.0)

	print("== seamless battle: victory dismisses cleanly ==")
	_resolved.clear()
	await _frames(5)  # let the intro finish
	battle._enemy.hp = 1
	battle.choose_fight()
	battle._on_ability(str((battle._player.ability_ids as Array)[0]))
	await _frames(12)
	_check("victory resolved", _resolved == ["win"])
	_check("layer dismissed after victory", not is_instance_valid(seamless))
	_check("movement unlocked after victory", not bool(player.get("move_locked")))
	_check("input unlocked after victory", not bool(player.get("input_locked")))
	_check("player still in same room after victory", player.get_parent() == room)
	_check("player position unchanged after victory", player.position == Vector2(100, 200))
	_check("pending cleared after victory", bm.pending.is_empty())
	_check("post-battle cooldown stamped", int(bm.last_battle_end_msec) >= 0)
	bm.clear_pending()

	print("== seamless battle: flee dismisses cleanly ==")
	_resolved.clear()
	_check("second wild start ok", bm.start_wild_battle("siltmaw", 2, "m3a", Vector2(100, 200)))
	seamless = _seamless_in(room)
	_check("seamless node spawned for flee bout", seamless != null)
	seamless.resolved.connect(_on_resolved)
	battle = _battle_of(seamless)
	await _frames(5)
	battle.try_flee()
	await _frames(8)
	_check("flee resolved", _resolved == ["flee"])
	_check("layer dismissed after flee", not is_instance_valid(seamless))
	_check("movement unlocked after flee", not bool(player.get("move_locked")))
	_check("player still in same room after flee", player.get_parent() == room)
	_check("player position unchanged after flee", player.position == Vector2(100, 200))
	_check("pending cleared after flee", bm.pending.is_empty())
	bm.clear_pending()

	print("== seamless battle: defeat is a memory (no shrine trip) ==")
	_resolved.clear()
	_check("third wild start ok", bm.start_wild_battle("deepjaw", 4, "m3a", Vector2(100, 200)))
	seamless = _seamless_in(room)
	seamless.resolved.connect(_on_resolved)
	battle = _battle_of(seamless)
	await _frames(5)
	await battle._lose()
	await _frames(5)
	_check("defeat resolved", _resolved == ["lose"])
	_check("layer dismissed after defeat", not is_instance_valid(seamless))
	_check("movement unlocked after defeat", not bool(player.get("move_locked")))
	_check("player still in same room after defeat", player.get_parent() == room)
	_check("player position unchanged after defeat (no shrine trip)",
		player.position == Vector2(100, 200))
	_check("pending cleared after defeat", bm.pending.is_empty())
	_check("no scene change on defeat", _scene_changes.is_empty())
	bm.clear_pending()

	print("== staged battles unchanged: boss keeps scene transition ==")
	_scene_changes.clear()
	_check("boss start ok",
		bm.start_boss_battle("harrow", 15, "m3a", Vector2(100, 200), "harrow_defeated"))
	_check("boss navigates to battle scene", _scene_changes.has("res://scenes/battle.tscn"))
	_check("no seamless node for boss", _seamless_in(room) == null)
	_check("boss pending is_boss", bool(bm.pending.get("is_boss")))
	bm.clear_pending()
	_scene_changes.clear()
	_check("trainer start ok", bm.start_trainer_battle("wrath_rival_1", "m3a", Vector2(100, 200)))
	_check("trainer navigates to battle scene", _scene_changes.has("res://scenes/battle.tscn"))
	_check("no seamless node for trainer", _seamless_in(room) == null)
	bm.clear_pending()

	current_scene = null
	room.queue_free()
	bm.queue_free()

	print("")
	if _failures.is_empty():
		print("SEAMLESS BATTLE: ALL PASS")
	else:
		print("SEAMLESS BATTLE: %d FAILURES" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
