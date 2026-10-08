extends Area2D
## NoFlyZone — an area where flight is forbidden. The player is forced
## to land on entry (e.g. interiors, dense canopy).
##
## Setup: Area2D with a CollisionShape2D child; collision_layer = 0,
## collision_mask = 1 (detect the player body).
##
## NOTE: intentionally no class_name (project convention).

signal forced_landing(zone)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	if not is_inside_tree():
		return
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	if body.get("flying") == true and body.has_method("land"):
		body.land()
		forced_landing.emit(self)
		print("[FLIGHT] forced landing in no-fly zone")
