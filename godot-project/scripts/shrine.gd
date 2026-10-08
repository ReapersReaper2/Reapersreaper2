extends Area2D
## Lantern Shrine: manual save point for Reaper's Reaper.
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Greybox visual: stone base + post + hanging lantern with a flickering
## soul-light glow. E opens the shrine menu (REST / TRAVEL / SOUL VAULT /
## LEAVE) when the player is in range: rest runs a brief sequence (screen
## dims, placeholder rest line through the room's dialogue box), then
## GameState.save_shrine(current_slot), heal to full vigor, the
## `shrine_<shrine_id>` flag, and the shrine joins the fast-travel network.
## TRAVEL lists every other lit shrine. Repeatable — resting is always allowed.
##
## game_state may be injected (headless tests) or resolved from the tree.

## Shrine identifier, e.g. "p1_1". The GameState flag is "shrine_" + shrine_id.
@export var shrine_id: String = "p1_1"
## Resting restores the player to full vigor.
@export var heals: bool = true

## Placeholder rest line (story bot replaces with canon).
const REST_LINE := "The lantern's light steadies you. Progress saved."

const StorageUIScript := preload("res://scripts/storage_ui.gd")
const Merchants := preload("res://scripts/merchants.gd")
const Stall := preload("res://scripts/stall.gd")
const Breeding := preload("res://scripts/breeding.gd")
const Still := preload("res://scripts/still.gd")

## GameState autoload, or injected (headless tests where the tree is cold).
var game_state = null

var _player_in_range: bool = false
var _player: Node2D = null
var _dialogue_box = null
var _resting: bool = false
var _t: float = 0.0

## Shrine menu (REST / TRAVEL / SOUL VAULT / LEAVE). E opens it; REST is
## selected by default so Enter preserves the old E-to-rest flow.
## TRAVEL opens the fast-travel list: every lit shrine except this one.
## Resting lights the shrine (joins the travel network).
var _menu_open: bool = false
var _menu_layer: CanvasLayer = null
var _menu_buttons: Array = []
var _menu_selected: int = 0
## True while the travel destination list is showing (second menu level).
var _travel_mode: bool = false

## Room display names for the travel list (wiring-written, functional).
const SHRINE_ROOM_NAMES := {
	"p1": "Bellhollow Bridge",
	"p3": "Black Sand Shore",
	"c1": "River Band",
	"h1": "Town Plaza",
	"h2": "Murray's Bar",
	"h3": "Dockside Shops",
	"h4": "Back Alleys",
	"nm": "Night Market",
}


static func room_display_name(room_id: String) -> String:
	return str(SHRINE_ROOM_NAMES.get(room_id, room_id.to_upper()))


func _ready() -> void:
	# Connection guards: under -s harnesses _ready() may be invoked
	# explicitly AND auto-fire, so never connect twice.
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	_resolve_refs()


func _resolve_refs() -> void:
	# Null-tree safe: under -s, explicit _ready() runs before the node
	# is inside the tree, so every tree service is guarded.
	if game_state == null and is_inside_tree():
		game_state = get_node_or_null("/root/GameState")
	if _dialogue_box == null and is_inside_tree():
		var box = get_tree().get_first_node_in_group("dialogue_box")
		_set_dialogue_box(box)


func _set_dialogue_box(box) -> void:
	_dialogue_box = box
	if _dialogue_box != null and _dialogue_box.has_signal("dialogue_finished"):
		if not _dialogue_box.dialogue_finished.is_connected(_on_dialogue_finished):
			_dialogue_box.dialogue_finished.connect(_on_dialogue_finished)


func _process(delta: float) -> void:
	_t += delta
	# Gentle soul-light flicker on the glow.
	var glow := get_node_or_null("Glow") as Polygon2D
	if glow != null:
		var a := 0.16 + 0.05 * sin(_t * 2.3) + 0.03 * sin(_t * 5.7)
		var c := glow.color
		glow.color = Color(c.r, c.g, c.b, a)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		_player = body
		$Prompt.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player") and body == _player:
		_player_in_range = false
		_player = null
		$Prompt.visible = false
		_close_shrine_menu()


func _unhandled_input(event: InputEvent) -> void:
	if _resting or not _player_in_range:
		return
	if _menu_open:
		if event.is_action_pressed("ui_cancel"):
			if _travel_mode:
				_open_shrine_menu_buttons()
			else:
				_close_shrine_menu()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_up"):
			_menu_selected = posmod(_menu_selected - 1, _menu_buttons.size())
			_refresh_shrine_menu()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_down"):
			_menu_selected = posmod(_menu_selected + 1, _menu_buttons.size())
			_refresh_shrine_menu()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("ui_accept"):
			_activate_menu_item()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):
		# Swallow the press so the dialogue box doesn't instantly advance.
		get_viewport().set_input_as_handled()
		_open_shrine_menu.call_deferred()


## Shrine menu: REST / TRAVEL / SOUL VAULT / LEAVE. Public for tests.
func _open_shrine_menu() -> void:
	if _menu_open or _resting:
		return
	_menu_open = true
	_travel_mode = false
	_open_shrine_menu_buttons()


## (Re)build the menu buttons for the top-level shrine menu.
func _open_shrine_menu_buttons() -> void:
	_travel_mode = false
	_menu_selected = 0  # REST default
	_build_menu_buttons([
		{"id": "rest", "text": "REST"},
		{"id": "travel", "text": "TRAVEL"},
		{"id": "vault", "text": "SOUL VAULT"},
		{"id": "leave", "text": "LEAVE"},
	])


## Build the travel destination list: every lit shrine except this one.
## Unlit shrines are not shown. Always ends with BACK.
func _open_travel_menu() -> void:
	_travel_mode = true
	_menu_selected = 0
	var defs: Array = []
	for d in _travel_destinations():
		defs.append({"id": "dest:" + str(d["id"]), "text": str(d["text"])})
	if defs.is_empty():
		defs.append({"id": "none", "text": "No other lanterns lit."})
	defs.append({"id": "back", "text": "BACK"})
	_build_menu_buttons(defs)


func _build_menu_buttons(defs: Array) -> void:
	# Tear down any existing menu layer first (travel is a second level).
	if _menu_layer != null and is_instance_valid(_menu_layer):
		_menu_layer.queue_free()
	_menu_open = true
	$Prompt.visible = false
	_menu_layer = CanvasLayer.new()
	_menu_layer.layer = 12
	_menu_layer.add_to_group("shrine_menu")
	add_child(_menu_layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_menu_layer.add_child(center)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	center.add_child(vbox)
	_menu_buttons = []
	for d in defs:
		var b := Button.new()
		b.text = str(d["text"])
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(360, 46)
		b.add_theme_font_size_override("font_size", 28)
		b.add_theme_color_override("font_color", Color(0.92, 0.90, 0.86))
		var item_id := str(d["id"])
		b.pressed.connect(_on_menu_pressed.bind(item_id))
		b.mouse_entered.connect(_on_menu_hovered.bind(item_id))
		vbox.add_child(b)
		_menu_buttons.append({"id": item_id, "button": b, "text": str(d["text"])})
	_refresh_shrine_menu()


func _close_shrine_menu() -> void:
	_menu_open = false
	if _menu_layer != null and is_instance_valid(_menu_layer):
		_menu_layer.queue_free()
	_menu_layer = null
	if _player_in_range and not _resting:
		$Prompt.visible = true


func _refresh_shrine_menu() -> void:
	for i in _menu_buttons.size():
		var b: Button = _menu_buttons[i]["button"]
		var prefix := "> " if i == _menu_selected else "   "
		b.text = prefix + str(_menu_buttons[i]["text"])
		b.modulate = Color(1, 1, 1) if i == _menu_selected else Color(0.7, 0.7, 0.72)


func _on_menu_pressed(item_id: String) -> void:
	for i in _menu_buttons.size():
		if str(_menu_buttons[i]["id"]) == item_id:
			_menu_selected = i
			break
	_activate_menu_item()


func _on_menu_hovered(item_id: String) -> void:
	for i in _menu_buttons.size():
		if str(_menu_buttons[i]["id"]) == item_id:
			_menu_selected = i
			_refresh_shrine_menu()
			break


func _menu_id() -> String:
	return str(_menu_buttons[_menu_selected]["id"])


func _activate_menu_item() -> void:
	var item_id := _menu_id()
	if _travel_mode:
		if item_id == "back":
			_open_shrine_menu_buttons()
		elif item_id.begins_with("dest:"):
			_travel_to(item_id.substr(5))
		# "none" (no destinations) does nothing.
		return
	match item_id:
		"rest":
			_close_shrine_menu()
			rest.call_deferred()
		"travel":
			_open_travel_menu()
		"vault":
			_close_shrine_menu()
			_open_storage_ui.call_deferred()
		"leave":
			_close_shrine_menu()


## Lit-shrine destinations for the travel list, excluding this shrine.
## Public for tests. Each entry: {"id": shrine_id, "text": display}.
func _travel_destinations() -> Array:
	_resolve_refs()
	var lit: Dictionary = {}
	var gs = _game_state()
	if gs != null and gs.has_method("get_lit_shrines"):
		lit = gs.get_lit_shrines()
	var out: Array = []
	for sid in lit.keys():
		if str(sid) == shrine_id:
			continue
		var info: Dictionary = lit[sid]
		var room_id := str(info.get("room", ""))
		out.append({"id": str(sid), "text": "Lantern — " + room_display_name(room_id)})
	return out


## Fast-travel to a lit shrine. Sets the spawn position (same path as
## room exits) and changes to the target room scene with a fade-out.
## Returns the target scene path ("" when the destination is unknown).
## Public for tests.
func _travel_to(dest_id: String) -> String:
	_resolve_refs()
	var gs = _game_state()
	var dest: Dictionary = {}
	if gs != null and gs.has_method("get_lit_shrines"):
		dest = gs.get_lit_shrines().get(dest_id, {})
	if dest.is_empty():
		return ""
	var room_id := str(dest.get("room", ""))
	if room_id == "":
		return ""
	var scene_path := "res://scenes/room_" + room_id + ".tscn"
	if gs != null and gs.has_method("set_position"):
		gs.set_position(room_id, float(dest.get("x", 0.0)), float(dest.get("y", 0.0)))
	print("[SHRINE] travel ", shrine_id, " -> ", dest_id, " (", scene_path, ")")
	if is_inside_tree():
		_close_shrine_menu()
		_fade_and_change_scene(scene_path)
	return scene_path


## Fade the shrine dim to black, then change scene.
func _fade_and_change_scene(scene_path: String) -> void:
	var dim := get_node_or_null("DimLayer/Dim") as ColorRect
	if dim == null or not is_inside_tree():
		get_tree().change_scene_to_file(scene_path)
		return
	dim.visible = true
	dim.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(dim, "modulate:a", 1.0, 0.45)
	tw.tween_callback(get_tree().change_scene_to_file.bind(scene_path))


func _open_storage_ui() -> void:
	_resolve_refs()
	var gs = _game_state()
	if gs == null:
		return
	var ui = StorageUIScript.new()
	ui.game_state = gs
	# Add to the scene root so the CanvasLayer renders above everything.
	var target: Node = get_tree().root if is_inside_tree() else self
	target.add_child(ui)
	ui._ready()
	ui.open()


## Begin the rest sequence. Public so tests/rooms can trigger it directly.
func rest() -> void:
	if _resting:
		return
	_resting = true
	$Prompt.visible = false
	_dim()
	_resolve_refs()
	if _dialogue_box != null and _dialogue_box.has_method("start_dialogue"):
		_dialogue_box.start_dialogue([{"type": "direction", "text": REST_LINE}])
	else:
		# No dialogue box (headless tests): finish the rest immediately.
		_finish_rest()


func _on_dialogue_finished() -> void:
	if not _resting:
		return
	_finish_rest()


func _finish_rest() -> void:
	var gs = _game_state()
	# Flag first: the save payload must capture the post-rest state.
	if gs != null and gs.has_method("set_flag"):
		gs.set_flag("shrine_" + shrine_id)
	# Resting is the day boundary: advance the day counter (resets daily
	# haggle attempts/locks and the per-day purchase cap).
	if gs != null:
		Merchants.advance_day(gs)
		Stall.on_day_advance(gs)
		# Breeding day boundary: eggs incubate, young creatures grow.
		Breeding.on_day_advance(gs)
		# Still night boundary: extractions complete, trust debt ticks.
		Still.on_day_advance(gs)
	# Blackout respawn point: shrine_id is "<room>_<n>" by convention.
	# Resting also lights the shrine: it joins the fast-travel network.
	if gs != null and gs.has_method("set_last_shrine"):
		var parts := shrine_id.split("_")
		var room_id := str(parts[0])
		gs.set_last_shrine(room_id, global_position.x, global_position.y)
		if gs.has_method("light_shrine"):
			gs.light_shrine(shrine_id, room_id, global_position.x, global_position.y)
	if gs != null and gs.has_method("save_shrine") and gs.has_method("get_current_slot"):
		gs.save_shrine(int(gs.get_current_slot()))
	if heals and _player != null and is_instance_valid(_player) and _player.has_method("heal_full"):
		_player.heal_full()
	_resting = false
	if _player_in_range:
		$Prompt.visible = true


func _game_state():
	if game_state == null:
		_resolve_refs()
	return game_state


func _dim() -> void:
	var dim := get_node_or_null("DimLayer/Dim") as ColorRect
	if dim == null or not is_inside_tree():
		return
	dim.visible = true
	dim.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(dim, "modulate:a", 0.35, 0.4)
	tw.tween_property(dim, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func() -> void: dim.visible = false)
