extends SceneTree
## Headless wild-encounter test: step counter, weighted table picks, range
## gating, dialogue/cutscene/pause guards, post-battle cooldown, zone exit.
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/wild_test.gd
##
## The body runs from _process (first frame), so the tree is active —
## the same pattern as battle_scene_test. Dependencies are injected
## (zone.battle_manager) and internals called directly.

const ZoneScript := preload("res://scripts/wild_zone.gd")
const BM_Script := preload("res://scripts/battle_manager.gd")

var _failures: Array[String] = []
var _scene_changes: Array = []
var _ran := false


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failures.append(name)
		print("  FAIL: ", name)


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false


func _on_scene_change(path: String) -> void:
	_scene_changes.append(path)


func _make_bm():
	var bm = BM_Script.new()
	root.add_child(bm)
	bm._ready()
	bm.scene_changer = Callable(self, "_on_scene_change")
	return bm


func _reset_cooldown(bm) -> void:
	bm.last_battle_end_msec = Time.get_ticks_msec() - 60000


func _make_player() -> Node2D:
	var player := Node2D.new()
	player.position = Vector2.ZERO
	root.add_child(player)
	player.add_to_group("player")
	return player


func _make_zone(bm, table_key: String) -> Area2D:
	var zone = ZoneScript.new()
	zone.table_key = table_key
	zone.steps_per_encounter = 4
	zone.encounter_rate = 1.0
	zone.cooldown_seconds = 8.0
	zone.cue_delay = 0.0
	var col := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(400, 300)
	col.shape = rect
	zone.add_child(col)
	root.add_child(zone)  # _ready runs here; the tree is active
	zone.battle_manager = bm
	return zone


func _walk(zone, player: Node2D, steps: int) -> void:
	for i in steps:
		player.position += Vector2(24.0, 0.0)
		zone._track_movement()
		zone._physics_process(0.016)


func _run() -> void:
	print("=== WILD TEST ===")

	# 1. Table loading from data/encounters.json.
	var p3t: Array = ZoneScript.table_for("p3")
	_check("p3 table has 2 entries", p3t.size() == 2)
	var ids := []
	for e in p3t:
		ids.append(str((e as Dictionary)["creature_id"]))
	_check("p3 table has siltmaw", ids.has("siltmaw"))
	_check("p3 table has bellowscap", ids.has("bellowscap"))
	_check("unknown key -> empty table", ZoneScript.table_for("nope").is_empty())
	var c1t: Array = ZoneScript.table_for("c1")
	_check("c1 table has 3 entries", c1t.size() == 3)

	var bm = _make_bm()
	var player := _make_player()
	var zone = _make_zone(bm, "p3")
	_check("zone resolved p3 table", (zone._table as Array).size() == 2)
	_check("zone rect read from shape", zone._zone_rect().size == Vector2(400, 300))
	_check("zone built grass tufts", not (zone._tufts as Array).is_empty())

	# 2. Step counter triggers an encounter at the threshold.
	zone._on_body_entered(player)
	_scene_changes.clear()
	_walk(zone, player, 6)
	_check("encounter fired after walking", _scene_changes.size() == 1)
	if _scene_changes.is_empty():
		_check("encounter went to battle scene", false)
	else:
		_check("encounter went to battle scene", str(_scene_changes[0]).ends_with("battle.tscn"))
	_check("battle pending holds wild enemy", str(bm.pending.get("enemy_creature_id", "")) != "")
	_check("wild battle not boss", not bool(bm.pending.get("is_boss", true)))
	bm.clear_pending()
	_reset_cooldown(bm)

	# 3. Weighted distribution roughly matches the table (60/40 on p3).
	var counts := {"siltmaw": 0, "bellowscap": 0}
	for i in 600:
		var pick: Dictionary = zone._pick_creature()
		counts[str(pick["creature_id"])] = int(counts[str(pick["creature_id"])]) + 1
	_check("both creatures picked", counts["siltmaw"] > 0 and counts["bellowscap"] > 0)
	var ratio := float(counts["siltmaw"]) / 600.0
	_check("siltmaw ratio ~0.6 (got %.2f)" % ratio, ratio > 0.45 and ratio < 0.75)

	# 4. Picked levels stay inside each entry's range.
	var levels_ok := true
	for i in 200:
		var pick: Dictionary = zone._pick_creature()
		var entry: Dictionary = {}
		for e in p3t:
			if str((e as Dictionary)["creature_id"]) == str(pick["creature_id"]):
				entry = e
		if int(pick["level"]) < int(entry["min_level"]) or int(pick["level"]) > int(entry["max_level"]):
			levels_ok = false
	_check("all picked levels in range", levels_ok)

	# 5. Standing still never triggers.
	var zone2 = _make_zone(bm, "p3")
	zone2._on_body_entered(player)
	_scene_changes.clear()
	for i in 10:
		zone2._physics_process(0.016)
	_check("no encounter standing still", _scene_changes.is_empty())

	# 6. No encounter while dialogue is open.
	var box := Control.new()
	zone2.dialogue_box = box
	root.add_child(box)
	box.visible = true
	_scene_changes.clear()
	_walk(zone2, player, 6)
	_check("no encounter during dialogue", _scene_changes.is_empty())
	box.visible = false
	_scene_changes.clear()
	_walk(zone2, player, 6)
	_check("encounter resumes after dialogue closes", _scene_changes.size() == 1)
	bm.clear_pending()
	box.queue_free()
	zone2.dialogue_box = null

	# 7. Post-battle cooldown: no encounter right after clear_pending...
	# (clear_pending above just stamped the clock).
	var zone3 = _make_zone(bm, "p3")
	zone3._on_body_entered(player)
	_scene_changes.clear()
	_walk(zone3, player, 6)
	_check("cooldown blocks immediate re-encounter", _scene_changes.is_empty())
	# ...but fires once the cooldown has elapsed.
	bm.last_battle_end_msec = Time.get_ticks_msec() - 20000
	_scene_changes.clear()
	_walk(zone3, player, 6)
	_check("encounter fires after cooldown elapses", _scene_changes.size() == 1)
	bm.clear_pending()

	# 8. Leaving the zone stops rolls.
	var zone4 = _make_zone(bm, "p3")
	zone4._on_body_entered(player)
	zone4._on_body_exited(player)
	_scene_changes.clear()
	_walk(zone4, player, 6)
	_check("no encounter after zone exit", _scene_changes.is_empty())

	# 9. Rustle cue spawns a "!" label.
	zone4._on_body_entered(player)
	zone4._show_rustle_cue()
	var found := false
	for child in zone4.get_children():
		if child is Label and (child as Label).text == "!":
			found = true
	_check("rustle cue shows '!'", found)

	# 10. Empty table never triggers.
	var zone5 = _make_zone(bm, "nope")
	zone5._on_body_entered(player)
	_scene_changes.clear()
	_walk(zone5, player, 6)
	_check("no encounter with empty table", _scene_changes.is_empty())

	print("=== WILD TEST: %d failure(s) ===" % _failures.size())
	for f in _failures:
		print("  FAILED: ", f)
	quit(0 if _failures.is_empty() else 1)
