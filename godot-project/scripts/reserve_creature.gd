extends Sprite2D
## ReserveCreature — living ambient resident, with proximity awareness.
## Keep this script canonical. No capture or lore is granted here:
## future Lullmother-bonding systems listen to the interacted signal.

const SpriteLoader := preload("res://scripts/critical_sprite_loader.gd")
const AmbientMotion := preload("res://scripts/reserve_creature_motion.gd")
const ContactShadow := preload("res://scripts/reserve_creature_shadow.gd")
const ART_DIR := "res://assets/creatures/"
## Three source paintings carry white paper around the subject. Preserve the
## original illustrations and mask the paper only in the gameplay renderer.
## Muse can replace these with transparent 3/4-view sprites later.
const PAPER_BACKGROUND_ART := ["dragonthorn", "gloomcap", "spinehopper"]
const PAPER_CUTOUT_SHADER := """
shader_type canvas_item;
void fragment() {
    vec4 sampled = texture(TEXTURE, UV);
    float paper = min(sampled.r, min(sampled.g, sampled.b));
    float cutout = 1.0 - smoothstep(0.91, 0.995, paper);
    COLOR.a *= cutout;
}
"""
static var _paper_shader: Shader = null

@export var art_id: String = ""
## ART REVIEW: first three native masters are QA-verified CANDIDATE exports.
## This per-resident switch permits side-by-side phone comparison against the
## old source painting without changing art files, story or save data.
@export var prefer_overworld_art: bool = true
## Keeps approved on-screen proportions when a 384px overworld master
## replaces an oversized temporary painting; zero keeps scene scale.
@export var overworld_display_height: float = 0.0

## The Android HUD labels its interaction button USE; show the same
## word on creature prompts so touchscreen players never need to guess
## which action the PC-only "E" label means.
static func interaction_caption(touchscreen: bool) -> String:
	return "USE" if touchscreen else "E / INTERACT"


signal noticed(creature: Node2D)
signal interacted(creature: Node2D)

@export var bob_amp: float = 8.0
@export var bob_speed: float = 1.6
@export var awareness_radius: float = 132.0
@export var sway_degrees: float = 2.5
## Presentation-only motion; no pathfinding, attacks, or capture side effects.
@export_enum("Rooted", "Drift", "Hop", "Prowl") var motion_style: int = 0

var _base_position := Vector2.ZERO
var _base_scale := Vector2.ONE
var _base_rotation: float = 0.0
var _phase: float = 0.0
var _reaction_time: float = 0.0
var _in_range: bool = false
var _selected: bool = false
var _elapsed: float = 0.0
var _motion_seed: float = 0.0
var _attention: float = 0.0
var _startle_time: float = 0.0
var _ground_offset: float = 45.0
var _shadow: Node2D = null
var _sensor: Area2D = null
var _prompt: Label = null
var _using_overworld_art: bool = false
var _overworld_visible_height: float = 0.0
var _overworld_visible_width: float = 0.0

func _ready() -> void:
	# Approved native 384px overworld art takes precedence when delivered.
	# The existing painted battle-art PNG remains the fallback until then.
	var name_id := art_id if not art_id.is_empty() else String(name).to_snake_case()
	if texture == null:
		var overworld_path := ART_DIR + name_id + "_overworld.png"
		if prefer_overworld_art and SpriteLoader.has_source(overworld_path):
			var overworld := SpriteLoader.load_texture(overworld_path)
			if overworld != null:
				_set_overworld_texture(overworld)
		if texture == null:
			var fallback_path := ART_DIR + name_id + ".png"
			texture = SpriteLoader.load_texture(fallback_path)
			if texture == null:
				push_error("[ReserveCreature] MISSING ART: " + overworld_path + " and " + fallback_path)
	if PAPER_BACKGROUND_ART.has(name_id) and not _using_overworld_art:
		_apply_paper_cutout_shader()
	_base_position = position
	_base_scale = scale
	_base_rotation = rotation
	# Offset motion by stable creature identity (not random restart flicker).
	_phase = float(abs(hash(String(name))) % 628) * 0.01
	_motion_seed = _phase
	if texture != null:
		# Native transparent cutouts have their visible feet aligned to the
		# actual encounter origin. Only the legacy centered battle painting
		# needs an estimated ground offset.
		_ground_offset = 0.0 if _using_overworld_art else clampf(
			texture.get_height() * absf(_base_scale.y) * 0.32, 24.0, 100.0)
	if is_inside_tree() and get_parent() != null:
		_create_awareness()
		_create_contact_shadow()


## Alpha is an essential part of the native Muse overworld masters.
## Each 384px canvas contains a smaller actual creature, and the source
## framing leaves the feet around y=353. Measure the visible silhouette,
## not the empty transparent border, when aligning the sprite to the ground.
##
## Return source-pixel coordinates so the method can be headless tested
## and other sprites can reuse the exact convention.
static func overworld_layout(art: Texture2D, target_height: float) -> Dictionary:
	if art == null or art.get_height() <= 0:
		return {}
	var image := art.get_image()
	if image == null or image.is_empty():
		return {}
	var visible: Rect2i = image.get_used_rect()
	if visible.size.x <= 0 or visible.size.y <= 0:
		return {}
	return {
		"visible": visible,
		"factor": target_height / float(visible.size.y) if target_height > 0.0 else 0.0,
		"offset_y": float(art.get_height()) * 0.5 - float(visible.end.y),
	}


func _set_overworld_texture(art: Texture2D) -> void:
	if art == null:
		return
	var layout: Dictionary = overworld_layout(art, overworld_display_height)
	if layout.is_empty():
		push_warning("[ReserveCreature] transparent overworld image has no visible silhouette")
		return
	var visible: Rect2i = layout["visible"]
	texture = art
	_using_overworld_art = true
	material = null
	centered = true
	# Keep the authored Node2D encounter position unchanged so the
	# awareness sensor, Guide waypoint and save data still target the
	# same location. Shift pixels inside Sprite2D instead.
	offset = Vector2(0.0, float(layout["offset_y"]))
	if overworld_display_height > 0.0:
		var factor: float = layout["factor"]
		scale = Vector2(-factor if scale.x < 0.0 else factor, factor)
	_overworld_visible_height = float(visible.size.y) * absf(scale.y)
	_overworld_visible_width = float(visible.size.x) * absf(scale.x)


func _apply_paper_cutout_shader() -> void:
	if _paper_shader == null:
		_paper_shader = Shader.new()
		_paper_shader.code = PAPER_CUTOUT_SHADER
	var matte := ShaderMaterial.new()
	matte.shader = _paper_shader
	material = matte


func _create_awareness() -> void:
	if _sensor != null:
		return
	_sensor = Area2D.new()
	_sensor.name = String(name) + "_Awareness"
	_sensor.collision_layer = 0
	_sensor.collision_mask = 1
	_sensor.monitoring = true
	_sensor.position = _base_position
	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = awareness_radius
	collision.shape = shape
	_sensor.add_child(collision)
	_sensor.body_entered.connect(_on_body_entered)
	_sensor.body_exited.connect(_on_body_exited)
	get_parent().add_child(_sensor)

	# A sibling avoids inheriting the sprite's 0.2x import scale.
	_prompt = Label.new()
	_prompt.name = String(name) + "_InteractPrompt"
	_prompt.text = interaction_caption(DisplayServer.is_touchscreen_available())
	_prompt.visible = false
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.size = Vector2(170, 36)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_font_size_override("font_size", 21)
	_prompt.add_theme_color_override("font_color", Color(0.89, 0.80, 0.57))
	get_parent().add_child(_prompt)
	_update_prompt_position()

func _create_contact_shadow() -> void:
	if _shadow != null:
		return
	var shadow := ContactShadow.new()
	shadow.name = "ContactShadow"
	shadow.top_level = true
	shadow.z_as_relative = false
	var visual_width := 120.0
	if _using_overworld_art:
		visual_width = _overworld_visible_width
	elif texture != null:
		visual_width = texture.get_width() * absf(_base_scale.x)
	shadow.radius_x = clampf(visual_width * 0.28, 22.0, 55.0)
	shadow.radius_y = shadow.radius_x * 0.34
	add_child(shadow)
	_shadow = shadow
	_update_contact_shadow(Vector2.ZERO, 0.0)

func _update_contact_shadow(offset: Vector2, lift: float) -> void:
	if _shadow == null or get_parent() == null:
		return
	# The shadow follows horizontal/ground steps, never a vertical hop.
	var floor_offset := Vector2(offset.x, offset.y + lift + _ground_offset)
	_shadow.global_position = get_parent().to_global(_base_position + floor_offset)
	_shadow.z_index = clampi(int(round(_shadow.global_position.y)) - 3, -1899, 1899)
	var alpha := clampf(1.0 - lift / 52.0, 0.38, 1.0)
	_shadow.modulate.a = alpha

func _update_prompt_position() -> void:
	if _prompt == null:
		return
	if _using_overworld_art:
		# The origin is the visible foot/hover contact. Keep the prompt
		# above the actual silhouette, not halfway through its head.
		_prompt.position = position + Vector2(-85.0,
			-maxf(_overworld_visible_height, 65.0) - 44.0)
		return
	var half_height := 80.0
	if texture != null:
		half_height = texture.get_height() * absf(_base_scale.y) * 0.5
	_prompt.position = position + Vector2(-85.0, -maxf(half_height, 65.0) - 55.0)

func _process(delta: float) -> void:
	_elapsed += maxf(delta, 0.0)
	_phase += delta * bob_speed
	_attention = move_toward(_attention, 1.0 if _in_range else 0.0, maxf(delta, 0.0) * 2.8)
	var motion: Dictionary = AmbientMotion.sample(motion_style, _elapsed, _motion_seed, _attention)
	var offset: Vector2 = motion["offset"]
	var lift: float = float(motion["lift"])
	var tilt: float = float(motion["tilt"])
	var breath: float = float(motion["breath"])
	# Brief, gentle acknowledgement when the player enters awareness.
	if _startle_time > 0.0:
		_startle_time = maxf(0.0, _startle_time - maxf(delta, 0.0))
		var recoil := sin(PI * (1.0 - _startle_time / 0.42))
		offset.y -= recoil * 6.0
	position = _base_position + offset + Vector2(0, sin(_phase) * bob_amp)
	rotation = _base_rotation + tilt + sin(_phase * 0.62) * deg_to_rad(sway_degrees)
	var scale_factor := 1.0 + breath + sin(_phase * 0.91) * 0.023
	scale = _base_scale * scale_factor
	_update_contact_shadow(offset, lift)
	if _sensor != null:
		_sensor.position = position
	if _prompt != null and _in_range:
		_update_prompt_position()
	if _reaction_time > 0.0:
		_reaction_time = maxf(0.0, _reaction_time - maxf(delta, 0.0))
		modulate = Color(1.15, 1.10, 1.24, 1.0)
		if _prompt != null:
			_prompt.text = "NOTICED"
	else:
		modulate = Color.WHITE
		if _prompt != null:
			_prompt.text = interaction_caption(DisplayServer.is_touchscreen_available())

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_in_range = true
	_startle_time = 0.42
	if _prompt != null:
		_prompt.visible = _selected
	_update_prompt_position()
	noticed.emit(self)

func _on_body_exited(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_in_range = false
	_selected = false
	if _prompt != null:
		_prompt.visible = false

## Centralized selection ensures only ONE nearby creature claims Interact.
## The ReserveGuide controller routes the same keyboard/touch action here.
func is_player_in_range() -> bool:
	return _in_range

func set_selected(selected: bool) -> void:
	_selected = selected and _in_range
	if _prompt != null:
		_prompt.visible = _selected

func trigger_interaction() -> bool:
	if not _in_range:
		return false
	_reaction_time = 0.72
	interacted.emit(self)
	return true

func display_name() -> String:
	return String(name).capitalize()

func _exit_tree() -> void:
	# Sensors and prompts live beside the Sprite2D, not under it.
	for extra in [_sensor, _prompt]:
		if extra != null and is_instance_valid(extra):
			extra.queue_free()
