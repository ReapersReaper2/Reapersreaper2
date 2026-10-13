extends Node2D
## ReserveGuide owns the shared Interact action for ambient residents:
## selecting the nearest aware creature means one press = one response.
## Observations go into the creature journal; this never captures creatures.

const ReactionVfx := preload("res://scripts/reserve_reaction_vfx.gd")
const CreatureData := preload("res://scripts/creature_data.gd")
const ResidentScript := preload("res://scripts/reserve_creature.gd")
const CompassArrow := preload("res://scripts/reserve_compass_arrow.gd")
const OBSERVED_KEY := "reserve_observed"
const HIGHLIGHT_SECONDS := 3.2
## Match ScytheRig's baseline active arc. Ambient residents are not hit targets.
const SWING_REACTION_RADIUS := 150.0
const SWING_REACTION_HALF_ANGLE_DEG := 75.0
const GOLD := Color(0.92, 0.81, 0.62)
const SOFT := Color(0.72, 0.80, 0.78)

var _player: Node2D = null
var _creatures: Node = null
var _selected: Sprite2D = null
var _status: Label = null
var _objective: Label = null
var _waypoint_label: Label = null
var _waypoint_arrow: Control = null
var _last_guided_id: String = ""
var _highlight_time := 0.0
var _highlight_text := ""
var _swing_hint_shown: bool = false
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
		if not child.is_connected("interacted", Callable(self, "_on_interacted")):
			child.connect("interacted", Callable(self, "_on_interacted"))
		if not child.is_connected("noticed", Callable(self, "_on_noticed")):
			child.connect("noticed", Callable(self, "_on_noticed"))
	# Listen to the actual weapon action, not a separate input binding. This
	# also works for Android's synthetic InputEventAction and both combo hits.
	var rig := _player.get_node_or_null("ScytheRig")
	if rig != null and rig.has_signal("swing_started"):
		var handler := Callable(self, "_on_scythe_swing_started")
		if not rig.is_connected("swing_started", handler):
			rig.connect("swing_started", handler)
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
		var eligible: bool = bool(creature.call("is_player_in_range"))
		var distance: float = creature.global_position.distance_squared_to(_player.global_position)
		if eligible and (distance < best_distance or (is_equal_approx(distance, best_distance) and
				(closest == null or str(creature.name) < str(closest.name)))):
			closest = creature
			best_distance = distance
	for child in _creatures.get_children():
		if _is_resident(child):
			child.call("set_selected", child == closest)
	_selected = closest

func is_observing_resident() -> bool:
	return _selected != null and is_instance_valid(_selected)


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
	_selected.call("trigger_interaction")

func _on_noticed(creature: Node2D) -> void:
	_highlight_text = "%s NOTICED YOU" % String(creature.name).to_upper()
	_highlight_time = 1.7

func _on_interacted(creature: Node2D) -> void:
	_spawn_reaction(creature)
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
	_highlight_text = "%s  ·  %d/%d" % [
		observation_summary(ident), _observed_count(), _resident_count()]
	_highlight_time = HIGHLIGHT_SECONDS


## A swing is NOT an observation or an attack on Reserve residents. Show
## one short controls hint and a purely visual startle for nearby creatures.
## This never calls interacted(), take_hit(), or modifies save state.
func _on_scythe_swing_started(_index: int) -> void:
	if _player == null or _creatures == null or get_tree().paused:
		return
	var facing: Vector2 = _player.get("facing")
	var reactions := 0
	for child in _creatures.get_children():
		if not _is_resident(child) or not child.has_method("react_to_scythe"):
			continue
		var resident := child as Node2D
		if within_swing_reaction_arc(_player.global_position, facing,
				resident.global_position, SWING_REACTION_RADIUS, SWING_REACTION_HALF_ANGLE_DEG):
			resident.call("react_to_scythe", _player.global_position)
			reactions += 1
	if reactions > 0:
		_highlight_text = "RESIDENTS REACT  ·  USE TO OBSERVE"
		_highlight_time = 2.0
	elif not _swing_hint_shown:
		_highlight_text = "SWING  ·  USE TO OBSERVE RESIDENTS"
		_highlight_time = 2.0
	_swing_hint_shown = true


## Pure geometry for deterministic headless regression coverage.
static func within_swing_reaction_arc(origin: Vector2, facing: Vector2,
		target: Vector2, radius: float, half_angle_deg: float) -> bool:
	if radius <= 0.0:
		return false
	var delta := target - origin
	if delta.length_squared() > radius * radius:
		return false
	if delta.length_squared() < 0.0001:
		return true
	var axis := facing.normalized() if facing.length_squared() > 0.0001 else Vector2.DOWN
	return axis.dot(delta.normalized()) >= cos(deg_to_rad(clampf(half_angle_deg, 0.0, 180.0)))


## Species information comes from data/creatures.json, never generated
## flavor text or unapproved bonding rules. Avoid showing boss classification
## as a spoiler and never expose catch rates as a substitute for bonding.
static func observation_summary(species_id: String) -> String:
	var info: Dictionary = CreatureData.get_creature(species_id)
	if info.is_empty():
		return species_id.capitalize()
	var n := str(info.get("name", species_id.capitalize())).to_upper()
	var temperament := str(info.get("temperament", "")).to_upper()
	var region := str(info.get("region", ""))
	var detail := ""
	if not temperament.is_empty() and temperament != "BOSS":
		detail = temperament
	if not region.is_empty():
		detail += ("  ·  " if not detail.is_empty() else "") + region
	return n + ("  ·  " + detail if not detail.is_empty() else "")


func _spawn_reaction(creature: Node2D) -> void:
	if not is_inside_tree() or not is_instance_valid(creature):
		return
	var effect := ReactionVfx.new()
	effect.name = "ObservedSoulThread"
	effect.global_position = creature.global_position
	# Add as a sibling of residents; the effect has its own world-scale
	# transform instead of inheriting the tiny Sprite2D texture scale.
	_creatures.add_child(effect)
	effect.global_position = creature.global_position + Vector2(0.0, 26.0)


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
		_status.text = ResidentScript.interaction_caption(DisplayServer.is_touchscreen_available()) + "   " + String(_selected.name).to_upper()
		_status.add_theme_color_override("font_color", GOLD)
	elif _resident_count() > 0 and _observed_count() >= _resident_count():
		_status.text = "Residents recorded  ·  continue along the trail"
		_status.add_theme_color_override("font_color", GOLD)
	else:
		_status.text = "Explore the paths to find living creatures"
		_status.add_theme_color_override("font_color", SOFT)
	_update_wayfinding()


## Pure selection: only living, unobserved entries qualify. Stable ties.
static func choose_unobserved(origin: Vector2, residents: Array,
		observed: Array) -> Dictionary:
	var chosen: Dictionary = {}
	var best_distance := INF
	for entry_value in residents:
		if not (entry_value is Dictionary):
			continue
		var entry: Dictionary = entry_value
		var ident := str(entry.get("id", ""))
		if ident.is_empty() or observed.has(ident):
			continue
		var candidate_position: Variant = entry.get("position", null)
		if not (candidate_position is Vector2):
			continue
		var d: float = origin.distance_squared_to(candidate_position)
		if d < best_distance - 0.001 or (absf(d - best_distance) <= 0.001 and
				(chosen.is_empty() or ident < str(chosen.get("id", "")))):
			best_distance = d
			chosen = entry
	return chosen


static func distance_hint(distance: float) -> String:
	if distance < 170.0:
		return "NEARBY"
	if distance < 490.0:
		return "AHEAD"
	return "FARTHER"


func _observed_ids() -> Array:
	if _game_state == null:
		return []
	var state: Variant = _game_state.get("state")
	if not (state is Dictionary):
		return []
	var ids: Variant = state.get(OBSERVED_KEY, [])
	return ids if ids is Array else []


func _update_wayfinding() -> void:
	if _waypoint_label == null or _waypoint_arrow == null or _player == null:
		return
	var entries: Array = []
	for child in _creatures.get_children():
		if _is_resident(child):
			entries.append({
				"id": String(child.name).to_snake_case(),
				"name": String(child.name).to_upper(),
				"position": (child as Node2D).global_position
			})
	var observed := _observed_ids()
	var best := choose_unobserved(_player.global_position, entries, observed)
	if best.is_empty():
		_last_guided_id = ""
		_waypoint_label.text = ""
		_waypoint_arrow.call("clear")
		return
	# Avoid oscillating target arrows between two walking residents.
	var selected := best
	for entry_value in entries:
		var entry: Dictionary = entry_value
		if str(entry.get("id", "")) != _last_guided_id or observed.has(_last_guided_id):
			continue
		var saved_distance := _player.global_position.distance_to(entry["position"])
		var best_distance := _player.global_position.distance_to(best["position"])
		if saved_distance <= best_distance + 65.0:
			selected = entry
		break
	_last_guided_id = str(selected["id"])
	var travel: Vector2 = selected["position"] - _player.global_position
	_waypoint_arrow.call("point_to", travel)
	_waypoint_label.text = "%s  ·  %s" % [
		distance_hint(travel.length()), str(selected["name"])]


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ReserveGuideHUD"
	layer.layer = 12
	add_child(layer)
	var panel := ColorRect.new()
	panel.color = Color(0.045, 0.065, 0.075, 0.80)
	panel.position = Vector2(19, 16)
	panel.size = Vector2(540, 122)
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
	# Display-only guidance: never moves the player or consumes touch input.
	_waypoint_arrow = CompassArrow.new()
	_waypoint_arrow.name = "NextResidentCompass"
	_waypoint_arrow.position = Vector2(35, 92)
	_waypoint_arrow.size = Vector2(31, 31)
	_waypoint_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_waypoint_arrow)
	_waypoint_label = Label.new()
	_waypoint_label.name = "NextResidentHint"
	_waypoint_label.position = Vector2(76, 94)
	_waypoint_label.size = Vector2(465, 31)
	_waypoint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_waypoint_label.add_theme_font_size_override("font_size", 17)
	_waypoint_label.add_theme_color_override("font_color", SOFT)
	layer.add_child(_waypoint_label)
