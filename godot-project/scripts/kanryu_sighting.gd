extends Node2D
## Kanryu sighting beats V1-V4 — WIRING ONLY, no story text.
##
## Four non-interactable seated-silhouette beats, one per room, spawned
## by room.gd when room_id is in KANRYU_BEATS (g2, s2, f3, gd6). Greybox dark
## silhouette placeholder visuals, motionless and distant.
##
## Story-bot rules enforced by construction:
## - NO name surfaced (no label, no name string anywhere player-facing).
## - NO inspect text, NO interact prompt (no Area2D, no dialogue hookup).
## - NO Journal entry (this script never touches journal APIs).
## - NO dialogue EXCEPT the one canon V1 Luna line: the story bot locked it
##   canon on 2026-10-05 (LUNA "...Did you see that?", MOLLOSAR "See what?"),
##   played verbatim through the room's dialogue box once, when the V1 figure
##   starts its approach fade ("gone when you blink"). V2-V4 stay SILENT.
## - NO approach: when the player crosses the mid-distance approach line
##   between the spawn path and the figure, the silhouette fades to alpha 0
##   and is removed (V3's "smoke tears him first" reads as the fade itself).
## - One-shot per playthrough: after the fade, flag kanryu_sight_done_<room>
##   is set and the beat never respawns.
## - CAP: registry holds exactly these four rooms. Nothing else may attach.
##
## NOTE: intentionally no class_name (project convention).

const FADE_SECONDS := 1.2
const FLAG_PREFIX := "kanryu_sight_done_"

## Beat registry: room_id -> config. Cap: these four rooms only.
## approach_line/approach_dir describe the mid-distance approach line between
## the player spawn path and the figure; crossing toward the figure starts
## the fade. (axis "y": fade when (player.y - line) * dir > 0, same for "x".)
const KANRYU_BEATS := {
	"g2": {
		"pos": Vector2(330, -460), "figure_scale": 1.0,
		"approach_axis": "y", "approach_line": -230.0, "approach_dir": -1.0,
		"set_dressing": "green_feet",  # V1: new green at his feet
	},
	"s2": {
		"pos": Vector2(0, -268), "figure_scale": 0.8,
		"approach_axis": "y", "approach_line": -80.0, "approach_dir": -1.0,
		"set_dressing": "high_root",  # V2: greybox root beam under the figure
	},
	"f3": {
		"pos": Vector2(360, -560), "figure_scale": 1.0,
		"approach_axis": "y", "approach_line": -280.0, "approach_dir": -1.0,
		"set_dressing": "smoke_veil",  # V3: faint veil; the fade reads as smoke tearing first
	},
	"gd6": {
		"pos": Vector2(860, -120), "figure_scale": 1.0,
		"approach_axis": "x", "approach_line": 480.0, "approach_dir": 1.0,
		"set_dressing": "green_ash",  # V4: green coming up through the ash
	},
}

## Canon V1 beat (story-bot locked, 2026-10-05): distant silhouette between
## the trees — gone when you blink. Played VERBATIM through the room's
## dialogue box once, when the V1 figure starts its approach fade. V2-V4
## have no line: SILENT stands. (Wiring authored no text here.)
const V1_LUNA_LINE: Array = [
	{"type": "dialogue", "character": "LUNA", "text": "...Did you see that?"},
	{"type": "dialogue", "character": "MOLLOSAR", "text": "See what?"},
]

var _room: Node2D = null
var _room_id: String = ""
var _cfg: Dictionary = {}
var _figure: Node2D = null
var _fading := false
var _fade_t := 0.0
var _v1_line_played := false


static func is_beat_room(room_id: String) -> bool:
	return KANRYU_BEATS.has(room_id)


static func beat_rooms() -> Array:
	return KANRYU_BEATS.keys()


## Attach the beat to a room node. Returns the sighting node, or null when
## the room is not a beat room or the beat was already spent this playthrough.
static func attach_to(room: Node2D) -> Node2D:
	var room_id := str(room.get("room_id"))
	if room_id == "" or not KANRYU_BEATS.has(room_id):
		return null
	if room.has_method("_flag") and bool(room.call("_flag", FLAG_PREFIX + room_id)):
		return null
	var node: Node2D = (load("res://scripts/kanryu_sighting.gd") as Script).new()
	node._room = room
	node._room_id = room_id
	node._cfg = KANRYU_BEATS[room_id]
	room.add_child(node)
	return node


func _ready() -> void:
	name = "Sighting"
	position = _cfg.get("pos", Vector2.ZERO)
	_build_visuals()
	print("[SIGHTING] beat staged for room ", _room_id)


func _build_visuals() -> void:
	_figure = Node2D.new()
	_figure.name = "DistantFigure"  # internal only; no name is shown to players
	_figure.scale = Vector2.ONE * float(_cfg.get("figure_scale", 1.0))
	add_child(_figure)
	_add_seated_silhouette()
	_add_set_dressing()


## Dark seated silhouette, greybox style. Back-of-figure profile, motionless.
func _add_seated_silhouette() -> void:
	var ink := Color(0.05, 0.05, 0.07, 1.0)
	var head := Polygon2D.new()
	head.color = ink
	head.polygon = PackedVector2Array([
		Vector2(9, -44), Vector2(6.4, -37.6), Vector2(0, -35), Vector2(-6.4, -37.6),
		Vector2(-9, -44), Vector2(-6.4, -50.4), Vector2(0, -53), Vector2(6.4, -50.4),
	])
	_figure.add_child(head)
	var torso := Polygon2D.new()
	torso.color = ink
	torso.polygon = PackedVector2Array([
		Vector2(-9, -36), Vector2(9, -36), Vector2(7, -8), Vector2(-7, -8),
	])
	_figure.add_child(torso)
	var drape := Polygon2D.new()  # back drape / cloak fold, back to the path
	drape.color = ink
	drape.polygon = PackedVector2Array([
		Vector2(-9, -36), Vector2(-7, -8), Vector2(-16, -8), Vector2(-16, -28),
	])
	_figure.add_child(drape)
	var legs := Polygon2D.new()  # seated legs folded forward
	legs.color = ink
	legs.polygon = PackedVector2Array([
		Vector2(7, -16), Vector2(34, -16), Vector2(34, -8), Vector2(7, -8),
	])
	_figure.add_child(legs)


## Greybox set dressing only — no story text, no labels.
func _add_set_dressing() -> void:
	match str(_cfg.get("set_dressing", "")):
		"green_feet", "green_ash":
			var green := Polygon2D.new()
			green.color = Color(0.16, 0.42, 0.18, 1.0)
			green.polygon = PackedVector2Array([
				Vector2(-26, 2), Vector2(30, 2), Vector2(22, -8), Vector2(10, -12),
				Vector2(-4, -9), Vector2(-16, -11),
			])
			add_child(green)
		"high_root":
			var root := Polygon2D.new()  # greybox high root beam under the figure
			root.color = Color(0.28, 0.20, 0.13, 1.0)
			root.polygon = PackedVector2Array([
				Vector2(-230, 8), Vector2(230, 8), Vector2(230, 0), Vector2(-230, 0),
			])
			add_child(root)
		"smoke_veil":
			var veil := Polygon2D.new()  # faint veil; fade reads as smoke tearing first
			veil.color = Color(0.45, 0.44, 0.44, 0.25)
			veil.polygon = PackedVector2Array([
				Vector2(-30, -60), Vector2(40, -60), Vector2(34, 4), Vector2(-24, 4),
			])
			_figure.add_child(veil)


func _process(delta: float) -> void:
	if _fading:
		_advance_fade(delta)
		return
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null and _approach_crossed(player.position):
		_begin_fade()


## True when the player crossed the mid-distance approach line toward the figure.
func _approach_crossed(p: Vector2) -> bool:
	var axis := str(_cfg.get("approach_axis", "y"))
	var line := float(_cfg.get("approach_line", 0.0))
	var dir := float(_cfg.get("approach_dir", 1.0))
	var v: float = p.y if axis == "y" else p.x
	return (v - line) * dir > 0.0


func is_fading() -> bool:
	return _fading


func figure_alpha() -> float:
	if _figure == null:
		return 0.0
	return _figure.modulate.a


func _begin_fade() -> void:
	if _fading:
		return
	_fading = true
	_fade_t = 0.0
	_play_v1_line()  # V1 only; V2-V4 stay silent
	print("[SIGHTING] approach line crossed in room ", _room_id, " — fading beat")


## V1 canon Luna line: fired once, when the g2 figure starts to fade
## ("gone when you blink"). Guarded to the room's dialogue box; a hard no-op
## for V2-V4 and whenever the room exposes no dialogue box (e.g. headless).
func _play_v1_line() -> void:
	if _room_id != "g2" or _v1_line_played:
		return
	_v1_line_played = true
	var box: Variant = null
	if _room != null and is_instance_valid(_room):
		box = _room.get("dialogue_box")
	if box != null and is_instance_valid(box) and box.has_method("start_dialogue"):
		box.start_dialogue(V1_LUNA_LINE)
		print("[SIGHTING] V1 canon Luna line played")


func _advance_fade(delta: float) -> void:
	_fade_t += delta
	var t: float = clampf(_fade_t / FADE_SECONDS, 0.0, 1.0)
	_figure.modulate.a = 1.0 - t
	if t >= 1.0:
		_spend()


func _spend() -> void:
	_figure.visible = false
	if _room != null and is_instance_valid(_room) and _room.has_method("_set_flag"):
		_room.call("_set_flag", FLAG_PREFIX + _room_id)
	print("[SIGHTING] beat spent in room ", _room_id)
	queue_free()
