extends Area2D
## WildZone — tall soul-flame grass encounter area.
##
## While the player is inside AND moving, steps accumulate (step counter on
## player movement, not a timer — classic). At the step threshold an
## encounter triggers: a brief "!" rustle cue, then
## BattleManager.start_wild_battle() with a weighted pick from the zone's
## encounter table (data/encounters.json, keyed by room_id).
##
## Anti-frustration: no encounter within cooldown_seconds of the last
## battle ending (BattleManager.last_battle_end_msec, stamped on
## clear_pending), none while dialogue/cutscene/pause is open, none while
## the player stands still. Leaving the zone stops all rolls.
##
## NOTE: intentionally no class_name (project convention).
## Place in a room .tscn as an Area2D child with a CollisionShape2D rect
## and table_key set (defaults to the parent room's room_id).

signal encounter_started(creature_id: String, level: int)

const ENCOUNTERS_PATH := "res://data/encounters.json"
const PartyScript := preload("res://scripts/party.gd")
const TwitchVotesScript := preload("res://scripts/twitch_votes.gd")

## Room-table key; defaults to the parent room's room_id.
@export var table_key: String = ""
## Steps (of STEP_PX each) before an encounter roll.
@export var steps_per_encounter: int = 48
## Probability of an encounter when the threshold is reached (1.0 = always).
@export var encounter_rate: float = 1.0
## Seconds after a battle ends during which no encounter may trigger.
@export var cooldown_seconds: float = 8.0
## Delay between the "!" rustle cue and the seamless battle layer (0 = instant).
@export var cue_delay: float = 0.6

## Pixels of player travel that count as one step.
const STEP_PX := 24.0

var game_state = null  # GameState autoload, or injected (headless tests)
var battle_manager = null  # BattleManager autoload, or injected
var dialogue_box = null

var _player: Node2D = null
var _inside: bool = false
var _steps: float = 0.0
var _threshold: float = 48.0
var _last_player_pos: Vector2 = Vector2.ZERO
var _cue_active: bool = false
var _table: Array = []
var _rng := RandomNumberGenerator.new()
var _tufts: Array = []
## Twitch wiring: last-seen battle-end stamp (post-battle vote trigger),
## and the Swarm followup (a second encounter right after this one).
var _last_seen_battle_end: int = -1
var _swarm_followup: bool = false

static var _encounters: Dictionary = {}


static func table_for(key: String) -> Array:
	if _encounters.is_empty():
		var f := FileAccess.open(ENCOUNTERS_PATH, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_encounters = parsed
	if _encounters.has(key):
		var t: Variant = _encounters[key]
		if t is Array:
			return t
	return []


func _ready() -> void:
	_rng.randomize()
	_resolve_services()
	if table_key == "":
		var room = get_parent()
		if room != null and "room_id" in room:
			table_key = str(room.room_id)
	_table = table_for(table_key)
	_jitter_threshold()
	_build_visual()
	# Guarded: under -s the tree is cold and _ready may run twice
	# (once on add_child, once explicit) — connecting twice is harmless
	# but spams errors, so check first.
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	# Catch the player already standing inside (room reload after battle).
	_scan_for_player()


func _resolve_services() -> void:
	if is_inside_tree():
		if game_state == null:
			game_state = get_node_or_null("/root/GameState")
		if battle_manager == null:
			battle_manager = get_node_or_null("/root/BattleManager")
		if dialogue_box == null:
			dialogue_box = get_tree().get_first_node_in_group("dialogue_box")


func _scan_for_player() -> void:
	if not is_inside_tree():
		return
	for body in get_overlapping_bodies():
		if body.is_in_group("player"):
			_on_body_entered(body)
			break


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group("player"):
		return
	_player = body
	_inside = true
	_last_player_pos = body.position
	_jitter_threshold()
	# Twitch: a viewer vote may open when the player walks into a wild zone.
	_resolve_services()
	TwitchVotesScript.maybe_open(game_state, self)


func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_player = null
		_inside = false
		_steps = 0.0


func _physics_process(_delta: float) -> void:
	if not _inside or _player == null or not is_instance_valid(_player):
		return
	if _cue_active:
		return
	_track_movement()
	# Twitch: a viewer vote may open after each battle (between encounters).
	_maybe_open_post_battle_vote()
	# Twitch The Swarm: the followup encounter triggers almost immediately.
	if _swarm_followup:
		_steps = maxf(_steps, _threshold)
	if _steps >= _threshold and _can_trigger():
		if _rng.randf() <= encounter_rate:
			_trigger()
		_steps = 0.0
		_jitter_threshold()


## After a battle ends while the player is in the zone, offer viewers a
## vote — the classic between-encounters moment.
func _maybe_open_post_battle_vote() -> void:
	if battle_manager == null:
		_resolve_services()
	if battle_manager == null:
		return
	var be := int(battle_manager.last_battle_end_msec)
	if be == _last_seen_battle_end:
		return
	_last_seen_battle_end = be
	if be >= 0 and _inside:
		TwitchVotesScript.maybe_open(game_state, self)


## Accumulate steps from player travel. Exposed for headless tests.
func _track_movement() -> void:
	if _player == null:
		return
	var d := _player.position.distance_to(_last_player_pos)
	if d >= STEP_PX:
		_steps += d / STEP_PX
		_last_player_pos = _player.position


func _jitter_threshold() -> void:
	_threshold = float(steps_per_encounter) * _rng.randf_range(0.75, 1.25)


func _can_trigger() -> bool:
	if _table.is_empty():
		return false
	if battle_manager != null:
		if not (battle_manager.pending as Dictionary).is_empty():
			return false
		var last_end := int(battle_manager.last_battle_end_msec)
		if last_end >= 0:
			var since_battle := (Time.get_ticks_msec() - last_end) / 1000.0
			# Twitch The Swarm: the followup encounter ignores the cooldown.
			if since_battle < cooldown_seconds and not _swarm_followup:
				return false
	# Injected dialogue box (headless tests) or the room's live one.
	var db: Variant = dialogue_box
	if db != null and is_instance_valid(db) and bool(db.get("visible")):
		return false
	if is_inside_tree():
		if get_tree().paused:
			return false
		if db == null:
			var live := get_tree().get_first_node_in_group("dialogue_box")
			if live != null and bool(live.get("visible")):
				return false
		var cs := get_tree().get_first_node_in_group("cutscene")
		if cs != null and cs.has_method("is_playing") and bool(cs.call("is_playing")):
			return false
	return _player_can_fight()


## Don't tease an encounter the party can't take: BattleManager would
## refuse the start anyway, so skip the cue entirely.
func _player_can_fight() -> bool:
	var gs = game_state
	if gs == null and is_inside_tree():
		gs = get_node_or_null("/root/GameState")
	if gs == null:
		return true  # headless tests inject battle_manager instead
	return not PartyScript.lead_for_battle(gs).is_empty()


func _pick_creature() -> Dictionary:
	# Twitch Rare Sighting (one-shot): force the rarest table entry —
	# the lowest-weight creature. Flag clears whether or not it fires.
	if _consume_twitch_flag("twitch_rare_spawn"):
		var rarest: Dictionary = _table[0]
		for e in _table:
			var entry := e as Dictionary
			if float(entry.get("weight", 1.0)) < float(rarest.get("weight", 1.0)):
				rarest = entry
		print("[TWITCH] Rare Sighting: ", str(rarest.get("creature_id", "?")))
		return _make_pick(rarest)
	var total := 0.0
	for e in _table:
		total += float((e as Dictionary).get("weight", 1.0))
	var roll := _rng.randf() * total
	for e in _table:
		var entry := e as Dictionary
		roll -= float(entry.get("weight", 1.0))
		if roll <= 0.0:
			return _make_pick(entry)
	return _make_pick(_table[_table.size() - 1] as Dictionary)


func _make_pick(entry: Dictionary) -> Dictionary:
	var lo := int(entry.get("min_level", 1))
	var hi := int(entry.get("max_level", lo))
	var level := _rng.randi_range(lo, hi)
	# Twitch Trial by Fire (one-shot): the encounter is +4 levels.
	if _consume_twitch_flag("twitch_hard_encounter"):
		level += 4
		print("[TWITCH] Trial by Fire: encounter at level ", level)
	return {
		"creature_id": str(entry.get("creature_id", "")),
		"level": level,
	}


## Read-and-clear a one-shot Twitch effect flag on the GameState.
## Returns true when the flag was set (and is now cleared).
func _consume_twitch_flag(flag: String) -> bool:
	var gs = game_state
	if gs == null and is_inside_tree():
		gs = get_node_or_null("/root/GameState")
	if gs == null:
		return false
	if bool(gs.get_stat(flag, false)):
		gs.set_stat(flag, false)
		return true
	return false


func _trigger() -> void:
	_cue_active = true
	# Twitch The Swarm (one-shot): this encounter is immediately followed
	# by a second one — the extra enemy arrives on the first battle's heels.
	if _consume_twitch_flag("twitch_swarm"):
		_swarm_followup = true
		print("[TWITCH] The Swarm: a second encounter is coming")
	elif _swarm_followup:
		# This trigger IS the swarm's followup encounter — stand down.
		_swarm_followup = false
	var pick := _pick_creature()
	encounter_started.emit(str(pick["creature_id"]), int(pick["level"]))
	_show_rustle_cue()
	if cue_delay > 0.0 and is_inside_tree():
		await get_tree().create_timer(cue_delay).timeout
		if not is_instance_valid(self):
			return
	_start_battle(pick)


func _start_battle(pick: Dictionary) -> void:
	_cue_active = false
	_steps = 0.0
	_jitter_threshold()
	if battle_manager == null:
		_resolve_services()
	if battle_manager == null or not battle_manager.has_method("start_wild_battle"):
		push_warning("wild_zone: BattleManager missing, encounter fizzled")
		return
	var room := table_key
	var room_node = get_parent()
	if room_node != null and "room_id" in room_node:
		room = str(room_node.room_id)
	var pos := _player.position if _player != null else Vector2.ZERO
	var ok := bool(battle_manager.start_wild_battle(str(pick["creature_id"]), int(pick["level"]), room, pos))
	if not ok:
		print("[WILD] encounter refused (no conscious lead?)")


## Greybox rustle cue: a "!" pops above the player and fades.
func _show_rustle_cue() -> void:
	if _player == null or not is_inside_tree():
		return
	var label := Label.new()
	label.text = "!"
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))
	label.position = _player.position + Vector2(-12, -110)
	add_child(label)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y - 40.0, 0.6)
	tw.tween_property(label, "modulate:a", 0.0, 0.6)
	tw.chain().tween_callback(label.queue_free)


## --- Visual: procedural soul-flame grass --------------------------------
## Translucent tint over the zone rect + scattered flame tufts with a
## gentle shimmer. All Polygon2D; no art assets.

func _build_visual() -> void:
	var rect := _zone_rect()
	if rect.size.x <= 0.0:
		return
	var tint := Polygon2D.new()
	tint.color = Color(0.15, 0.5, 0.55, 0.16)
	tint.polygon = PackedVector2Array([
		rect.position, rect.position + Vector2(rect.size.x, 0),
		rect.end, rect.position + Vector2(0, rect.size.y)])
	add_child(tint)
	var colors := [Color(0.3, 0.9, 0.85, 0.75), Color(0.4, 0.65, 1.0, 0.75),
		Color(0.55, 1.0, 0.9, 0.6)]
	var count := int(clamp(rect.size.x * rect.size.y / 9000.0, 8.0, 40.0))
	for i in count:
		var tuft := Polygon2D.new()
		var w := _rng.randf_range(10.0, 20.0)
		var h := _rng.randf_range(26.0, 52.0)
		var x := _rng.randf_range(rect.position.x, rect.end.x)
		var y := _rng.randf_range(rect.position.y, rect.end.y)
		tuft.polygon = PackedVector2Array([
			Vector2(x - w * 0.5, y), Vector2(x + w * 0.5, y),
			Vector2(x + _rng.randf_range(-6.0, 6.0), y - h)])
		tuft.color = colors[_rng.randi_range(0, colors.size() - 1)]
		add_child(tuft)
		_tufts.append({"node": tuft, "phase": _rng.randf_range(0.0, TAU), "base_a": tuft.color.a})


func _zone_rect() -> Rect2:
	for child in get_children():
		if child is CollisionShape2D:
			var shape: Shape2D = (child as CollisionShape2D).shape
			if shape is RectangleShape2D:
				var sz := (shape as RectangleShape2D).size
				return Rect2(child.position - sz * 0.5, sz)
	return Rect2()


func _process(_delta: float) -> void:
	# Twitch: drive any open viewer vote (poll chat, refresh overlay,
	# apply the winner). Runs even when the player isn't inside so votes
	# never stall.
	TwitchVotesScript.process(game_state, self)
	if _tufts.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0
	for tuft in _tufts:
		var node: Polygon2D = tuft["node"]
		if is_instance_valid(node):
			var c := node.color
			c.a = float(tuft["base_a"]) * (0.65 + 0.35 * sin(t * 2.2 + float(tuft["phase"])))
			node.color = c
