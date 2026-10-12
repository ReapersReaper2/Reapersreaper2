extends Node2D
## In-world trail marker: a physical-looking sign, never a UI overlay.
@export var destination: String = "TRAIL"
@export var direction: String = "→"

const POST := Color(0.17, 0.135, 0.12)
const BOARD := Color(0.31, 0.245, 0.18)
const EDGE := Color(0.58, 0.46, 0.31)

func _ready() -> void:
	z_index = clampi(int(round(position.y)), -1800, 1800)
	var lettering := Label.new()
	lettering.name = "Lettering"
	lettering.text = direction + "  " + destination
	lettering.position = Vector2(-102, -79)
	lettering.size = Vector2(204, 26)
	lettering.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lettering.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lettering.add_theme_font_size_override("font_size", 16)
	lettering.add_theme_color_override("font_color", Color(0.93, 0.82, 0.62))
	add_child(lettering)

func _draw() -> void:
	draw_line(Vector2(0, 23), Vector2(0, -57), POST, 10.0, true)
	draw_rect(Rect2(-108, -84, 216, 43), POST)
	draw_rect(Rect2(-103, -79, 206, 33), BOARD)
	draw_line(Vector2(-101, -77), Vector2(101, -77), EDGE, 2.0, true)
	draw_circle(Vector2(-95, -62), 2.5, EDGE)
	draw_circle(Vector2(95, -62), 2.5, EDGE)
