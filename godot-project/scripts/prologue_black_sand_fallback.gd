extends Node2D
## PROVISIONAL P3 dark shoreline. Displays only when the painted shore PNG
## is absent/unreadable (not a substitute for the approved source image).
## Source-agnostic deterministic geometry avoids the flat gray Android void.
const LEFT := -1280.0
const TOP := -360.0
const W := 2560.0
const H := 720.0


func _draw() -> void:
	# Opaque base over the entire scrolling room: the engine's gray clear
	# color must never show through, even around the river/shore silhouette.
	draw_rect(Rect2(LEFT, TOP, W, H), Color(0.013, 0.018, 0.032))
	for band in range(72):
		var t := float(band) / 71.0
		var shade := Color(0.012, 0.015, 0.034).lerp(Color(0.032, 0.049, 0.069), t)
		draw_rect(Rect2(LEFT, TOP + float(band) * 6.0, W, 6.0), shade)

	# Distant black shore at the top, with drifting blue light on the Styx.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-1280, -206), Vector2(-1000, -224), Vector2(-790, -196),
		Vector2(-520, -236), Vector2(-215, -208), Vector2(130, -248),
		Vector2(430, -217), Vector2(780, -236), Vector2(1060, -200),
		Vector2(1280, -217), Vector2(1280, -115), Vector2(-1280, -115)
	]), Color(0.020, 0.024, 0.039))
	draw_rect(Rect2(LEFT, -114, W, 184), Color(0.020, 0.061, 0.093))
	for stripe in range(40):
		var y := -104.0 + float(stripe) * 4.2
		var brightness := float(stripe) / 40.0
		draw_line(Vector2(LEFT, y), Vector2(LEFT + W, y),
			Color(0.048, 0.105, 0.143, 0.46 - brightness * 0.29), 2.0)
	for glimmer in range(44):
		var x := LEFT + float(glimmer * 59 % 2530)
		var y := -103.0 + float(glimmer * 37 % 158)
		draw_line(Vector2(x, y), Vector2(x + 28 + glimmer % 48, y),
			Color(0.14, 0.50, 0.64, 0.12 + float(glimmer % 5) * 0.045), 2.0)

	# The walkable black-sand bank. Keep this detailed but low-contrast so
	# actors, Luna, and shrine remain readable at native phone game scale.
	draw_colored_polygon(PackedVector2Array([
		Vector2(LEFT, 35), Vector2(-1120, 20), Vector2(-880, 44),
		Vector2(-570, 26), Vector2(-250, 50), Vector2(120, 21),
		Vector2(460, 55), Vector2(815, 31), Vector2(1150, 43),
		Vector2(1280, 27), Vector2(1280, 360), Vector2(LEFT, 360)
	]), Color(0.072, 0.076, 0.102))
	draw_rect(Rect2(LEFT, 166, W, 194), Color(0.064, 0.069, 0.085, 0.84))
	for pebble in range(180):
		var px := LEFT + float(pebble * 97 % 2550)
		var py := 65.0 + float(pebble * 73 % 286)
		var rad := 1.5 + float(pebble % 4)
		draw_circle(Vector2(px, py), rad,
			Color(0.13, 0.14, 0.17, 0.18 + float(pebble % 3) * 0.07))

	# Rare shorebound soul-lights as environmental markers, not fake sprites.
	for glow in range(17):
		var pos := Vector2(-1180 + glow * 151, -92 + (glow * 73 % 145))
		draw_circle(pos, 3.0, Color(0.37, 0.70, 0.84, 0.55))
		draw_circle(pos, 8.0, Color(0.12, 0.45, 0.61, 0.12))
