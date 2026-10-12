extends Node2D
## Small explorable sanctuary interior, deliberately constructed from
## separately placed architectural/furniture shapes rather than a backdrop.
const FLOOR := Color(0.17, 0.16, 0.145)
const PLANK := Color(0.22, 0.20, 0.17)
const WALL := Color(0.26, 0.27, 0.25)
const BRICK := Color(0.35, 0.35, 0.32)
const WOOD := Color(0.31, 0.23, 0.19)
const GOLD := Color(0.72, 0.49, 0.25)

func _draw() -> void:
	draw_rect(Rect2(-640, -360, 1280, 720), Color(0.055, 0.064, 0.065))
	draw_rect(Rect2(-520, -285, 1040, 560), FLOOR)
	for y in range(-265, 275, 35):
		draw_line(Vector2(-505, y), Vector2(505, y), PLANK, 3.0)
	for x in range(-490, 510, 76):
		draw_line(Vector2(x, -270), Vector2(x, 265), PLANK.darkened(0.2), 1.5)
	draw_rect(Rect2(-540, -310, 1080, 45), WALL)
	draw_rect(Rect2(-540, -310, 35, 615), BRICK)
	draw_rect(Rect2(505, -310, 35, 615), BRICK)
	draw_rect(Rect2(-540, 270, 480, 35), BRICK)
	draw_rect(Rect2(60, 270, 480, 35), BRICK)
	# Open door at south wall.
	draw_rect(Rect2(-60, 270, 120, 18), GOLD.darkened(0.4))
	draw_rect(Rect2(-340, -200, 185, 95), WOOD)
	draw_rect(Rect2(-335, -198, 175, 20), WOOD.lightened(0.18))
	draw_rect(Rect2(235, -205, 160, 55), WOOD)
	draw_rect(Rect2(253, -232, 30, 30), BRICK)
	draw_circle(Vector2(350, -186), 14, GOLD)
	draw_rect(Rect2(-20, -190, 70, 70), BRICK)
	draw_circle(Vector2(15, -155), 18, GOLD.darkened(0.32))
