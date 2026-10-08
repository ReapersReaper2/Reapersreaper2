extends Node2D
## M0 greybox test room: 2560x1440, walls, obstacles, one trigger zone.
## Sets the player camera limits to the room bounds (region-locked camera).

@export var room_rect: Rect2 = Rect2(-1280.0, -720.0, 2560.0, 1440.0)


func _ready() -> void:
	var player: CharacterBody2D = $Player
	var cam: Camera2D = player.get_node("Camera2D") as Camera2D
	cam.limit_left = int(room_rect.position.x)
	cam.limit_top = int(room_rect.position.y)
	cam.limit_right = int(room_rect.end.x)
	cam.limit_bottom = int(room_rect.end.y)
	cam.make_current()
	($TriggerZone as Area2D).body_entered.connect(_on_trigger_zone_body_entered)
	var luna: Node2D = $Luna
	luna.set_target(player)
	print("[ROOM] test room ready, camera limits set to ", room_rect)


func _on_trigger_zone_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		print("[TRIGGER] player entered the tutorial trigger zone")
