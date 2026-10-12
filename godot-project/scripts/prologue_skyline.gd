extends Sprite2D
## Keep the established painted skyline behind the new walkable bridge deck.
## Loading at runtime avoids hard-wiring an LFS pointer into the .tscn.
const CriticalSpriteLoader := preload("res://scripts/critical_sprite_loader.gd")

func _ready() -> void:
	texture = CriticalSpriteLoader.load_texture(
		"res://assets/backgrounds/p1_bellhollow_bridge_1280x720.png"
	)
	if texture == null:
		push_warning("[Bellhollow] background art unavailable; bridge deck remains playable")
