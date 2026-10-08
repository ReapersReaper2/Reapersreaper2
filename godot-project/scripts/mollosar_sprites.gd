extends Node2D
class_name MollosarSprites
## Sprite manager for Mollosar's 10 forms.
##
## Given a form number + facing direction, shows the right walk-strip
## frame. spec384 sheets live in res://sprites/mollosar/ as
## form{N}_walk_{down,up,left,right}_spec384.png — each a row of
## 384x384 cells (3 or 4 frames depending on the strip).
##
## 8-direction movement maps to the 4 strips by dominant axis:
## up-left / up-right -> up, down-left / down-right -> down.
##
## Greybox fallback: if a form has no strips, the sprite hides itself
## and the old greybox polygons stay visible.

const SPRITE_DIR := "res://sprites/mollosar/"
const CELL := 384
const WALK_FPS := 8.0
const SWING_FPS := 14.0
## Figure is ~256px tall inside the 384 cell; 0.5 scale ~= 128px,
## matching the old greybox capsule.
const SPRITE_SCALE := 0.5

const DIRS := ["down", "up", "left", "right"]

var _form: int = 0
var _strips: Dictionary = {}
var _frames: Dictionary = {}
var _strip_dir: String = "down"
var _mirrored: bool = false
var _frame: int = 0
var _walk_t: float = 0.0
var _swinging: bool = false
var _swing_t: float = 0.0
var _swing_tex: Texture2D = null
var _swing_frames: int = 0

var _sprite: Sprite2D = null
var _greybox: Array = []


var _ready_done := false


func _ready() -> void:
	if _ready_done:
		return
	_ready_done = true
	_sprite = Sprite2D.new()
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_sprite.centered = true
	add_child(_sprite)
	# Everything else under the parent (the greybox polygons) is the
	# fallback visual set; hide them once real sprites are showing.
	for child in get_parent().get_children():
		if child != self:
			_greybox.append(child)
	refresh()


## Re-read the form from GameState; reload strips if it changed.
## Safe to call every frame (cheap int compare).
func refresh() -> void:
	var form := _current_form()
	if form != _form:
		_load_form(form)


func _current_form() -> int:
	# Absolute-path lookup is illegal before the node is inside the tree
	# (headless -s harnesses); in-game this always resolves.
	if not is_inside_tree():
		return 1
	var gs = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("get_form"):
		return int(gs.get_form())
	return 1


## Headless-safe texture load: FileAccess + ImageTexture, because
## ResourceLoader needs the editor import cache (absent for files
## dropped in via the filesystem and in headless runs).
static func _load_tex(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


func _load_form(form: int) -> void:
	_form = form
	_strips.clear()
	_frames.clear()
	_swing_tex = null
	_swing_frames = 0
	for d in DIRS:
		var tex := _load_tex("%sform%d_walk_%s_spec384.png" % [SPRITE_DIR, form, d])
		if tex == null and d == "right":
			# Form 7 shipped without a right strip (Gage's ChatGPT
			# retry pending): mirror the left strip until it lands.
			tex = _load_tex("%sform%d_walk_left_spec384.png" % [SPRITE_DIR, form])
			if tex != null:
				_strips["right_mirrored"] = true
		if tex != null:
			_strips[d] = tex
			_frames[d] = maxi(1, int(tex.get_width() / CELL))
	# Form 3's reap-swing strip exists: use it during scythe swings.
	_swing_tex = _load_tex("%sform%d_reap_swing_spec384.png" % [SPRITE_DIR, form])
	if _swing_tex != null:
		_swing_frames = maxi(1, int(_swing_tex.get_width() / CELL))
	else:
		_swing_frames = 0
		_swinging = false
	_apply_greybox_visibility()
	_set_strip(_strip_dir)


func has_sprites() -> bool:
	return not _strips.is_empty()


func current_form() -> int:
	return _form


func _apply_greybox_visibility() -> void:
	var show_real := has_sprites()
	if _sprite != null:
		_sprite.visible = show_real
	for g in _greybox:
		if is_instance_valid(g):
			# CanvasItem covers Node2D (polygons) and Control
			# (the eye ColorRects) alike.
			(g as CanvasItem).visible = not show_real


## Map an 8-direction facing vector to one of the 4 strips.
static func strip_for(facing: Vector2) -> String:
	if absf(facing.x) > absf(facing.y):
		return "right" if facing.x > 0.0 else "left"
	return "down" if facing.y > 0.0 else "up"


func _set_strip(d: String) -> void:
	_strip_dir = d
	_mirrored = bool(_strips.get(d + "_mirrored", false))
	_frame = 0
	_walk_t = 0.0
	_draw_frame()


func _draw_frame() -> void:
	if _sprite == null:
		return
	if _swinging and _swing_tex != null:
		_sprite.texture = _swing_tex
		_sprite.flip_h = false
		var n := _swing_frames
		_sprite.region_enabled = true
		_sprite.region_rect = Rect2((_frame % n) * CELL, 0, CELL, CELL)
		return
	var tex: Texture2D = _strips.get(_strip_dir, null)
	if tex == null:
		return
	_sprite.texture = tex
	_sprite.flip_h = _mirrored
	var count: int = int(_frames.get(_strip_dir, 1))
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2((_frame % count) * CELL, 0, CELL, CELL)


## Advance animation. Call from the player's _physics_process with the
## current facing vector and whether the player is actually moving.
func tick(delta: float, facing: Vector2, moving: bool) -> void:
	refresh()
	if not has_sprites():
		return
	var d := strip_for(facing)
	if d != _strip_dir and not _swinging:
		_set_strip(d)
	if _swinging:
		_swing_t += delta
		var sf := int(_swing_t * SWING_FPS)
		if sf != _frame:
			_frame = sf
			_draw_frame()
		return
	if moving:
		_walk_t += delta
		var f := int(_walk_t * WALK_FPS)
		if f != _frame:
			_frame = f
			_draw_frame()
	elif _frame != 0:
		_frame = 0
		_walk_t = 0.0
		_draw_frame()


## Called on scythe swing_started: play the reap-swing strip if this
## form has one (currently only Form 3).
func play_swing() -> void:
	if _swing_tex != null and not _swinging:
		_swinging = true
		_swing_t = 0.0
		_frame = 0
		_draw_frame()


## Called on scythe swing_ended: back to walk/idle.
func stop_swing() -> void:
	if _swinging:
		_swinging = false
		_frame = 0
		_walk_t = 0.0
		_draw_frame()
