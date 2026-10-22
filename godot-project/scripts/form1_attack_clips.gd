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

static func _trace(message: String) -> void:
	if OS.has_environment("DQ005_PROBE") or bool(ProjectSettings.get_setting("dq005_probe/enabled", false)):
		print("[DQ005 FORM1] " + message)

static func _reject(message: String) -> Dictionary:
	_trace("REJECT " + message)
	return {}


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
		return _reject("manifest status=" + str(source.get("status", "")))
	var strips: Variant = source.get("strips", {})
	if not (strips is Dictionary):
		return _reject("strips is not Dictionary; type=" + type_string(typeof(strips)))
	var loaded: Dictionary = {}
	for key in required_keys():
		var entry: Variant = strips.get(key, {})
		if not (entry is Dictionary):
			return _reject(key + ": missing dictionary entry")
		var path := str(entry.get("texture", ""))
		if not path.begins_with(ALLOWED_ROOT) or not path.ends_with(".png") or \
				path.contains("..") or not loader.is_valid():
			return _reject(key + ": forbidden texture path or invalid loader " + path)
		var frames := int(entry.get("frames", -1))
		if frames != (8 if key.begins_with("heavy_") else 6):
			return _reject(key + ": frame count=" + str(frames))
		var cell: Variant = entry.get("cell", [])
		# JSON parses numbers as floats; whole-array equality rejects a
		# valid on-disk [384,384] even though synthetic integer fixtures pass.
		if not (cell is Array) or cell.size() != 2 or \
				float(cell[0]) != float(CELL) or float(cell[1]) != float(CELL):
			return _reject(key + ": cell mismatch=" + str(cell))
		var pivot: Variant = entry.get("pivot", [])
		if not _valid_pivot(pivot):
			return _reject(key + ": bad pivot=" + str(pivot))
		if absf(float(entry.get("fps", 0.0)) - 12.0) > 0.01:
			return _reject(key + ": bad fps=" + str(entry.get("fps", null)))
		var tex: Variant = loader.call(path)
		_trace(key + ": loader returned " + ("null" if tex == null else str(tex.get_class())) + " from " + path)
		if not (tex is Texture2D):
			return _reject(key + ": loader did not return Texture2D")
		var texture: Texture2D = tex as Texture2D
		if texture.get_width() != frames * CELL or texture.get_height() != CELL:
			return _reject(key + ": loaded texture geometry=" + str(texture.get_size()))
		loaded[key] = {
			"texture": texture,
			"frames": frames,
			"pivot": Vector2(float(pivot[0]), float(pivot[1])),
		}
	_trace("validate success count=" + str(loaded.size()))
	return loaded


static func load_approved(loader: Callable) -> Dictionary:
	_trace("manifest exists=" + str(FileAccess.file_exists(MANIFEST_PATH)) + " resource_exists=" + str(ResourceLoader.exists(MANIFEST_PATH)))
	if not FileAccess.file_exists(MANIFEST_PATH):
		return _reject("manifest not found by FileAccess")
	var raw_json := FileAccess.get_file_as_string(MANIFEST_PATH)
	_trace("manifest byte_count=" + str(raw_json.to_utf8_buffer().size()))
	var parsed: Variant = JSON.parse_string(raw_json)
	_trace("JSON parsed type=" + type_string(typeof(parsed)))
	if not (parsed is Dictionary):
		push_error("[FORM1 ATTACK] Approved manifest is not valid JSON object")
		_trace("REJECT invalid JSON")
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
