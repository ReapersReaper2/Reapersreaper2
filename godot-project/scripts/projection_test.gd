extends SceneTree
## Headless memory-currency / projection verification: the memory pool,
## the inn trade economy, permanent spends, and Whisper-line projection.
##
## Run: Godot --headless --path <project> -s res://scripts/projection_test.gd

const GameStateScript = preload("res://scripts/game_state.gd")
const MemoriesScript = preload("res://scripts/memories.gd")
const D06BScript = preload("res://scripts/dialogue_06b.gd")

var _gs = null
var _passed := 0
var _failed := 0


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] projection: ", label)


func _initialize() -> void:
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		_gs = GameStateScript.new()
		_gs.name = "GameState"
		root.add_child(_gs)
		_gs._ready()
	_gs.new_game()
	_run()
	print("[projection_test] done: ", _passed, " passed, ", _failed, " failed")
	quit()


func _fresh_gs():
	var g = GameStateScript.new()
	g.name = "GameState"
	root.add_child(g)
	g._ready()
	g.new_game()
	return g


func _run() -> void:
	_test_pool()
	_test_trade()
	_test_spend_safety()
	_test_projection()
	_test_06b_choice_routing()


func _test_pool() -> void:
	var g = _fresh_gs()
	_check(MemoriesScript.count(g) == 6, "pool: 6 memories at new game")
	_check(MemoriesScript.owned(g) == ["horsemen", "church_bells", "silver_helmet", "invaders", "bell_tower", "bridge"],
		"pool: canonical order")
	_check(MemoriesScript.has(g, "horsemen"), "pool: has horsemen")
	_check(not MemoriesScript.gone(g, "horsemen"), "pool: horsemen not gone")
	_check(MemoriesScript.memory_name("church_bells") == "The Church Bells", "pool: name lookup")
	g.queue_free()


func _test_trade() -> void:
	var g = _fresh_gs()
	_check(MemoriesScript.trade_key_for_letter("A") == "horsemen", "trade: A->horsemen")
	_check(MemoriesScript.trade_key_for_letter("d") == "invaders", "trade: d->invaders (case-insensitive)")
	_check(MemoriesScript.trade_key_for_letter("Z") == "", "trade: unknown letter -> empty")
	_check(MemoriesScript.trade(g, "horsemen"), "trade: horsemen trades")
	_check(bool(g.get_flag("memory_traded", false)), "trade: memory_traded flag set")
	_check(bool(g.get_flag("flashback_gone_horsemen", false)), "trade: flashback_gone_horsemen set")
	_check(MemoriesScript.count(g) == 5, "trade: count drops to 5")
	_check(MemoriesScript.gone(g, "horsemen"), "trade: horsemen gone permanently")
	_check(not MemoriesScript.trade(g, "horsemen"), "trade: cannot re-trade spent memory")
	# Trade options only offer held memories.
	var opts: Array = MemoriesScript.trade_options(g)
	var letters: Array = []
	for o in opts:
		letters.append(str((o as Dictionary).get("letter")))
	_check(not letters.has("A"), "trade: spent memory not re-offered")
	_check(letters.has("B") and letters.has("C") and letters.has("D"), "trade: held memories still offered")
	g.queue_free()


func _test_spend_safety() -> void:
	var g = _fresh_gs()
	_check(not MemoriesScript.spend(g, "not_a_memory"), "spend: unknown key rejected")
	MemoriesScript.spend(g, "bridge")
	_check(not MemoriesScript.spend(g, "bridge"), "spend: cannot spend what you don't have")
	_check(not bool(g.get_flag("memory_traded", false)), "spend: plain spend does not set memory_traded")
	g.queue_free()


func _test_projection() -> void:
	var g = _fresh_gs()
	_check(not MemoriesScript.can_project(g), "projection: locked before Whisper-line")
	_check(MemoriesScript.project(g, "invaders").is_empty(), "projection: refused while locked")
	_check(MemoriesScript.count(g) == 6, "projection: refused cast spends nothing")
	g.set_flag("projection_unlocked", true)
	_check(MemoriesScript.can_project(g), "projection: unlocked with memories")
	var mem: Dictionary = MemoriesScript.project(g, "invaders")
	_check(not mem.is_empty(), "projection: cast returns memory data")
	_check(str(mem.get("name", "")) == "The Invaders", "projection: replay data is the memory")
	_check(MemoriesScript.gone(g, "invaders"), "projection: memory burned permanently")
	_check(MemoriesScript.count(g) == 5, "projection: count drops")
	_check(MemoriesScript.projection_active(g), "projection: active after cast")
	_check(MemoriesScript.projection_memory(g) == "invaders", "projection: remembers which memory")
	MemoriesScript.end_projection(g)
	_check(not MemoriesScript.projection_active(g), "projection: ends cleanly")
	# Burn everything: projection impossible at 0 memories.
	for key in MemoriesScript.owned(g).duplicate():
		MemoriesScript.spend(g, key)
	_check(MemoriesScript.count(g) == 0, "projection: pool can empty")
	_check(not MemoriesScript.can_project(g), "projection: no memories, no projection")
	g.queue_free()


func _test_06b_choice_routing() -> void:
	# The inn choice letters must map to real memory keys (regression: the
	# old code flagged flashback_gone_a instead of flashback_gone_horsemen).
	var g = _fresh_gs()
	var ctx := {"game_state": g, "room": null, "scene": {}}
	D06BScript.apply_choice({"key": "B", "text": "The church bells."}, ctx)
	_check(bool(g.get_flag("flashback_gone_church_bells", false)),
		"06b: choice B burns church_bells (not flashback_gone_b)")
	_check(not bool(g.get_flag("flashback_gone_b", false)), "06b: no letter-flag set")
	_check(bool(g.get_flag("memory_traded", false)), "06b: choice sets memory_traded")
	_check(MemoriesScript.count(g) == 5, "06b: pool reflects the trade")
	g.queue_free()
