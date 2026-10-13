extends SceneTree
## Installs five native transparent overworld portraits over the old
## paper-matte battle paintings, without forcing a redesign. Runs under
## Godot 4.3 headless after project import.
## godot --headless --path godot-project --script res://scripts/reserve_native_overworld_test.gd

const Resident := preload("res://scripts/reserve_creature.gd")
const Loader := preload("res://scripts/critical_sprite_loader.gd")
const Room := preload("res://scenes/room_gd1.tscn")
const ROOT := "res://assets/creatures/"

const SPECIES := [
	["dragonthorn", 168.0, 146856],
	["gloomcap", 179.2, 72111],
	["spinehopper", 174.7, 44931],
	["bellmaw", 146.0, 137645],
	["wispwillow", 146.0, 182909]
]

var _checks := 0
var _failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for spec in SPECIES:
		var key: String = spec[0]
		var desired_height: float = spec[1]
		var expected_bytes: int = spec[2]
		var native_path := ROOT + key + "_overworld.png"
		var original_path := ROOT + key + ".png"
		_check(FileAccess.file_exists(native_path),
			key + ": 384px native art is actually in the repository")
		_check(FileAccess.get_file_as_bytes(native_path).size() == expected_bytes,
			key + ": exact delivered candidate/original bytes are preserved")
		_check(not Loader.is_lfs_pointer(native_path),
			key + ": native art is binary PNG, never a Git LFS text pointer")
		var image := Image.new()
		var err := image.load_png_from_buffer(FileAccess.get_file_as_bytes(native_path))
		_check(err == OK and image.get_size() == Vector2i(384, 384),
			key + ": original native PNG keeps its 384x384 framing")
		_check(image.get_format() == Image.FORMAT_RGBA8,
			key + ": native overworld sprite has true RGBA alpha")
		_check(image.get_pixel(0, 0).a < 0.01 and
			image.get_pixel(383, 383).a < 0.01,
			key + ": no painted backdrop or opaque matte plate")
		var used: Rect2i = image.get_used_rect()
		_check(used.end.y >= 345 and used.end.y <= 367,
			key + ": the visual foot/hover anchor sits near y=352")
		_check(used.position.x > 25 and used.end.x < 355,
			key + ": full creature silhouette fits inside art canvas")

		# The real resident contract should auto-select native art in a
		# fixture and preserve the original scene-scale height, not show
		# a tiny miniature or 1600px painting.
		var root_node := Node2D.new()
		root_node.name = key + "_fixture"
		root.add_child(root_node)
		var resident = Resident.new()
		resident.name = key.capitalize()
		resident.overworld_display_height = desired_height
		root_node.add_child(resident)
		_check(resident.get("_using_overworld_art"),
			key + ": visible garden resident selects native transparent PNG")
		_check(resident.material == null,
			key + ": native alpha completely replaces old paper cutout shader")
		_check(resident.texture != null and resident.texture.get_size() == Vector2(384, 384),
			key + ": native texture is resolved by existing critical sprite loader")
		var actual_height := resident.texture.get_height() * absf(resident.scale.y)
		_check(absf(actual_height - desired_height) < 1.1,
			key + ": original in-world size survives sprite replacement")
		root_node.queue_free()

		# Source battle painting stays available and rollback is a single
		# scene export boolean, never a file deletion.
		_check(Loader.has_source(original_path),
			key + ": the old approved painting remains recoverable")
		var fallback_root := Node2D.new()
		root.add_child(fallback_root)
		var fallback = Resident.new()
		fallback.name = key.capitalize()
		fallback.prefer_overworld_art = false
		fallback_root.add_child(fallback)
		_check(not fallback.get("_using_overworld_art"),
			key + ": art-review toggle restores the old painting")
		_check(fallback.texture != null,
			key + ": old painting fallback still loads")
		fallback_root.queue_free()

	var scene = Room.instantiate()
	for spec in SPECIES:
		var resident := scene.get_node_or_null("Creatures/" + str(spec[0]).capitalize())
		_check(resident != null and resident.overworld_display_height > 0.0,
			str(spec[0]) + ": garden keeps per-species scaled art setup")
	_check(scene.get_node_or_null("ReserveGuide") != null and
		scene.get_node_or_null("ReserveClock") != null,
		"native art does not disrupt clock and observation controller")
	scene.free()

	if _failures == 0:
		print("[RESERVE NATIVE OVERWORLD] PASS %d checks" % _checks)
	else:
		push_error("[RESERVE NATIVE OVERWORLD] FAIL %d/%d" % [_failures, _checks])
	quit(1 if _failures > 0 else 0)

func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error("[RESERVE NATIVE OVERWORLD] " + message)
