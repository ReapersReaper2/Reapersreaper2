extends SceneTree
## NPC master art wiring test (M4): Ivy, Marrow, Harrow, Originator.
## Verifies each room loads, the NPC node exists, and the art resolves.

const NPCScript := preload("res://scripts/npc.gd")

var _passed := 0
var _failed := 0

func _check(desc: String, cond: bool) -> void:
	print(("  PASS: " if cond else "  FAIL: ") + desc)
	if cond:
		_passed += 1
	else:
		_failed += 1

func _room_has_npc_with_art(room_path: String, node_name: String, npc_name: String, art_stem: String) -> void:
	var packed: PackedScene = load(room_path)
	_check(room_path + " loads", packed != null)
	if packed == null:
		return
	var room: Node = packed.instantiate()
	_check(node_name + " node present", room.get_node_or_null(node_name) != null)
	var npc := room.get_node_or_null(node_name)
	if npc == null:
		room.queue_free()
		return
	_check("npc_name == " + npc_name, npc.get("npc_name") == npc_name)
	# Art resolution: static call via a temp NPC instance is heavy;
	# instead verify the mapping + file directly.
	_check("NPC_ART has " + npc_name, NPCScript.NPC_ART.has(npc_name))
	_check("NPC_ART[" + npc_name + "] == " + art_stem, NPCScript.NPC_ART.get(npc_name, "") == art_stem)
	var art_path := "res://assets/npc/" + art_stem + ".png"
	_check(art_path + " exists", FileAccess.file_exists(art_path))
	var img := Image.load_from_file(art_path)
	_check(art_stem + ".png loads as image", img != null and not img.is_empty())
	room.queue_free()

func _init() -> void:
	print("[TEST] npc_master_art")
	_room_has_npc_with_art("res://scenes/room_gd3.tscn", "Ivy", "IVY", "ivy")
	_room_has_npc_with_art("res://scenes/room_t5.tscn", "Marrow", "MARROW", "marrow")
	_room_has_npc_with_art("res://scenes/room_gd5.tscn", "Harrow", "HARROW", "harrow")
	_room_has_npc_with_art("res://scenes/room_o2.tscn", "OriginatorNPC", "ORIGINATOR", "originator")
	# gd5: no duplicate ext_resource ids
	var gd5_text := FileAccess.get_file_as_string("res://scenes/room_gd5.tscn")
	var id8_count := gd5_text.count('id="8"')
	_check("room_gd5 has no duplicate id=8", id8_count == 1)
	print("[TEST] npc_master_art: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
