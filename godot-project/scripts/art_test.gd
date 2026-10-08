extends SceneTree
## Headless NPC/environment art test: art files load, NPCs show real art
## with greybox fallback, room backgrounds are wired and behind gameplay.
## Run: ./Godot_v4.3-stable_linux.x86_64 --headless --path <project> -s res://scripts/art_test.gd
##
## Body runs from _process (first frame) so the tree is active.

const NPCScene := preload("res://scenes/npc.tscn")
const NPCScript := preload("res://scripts/npc.gd")

var _failures: Array[String] = []
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


func _load_tex(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


func _make_npc(npc_name: String) -> Area2D:
	var npc = NPCScene.instantiate()
	npc.npc_name = npc_name
	root.add_child(npc)
	return npc


func _run() -> void:
	print("== art_test ==")

	# 1. Art files exist and load headless-safe.
	var files := {"mira": "res://assets/npc/mira.png",
		"wounded_soldier": "res://assets/npc/wounded_soldier.png",
		"styx": "res://assets/npc/styx.png"}
	for key in files:
		var tex := _load_tex(files[key])
		_check("art file loads: " + key, tex != null)
		if tex != null:
			_check("art has size: " + key, tex.get_width() > 0 and tex.get_height() > 0)

	# 2. NPCs with art show it, greybox body hides.
	var cases := {"MIRA": "mira", "SOLDIER": "wounded_soldier", "STYX": "styx"}
	for npc_name in cases:
		var npc := _make_npc(npc_name)
		_check(npc_name + " has_art", npc.has_art())
		_check(npc_name + " body hidden", not (npc.get_node("Body") as Polygon2D).visible)
		var art := npc.get_node("Art") as Sprite2D
		_check(npc_name + " art node present", art != null)
		if art != null:
			# Scaled to ~120px tall.
			var h := art.texture.get_height() * art.scale.y
			_check(npc_name + " art ~120px tall", h > 100.0 and h < 140.0)
			# Feet near y=0 (sprite centered at -60).
			_check(npc_name + " art positioned", art.position.y < 0.0)
		npc.queue_free()

	# 3. NPCs without art stay greybox (shopkeeper, trainers).
	for npc_name in ["FERRY STALL", "SHORE SCAVENGER", "TIDE HUNTER", "SOMEONE"]:
		var npc := _make_npc(npc_name)
		_check(npc_name + " greybox fallback", not npc.has_art())
		_check(npc_name + " body visible", (npc.get_node("Body") as Polygon2D).visible)
		npc.queue_free()

	# 4. art_id export override works.
	var npc2 := _make_npc("CUSTOM")
	npc2.art_id = "mira"
	# _ready already ran with no art; re-apply via direct call.
	npc2._apply_art()
	_check("art_id override shows art", npc2.has_art())
	npc2.queue_free()

	# 5. Room backgrounds: texture present, behind gameplay (first child).
	var rooms := {"p1": "res://scenes/room_p1.tscn",
		"p3": "res://scenes/room_p3.tscn",
		"c1": "res://scenes/room_c1.tscn"}
	for room_id in rooms:
		var packed: PackedScene = load(rooms[room_id])
		_check("room loads: " + room_id, packed != null)
		if packed == null:
			continue
		var room = packed.instantiate()
		root.add_child(room)
		var bg := room.get_node_or_null("Background") as Sprite2D
		_check(room_id + " background node", bg != null)
		if bg != null:
			_check(room_id + " background has texture", bg.texture != null)
			# First child of the room root = drawn behind everything else.
			_check(room_id + " background is first child", room.get_child(0) == bg)
		# Collision and NPCs untouched.
		_check(room_id + " walls present", room.get_node_or_null("Walls") != null)
		room.queue_free()

	# 6. Real room instances carry art NPCs (Mira / soldier / Styx).
	var packed_p1: PackedScene = load("res://scenes/room_p1.tscn")
	var room_p1 = packed_p1.instantiate()
	root.add_child(room_p1)
	var mira := room_p1.get_node_or_null("Mira")
	_check("p1 Mira node exists", mira != null)
	if mira != null:
		_check("p1 Mira shows art", mira.has_art())
	var soldier := room_p1.get_node_or_null("WoundedSoldier")
	_check("p1 soldier node exists", soldier != null)
	if soldier != null:
		_check("p1 soldier shows art", soldier.has_art())
	room_p1.queue_free()
	var packed_c1: PackedScene = load("res://scenes/room_c1.tscn")
	var room_c1 = packed_c1.instantiate()
	root.add_child(room_c1)
	var styx := room_c1.get_node_or_null("Styx")
	_check("c1 Styx node exists", styx != null)
	if styx != null:
		_check("c1 Styx shows art", styx.has_art())
	room_c1.queue_free()

	print("== art_test: %d failures ==" % _failures.size())
	for f in _failures:
		print("  FAILED: ", f)
	quit(1 if not _failures.is_empty() else 0)
