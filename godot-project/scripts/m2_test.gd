extends SceneTree
## Headless M2 (Chapter 2 hub) verification: all 4 rooms load with zero
## errors, shrine/bounty board/shops/wild zone/creep pod are wired, Wrath
## trigger fires once, trainer data is sane, transitions connect.
##
## Run: Godot --headless --path <project> -s res://scripts/m2_test.gd

const BountyBoard := preload("res://scripts/bounty_board.gd")
const CreepPod := preload("res://scripts/creep_pod.gd")
const TrainerData := preload("res://scripts/trainer_data.gd")
const CreatureData := preload("res://scripts/creature_data.gd")
const WildZone := preload("res://scripts/wild_zone.gd")

var _frame: int = 0
var _failed: int = 0
var _room = null

const ROOMS := [
	"res://scenes/room_h1.tscn",
	"res://scenes/room_h2.tscn",
	"res://scenes/room_h3.tscn",
	"res://scenes/room_h4.tscn",
]
const ROOM_IDS := ["h1", "h2", "h3", "h4"]


func _initialize() -> void:
	print("[TEST] m2 test starting")


func _check(name: String, cond: bool) -> void:
	if cond:
		print("  PASS: ", name)
	else:
		_failed += 1
		print("  FAILED: ", name)


func _physics_process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		_data_checks()
		_load_room(0)
		return false
	if _room != null and _frame % 12 == 0:
		_verify_room(ROOM_IDS[_room_index])
		_room.get_parent().remove_child(_room)
		_room.queue_free()
		_room = null
		_load_room(_room_index + 1)
	if _room_index >= ROOMS.size() and _room == null:
		_report()
		quit(1 if _failed > 0 else 0)
	return false


var _room_index: int = -1


func _load_room(i: int) -> void:
	_room_index = i
	if i >= ROOMS.size():
		return
	var ps: PackedScene = load(ROOMS[i])
	_room = ps.instantiate()
	root.add_child(_room)


func _data_checks() -> void:
	# --- bounty board data ---
	var board := BountyBoard.load_board()
	_check("bounty board loads", not board.is_empty())
	var acts: Dictionary = board.get("acts", {})
	var act1: Dictionary = acts.get("act1", {})
	_check("board has mollosar tally", int(act1.get("mollosar", {}).get("completed", -1)) >= 0)
	_check("board has wrath tally", int(act1.get("wrath", {}).get("completed", -1)) >= 0)
	var kanryu: Dictionary = board.get("kanryu", {})
	_check("kanryu entry sealed", bool(kanryu.get("sealed", false)))
	_check("kanryu terms mention 50,000", "50,000" in str(kanryu.get("terms", "")))
	# --- new creatures ---
	_check("wispwillow in creature data", not CreatureData.get_creature("wispwillow").is_empty())
	_check("floatbladder in creature data", not CreatureData.get_creature("floatbladder").is_empty())
	_check("wispwillow is DOCILE", str(CreatureData.get_creature("wispwillow").get("temperament", "")) == "DOCILE")
	# --- h4 encounter table ---
	var h4 := WildZone.table_for("h4")
	var ids := []
	for e in h4:
		ids.append(str(e.get("creature_id", "")))
	_check("h4 table has wispwillow", "wispwillow" in ids)
	_check("h4 table has floatbladder", "floatbladder" in ids)
	_check("h4 table has siltmaw", "siltmaw" in ids)
	# --- creep pod item ---
	var pod := CreatureData.get_item("creep_pod")
	_check("creep_pod item exists", not pod.is_empty())
	# --- shops ---
	for sid in ["murrays_bar", "oddments", "apothecary", "needles_and_flights"]:
		var shop := CreatureData.get_shop(sid)
		_check("shop " + sid + " exists with stock", not shop.is_empty() and int((shop.get("stock", []) as Array).size()) > 0)
	# --- wrath trainer ---
	var wrath := TrainerData.get_trainer("wrath_rival_1")
	_check("wrath_rival_1 exists", not wrath.is_empty())
	_check("wrath has 2-creature roster", int((wrath.get("roster", []) as Array).size()) == 2)
	_check("wrath spares on loss", bool(wrath.get("spare_on_loss", false)))
	_check("wrath has rivalry_flag", str(wrath.get("rivalry_flag", "")) == "wrath_rivalry")


func _verify_room(rid: String) -> void:
	_check(rid + " room_id set", str(_room.get("room_id")) == rid)
	_check(rid + " has Player", _room.get_node_or_null("Player") != null)
	_check(rid + " has DialogueBox", _room.get_node_or_null("DialogueBox") != null)
	# Exits all have targets.
	var exits := 0
	for n in _room.find_children("*", "Area2D", true, false):
		if n.is_in_group("exit"):
			exits += 1
			_check(rid + " exit has target", str(n.get_meta("target_scene", "")) != "")
	_check(rid + " has exits", exits > 0)
	match rid:
		"h1":
			_verify_h1()
		"h2":
			_verify_h2()
		"h3":
			_verify_h3()
		"h4":
			_verify_h4()


func _verify_h1() -> void:
	_check("h1 shrine present", _room.get_node_or_null("ShrineH1") != null)
	var shrine = _room.get_node_or_null("ShrineH1")
	if shrine != null:
		_check("h1 shrine_id h1_1", str(shrine.get("shrine_id")) == "h1_1")
	_check("h1 bounty board present", _room.get_node_or_null("BountyBoard") != null)
	var board = _room.get_node_or_null("BountyBoard")
	if board != null:
		_check("h1 board has Prompt", board.get_node_or_null("Prompt") != null)
	# Wrath trigger: one-shot, correct id.
	var trig = _room.get_node_or_null("WrathConfront")
	_check("h1 wrath trigger present", trig != null)
	if trig != null:
		_check("h1 wrath trigger id", str(trig.get_meta("trigger_id", "")) == "wrath_confront")
		_check("h1 wrath trigger one-shot", bool(trig.get_meta("one_shot", false)))
	# Townsfolk NPCs.
	var folk := 0
	for n in _room.find_children("*", "Area2D", true, false):
		if str(n.get("npc_name", "")) == "TOWNSFOLK":
			folk += 1
	_check("h1 has 3 townsfolk", folk == 3)


func _verify_h2() -> void:
	var murray = _room.get_node_or_null("Murray")
	_check("h2 Murray present", murray != null)
	if murray != null:
		_check("h2 Murray is shopkeeper", bool(murray.get("is_shopkeeper")))
		_check("h2 Murray shop murrays_bar", str(murray.get("shop_id")) == "murrays_bar")
		_check("h2 Murray shows art", murray.has_method("has_art") and bool(murray.call("has_art")))
	var trig = _room.get_node_or_null("KanryuAnnounce")
	_check("h2 kanryu trigger present", trig != null)
	if trig != null:
		_check("h2 kanryu trigger one-shot", bool(trig.get_meta("one_shot", false)))


func _verify_h3() -> void:
	var shops := {"OddmentsDoor": "oddments", "ApothecaryDoor": "apothecary", "FletcherDoor": "needles_and_flights"}
	for node_name in shops:
		var n = _room.get_node_or_null(node_name)
		_check("h3 " + node_name + " present", n != null)
		if n != null:
			_check("h3 " + node_name + " opens " + shops[node_name], str(n.get("shop_id")) == shops[node_name])
			_check("h3 " + node_name + " is shopkeeper", bool(n.get("is_shopkeeper")))
	var fenna = _room.get_node_or_null("Fenna")
	_check("h3 Fenna present", fenna != null)
	if fenna != null:
		_check("h3 Fenna shows art", fenna.has_method("has_art") and bool(fenna.call("has_art")))
	# Canon descriptions resolve for all three shops.
	var UiText = load("res://scripts/ui_text.gd")
	_check("h3 oddments desc", str(UiText.store_desc("oddments")) != "")
	_check("h3 apothecary desc", str(UiText.store_desc("apothecary")) != "")
	_check("h3 needles desc", str(UiText.store_desc("needles_and_flights")) != "")


func _verify_h4() -> void:
	var zone = _room.get_node_or_null("WildZoneH4")
	_check("h4 wild zone present", zone != null)
	if zone != null:
		_check("h4 zone table h4", str(zone.get("table_key")) == "h4")
	var pod = _room.get_node_or_null("CreepPodCluster")
	_check("h4 creep pod present", pod != null)
	if pod != null:
		_check("h4 pod id h4_1", str(pod.get("pod_id")) == "h4_1")
		_check("h4 pod has Prompt", pod.get_node_or_null("Prompt") != null)


func _report() -> void:
	print("=== M2 TEST: ", _failed, " failures ===")
