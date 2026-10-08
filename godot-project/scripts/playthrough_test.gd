extends SceneTree
## Headless critical-path playthrough: drives the game at the API level in
## the order a player would experience it, verifying state after each step.
## This is QA infrastructure, not a game feature — it catches integration
## bugs that unit tests miss (cross-system state, room flow, save/load).
##
## Approach: "integration test", not "bot with a controller". We call the
## same methods the UI calls (triggers, spawner, contract accept, shrine
## rest/travel, etc.) in player order. Frame-driven state machine because
## scene instantiation, spawners, and cutscenes need frames to settle.
##
## Run: Godot_v4.3-stable_linux.x86_64 --headless --path <project> \
##        -s res://scripts/playthrough_test.gd
## Uses save slot 97 as throwaway (deleted before and after).
##
## Error policy: the script exits non-zero on any failed assertion. For the
## no-errors/no-warnings check, capture stderr when running:
##   ... -s res://scripts/playthrough_test.gd 2>err.log; grep -c "SCRIPT ERROR" err.log
## (GDScript has no hook for push_error; the external check is the reliable one.)

const SLOT := 97

const TitleScript := preload("res://scripts/title_screen.gd")
const GameStateScript := preload("res://scripts/game_state.gd")
const SaveSystemScript := preload("res://scripts/save_system.gd")
const AchScript := preload("res://scripts/achievements.gd")
const PartyScript := preload("res://scripts/party.gd")
const ContractsScript := preload("res://scripts/contracts.gd")
const MerchantsScript := preload("res://scripts/merchants.gd")
const StallScript := preload("res://scripts/stall.gd")
const JournalScript := preload("res://scripts/journal.gd")
const CreatureDataScript := preload("res://scripts/creature_data.gd")
const CutsceneP2Script := preload("res://scripts/cutscene_p2.gd")

var _frame := 0
var _phase := 0
var _phase_frame := 0
var _failed := 0
var _passed := 0
var _skipped: Array[String] = []

var _ss = null
var _ach = null
var _gs = null
var _room = null
var _nav_paths: Array = []
var _spawner = null
var _cutscene = null
var _journal = null


func _check(name: String, cond: bool) -> void:
	if cond:
		_passed += 1
		print("  PASS: ", name)
	else:
		_failed += 1
		print("  FAIL: ", name)


func _skip(name: String, reason: String) -> void:
	_skipped.append(name + " (" + reason + ")")
	print("  SKIP: ", name, " — ", reason)


func _initialize() -> void:
	print("== playthrough_test: critical path ==")


func _make_stack() -> void:
	# Use the REAL autoload singletons. Rooms, spawners, and cutscenes all
	# resolve /root/GameState — a shadow copy would silently diverge from
	# what the game actually touches, defeating the purpose of this test.
	_ss = root.get_node("SaveSystem")
	_ach = root.get_node("Achievements")
	_gs = root.get_node("GameState")


func _load_room(scene_path: String):
	# Detach the previous room so group lookups can't see stale nodes.
	if _room != null:
		if _room.get_parent() != null:
			_room.get_parent().remove_child(_room)
		_room.queue_free()
		_room = null
	_room = (load(scene_path) as PackedScene).instantiate()
	root.add_child(_room)
	return _room


func _exits_in(node) -> Array:
	var out: Array = []
	for n in node.find_children("*", "Area2D", true, false):
		if n.is_in_group("exit"):
			out.append(n)
	return out


func _physics_process(_delta: float) -> bool:
	_frame += 1
	_phase_frame += 1
	match _phase:
		0:
			_phase_setup()
		1:
			_phase_p1_waves()
		2:
			_phase_p1_collapse()
		3:
			_phase_p3_luna()
		4:
			_phase_c1()
		5:
			_phase_h1()
		6:
			_phase_h2_h3_h4_nm()
		7:
			_phase_systems()
		8:
			_phase_saveload()
		9:
			_phase_travel()
		_:
			_report()
			return true
	return false


# ---------------------------------------------------------------- setup ---

func _phase_setup() -> void:
	if _phase_frame == 1:
		_make_stack()
		_ss.delete_save(SLOT)
		var ts = TitleScript.new()
		ts.game_state = _gs
		ts.scene_changer = _nav_paths.append
		root.add_child(ts)
		ts._slot = SLOT  # new_game() applies the title's selected slot
		ts.activate("new")
		_check("title: new game boots room_p1",
			_nav_paths.size() > 0 and str(_nav_paths[0]).ends_with("room_p1.tscn"))
		_check("new game: starter party", PartyScript.size(_gs) >= 1)
		_check("new game: starter snares", _gs.get_item_count("soul_snare") > 0)
		_check("new game: starting credits", _gs.get_soul_credits() > 0)
		_check("new game: slot set", _gs.get_current_slot() == SLOT)
		ts.queue_free()
		_next_phase()


func _next_phase() -> void:
	_phase += 1
	_phase_frame = 0


# ------------------------------------------------------------- p1 waves ---

func _phase_p1_waves() -> void:
	if _phase_frame == 1:
		_load_room("res://scenes/room_p1.tscn")
		return
	if _phase_frame == 3:
		var player = _room.get_node_or_null("Player")
		_check("p1: player spawned", player != null and player.is_in_group("player"))
		var luna = _room.get_node_or_null("Luna")
		_check("p1: luna present", luna != null)
		_spawner = _room.get_node_or_null("WaveSpawner")
		_check("p1: wave spawner present", _spawner != null and _spawner.has_method("start_waves"))
		# Drive the tutorial trigger like the player walking into it.
		_room._on_room_trigger("tutorial", null)
		var box = _room.get_node_or_null("DialogueBox")
		_check("p1: tutorial dialogue started",
			box != null and box.get("visible") == true)
		# Player finishes the dialogue (force_close emits dialogue_finished,
		# which is what starts the waves in-game). Also start directly —
		# start_waves() is idempotent, so this is safe either way.
		_spawner.start_waves()
		if box != null and box.has_method("force_close"):
			box.force_close()
		return
	if _phase_frame > 3 and _phase_frame % 3 == 0 and _spawner != null:
		# The scythe's kill path, at API level.
		for inv in _spawner._invader_list().duplicate():
			if is_instance_valid(inv) and inv.has_method("is_alive") and inv.is_alive():
				inv.take_hit(9999, Vector2.ZERO)
		if _spawner.is_done():
			_check("p1: all three waves cleared", true)
			_check("p1: p1_bridge_cleared flag set", _gs.get_flag("p1_bridge_cleared"))
			_check("p1: spawner reports done", _spawner.is_done())
			_next_phase()
			return
	if _phase_frame > 3 and _phase_frame == 6:
		_check("p1: waves in progress", not _spawner.is_done())
	if _phase_frame > 4000:
		# Safety valve: ~66s of game time is far more than waves need.
		_check("p1: waves finished in reasonable time", false)
		_next_phase()



# ---------------------------------------------------------- p2 collapse ---

func _phase_p1_collapse() -> void:
	if _phase_frame == 1:
		# Player walks to the east end of the cleared bridge.
		_room._on_room_trigger("bridge_end", null)
		return
	if _phase_frame == 5:
		# The cutscene node goes on the tree root.
		for n in root.get_children():
			if n.has_signal("cutscene_finished"):
				_cutscene = n
				break
		_check("p2: collapse cutscene started", _cutscene != null)
		if _cutscene != null and _cutscene.has_method("_do_skip"):
			# Skipping is a legitimate player action; consequential
			# steps (flags) still land.
			_cutscene._do_skip()
		return
	if _phase_frame == 10:
		_check("p2: p2_collapse_seen flag set", _gs.get_flag("p2_collapse_seen"))
		# The cutscene's steps carry the p3 transition; verify the
		# static step list ends with the room_p3 scene change.
		var steps: Array = CutsceneP2Script.steps()
		var goes_p3 := false
		for s in steps:
			if s is Dictionary and str(s.get("type", "")) == "scene" \
				and str(s.get("path", "")).ends_with("room_p3.tscn"):
				goes_p3 = true
		_check("p2: cutscene leads to room_p3", goes_p3)
		if _cutscene != null:
			_cutscene.queue_free()
			_cutscene = null
		_next_phase()


# --------------------------------------------------------------- p3 luna ---

func _phase_p3_luna() -> void:
	if _phase_frame == 1:
		_load_room("res://scenes/room_p3.tscn")
		return
	if _phase_frame == 5:
		var box = _room.get_node_or_null("DialogueBox")
		# The intro auto-plays on room ready (deferred).
		_check("p3: luna intro dialogue started",
			box != null and (box.get("visible") == true or _gs.get_flag("p3_luna_intro_done")))
		if box != null and box.has_method("force_close") and box.get("visible") == true:
			box.force_close()
		return
	if _phase_frame == 8:
		_check("p3: p3_luna_intro_done flag set", _gs.get_flag("p3_luna_intro_done"))
		_check("p3: form 2 unlocked", _gs.get_form() == 2)
		_next_phase()


# ------------------------------------------------------------------ c1 ---

func _phase_c1() -> void:
	if _phase_frame == 1:
		_load_room("res://scenes/room_c1.tscn")
		return
	if _phase_frame == 3:
		var styx = _room.get_node_or_null("Styx")
		_check("c1: styx npc present", styx != null)
		# Trigger wiring: the bellmaw + bounty triggers must exist.
		var triggers: Array = []
		for n in _room.find_children("*", "Area2D", true, false):
			if n.is_in_group("trigger"):
				triggers.append(str(n.get_meta("trigger_id", "")))
		_check("c1: bounty_a trigger wired", "bounty_a" in triggers)
		_check("c1: bellmaw trigger wired", "bellmaw" in triggers)
		# Bellmaw boss data is sane (the fight itself is covered by
		# battle_scene_test; here we verify the trigger path exists).
		_check("c1: bellmaw creature data exists",
			not CreatureDataScript.get_creature("bellmaw").is_empty())
		var exits := _exits_in(_room)
		var to_h1 := false
		for e in exits:
			if str(e.get_meta("target_scene", "")).ends_with("room_h1.tscn"):
				to_h1 = true
		_check("c1: exit to h1 wired", to_h1)
		_next_phase()



# ----------------------------------------------------------------- h1 hub ---

func _phase_h1() -> void:
	if _phase_frame == 1:
		_load_room("res://scenes/room_h1.tscn")
		return
	if _phase_frame == 3:
		var board = _room.get_node_or_null("BountyBoard")
		_check("h1: bounty board present", board != null and board.has_method("open_board"))
		if board != null:
			board.open_board()
			_check("h1: bounty board opens", board.is_open())
			board.close_board()
		# Kanryu must never be takeable.
		_check("h1: kanryu sealed (not acceptable)",
			not ContractsScript.can_accept(_gs, "kanryu"))
		# Accept a real contract, like the player would.
		var ok: bool = ContractsScript.accept(_gs, "c_strays")
		_check("h1: contract c_strays accepted", ok and ContractsScript.is_accepted(_gs, "c_strays"))
		# Simulate reaping 2 of 4 wispwillows.
		ContractsScript.record_reap(_gs, "wispwillow")
		ContractsScript.record_reap(_gs, "wispwillow")
		var prog: Array = ContractsScript.objectives_progress(_gs, "c_strays")
		var done_count := 0
		if prog.size() > 0:
			done_count = int(prog[0].get("current", 0))
		_check("h1: contract progress tracked (2/4)", done_count == 2)
		_check("h1: contract not complete yet", not ContractsScript.is_complete(_gs, "c_strays"))
		return
	if _phase_frame == 6:
		# Shrine: rest restores vigor and lights the shrine.
		var shrine = null
		for n in _room.find_children("*", "Area2D", true, false):
			if n.get_script() != null and str(n.get_script().resource_path).ends_with("shrine.gd"):
				shrine = n
				break
		_check("h1: lantern shrine present", shrine != null)
		if shrine != null:
			shrine.game_state = _gs
			_gs.heal_to_full()
			var vigor_max: int = int(_gs.state["player"].get("vigor_max", 0))
			var vigor: int = int(_gs.state["player"].get("vigor", 0))
			_check("h1: heal_to_full restores vigor", vigor_max > 0 and vigor == vigor_max)
			shrine._finish_rest()
			_check("h1: shrine lit in network", not _gs.get_lit_shrines().is_empty())
			_check("h1: rest autosaves", _ss.has_save(SLOT))
		# Exits to the rest of the hub.
		var exits := _exits_in(_room)
		var targets: Array = []
		for e in exits:
			targets.append(str(e.get_meta("target_scene", "")))
		var has := func(suffix: String) -> bool:
			for t in targets:
				if str(t).ends_with(suffix):
					return true
			return false
		_check("h1: exit to h2 wired", has.call("room_h2.tscn"))
		_check("h1: exit to h3 wired", has.call("room_h3.tscn"))
		_check("h1: exit to h4 wired", has.call("room_h4.tscn"))
		_check("h1: moon-gate to night market wired", has.call("room_nm.tscn"))
		_next_phase()



# ------------------------------------------------- h2 h3 h4 nm walk ---

func _phase_h2_h3_h4_nm() -> void:
	var step := _phase_frame
	if step == 1:
		_load_room("res://scenes/room_h2.tscn")
		return
	if step == 4:
		var murray = _room.get_node_or_null("Murray")
		_check("h2: murray npc present", murray != null)
		_check("h2: murray has real art", murray != null and murray.has_method("has_art") and murray.has_art())
		_check("h2: murray is shopkeeper", murray != null and bool(murray.get("is_shopkeeper")))
		_load_room("res://scenes/room_h3.tscn")
		return
	if step == 7:
		var shopkeepers := 0
		for n in _room.find_children("*", "Area2D", true, false):
			if n.get("is_shopkeeper") == true:
				shopkeepers += 1
		_check("h3: three dockside shops present", shopkeepers >= 3)
		_load_room("res://scenes/room_h4.tscn")
		return
	if step == 10:
		var zone = null
		for n in _room.find_children("*", "Area2D", true, false):
			if n.get_script() != null and str(n.get_script().resource_path).ends_with("wild_zone.gd"):
				zone = n
				break
		_check("h4: wild encounter zone present", zone != null)
		var pod = _room.get_node_or_null("CreepPodCluster")
		_check("h4: creep pod cluster present", pod != null)
		var pod_art = pod.get_node_or_null("Art") if pod != null else null
		_check("h4: creep pod has real sprite", pod_art != null)
		_load_room("res://scenes/room_nm.tscn")
		return
	if step == 13:
		var vendors := 0
		for n in _room.find_children("*", "Area2D", true, false):
			var nm = str(n.name).to_upper()
			if "IVY" in nm or "MASKED" in nm or "TOLL" in nm:
				vendors += 1
		_check("nm: three night vendors present", vendors >= 3)
		var exits := _exits_in(_room)
		var back_to_h1 := false
		for e in exits:
			if str(e.get_meta("target_scene", "")).ends_with("room_h1.tscn"):
				back_to_h1 = true
		_check("nm: exit back to h1 wired", back_to_h1)
		_next_phase()


# ------------------------------------------------------ systems ----------

func _phase_systems() -> void:
	if _phase_frame == 1:
		# Simulated catch: battle start marks seen, victory adds to party.
		_gs.mark_seen("wispwillow")
		var added: bool = PartyScript.add_creature(_gs, "wispwillow", 5)
		_check("catch: creature added to party", added and PartyScript.size(_gs) >= 2)
		_check("catch: journal ledger shows caught",
			_journal_ledger("wispwillow") == "caught")
		_check("catch: unseen creature still ???",
			_journal_ledger("floatbladder") == "unseen")
		# Journal quest reflects live flags.
		var qs := _journal_quest("q_bridge")
		_check("journal: quest data loads", not qs.is_empty())
		# Merchant disposition from purchases.
		MerchantsScript.add_points(_gs, "oddments", 10)
		_check("merchants: regular tier at 10 pts",
			MerchantsScript.get_tier(_gs, "oddments") == "regular")
		_check("merchants: price multiplier below list",
			MerchantsScript.price_multiplier(_gs, "oddments") < 1.0)
		# Player stall unlock (fund first).
		_gs.add_soul_credits(10000)
		var r: Dictionary = StallScript.unlock(_gs)
		_check("stall: unlocks with fee", bool(r.get("ok", false)) and StallScript.is_unlocked(_gs))
		_next_phase()


func _journal_ledger(creature_id: String) -> String:
	if _journal == null:
		_journal = JournalScript.new()
		_journal.game_state = _gs
	return str(_journal.ledger_state(creature_id))


func _journal_quest(quest_id: String) -> Dictionary:
	if _journal == null:
		_journal = JournalScript.new()
		_journal.game_state = _gs
	for q in JournalScript.load_quests():
		if str(q.get("id", "")) == quest_id:
			return _journal.quest_status(q)
	return {}



# ------------------------------------------------- save/load ----------

func _phase_saveload() -> void:
	if _phase_frame == 1:
		# Mid-playthrough round-trip: mutate, save, clobber, load, verify.
		var credits_before: int = _gs.get_soul_credits()
		_check("save: contract accepted before save",
			ContractsScript.is_accepted(_gs, "c_strays"))
		_check("save: merchant points before save",
			MerchantsScript.get_points(_gs, "oddments") == 10)
		_check("save: stall unlocked before save", StallScript.is_unlocked(_gs))
		_check("save: shrines lit before save", not _gs.get_lit_shrines().is_empty())
		_check("save: flags before save", _gs.get_flag("p1_bridge_cleared"))
		_gs.save_to_slot(SLOT)
		# Clobber live state.
		_gs.set_flag("p1_bridge_cleared", false)
		_gs.add_soul_credits(-credits_before)
		_check("save: state clobbered", not _gs.get_flag("p1_bridge_cleared"))
		_gs.load_from_slot(SLOT)
		_check("load: flags restored", _gs.get_flag("p1_bridge_cleared"))
		_check("load: credits restored", _gs.get_soul_credits() == credits_before)
		_check("load: contract still accepted",
			ContractsScript.is_accepted(_gs, "c_strays"))
		var prog: Array = ContractsScript.objectives_progress(_gs, "c_strays")
		var done_count := 0
		if prog.size() > 0:
			done_count = int(prog[0].get("current", 0))
		_check("load: contract progress preserved (2/4)", done_count == 2)
		_check("load: merchant points preserved",
			MerchantsScript.get_points(_gs, "oddments") == 10)
		_check("load: stall still unlocked", StallScript.is_unlocked(_gs))
		_check("load: shrines still lit", not _gs.get_lit_shrines().is_empty())
		_check("load: party preserved", PartyScript.size(_gs) >= 2)
		_check("load: seen set preserved", _gs.has_seen("wispwillow"))
		# Finish the contract now (post-load, like a real player would).
		ContractsScript.record_reap(_gs, "wispwillow")
		ContractsScript.record_reap(_gs, "wispwillow")
		_check("contract: complete at 4/4", ContractsScript.is_complete(_gs, "c_strays"))
		var before: int = _gs.get_soul_credits()
		var res: Dictionary = ContractsScript.turn_in(_gs, "c_strays")
		_check("contract: turn-in succeeds", bool(res.get("ok", false)))
		_check("contract: reward paid", _gs.get_soul_credits() > before)
		_check("contract: marked turned in", ContractsScript.is_turned_in(_gs, "c_strays"))
		_next_phase()


# ------------------------------------------------- fast travel ----------

func _phase_travel() -> void:
	if _phase_frame == 1:
		_load_room("res://scenes/room_h1.tscn")
		return
	if _phase_frame == 3:
		# Light a second shrine directly (h1's was lit by rest in phase 5).
		_gs.light_shrine("p1_1", "p1", -1700.0, 100.0)
		var lit: Dictionary = _gs.get_lit_shrines()
		_check("travel: two shrines lit", lit.size() >= 2)
		var shrine = null
		for n in _room.find_children("*", "Area2D", true, false):
			if n.get_script() != null and str(n.get_script().resource_path).ends_with("shrine.gd"):
				shrine = n
				break
		_check("travel: shrine node found", shrine != null)
		if shrine != null:
			shrine.game_state = _gs
			var dests: Array = shrine._travel_destinations()
			var ids: Array = []
			for d in dests:
				ids.append(str(d.get("id", "")))
			_check("travel: p1_1 listed as destination", "p1_1" in ids)
			var my_id := str(shrine.shrine_id)
			_check("travel: current shrine excluded", not (my_id in ids))
			var path: String = shrine._travel_to("p1_1")
			_check("travel: returns p1 scene path", path.ends_with("room_p1.tscn"))
			var pos: Dictionary = _gs.get_position()
			_check("travel: spawn set to p1", str(pos.get("room", "")) == "p1")
			_check("travel: unknown destination fails safe", shrine._travel_to("nope_9") == "")
		_next_phase()


# ------------------------------------------------- report ----------

func _report() -> void:
	print("")
	print("== playthrough_test DONE: %d passed, %d failed, %d skipped ==" % [_passed, _failed, _skipped.size()])
	for s in _skipped:
		print("  SKIPPED: ", s)
	# Clean up the throwaway slot.
	_ss.delete_save(SLOT)
	if _journal != null and is_instance_valid(_journal):
		_journal.free()
		_journal = null
	if _room != null and is_instance_valid(_room):
		if _room.get_parent() != null:
			_room.get_parent().remove_child(_room)
		_room.queue_free()
	quit(1 if _failed > 0 else 0)
