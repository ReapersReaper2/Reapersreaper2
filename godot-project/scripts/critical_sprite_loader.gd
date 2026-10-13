extends RefCounted
## LFS-independent art loader for the opening scenes.
## First prefer the original image. If the checkout contains a Git LFS
## pointer (common in GitHub ZIP / unconfigured Android builds), decode
## the small set of bundled, exact-source master assets.
const CRITICAL_DIR := "res://assets/critical_sprites/"
static var _cache: Dictionary = {}

static func load_texture(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var result: Texture2D = null
	var raw_exists := FileAccess.file_exists(path)
	# An LFS stub is plain text masquerading as a PNG. Never pass it to
	# ResourceLoader, which may emit importer errors or a bogus texture.
	var pointer := raw_exists and is_lfs_pointer(path)
	if not pointer and ResourceLoader.exists(path, "Texture2D"):
		# Godot exports imported .ctex resources and often omits source
		# images. ResourceLoader resolves that remap in Android/Web builds;
		# Image.load_from_file() cannot and prints export warnings.
		var resource: Resource = ResourceLoader.load(path, "Texture2D")
		if resource is Texture2D:
			result = resource as Texture2D
	if result == null and raw_exists and not pointer:
		# Editor/ZIP fallback if a valid source PNG hasn't been imported.
		# Loading from bytes avoids Image.load_from_file's export warning.
		var bytes := FileAccess.get_file_as_bytes(path)
		if not bytes.is_empty():
			var image := Image.new()
			if image.load_png_from_buffer(bytes) == OK and not image.is_empty():
				result = ImageTexture.create_from_image(image)
	if result == null:
		result = _load_bundled(path)
	if result != null:
		_cache[path] = result
	return result

## Check presence without emitting missing-art errors. Use this ONLY for
## optional idle/NPC animation sheets; required gameplay sprites still load
## through load_texture(), which reports missing art loudly.
static func has_source(path: String) -> bool:
	var raw_exists := FileAccess.file_exists(path)
	if raw_exists and not is_lfs_pointer(path):
		return true
	# On exported Android/iOS builds the original PNG may not be in
	# FileAccess, while the imported texture remap is still available.
	if not raw_exists and ResourceLoader.exists(path, "Texture2D"):
		return true
	var stem := path.get_file().get_basename()
	return FileAccess.file_exists(CRITICAL_DIR + stem + ".b64") or \
		FileAccess.file_exists(CRITICAL_DIR + path.get_file() + ".b64")

static func is_lfs_pointer(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	# Reading binary PNGs through get_line() caused UTF-8 decoding errors.
	# LFS pointer files are ASCII; checking raw bytes is safe for both types.
	var heading := file.get_buffer(64).get_string_from_ascii()
	file.close()
	return heading.begins_with("version https://git-lfs.github.com/spec/v1")

static func _load_bundled(path: String) -> Texture2D:
	var basename := path.get_file().get_basename()
	# Prologue sheets use <stem>.b64, but later Reserve exports use
	# <stem>.png.b64. Both contain base64-encoded approved PNG bytes.
	# Support both conventions so LFS-stub checkouts render every sprite.
	var bundled := CRITICAL_DIR + basename + ".b64"
	if not FileAccess.file_exists(bundled):
		bundled = CRITICAL_DIR + path.get_file() + ".b64"
	if not FileAccess.file_exists(bundled):
		push_error("[CriticalSpriteLoader] Missing PNG and both fallback names: " +
			path + " (" + basename + ".b64 / " + path.get_file() + ".b64)")
		return null
	var encoded := FileAccess.get_file_as_string(bundled).strip_edges()
	if encoded.is_empty():
		push_error("[CriticalSpriteLoader] empty bundled image: " + bundled)
		return null
	var bytes := Marshalls.base64_to_raw(encoded)
	var image := Image.new()
	var err := image.load_png_from_buffer(bytes)
	if err != OK or image.is_empty():
		push_error("[CriticalSpriteLoader] malformed bundled PNG: " + bundled)
		return null
	print("[ART] Loaded playable image fallback: " + basename)
	return ImageTexture.create_from_image(image)
