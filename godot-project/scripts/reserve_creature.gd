extends Sprite2D
## ReserveCreature — living ambient resident, with proximity awareness.
## Keep this script canonical. No capture or lore is granted here:
## future Lullmother-bonding systems listen to the interacted signal.

const SpriteLoader := preload("res://scripts/critical_sprite_loader.gd")
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
## Keeps approved on-screen proportions when a 384px overworld master
## replaces an oversized temporary painting; zero keeps scene scale.
@export var overworld_display_height: float = 0.0

signal noticed(creature: Node2D)
signal interacted(creature: Node2D)

@export var bob_amp: float = 8.0
@export var bob_speed: float = 1.6
@export var awareness_radius: float = 132.0
@export var sway_degrees: float = 2.5

var _base_position := Vector2.ZERO
var _base_scale := Vector2.ONE
var _base_rotation: float = 0.0
var _phase: float = 0.0
var _reaction_time: float = 0.0
var _in_range: bool = false
var _selected: bool = false
var _sensor: Area2D = null
var _prompt: Label = null
var _using_overworld_art: bool = false

func _ready() -> void:
	# Approved native 384px overworld art takes precedence when delivered.
	# The existing painted battle-art PNG remains the fallback until then.
	var name_id := art_id if not art_id.is_empty() else String(name).to_snake_case()
	if texture == null:
		var overworld_path := ART_DIR + name_id + "_overworld.png"
		if SpriteLoader.has_source(overworld_path):
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
	if is_inside_tree() and get_parent() != null:
		_create_awareness()


## Production overworld sprites are transparent, not white-matted. Use a
## per-species target height so the replacement cannot shrink to 30 pixels
## because its temporary painting was imported at 1600–2240px.
func _set_overworld_texture(art: Texture2D) -> void:
	if art == null:
		return
	texture = art
	_using_overworld_art = true
	material = null
	if overworld_display_height > 0.0 and art.get_height() > 0:
		var factor := overworld_display_height / float(art.get_height())
		scale = Vector2(-factor if scale.x < 0.0 else factor,
			-factor if scale.y < 0.0 else factor)


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
	_prompt.text = "E / INTERACT"
	_prompt.visible = false
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.size = Vector2(170, 36)
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_theme_font_size_override("font_size", 21)
	_prompt.add_theme_color_override("font_color", Color(0.89, 0.80, 0.57))
	get_parent().add_child(_prompt)
	_update_prompt_position()

func _update_prompt_position() -> void:
	if _prompt == null:
		return
	var half_height := 80.0
	if texture != null:
		half_height = texture.get_height() * absf(_base_scale.y) * 0.5
	_prompt.position = position + Vector2(-85.0, -maxf(half_height, 65.0) - 55.0)

func _process(delta: float) -> void:
	_phase += delta * bob_speed
	position = _base_position + Vector2(0, sin(_phase) * bob_amp)
	rotation = _base_rotation + sin(_phase * 0.62) * deg_to_rad(sway_degrees)
	var breath := 1.0 + sin(_phase * 0.91) * 0.034
	scale = _base_scale * breath
	if _sensor != null:
		_sensor.position = position
	if _prompt != null and _in_range:
		_update_prompt_position()
	if _reaction_time > 0.0:
		_reaction_time = maxf(0.0, _reaction_time - delta)
		modulate = Color(1.15, 1.10, 1.24, 1.0)
		if _prompt != null:
			_prompt.text = "NOTICED"
	else:
		modulate = Color.WHITE
		if _prompt != null:
			_prompt.text = "E / INTERACT"

func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_in_range = true
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
