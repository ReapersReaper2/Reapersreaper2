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
	print("[DQ005] validate_manifest status=%s strips_type=%s" % [str(source.get("status", "MISSING")), type_string(typeof(source.get("strips", null)))])
	if str(source.get("status", "")) != "APPROVED":
		print("[DQ005] REJECT status not APPROVED")
		return {}
	var strips: Variant = source.get("strips", {})
	if not (strips is Dictionary):
		print("[DQ005] REJECT strips not Dictionary")
		return {}
	var loaded: Dictionary = {}
	for key in required_keys():
		var entry: Variant = strips.get(key, {})
		if not (entry is Dictionary):
			print("[DQ005] REJECT %s missing/not dictionary" % key)
			return {}
		var path := str(entry.get("texture", ""))
		if not path.begins_with(ALLOWED_ROOT) or not path.ends_with(".png") or \
				path.contains("..") or not loader.is_valid():
			print("[DQ005] REJECT %s invalid texture path/callable: %s" % [key, path])
			return {}
		var frames := int(entry.get("frames", -1))
		if frames != (8 if key.begins_with("heavy_") else 6):
			print("[DQ005] REJECT %s frame count=%d" % [key, frames])
			return {}
		var cell: Variant = entry.get("cell", [])
		# JSON parses numbers as floats; whole-array equality rejects a
		# valid on-disk [384,384] even though synthetic integer fixtures pass.
		if not (cell is Array) or cell.size() != 2 or \
				float(cell[0]) != float(CELL) or float(cell[1]) != float(CELL):
			print("[DQ005] REJECT %s cell=%s" % [key, str(cell)])
			return {}
		var pivot: Variant = entry.get("pivot", [])
		if not _valid_pivot(pivot):
			print("[DQ005] REJECT %s pivot=%s" % [key, str(pivot)])
			return {}
		if absf(float(entry.get("fps", 0.0)) - 12.0) > 0.01:
			print("[DQ005] REJECT %s fps=%s" % [key, str(entry.get("fps", "MISSING"))])
			return {}
		print("[DQ005] %s raw=%s imported=%s ResourceLoader.exists=%s" % [key, str(FileAccess.file_exists(path)), str(FileAccess.file_exists(path + ".import")), str(ResourceLoader.exists(path))])
		var tex: Variant = loader.call(path)
		print("[DQ005] %s loaded_type=%s" % [key, (tex.get_class() if tex is Object else type_string(typeof(tex)))])
		if not (tex is Texture2D):
			print("[DQ005] REJECT %s not a Texture2D" % key)
			return {}
		var texture: Texture2D = tex as Texture2D
		print("[DQ005] %s texture size=%dx%d" % [key, texture.get_width(), texture.get_height()])
		if texture.get_width() != frames * CELL or texture.get_height() != CELL:
			print("[DQ005] REJECT %s bad size" % key)
			return {}
		loaded[key] = {
			"texture": texture,
			"frames": frames,
			"pivot": Vector2(float(pivot[0]), float(pivot[1])),
		}
	return loaded


static func load_approved(loader: Callable) -> Dictionary:
	print("[DQ005] manifest=%s file_exists=%s resource_exists=%s" % [MANIFEST_PATH, str(FileAccess.file_exists(MANIFEST_PATH)), str(ResourceLoader.exists(MANIFEST_PATH))])
	if not FileAccess.file_exists(MANIFEST_PATH):
		print("[DQ005] REJECT manifest FileAccess.file_exists=false")
		return {}
	var raw_manifest := FileAccess.get_file_as_string(MANIFEST_PATH)
	print("[DQ005] manifest bytes=%d" % raw_manifest.to_utf8_buffer().size())
	var parsed: Variant = JSON.parse_string(raw_manifest)
	if not (parsed is Dictionary):
		print("[DQ005] REJECT manifest JSON parse/type=%s" % type_string(typeof(parsed)))
		push_error("[FORM1 ATTACK] Approved manifest is not valid JSON object")
		return {}
	var clips := validate_manifest(parsed, loader)
	print("[DQ005] load_approved result size=%d" % clips.size())
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
