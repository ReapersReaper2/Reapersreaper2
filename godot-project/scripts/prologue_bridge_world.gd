extends Node2D
## Bellhollow Bridge — an authored traversable stone deck over the existing
## burning city skyline. The skyline remains atmosphere; this is the ground.
## Coordinates match room_p1's existing world space and NPC placements.
@export var bounds: Rect2 = Rect2(-1280, -360, 2560, 720)

const DECK := Color(0.20, 0.20, 0.215)
const DARK := Color(0.105, 0.112, 0.135)
const STONE := Color(0.32, 0.32, 0.325)
const HIGHLIGHT := Color(0.41, 0.39, 0.37)
const ASH := Color(0.14, 0.15, 0.155)
const EMBER := Color(0.90, 0.35, 0.13)

func _ready() -> void:
	z_index = -1
	queue_redraw()

func _draw() -> void:
	var left := bounds.position.x
	var right := bounds.end.x
	# Wide isometric-feeling stone walkway, with readable deck edges.
	draw_rect(Rect2(left, -105, bounds.size.x, 401), DARK)
	draw_rect(Rect2(left, -92, bounds.size.x, 373), DECK)
	var rng := RandomNumberGenerator.new()
	rng.seed = 71011
	var row := 0
	for y in range(-90, 280, 54):
		var x := int(left) - 46 if row % 2 == 0 else int(left) - 10
		while x < right:
			var w := rng.randi_range(78, 110)
			var h := 49
			var base := DECK.lerp(STONE, rng.randf_range(0.16, 0.50))
			var tile := Rect2(Vector2(x + 3, y + 2), Vector2(w - 6, h))
			draw_rect(tile, base)
			draw_line(tile.position, tile.position + Vector2(tile.size.x, 0), HIGHLIGHT.darkened(rng.randf_range(0.1, 0.35)), 2.0)
			if rng.randf() < 0.17:
				var mid := tile.get_center()
				draw_line(mid + Vector2(-9, -20), mid + Vector2(6, -5), ASH, 2.0)
				draw_line(mid + Vector2(6, -5), mid + Vector2(1, 18), ASH, 1.5)
			if rng.randf() < 0.05:
				draw_circle(tile.get_center() + Vector2(8, -6), 2.5, EMBER.darkened(0.3))
			x += w
		row += 1
	# Guardrails mark the genuine collision boundary along the bridge.
	draw_rect(Rect2(left, -151, bounds.size.x, 53), DARK)
	draw_rect(Rect2(left, -153, bounds.size.x, 18), STONE)
	draw_line(Vector2(left, -140), Vector2(right, -140), HIGHLIGHT, 4.0)
	draw_rect(Rect2(left, 293, bounds.size.x, 50), DARK)
	draw_rect(Rect2(left, 292, bounds.size.x, 15), STONE)
	draw_line(Vector2(left, 305), Vector2(right, 305), HIGHLIGHT, 3.0)
	for x in range(int(left + 90), int(right), 192):
		_draw_post(Vector2(x, -145))
		_draw_post(Vector2(x + 92, 305))
	for x in [-820.0, -150.0, 420.0, 1030.0]:
		_draw_ruin(Vector2(x, -87))
	# Grounding markers: routes are physically forward/back across the deck.
	draw_line(Vector2(left + 32, 273), Vector2(right - 32, 273), ASH, 3.0)

func _draw_post(p: Vector2) -> void:
	draw_rect(Rect2(p + Vector2(-16, -25), Vector2(32, 56)), DARK)
	draw_rect(Rect2(p + Vector2(-20, -29), Vector2(40, 12)), STONE)
	draw_line(p + Vector2(-12, -20), p + Vector2(-12, 27), HIGHLIGHT.darkened(0.2), 3.0)

func _draw_ruin(p: Vector2) -> void:
	# Ruined barricade, visual only; never block the critical story road.
	draw_line(p + Vector2(-22, 10), p + Vector2(26, -23), ASH, 10.0)
	draw_line(p + Vector2(-18, -16), p + Vector2(30, 11), STONE.darkened(0.32), 8.0)
	draw_circle(p + Vector2(-6, 7), 9.0, ASH)
