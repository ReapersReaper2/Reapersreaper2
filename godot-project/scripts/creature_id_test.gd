extends SceneTree
## Test all authored room_*.tscn sources for stable Reserve resident IDs.
## A change to scene names/IDs is a save schema change, not visual polish.
const Resident := preload("res://scripts/reserve_creature.gd")
var checks := 0
var failures := 0
var residents_seen := 0

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[CREATURE ID] " + description)

func _run() -> void:
	var scenes := DirAccess.get_files_at("res://scenes")
	var room_count := 0
	for filename in scenes:
		if not filename.begins_with("room_") or not filename.ends_with(".tscn"):
			continue
		room_count += 1
		var path := "res://scenes/" + filename
		var packed = load(path)
		_check(packed is PackedScene, "room parses: " + filename)
		if not (packed is PackedScene):
			continue
		var room: Node = (packed as PackedScene).instantiate()
		var creatures: Node = room.get_node_or_null("Creatures")
		if creatures != null:
			var room_name := filename.get_basename()
			var seen: Dictionary = {}
			var index := 0
			for item in creatures.get_children():
				if item.get_script() != Resident:
					continue
				index += 1
				residents_seen += 1
				var key: String = str(item.get("creature_id"))
				_check(not key.is_empty(), filename + " resident has authored key")
				_check(key == "%s_%02d" % [room_name, index],
					filename + " keeps <room>_<index> identity")
				_check(not seen.has(key), filename + " has no repeated IDs")
				seen[key] = true
				# Species ID and creature identity are different. Multiple
				# of the same species can inhabit another room safely.
				_check(key != str(item.get("art_id")),
					filename + " key is not an asset/species name")
		room.free()
	_check(room_count > 0, "room scenes discovered for identity validation")
	_check(residents_seen == 5, "five existing Garden residents have stable keys")
	if failures == 0:
		print("[CREATURE ID] PASS %d checks" % checks)
	else:
		push_error("[CREATURE ID] FAIL %d/%d" % [failures, checks])
	quit(1 if failures > 0 else 0)

func _check_stub() -> void:
	# Reserved for future encounter room fixtures; never allocate IDs at
	# runtime based on spawn order, which would change across save/load.
	pass
