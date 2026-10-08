extends CanvasLayer
## DepowerIndicator — small status text shown while Mollosar is
## depowered (Ch13-14) or partially repowered (U2-U3).
##
## Created and owned by the player (player.gd _ready). Polls
## Depower.state() each frame; hidden when state is NONE.
## Follows the dialogue_box.gd CanvasLayer pattern.

const Depower = preload("res://scripts/depower.gd")

var _label: Label = null
var _game_state = null


func _ready() -> void:
	if _label != null:
		return  # _ready ran twice (cold-tree explicit call + tree)
	layer = 10
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	_label.visible = false
	add_child(_label)


func _process(_delta: float) -> void:
	if _game_state == null:
		_game_state = get_node_or_null("/root/GameState")
		if _game_state == null:
			return
	var text: String = Depower.state_label(_game_state)
	if text.is_empty():
		_label.visible = false
		return
	_label.visible = true
	if _label.text != text:
		_label.text = text
	# Full depower reads red; partial (weakened) reads amber.
	if Depower.is_partial(_game_state):
		_label.add_theme_color_override("font_color", Color(1.0, 0.65, 0.25))
	else:
		_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
