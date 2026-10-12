extends Node2D
## ReserveGuide owns the shared Interact action for ambient residents:
## selecting the nearest aware creature means one press = one response.
## Observations go into the creature journal; this never captures creatures.

const OBSERVED_KEY := "reserve_observed"
const HIGHLIGHT_SECONDS := 3.2
const GOLD := Color(0.92, 0.81, 0.62)
const SOFT := Color(0.72, 0.80, 0.78)

var _player: Node2D = null
var _creatures: Node = null
var _selected: Sprite2D = null
var _status: Label = null
var _objective: Label = null
var _highlight_time := 0.0
var _highlight_text := ""
var _game_state: Node = null

func _ready() -> void:
	_player = get_parent().get_node_or_null("Player") as Node2D
	_creatures = get_parent().get_node_or_null("Creatures")
	_game_state = get_node_or_null("/root/GameState")
	if _creatures == null or _player == null:
		push_warning("[ReserveGuide] Player or Creatures missing")
		return
	for child in _creatures.get_children():
		if not _is_resident(child):
			continue
		if not child.interacted.is_connected(_on_interacted):
			child.interacted.connect(_on_interacted)
		if not child.noticed.is_connected(_on_noticed):
			child.noticed.connect(_on_noticed)
	_build_hud()
	_update_hud()

func _process(delta: float) -> void:
	if _creatures == null or _player == null:
		return
	if _highlight_time > 0.0:
		_highlight_time = maxf(0.0, _highlight_time - delta)
	_select_nearest()
	_update_hud()

func _select_nearest() -> void:
	var closest: Sprite2D = null
	var best_distance := INF
	for child in _creatures.get_children():
		if not _is_resident(child):
			continue
		var creature := child as Sprite2D
		var eligible: bool = creature.is_player_in_range()
		var distance: float = creature.global_position.distance_squared_to(_player.global_position)
		if eligible and (distance < best_distance or (is_equal_approx(distance, best_distance) and
				(closest == null or str(creature.name) < str(closest.name)))):
			closest = creature
			best_distance = distance
	for child in _creatures.get_children():
		if _is_resident(child):
			child.set_selected(child == closest)
	_selected = closest

func _unhandled_input(event: InputEvent) -> void:
	if _selected == null or not event.is_action_pressed("interact"):
		return
	if get_tree().paused:
		return
	var box = get_tree().get_first_node_in_group("dialogue_box")
	if box != null and box.visible:
		return
	var cs = get_tree().get_first_node_in_group("cutscene")
	if cs != null and cs.has_method("is_playing") and cs.is_playing():
		return
	get_viewport().set_input_as_handled()
	_selected.trigger_interaction()

func _on_noticed(creature: Node2D) -> void:
	_highlight_text = "%s NOTICED YOU" % String(creature.name).to_upper()
	_highlight_time = 1.7

func _on_interacted(creature: Node2D) -> void:
	# "Seen" is already a separate ledger from captured / bonded creatures.
	var ident := String(creature.name).to_snake_case()
	if _game_state != null:
		if _game_state.has_method("mark_seen"):
			_game_state.mark_seen(ident)
		var state: Variant = _game_state.get("state")
		if state is Dictionary:
			var observed: Array = state.get(OBSERVED_KEY, [])
			if not observed.has(ident):
				observed.append(ident)
			state[OBSERVED_KEY] = observed
	_highlight_text = "%s OBSERVED  ·  %d/%d RESIDENTS" % [
		String(creature.name).to_upper(), _observed_count(), _resident_count()]
	_highlight_time = HIGHLIGHT_SECONDS

func _is_resident(node: Node) -> bool:
	return node is Sprite2D and node.has_method("is_player_in_range") and node.has_method("trigger_interaction")

func _resident_count() -> int:
	if _creatures == null:
		return 0
	var n := 0
	for child in _creatures.get_children():
		if _is_resident(child):
			n += 1
	return n

func _observed_count() -> int:
	if _game_state == null:
		return 0
	var state: Variant = _game_state.get("state")
	if not (state is Dictionary):
		return 0
	var observed: Array = state.get(OBSERVED_KEY, [])
	var n := 0
	for child in _creatures.get_children():
		if _is_resident(child) and observed.has(String(child.name).to_snake_case()):
			n += 1
	return n

func _update_hud() -> void:
	if _objective == null:
		return
	_objective.text = "RESERVE   Observe residents  ·  %d/%d" % [_observed_count(), _resident_count()]
	if _status == null:
		return
	if _highlight_time > 0.0:
		_status.text = _highlight_text
		_status.add_theme_color_override("font_color", GOLD)
	elif _selected != null:
		_status.text = "E / INTERACT   " + String(_selected.name).to_upper()
		_status.add_theme_color_override("font_color", GOLD)
	else:
		_status.text = "Explore the paths to find living creatures"
		_status.add_theme_color_override("font_color", SOFT)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ReserveGuideHUD"
	layer.layer = 12
	add_child(layer)
	var panel := ColorRect.new()
	panel.color = Color(0.045, 0.065, 0.075, 0.80)
	panel.position = Vector2(19, 16)
	panel.size = Vector2(540, 79)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(panel)
	_objective = Label.new()
	_objective.position = Vector2(36, 24)
	_objective.size = Vector2(508, 29)
	_objective.add_theme_font_size_override("font_size", 20)
	_objective.add_theme_color_override("font_color", GOLD)
	_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_objective)
	_status = Label.new()
	_status.position = Vector2(36, 57)
	_status.size = Vector2(510, 27)
	_status.add_theme_font_size_override("font_size", 17)
	_status.add_theme_color_override("font_color", SOFT)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_status)
