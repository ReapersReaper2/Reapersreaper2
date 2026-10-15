extends Node2D
class_name MollosarSprites
## Sprite manager for Mollosar's 10 forms.
##
## Given a form number + facing direction, shows the right walk-strip
## frame. spec384 sheets live in res://sprites/mollosar/ as
## form{N}_walk_{down,up,left,right}_spec384.png — each a row of
## 384x384 cells (3 or 4 frames depending on the strip). Optional
## form{N}_idle_{dir}_spec384.png sheets animate while standing still.
##
## 8-direction movement maps to the 4 strips by dominant axis:
## up-left / up-right -> up, down-left / down-right -> down.
##
## Greybox fallback: if a form has no strips, the sprite hides itself
## and the old greybox polygons stay visible. Load failures are LOUD
## (push_error with the exact path + LFS hint) so a silent polygon can
## never ship unnoticed again.

const CriticalSpriteLoader := preload("res://scripts/critical_sprite_loader.gd")
const RestingBladeShader := preload("res://shaders/form1_resting_blade.gdshader")
const SwingBladeShader := preload("res://shaders/form1_swing_blade.gdshader")
const SwordArc := preload("res://scripts/scythe_visual.gd")
const Form1AttackClips := preload("res://scripts/form1_attack_clips.gd")
const SPRITE_DIR := "res://sprites/mollosar/"
const CELL := 384
const WALK_FPS := 6.0
const SWING_FPS := 14.0
## Figure is ~256px tall inside the 384 cell; 0.5 scale ~= 128px,
## matching the old greybox capsule.
const SPRITE_SCALE := 0.40

const DIRS := ["down", "up", "left", "right"]

## Idle animation speed (idle sheets are 2-frame loops).
const IDLE_FPS := 1.25
## Vertical grounding: form sheets draw the figure ~350px tall inside the
## 384 cell, feet ~86px below the cell center at 0.5 scale. Offset the
## sprite so the feet land on the CollisionShape2D capsule bottom (+64)
## instead of floating 22px below it.
const SPRITE_Y_OFFSET := -5.0

var _form: int = 0
var _strips: Dictionary = {}
var _frames: Dictionary = {}
## Optional idle strips: form{N}_idle_{down,up,left,right}_spec384.png.
## Shown (animated) when the player is standing still; directions without
## an idle sheet keep the old behavior (walk strip, frame 0).
var _idle: Dictionary = {}
var _idle_frames: Dictionary = {}
var _idle_scales: Dictionary = {}
var _ground_offsets: Dictionary = {}
var _idle_on: bool = false
var _idle_t: float = 0.0
var _strip_dir: String = "down"
var _mirrored: bool = false
var _frame: int = 0
var _walk_t: float = 0.0
var _swinging: bool = false
var _swing_t: float = 0.0
var _swing_tex: Texture2D = null
var _swing_frames: int = 0

var _sprite: Sprite2D = null
var _neutral_sprite_y: float = SPRITE_Y_OFFSET
var _mortal_pose_active: bool = false
## Two layers reference the SAME approved sprite texture: an alpha cut on
## the resting blade and a rotated copy of its original painted pixels.
## No duplicate synthetic sword, no new LFS payload, no change to hitbox.
## Candidate attack art is NEVER loaded. An explicit 20-strip APPROVED
## manifest can replace the procedural sword pose without code surgery.
var _attack_clips: Dictionary = {}
var _approved_attack_active: bool = false
## Freeze facing for the duration of one attack action. The player can turn
## between strikes, but never splice front/side/back art within a single cut.
var _approved_action: int = 0
var _approved_facing: Vector2 = Vector2.DOWN
var _mortal_blade_sprite: Sprite2D = null
var _mortal_rest_material: ShaderMaterial = null
var _mortal_swing_material: ShaderMaterial = null
var _greybox: Array = []


var _ready_done := false


func _ready() -> void:
	if _ready_done:
		return
	_ready_done = true
	_sprite = Sprite2D.new()
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_sprite.position.y = SPRITE_Y_OFFSET
	_sprite.centered = true
	_sprite.region_filter_clip_enabled = true
	add_child(_sprite)
	_build_mortal_blade_rig()
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
	return CriticalSpriteLoader.load_texture(path)


## True when the file is a Git LFS pointer stub (131-byte text) rather
## than the real PNG. This is the silent-polygon trap: Image.load_from_file
## on a pointer fails, _load_form finds no strips, and the greybox stays
## visible with no error anywhere. Callers use this to say so loudly.
static func _is_lfs_pointer(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	# Check the raw file header; valid PNG bytes are not UTF-8 lines.
	var line := f.get_buffer(64).get_string_from_ascii()
	f.close()
	return line.begins_with("version https://git-lfs.github.com")


func _load_form(form: int) -> void:
	_form = form
	_strips.clear()
	_frames.clear()
	_idle.clear()
	_idle_frames.clear()
	_idle_scales.clear()
	_swing_tex = null
	_swing_frames = 0
	_ground_offsets.clear()
	_reset_mortal_sword_pose()
	_approved_action = 0
	# Attack sheets were visually rejected: they do not depict the same Mollosar.
	# Keep them quarantined until replacement frames match the walk/idle master.
	_attack_clips = {}
	# Form changes always release Form 1's shader before loading other art.
	_release_mortal_blade()
	for d in DIRS:
		var wpath := "%sform%d_walk_%s_spec384.png" % [SPRITE_DIR, form, d]
		var tex := _load_tex(wpath)
		if tex == null and d == "right":
			# Form 7 shipped without a right strip (Gage's ChatGPT
			# retry pending): mirror the left strip until it lands.
			tex = _load_tex("%sform%d_walk_left_spec384.png" % [SPRITE_DIR, form])
			if tex != null:
				_strips["right_mirrored"] = true
		if tex == null:
			if FileAccess.file_exists(wpath) and _is_lfs_pointer(wpath):
				push_error("[MollosarSprites] walk strip is an LFS pointer stub, not a PNG: " + wpath + " — run 'git lfs pull' on this machine (or enable LFS smudge on the build machine); the greybox polygon stays visible until the real sheet lands.")
			elif d != "right":
				push_error("[MollosarSprites] walk strip missing or undecodable: " + wpath)
		else:
			_strips[d] = tex
			_frames[d] = maxi(1, int(tex.get_width() / CELL))
		# Optional idle sheet for this direction (Form 1 ships idle_down).
		var ipath := "%sform%d_idle_%s_spec384.png" % [SPRITE_DIR, form, d]
		var itex: Texture2D = null
		if CriticalSpriteLoader.has_source(ipath):
			itex = _load_tex(ipath)
		if itex != null:
			_idle[d] = itex
			_idle_frames[d] = maxi(1, int(itex.get_width() / CELL))
			# The front idle master has much more padding than the walk.
			# Match the figure height once, retaining original painted bytes.
			if form == 1 and tex != null:
				var walk_bounds := tex.get_image().get_region(Rect2i(0, 0, CELL, CELL)).get_used_rect()
				var idle_bounds := itex.get_image().get_region(Rect2i(0, 0, CELL, CELL)).get_used_rect()
				if walk_bounds.has_area() and idle_bounds.has_area():
					_idle_scales[d] = SPRITE_SCALE * float(walk_bounds.size.y) / float(idle_bounds.size.y)
	# Form 3's reap-swing strip exists: use it during scythe swings.
	var swing_path := "%sform%d_reap_swing_spec384.png" % [SPRITE_DIR, form]
	_swing_tex = _load_tex(swing_path) if CriticalSpriteLoader.has_source(swing_path) else null
	if _swing_tex != null:
		_swing_frames = maxi(1, int(_swing_tex.get_width() / CELL))
	else:
		_swing_frames = 0
		_swinging = false
	if _strips.is_empty():
		push_error("[MollosarSprites] NO walk strips loaded for form %d — greybox fallback engaged, the player renders as a polygon. Check the sheet paths and LFS state above." % form)
	_apply_greybox_visibility()
	_set_strip(_strip_dir)
	queue_redraw()


func has_sprites() -> bool:
	return not _strips.is_empty()


func current_form() -> int:
	return _form


func _apply_greybox_visibility() -> void:
	var show_real := has_sprites()
	if _sprite != null:
		_sprite.visible = show_real
	if _mortal_blade_sprite != null and not show_real:
		_mortal_blade_sprite.visible = false
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
	_idle_t = 0.0
	_draw_frame()


func _draw_frame() -> void:
	if _sprite == null:
		return
	if _swinging and _swing_tex != null:
		_sprite.scale = Vector2.ONE * SPRITE_SCALE
		_sprite.texture = _swing_tex
		_sprite.flip_h = false
		var n := _swing_frames
		_sprite.region_enabled = true
		var swing_frame := _frame % n
		_sprite.region_rect = Rect2(swing_frame * CELL, 0, CELL, CELL)
		_apply_grounding(_swing_tex, swing_frame)
		return
	var tex: Texture2D = _strips.get(_strip_dir, null)
	var count: int = int(_frames.get(_strip_dir, 1))
	var display_scale := SPRITE_SCALE
	if _idle_on:
		var itex: Texture2D = _idle.get(_strip_dir, null)
		if itex != null:
			tex = itex
			count = int(_idle_frames.get(_strip_dir, 1))
			display_scale = float(_idle_scales.get(_strip_dir, SPRITE_SCALE))
	if tex == null:
		return
	_sprite.texture = tex
	_sprite.rotation = 0.0
	_sprite.scale = Vector2.ONE * display_scale
	_sprite.flip_h = _mirrored
	_sprite.region_enabled = true
	var strip_frame := _frame % count
	_sprite.region_rect = Rect2(strip_frame * CELL, 0, CELL, CELL)
	_apply_grounding(tex, strip_frame)


## Each 384px cell has its own transparent padding and foot placement.
## Whole-sheet bounds mix poses and make the character float or sink.
## Keep the collision capsule's +64 baseline for walk, idle, and swing.
static func grounding_offset_for_frame(image: Image, frame_index: int, display_scale: float = SPRITE_SCALE) -> float:
	if image == null or image.is_empty() or frame_index < 0:
		return SPRITE_Y_OFFSET
	var left := frame_index * CELL
	if left >= image.get_width():
		return SPRITE_Y_OFFSET
	var width := mini(CELL, image.get_width() - left)
	var height := mini(CELL, image.get_height())
	if width <= 0 or height <= 0:
		return SPRITE_Y_OFFSET
	var frame_image := image.get_region(Rect2i(left, 0, width, height))
	var used := frame_image.get_used_rect()
	if not used.has_area():
		return SPRITE_Y_OFFSET
	var bottom_px := float(used.end.y)
	var offset := 64.0 - (bottom_px - float(CELL) * 0.5) * display_scale
	return clampf(offset, -28.0, 22.0) if is_equal_approx(display_scale, SPRITE_SCALE) else offset


## Cache by (texture, frame), not by texture alone. At 5-6fps this
## performs a pixel scan only on the first visit to each animation cell.
func _apply_grounding(tex: Texture2D, frame_index: int) -> void:
	if _sprite == null or tex == null:
		return
	var key := "%d:%d:%f" % [tex.get_instance_id(), frame_index, _sprite.scale.y]
	if not _ground_offsets.has(key):
		_ground_offsets[key] = grounding_offset_for_frame(tex.get_image(), frame_index, _sprite.scale.y)
	_neutral_sprite_y = float(_ground_offsets[key])
	_sprite.position.y = _neutral_sprite_y


## Mortal sword body language adds a brief torso recoil and rotation
## instead of leaving the detailed painted character frozen while an
## unrelated steel stick spins over it. Only Form 1 uses this fallback;
## later approved swing sprite sheets remain authoritative.
static func mortal_attack_pose(index: int, fraction: float) -> Vector2:
	var p := clampf(fraction, 0.0, 1.0)
	var lean := 0.0
	if p < 0.19:
		lean = lerpf(0.0, -0.055, p / 0.19)
	elif p < 0.67:
		lean = lerpf(-0.055, 0.065, (p - 0.19) / 0.48)
	else:
		lean = lerpf(0.065, 0.0, (p - 0.67) / 0.33)
	if index == 2:
		lean = -lean
	return Vector2(lean, sin(PI * p) * 3.0)


## Advance animation. Call from the player's _physics_process with the
## current facing vector and whether the player is actually moving.
func tick(delta: float, facing: Vector2, moving: bool) -> void:
	refresh()
	if not has_sprites():
		return
	# Form 1 holds the FIRST WALK frame for the entire committed strike.
	# Player._physics_process owns the ONE grounded body pose and blade rig:
	# the old tick() pose fought that transformation each physics frame.
	if _form == 1 and _sprite != null:
		var actor: Node = get_parent().get_parent() if get_parent() != null else null
		var rig: Node = actor.get_node_or_null("ScytheRig") if actor != null else null
		var attack_state: int = int(rig.get("state")) if rig != null else 0
		if attack_state != 0 or (rig != null and rig.has_method("is_charging") and rig.is_charging()):
			if not _attack_clips.is_empty():
				return # Player applies the coherent attack frame below tick().
			var was_idle := _idle_on
			_idle_on = false
			if _frame != 0 or was_idle:
				_frame = 0
				_draw_frame()
			return
	if _approved_attack_active:
		_reset_mortal_sword_pose()
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
	# Standing still with an idle sheet for this direction: play the
	# idle loop instead of freezing on walk frame 0.
	var want_idle := (not moving) and _idle.has(_strip_dir)
	if want_idle != _idle_on:
		_idle_on = want_idle
		_frame = 0
		_idle_t = 0.0
		_walk_t = 0.0
		_draw_frame()
	if moving:
		_walk_t += delta
		var f := int(_walk_t * WALK_FPS)
		if f != _frame:
			_frame = f
			_draw_frame()
	elif _idle_on:
		_idle_t += delta
		var f2 := int(_idle_t * IDLE_FPS)
		if f2 != _frame:
			_frame = f2
			_draw_frame()
	elif _frame != 0:
		_frame = 0
		_walk_t = 0.0
		_draw_frame()


## Form 1 does not have approved four-direction sword-attack sprite
## sheets yet. This *body pose* bridges the gap without showing an idle,
## frozen Mollosar beside a swinging detached sword. It is deliberately
## small: foot-anchored anticipation, committed strike, and recovery.
## Once Muse supplies the attack strips, the actual painted poses replace it.
static func mortal_sword_pose(swing_index: int, fraction: float) -> Dictionary:
	var p := clampf(fraction, 0.0, 1.0)
	var lean := 0.0
	var squash := 1.0
	var shoulder := 0.0
	if swing_index == 3:
		# Wind up in place while the player holds the existing SWORD button.
		var wound := p * p * (3.0 - 2.0 * p)
		return {"lean": -0.105 * wound, "scale": 1.0 - 0.036 * wound,
			"shoulder": -6.0 * wound}
	if swing_index == 4:
		# Resume EXACTLY from the fully wound pose. Re-entering the normal
		# attack's anticipation at release caused a visible backward snap.
		# This is one heavy forward cut followed by grounded recovery.
		if p < 0.67:
			var u := p / 0.67
			var drive := u * u * (3.0 - 2.0 * u)
			return {"lean": lerpf(-0.105, 0.121, drive),
				"scale": lerpf(0.964, 1.047, drive),
				"shoulder": lerpf(-6.0, 9.5, drive)}
		var u := (p - 0.67) / 0.33
		var settle := 1.0 - u * u * (3.0 - 2.0 * u)
		return {"lean": 0.121 * settle,
			"scale": 1.0 + 0.047 * settle,
			"shoulder": 9.5 * settle}
	if p < 0.19:
		var u := p / 0.19
		var ease := u * u * (3.0 - 2.0 * u)
		lean = -0.083 * ease
		squash = 1.0 - 0.033 * ease
		shoulder = -4.0 * ease
	elif p < 0.67:
		var u := (p - 0.19) / 0.48
		var snap := 1.0 - pow(1.0 - u, 2.25)
		lean = lerpf(-0.083, 0.102, snap)
		squash = 0.967 + 0.078 * sin(PI * u)
		shoulder = lerpf(-4.0, 8.0, snap)
	else:
		var u := (p - 0.67) / 0.33
		var settle := 1.0 - u * u * (3.0 - 2.0 * u)
		lean = 0.102 * settle
		squash = 1.0 + 0.012 * settle
		shoulder = 8.0 * settle
	# Combo 2 reverses the body twist as well as the blade's attack arc.
	var sign_value := -1.0 if swing_index == 2 else 1.0
	return {
		"lean": lean * sign_value,
		"scale": squash,
		"shoulder": shoulder * sign_value,
	}


## Hand-authored from the approved Muse walk sheets (384px cells).
## Anchor = tip of gold crossguard/right wrist; tip = steel point.
## This is PRESENTATION ONLY. Rig/hitbox remain governed by ScytheRig.
static func mortal_blade_geometry(direction: String) -> Dictionary:
	match direction:
		"down":
			return {"guard": Vector2(138.0, 229.0),
				"tip": Vector2(64.0, 342.0), "sign": 1.0, "fill": -1.0}
		"left":
			return {"guard": Vector2(144.0, 220.0),
				"tip": Vector2(51.0, 327.0), "sign": 1.0, "fill": -1.0}
		"right":
			return {"guard": Vector2(199.0, 228.0),
				"tip": Vector2(302.0, 347.0), "sign": -1.0, "fill": 1.0}
		"up":
			return {"guard": Vector2(291.0, 197.0),
				"tip": Vector2(326.0, 285.0), "sign": -1.0, "fill": 1.0}
	return {}


static func mortal_blade_angle(direction: String, index: int, fraction: float) -> float:
	var geometry := mortal_blade_geometry(direction)
	if geometry.is_empty():
		return 0.0
	if index == 3:
		return float(geometry["sign"]) * lerpf(0.0, -1.22, clampf(fraction, 0.0, 1.0))
	if index == 4:
		# The charge ends at -1.22 radians, so the blade MUST start there.
		# No second backward pull, separate weapon mesh, or resting-blade snap.
		var p := clampf(fraction, 0.0, 1.0)
		var angle := -1.22
		if p < 0.67:
			var u := p / 0.67
			var drive := u * u * (3.0 - 2.0 * u)
			angle = lerpf(-1.22, 1.08, drive)
		else:
			var u := (p - 0.67) / 0.33
			var settle := u * u * (3.0 - 2.0 * u)
			angle = lerpf(1.08, 0.0, settle)
		return float(geometry["sign"]) * angle
	return float(geometry["sign"]) * SwordArc.sword_stroke_angle(index, fraction)


func uses_painted_mortal_blade() -> bool:
	return _form == 1 and has_sprites() and _mortal_blade_sprite != null and _sprite.texture != null


func _build_mortal_blade_rig() -> void:
	if _mortal_blade_sprite != null:
		return
	_mortal_rest_material = ShaderMaterial.new()
	_mortal_rest_material.shader = RestingBladeShader
	_mortal_swing_material = ShaderMaterial.new()
	_mortal_swing_material.shader = SwingBladeShader
	_mortal_blade_sprite = Sprite2D.new()
	_mortal_blade_sprite.name = "PaintedMortalBlade"
	_mortal_blade_sprite.centered = true
	_mortal_blade_sprite.region_enabled = true
	_mortal_blade_sprite.z_index = 1
	_mortal_blade_sprite.material = _mortal_swing_material
	_mortal_blade_sprite.visible = false
	add_child(_mortal_blade_sprite)


func _animate_mortal_blade(index: int, fraction: float) -> void:
	if _mortal_blade_sprite == null or _sprite == null or _sprite.texture == null:
		return
	var geometry := mortal_blade_geometry(_strip_dir)
	if geometry.is_empty():
		_release_mortal_blade()
		return
	# Keep the ink/texture of the currently displayed frame. Attack always
	# pins the first walking frame before invoking this method.
	_mortal_blade_sprite.texture = _sprite.texture
	_mortal_blade_sprite.region_rect = _sprite.region_rect
	_mortal_blade_sprite.flip_h = _sprite.flip_h
	_mortal_blade_sprite.position = _sprite.position
	_mortal_blade_sprite.rotation = _sprite.rotation
	_mortal_blade_sprite.scale = _sprite.scale
	var left_px := float(_sprite.region_rect.position.x)
	var guard: Vector2 = geometry["guard"]
	var tip: Vector2 = geometry["tip"]
	for mat in [_mortal_rest_material, _mortal_swing_material]:
		mat.set_shader_parameter("guard_px", guard)
		mat.set_shader_parameter("tip_px", tip)
		mat.set_shader_parameter("frame_left_px", left_px)
	_mortal_rest_material.set_shader_parameter("fill_side", float(geometry["fill"]))
	_mortal_rest_material.set_shader_parameter("cut_amount", 1.0)
	_mortal_swing_material.set_shader_parameter("opacity", 1.0)
	_mortal_swing_material.set_shader_parameter(
		"swing_angle_radians", mortal_blade_angle(_strip_dir, index, fraction))
	_sprite.material = _mortal_rest_material
	_mortal_blade_sprite.visible = true


func _release_mortal_blade() -> void:
	if _sprite != null:
		_sprite.material = null
	if _mortal_blade_sprite != null:
		_mortal_blade_sprite.visible = false
	if _mortal_rest_material != null:
		_mortal_rest_material.set_shader_parameter("cut_amount", 0.0)
	if _mortal_swing_material != null:
		_mortal_swing_material.set_shader_parameter("opacity", 0.0)


## Unlike the shader fallback, approved painted strips include sword,
## armor and smear on the SAME transparent frame. No detached weapon mesh.
func _try_approved_attack(swing_index: int, fraction: float, facing: Vector2) -> bool:
	if _attack_clips.is_empty():
		return false
	if not _approved_attack_active or _approved_action != swing_index:
		_approved_action = swing_index
		_approved_facing = facing if facing.length_squared() > 0.001 else Vector2.DOWN
	var sample: Dictionary = Form1AttackClips.sample(_attack_clips, swing_index, fraction, _approved_facing)
	if sample.is_empty():
		return false
	_release_mortal_blade()
	_sprite.material = null
	_sprite.texture = sample["texture"]
	_sprite.flip_h = false
	_sprite.region_enabled = true
	_sprite.region_rect = Rect2(int(sample["frame"]) * CELL, 0, CELL, CELL)
	_sprite.rotation = 0.0
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_sprite.position = Vector2(0.0,
		Form1AttackClips.grounded_sprite_y(sample["pivot"], SPRITE_SCALE))
	_approved_attack_active = true
	_mortal_pose_active = false
	return true


func set_mortal_sword_pose(swing_index: int, fraction: float, facing: Vector2) -> void:
	if _sprite == null:
		return
	if _form != 1 or not has_sprites() or swing_index == 0:
		_reset_mortal_sword_pose()
		return
	if _try_approved_attack(swing_index, fraction, facing):
		return
	if swing_index == 5:
		_reset_mortal_sword_pose()
		return
	var pose: Dictionary = mortal_sword_pose(swing_index, fraction)
	var side := -1.0 if facing.x < -0.10 else 1.0
	var lean: float = float(pose["lean"]) * side
	var scale_ratio: float = float(pose["scale"])
	_sprite.rotation = lean
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE) * scale_ratio
	# Body imagery is a 384px centered cell, with each painted frame
	# grounded at y=64. Compensate pivot displacement so a shoulder turn
	# NEVER drags feet across the floor while the hitbox stays still.
	var ground_pivot := Vector2(0.0, 64.0 - _neutral_sprite_y)
	var correction := ground_pivot - ground_pivot.rotated(lean) * scale_ratio
	var shoulder: float = float(pose["shoulder"])
	_sprite.position = Vector2(0.0, _neutral_sprite_y) + correction + Vector2(
		shoulder * 0.13, -absf(shoulder) * 0.18)
	_mortal_pose_active = true
	_animate_mortal_blade(swing_index, fraction)


func _reset_mortal_sword_pose() -> void:
	_release_mortal_blade()
	if _approved_attack_active:
		_approved_attack_active = false
		_approved_action = 0
		_frame = 0
		_walk_t = 0.0
		_idle_t = 0.0
		_idle_on = false
		# Returning to the actual walk source is essential; otherwise the
		# last attack-strip cell sticks on the next idle frame.
		if _sprite != null:
			_draw_frame()
		return
	if not _mortal_pose_active or _sprite == null:
		return
	_sprite.position = Vector2(0.0, _neutral_sprite_y)
	_sprite.rotation = 0.0
	_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_mortal_pose_active = false


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


## Soft contact shadow anchors the painted character to the collision ground.
## It is behind the Sprite2D child and never becomes a collision shape.
func _draw() -> void:
	if not has_sprites():
		return
	draw_set_transform(Vector2(0, 64), 0.0, Vector2(1.0, 0.24))
	draw_circle(Vector2.ZERO, 42.0, Color(0.01, 0.015, 0.02, 0.34))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
