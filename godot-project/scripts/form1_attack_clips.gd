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
		return {}
	var strips: Variant = source.get("strips", {})
	if not (strips is Dictionary):
		return {}
	var loaded: Dictionary = {}
	for key in required_keys():
		var entry: Variant = strips.get(key, {})
		if not (entry is Dictionary):
			return {}
		var path := str(entry.get("texture", ""))
		if not path.begins_with(ALLOWED_ROOT) or not path.ends_with(".png") or \
				path.contains("..") or not loader.is_valid():
			return {}
		var frames := int(entry.get("frames", -1))
		if frames != (8 if key.begins_with("heavy_") else 6):
			return {}
		var cell: Variant = entry.get("cell", [])
		if not (cell is Array) or cell != [CELL, CELL]:
			return {}
		var pivot: Variant = entry.get("pivot", [])
		if not _valid_pivot(pivot):
			return {}
		if absf(float(entry.get("fps", 0.0)) - 12.0) > 0.01:
			return {}
		var tex: Variant = loader.call(path)
		if not (tex is Texture2D):
			return {}
		var texture: Texture2D = tex as Texture2D
		if texture.get_width() != frames * CELL or texture.get_height() != CELL:
			return {}
		loaded[key] = {
			"texture": texture,
			"frames": frames,
			"pivot": Vector2(float(pivot[0]), float(pivot[1])),
		}
	return loaded


static func load_approved(loader: Callable) -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not (parsed is Dictionary):
		push_error("[FORM1 ATTACK] Approved manifest is not valid JSON object")
		return {}
	var clips := validate_manifest(parsed, loader)
	if clips.is_empty():
		push_error("[FORM1 ATTACK] Incomplete/invalid approved attack set; retaining shader fallback")
	return clips


## Combat drive's normalized progress, not animation FPS, owns the hit
## window. The art strip poses sample without ever looping mid-swing.
## Windup 3: held charge; normal 1, reverse 2, heavy 4: direct strike
## then recovery. The rest pose comes from existing walking strip.
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
		_: return {}
	var p := clampf(fraction, 0.0, 1.0)
	if swing_index != 3 and p >= 0.68:
		action = "recover"
		p = (p - 0.68) / 0.32
	elif swing_index != 3:
		p /= 0.68
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
