extends RefCounted
## Approval-gated Form 1 sword animation data and frame sampler.
## We accept only complete, explicitly APPROVED 384x384 artist sheets.
## Nothing in Asset Candidates is searched or promoted automatically.
## The current shader/body-pose attack stays authoritative if absent.
const CELL := 384
const MANIFEST_PATH := "res://sprites/mollosar/approved/form1_attack_manifest.json"
const ACTIONS := ["windup", "slash", "rslash", "heavy", "recover"]
const DIRECTIONS := ["front", "back", "side-l", "side-r"]
const ALLOWED_ROOT := "res://sprites/mollosar/approved/"

static func direction_for_facing(facing: Vector2) -> String:
	if absf(facing.x) > absf(facing.y):
		return "side-r" if facing.x > 0.0 else "side-l"
	return "front" if facing.y >= 0.0 else "back"


static func clip_key(action: String, direction: String) -> String:
	return action + "_" + direction


static func required_keys() -> Array[String]:
	var result: Array[String] = []
	for action in ACTIONS:
		for direction in DIRECTIONS:
			result.append(clip_key(action, direction))
	return result


static func _valid_pivot(pivot: Variant) -> bool:
	if not (pivot is Array) or pivot.size() != 2:
		return false
	return float(pivot[0]) >= 0.0 and float(pivot[0]) <= CELL and \
		float(pivot[1]) >= 0.0 and float(pivot[1]) <= CELL


## A complete sheet set is atomic. If heavy_back (or any other strip)
## is absent, do not load a mix of production and provisional animation.
## The loader is injected to keep every validation unit-testable.
static func validate_manifest(source: Dictionary, loader: Callable) -> Dictionary:
	if str(source.get("status", "")) != "APPROVED":
		print("[DQ005] reject: status=", source.get("status", "<missing>"))
		return {}
	var strips: Variant = source.get("strips", {})
	if not (strips is Dictionary):
		print("[DQ005] reject: strips not Dictionary: ", type_string(typeof(strips)))
		return {}
	var loaded: Dictionary = {}
	for key in required_keys():
		var entry: Variant = strips.get(key, {})
		if not (entry is Dictionary):
			print("[DQ005] reject: missing/non-dictionary entry ", key)
			return {}
		var path := str(entry.get("texture", ""))
		if not path.begins_with(ALLOWED_ROOT) or not path.ends_with(".png") or \
				path.contains("..") or not loader.is_valid():
			print("[DQ005] reject: invalid texture path or callable: ", key, " path=", path)
			return {}
		var frames := int(entry.get("frames", -1))
		if frames != (8 if key.begins_with("heavy_") else 6):
			print("[DQ005] reject: frame count ", key, " got=", frames)
			return {}
		var cell: Variant = entry.get("cell", [])
		# JSON parses numbers as floats; whole-array equality rejects a
		# valid on-disk [384,384] even though synthetic integer fixtures pass.
		if not (cell is Array) or cell.size() != 2 or \
				float(cell[0]) != float(CELL) or float(cell[1]) != float(CELL):
			print("[DQ005] reject: bad cell ", key, " value=", cell)
			return {}
		var pivot: Variant = entry.get("pivot", [])
		if not _valid_pivot(pivot):
			print("[DQ005] reject: invalid pivot ", key, " value=", pivot)
			return {}
		if absf(float(entry.get("fps", 0.0)) - 12.0) > 0.01:
			print("[DQ005] reject: fps ", key, " value=", entry.get("fps", "<missing>"))
			return {}
		print("[DQ005] validate ", key, " raw_exists=", FileAccess.file_exists(path), " resource_exists=", ResourceLoader.exists(path))
		var tex: Variant = loader.call(path)
		if not (tex is Texture2D):
			print("[DQ005] reject: texture loader returned ", type_string(typeof(tex)), " for ", key, " path=", path)
			return {}
		var texture: Texture2D = tex as Texture2D
		print("[DQ005] loaded ", key, " class=", texture.get_class(), " size=", texture.get_width(), "x", texture.get_height())
		if texture.get_width() != frames * CELL or texture.get_height() != CELL:
			print("[DQ005] reject: invalid texture dimensions ", key)
			return {}
		loaded[key] = {
			"texture": texture,
			"frames": frames,
			"pivot": Vector2(float(pivot[0]), float(pivot[1])),
		}
	print("[DQ005] validate PASS clips=", loaded.size())
	return loaded


static func load_approved(loader: Callable) -> Dictionary:
	print("[DQ005] manifest raw_exists=", FileAccess.file_exists(MANIFEST_PATH), " resource_exists=", ResourceLoader.exists(MANIFEST_PATH), " path=", MANIFEST_PATH)
	if not FileAccess.file_exists(MANIFEST_PATH):
		print("[DQ005] reject: manifest FileAccess.file_exists returned false")
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	print("[DQ005] manifest bytes=", FileAccess.get_file_as_string(MANIFEST_PATH).length(), " parsed=", type_string(typeof(parsed)))
	if not (parsed is Dictionary):
		push_error("[FORM1 ATTACK] Approved manifest is not valid JSON object")
		return {}
	var clips := validate_manifest(parsed, loader)
	if clips.is_empty():
		push_error("[FORM1 ATTACK] Incomplete/invalid approved attack set; retaining shader fallback")
	return clips


## Combat drive's normalized progress, not animation FPS, owns the hit
## window. The art strip poses sample without ever looping mid-swing.
## Windup 3: held charge; normal 1, reverse 2, heavy 4: strike;
## recovery 5: the rig's separate RECOVER state. Each strip gets the
## entire existing state duration, including combat-scoped hitstop.
static func sample(clips: Dictionary, swing_index: int, fraction: float,
		facing: Vector2) -> Dictionary:
	if clips.is_empty() or swing_index <= 0:
		return {}
	var action := ""
	match swing_index:
		1: action = "slash"
		2: action = "rslash"
		3: action = "windup"
		4: action = "heavy"
		5: action = "recover"
		_: return {}
	var p := clampf(fraction, 0.0, 1.0)
	var key := clip_key(action, direction_for_facing(facing))
	var clip: Dictionary = clips.get(key, {})
	if clip.is_empty():
		return {}
	var frames := int(clip["frames"])
	return {
		"texture": clip["texture"],
		"frame": mini(frames - 1, int(floorf(p * float(frames)))),
		"frames": frames,
		"pivot": clip["pivot"],
		"action": action,
		"direction": direction_for_facing(facing),
	}


static func grounded_sprite_y(pivot: Vector2, scale: float, foot_y: float = 64.0) -> float:
	return foot_y - (pivot.y - float(CELL) * 0.5) * scale
