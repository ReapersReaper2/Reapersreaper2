extends CharacterBody2D
class_name ReaperPlayer

const Fabricator := preload("res://scripts/fabricator.gd")
const Depower := preload("res://scripts/depower.gd")
const DepowerIndicator := preload("res://scripts/depower_indicator.gd")
const Flight := preload("res://scripts/flight.gd")
const CombatTime := preload("res://scripts/combat_time.gd")
## M0 player controller: top-down 8-direction movement with
## acceleration/deceleration smoothing. Placeholder visuals only.

@export var walk_speed: float = 200.0
@export var acceleration: float = 1200.0
@export var friction: float = 1400.0

## Last non-zero movement direction (used by combat/interact facing).
var facing: Vector2 = Vector2.DOWN

## Set by ScytheRig during committed swings: movement input is ignored
## while true (the swing plants the player's feet).
var move_locked: bool = false

## Set by the cutscene player: ALL input actions (swing, interact) are
## ignored while true, so scripted sequences can't be interrupted.
var input_locked: bool = false

## Set by the GuideRig during a guide-touch: the scythe cannot be swung
## while cradling a soul (the two modes are mutually exclusive).
var guide_active: bool = false

## Set by Tendril during a tendril ride: the player is being carried
## along a path. move_locked/input_locked are set alongside this;
## damage is ignored while true (can't be hit mid-ride).
var tendril_riding: bool = false

## Form 9 flight mode (unlocked at U3 wings). While flying: faster
## movement, fly-over barriers (collision layer 4) are ignored, and the
## Visuals node lifts for an altitude cue. Toggle with [F] (fly_toggle).
var flying: bool = false

signal flight_changed(flying: bool)


## Sprite manager: swaps greybox polygons for the real Mollosar
## form sprites. Created in _ready under Visuals.
## Untyped on purpose: class_name globals don't resolve in headless
## -s runs (same reason as the rig vars below).
var sprites = null


func _physics_process(delta: float) -> void:
	var input_dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	# Ch13-14 depower: walk speed slightly reduced while fully depowered.
	# Flight (Form 9) is faster and ignores fly-over barriers.
	var speed := walk_speed * Depower.walk_speed_mult(_game_state())
	if flying:
		speed = walk_speed * Flight.speed_mult()
	if move_locked:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	elif input_dir.length() > 0.01:
		facing = input_dir.normalized()
		velocity = velocity.move_toward(facing * speed, acceleration * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	move_and_slide()
	_update_flight_visual()
	if sprites != null:
		sprites.tick(delta, facing, velocity.length() > 20.0)


## Altitude cue: lift the Visuals node while flying.
func _update_flight_visual() -> void:
	var visuals := get_node_or_null("Visuals")
	if visuals == null:
		return
	var target_y := -Flight.LIFT_PX if flying else 0.0
	visuals.position.y = lerpf(visuals.position.y, target_y, 0.2)


func _unhandled_input(event: InputEvent) -> void:
	if input_locked:
		return
	if event.is_action_pressed("scythe_swing"):
		if guide_active:
			return
		# Untyped var on purpose: try_swing() is dynamically dispatched.
		var rig = get_node_or_null("ScytheRig")
		if rig != null:
			rig.try_swing()
	elif event.is_action_pressed("interact"):
		# Guide-touch gets first claim on E: taking up a soul swallows
		# the press so NPCs/dialogue don't also fire.
		var grig = get_node_or_null("GuideRig")
		var handled := false
		if grig != null and grig.has_method("try_guide"):
			handled = bool(grig.try_guide())
		if handled:
			get_viewport().set_input_as_handled()
		else:
			print("[INPUT] interact pressed")
	elif event.is_action_pressed("ui_cancel"):
		print("[INPUT] ui_cancel pressed")
	elif event.is_action_pressed("fly_toggle"):
		try_toggle_flight()


## --- Flight (Form 9) --------------------------------------------------
## [F] toggles flight when unlocked (U3 wings: form9_unlocked +
## depower NONE). Flying: 1.4x speed, fly-over barriers ignored,
## altitude visual. Landing restores the walking collision mask.

func try_toggle_flight() -> void:
	if flying:
		land()
		return
	var gs = _game_state()
	if Flight.can_fly(gs):
		take_off()
	else:
		_say_flight_hint(Flight.locked_hint(gs))


func take_off() -> void:
	var gs = _game_state()
	if not Flight.can_fly(gs):
		_say_flight_hint(Flight.locked_hint(gs))
		return
	if tendril_riding or move_locked:
		return
	flying = true
	collision_mask = Flight.FLY_MASK
	flight_changed.emit(true)
	# Steam "wings" fires on the form9_unlocked flag (trigger map),
	# not on takeoff.
	print("[FLIGHT] takeoff")


func land() -> void:
	if not flying:
		return
	flying = false
	collision_mask = Flight.WALK_MASK
	flight_changed.emit(false)
	print("[FLIGHT] landing")


func _say_flight_hint(text: String) -> void:
	if text == "":
		return
	if not is_inside_tree():
		print("[FLIGHT] ", text)
		return
	var box = get_tree().get_first_node_in_group("dialogue_box")
	if box != null and box.has_method("start_dialogue"):
		box.start_dialogue([{"type": "direction", "text": text}])
	else:
		print("[FLIGHT] ", text)


## --- Vigor / damage ---------------------------------------------------
## The prologue cannot be lost (it's a memory): hitting 0 vigor emits
## player_died and the wave spawner resets the current wave — no game over.

signal vigor_changed(vigor: int, vigor_max: int)
signal player_died

var vigor: int = 3
var vigor_max: int = 3


func _ready() -> void:
	pull_vigor()
	_wire_sprites()
	_wire_depower_indicator()
	# Walking mask includes the fly-over barrier layer (see flight.gd).
	collision_mask = Flight.WALK_MASK


## Depower status indicator (CanvasLayer label, hidden when not depowered).
func _wire_depower_indicator() -> void:
	var ind = DepowerIndicator.new()
	add_child(ind)
	# Explicit _ready(): under -s the tree is cold and _ready doesn't
	# fire on add_child (guarded pattern used elsewhere in this file).
	ind._ready()


## Attach the Mollosar sprite manager under Visuals; it hides the
## greybox polygons once real form strips are showing. Also hooks
## the scythe swing signals for the reap-swing strip (Form 3).
func _wire_sprites() -> void:
	if sprites != null:
		return  # _ready ran twice (cold-tree explicit call + tree)
	var visuals := get_node_or_null("Visuals")
	if visuals == null:
		return
	var mgr_script = load("res://scripts/mollosar_sprites.gd")
	sprites = mgr_script.new()
	visuals.add_child(sprites)
	# Explicit _ready(): under -s the tree is cold and _ready doesn't
	# fire on add_child (guarded against double-run in the script).
	sprites._ready()
	var rig = get_node_or_null("ScytheRig")
	if rig != null:
		if rig.has_signal("swing_started"):
			rig.swing_started.connect(_on_swing_started)
		if rig.has_signal("swing_ended"):
			rig.swing_ended.connect(_on_swing_ended)


func _on_swing_started(_index: int) -> void:
	if sprites != null:
		sprites.play_swing()


func _on_swing_ended() -> void:
	if sprites != null:
		sprites.stop_swing()


## Force a form re-read (e.g. after the story unlocks a new form).
func refresh_sprites() -> void:
	if sprites != null:
		sprites.refresh()


func _game_state():
	# Absolute-path lookup is illegal before the node is inside the tree
	# (headless -s harnesses); in-game this always resolves.
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/GameState")


## Achievement hook (null-safe: headless tests have no Achievements).
func _ach_unlock(id: String) -> void:
	var ach = get_node_or_null("/root/Achievements")
	if ach != null and ach.has_method("unlock"):
		ach.unlock(id)


func take_damage(amount: int) -> void:
	take_damage_from(amount, null, [])


## Damage with an attacker reference and damage tags (e.g. ["fire"]).
## Thorn graft: attackers take retaliation. Cinder bark: fire/ash reduced.
func take_damage_from(amount: int, attacker: Node2D = null, tags: Array = []) -> void:
	if vigor <= 0:
		return
	if tendril_riding:
		return  # Can't be hit mid-tendril-ride.
	var final := amount
	var gs = _game_state()
	if gs != null:
		final = maxi(0, final - int(Fabricator.cinder_mitigation(gs, tags)))
	vigor = maxi(0, vigor - final)
	_push_vigor()
	_stats_record_damage(final)
	vigor_changed.emit(vigor, vigor_max)
	_thorn_retaliate(attacker, gs)
	if vigor <= 0:
		# Steam "first_death" fires on the prologue_complete flag
		# (trigger map: mortal-death cutscene), not on every death.
		# Steam "She Counted" (eleven_flowers): a gravebloom grows on
		# every player defeat — canon says they're the only source.
		if gs != null and gs.has_method("on_player_defeat"):
			gs.on_player_defeat()
		player_died.emit()


## Thorn graft retaliation: the armor bites back at whoever landed the hit.
func _thorn_retaliate(attacker: Node2D, gs) -> void:
	if attacker == null or not is_instance_valid(attacker):
		return
	if gs == null:
		return
	var retail := int(Fabricator.thorn_retaliation(gs))
	if retail <= 0:
		return
	if attacker.has_method("take_hit"):
		var away: Vector2 = (global_position - attacker.global_position).normalized()
		attacker.take_hit(retail, away)
		print("[FABRICATOR] thorn retaliation: ", retail)


## Feed the achievement stat tracker (null-safe: headless tests have no Stats).
func _stats_record_damage(amount: int) -> void:
	if not is_inside_tree():
		return
	var st = get_node_or_null("/root/Stats")
	if st != null and st.has_method("record_damage"):
		st.record_damage(amount)


func heal_full() -> void:
	vigor = vigor_max
	_push_vigor()
	vigor_changed.emit(vigor, vigor_max)


func is_alive() -> bool:
	return vigor > 0


func pull_vigor() -> void:
	var gs = _game_state()
	if gs == null:
		return
	var st = gs.get("state")
	if st is Dictionary:
		var p = (st as Dictionary).get("player", {})
		if p is Dictionary:
			vigor = int((p as Dictionary).get("vigor", vigor))
			vigor_max = int((p as Dictionary).get("vigor_max", vigor_max))


func _push_vigor() -> void:
	var gs = _game_state()
	if gs != null and gs.has_method("set_vigor"):
		gs.set_vigor(vigor, vigor_max)


## Scythe-break visual: the scythe shatters. Heavy screen shake, a shard
## particle burst, and a brief combat freeze. Called by ScytheBreak.on_break()
## via the player group. Safe in headless tests (no tree = no-op).
func play_scythe_break() -> void:
	if not is_inside_tree():
		return
	# Heavy shake.
	var cam := get_node_or_null("Camera2D")
	if cam != null and cam.has_method("add_trauma"):
		cam.add_trauma(0.9)
	# Shard burst: violet-white fragments flying outward.
	var burst := CPUParticles2D.new()
	burst.amount = 36
	burst.lifetime = 0.7
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.direction = Vector2.ZERO
	burst.spread = 180.0
	burst.initial_velocity_min = 180.0
	burst.initial_velocity_max = 420.0
	burst.gravity = Vector2(0, 500)
	burst.scale_amount_min = 2.0
	burst.scale_amount_max = 5.0
	burst.color = Color(0.75, 0.45, 1.0)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.85, 0.6, 1.0))
	grad.set_color(1, Color(0.4, 0.2, 0.8, 0.0))
	burst.color_ramp = grad
	burst.position = Vector2.ZERO
	add_child(burst)
	burst.emitting = true
	# Combat-scoped freeze for impact (UI-safe, unlike Engine.time_scale),
	# then clean up the burst.
	CombatTime.hitstop(0.35)
	var tree := get_tree()
	if tree != null:
		await tree.create_timer(0.8, true, false, true).timeout
		if is_instance_valid(burst):
			burst.queue_free()
