extends Node2D
## Harrow boss fight controller (GD5, the mirror-boss).
## 150 Vigor. "This is where you fight yourself."
##
## Locked mechanics (decision log, doc 00 + Appendix C G5):
## - Mirror-boss: Harrow mirrors the player's position across the arena
##   center and answers scythe swings with mirrored strikes.
## - Despair Feed: heals 10 Vigor per player missed scythe swing.
## - Reconstitute: at 50% Vigor, one-time, restores 30 Vigor with a
##   visible telegraph.
## - Damage gate (the real gimmick): 3 plant-tendrils, 30 Vigor each, as
##   sub-targets. Harrow is INVULNERABLE while any tendril lives —
##   "break his concentration, then he can be damaged."
##
## NOTE: intentionally no class_name (project convention).
## Harrow himself is the controller node (CharacterBody2D movement is
## overkill for a mirror); he is a "hittable" Area2D-ish target via the
## take_hit method and the "hittable" group.

signal fight_started
signal fight_won
signal fight_reset
signal reconstituted

const TendrilScript := preload("res://scripts/harrow_tendril.gd")

const VICTORY_FLAG := "harrow_defeated"
const TRIGGER_NAME := "HarrowFight"

## Locked stat block: 150 Vigor / 20 Power / 14 Guard / 14 Speed.
const MAX_VIGOR := 150
const DESPAIR_FEED_HEAL := 10
const RECONSTITUTE_AT := 75  # 50% of 150
const RECONSTITUTE_HEAL := 30

enum Phase { IDLE, INTRO, FIGHTING, RECONSTITUTING, WON }

var game_state = null

var vigor: int = MAX_VIGOR
var _phase: int = Phase.IDLE
var _tendrils: Array = []
var _reconstituted: bool = false
var _reconst_t: float = 0.0
var _strike_cd: float = 0.0
var _flash: float = 0.0
var _immune_flash: float = 0.0
var _player = null
var _scythe = null
var _trigger = null
var _waiting_for_dialogue: bool = false
var _arena_center: Vector2 = Vector2.ZERO
var _hp_label: Label = null


func _ready() -> void:
	if game_state == null and is_inside_tree():
		game_state = get_node_or_null("/root/GameState")
	vigor = MAX_VIGOR
	add_to_group("hittable")
	_arena_center = global_position
	_hp_label = Label.new()
	_hp_label.name = "HPLabel"
	_hp_label.position = Vector2(-24, -70)
	_hp_label.add_theme_font_size_override("font_size", 18)
	add_child(_hp_label)
	_refresh_hp()
	_trigger = get_parent().get_node_or_null(TRIGGER_NAME) if get_parent() != null else null
	if _trigger != null and _trigger.has_signal("activated"):
		_trigger.activated.connect(_on_trigger_activated)
	_resolve_player()
	_resolve_scythe()


func _resolve_player() -> void:
	if _player != null and is_instance_valid(_player):
		return
	if not is_inside_tree():
		return
	_player = get_tree().get_first_node_in_group("player")
	if _player != null and _player.has_signal("player_died"):
		if not _player.player_died.is_connected(_on_player_died):
			_player.player_died.connect(_on_player_died)


func _resolve_scythe() -> void:
	if _scythe != null and is_instance_valid(_scythe):
		return
	if not is_inside_tree():
		return
	_scythe = get_tree().get_first_node_in_group("scythe")
	if _scythe != null and _scythe.has_signal("swing_whiffed"):
		if not _scythe.swing_whiffed.is_connected(_on_swing_whiffed):
			_scythe.swing_whiffed.connect(_on_swing_whiffed)


func _physics_process(delta: float) -> void:
	_resolve_player()
	_resolve_scythe()
	_flash = maxf(0.0, _flash - delta * 4.0)
	_immune_flash = maxf(0.0, _immune_flash - delta * 3.0)
	if _waiting_for_dialogue:
		if _trigger == null or not _trigger.has_method("is_dialogue_open") or not _trigger.is_dialogue_open():
			_waiting_for_dialogue = false
			_begin_intro()
		return
	match _phase:
		Phase.FIGHTING:
			_mirror(delta)
			_strike_cd = maxf(0.0, _strike_cd - delta)
			if _strike_cd <= 0.0:
				_mirror_strike()
		Phase.RECONSTITUTING:
			_reconst_t += delta
			if _reconst_t >= 1.5:
				_finish_reconstitute()
	queue_redraw()


## Mirror-boss: Harrow reflects the player's position across the arena
## center. "You fight yourself."
func _mirror(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var want: Vector2 = _arena_center * 2.0 - _player.global_position
	# Keep him inside a sane arena radius.
	var off: Vector2 = want - _arena_center
	if off.length() > 320.0:
		want = _arena_center + off.normalized() * 320.0
	global_position = global_position.lerp(want, 0.08)


func _mirror_strike() -> void:
	# Answers aggression with aggression: a mirrored strike telegraph
	# that lands where the player is standing.
	_strike_cd = 2.4
	if _player == null or not is_instance_valid(_player):
		return
	if not _player.has_method("take_damage_from"):
		return
	if (_player.global_position - global_position).length() <= 150.0:
		_player.take_damage_from(1, self, ["dark"])


## Despair Feed: every missed scythe swing feeds him 10 Vigor.
func _on_swing_whiffed() -> void:
	if _phase != Phase.FIGHTING:
		return
	if vigor <= 0:
		return
	vigor = mini(MAX_VIGOR, vigor + DESPAIR_FEED_HEAL)
	_refresh_hp()


## The scythe hits Harrow directly. Tendrils gate all damage.
func take_hit(dmg: int, _from_dir: Vector2) -> void:
	if _phase != Phase.FIGHTING:
		return
	if vigor <= 0:
		return
	if _tendrils_alive() > 0:
		# Invulnerable while any tendril lives. The gate holds.
		_immune_flash = 1.0
		return
	vigor = maxi(0, vigor - dmg)
	_flash = 1.0
	_refresh_hp()
	if vigor <= 0:
		_win()
	elif not _reconstituted and vigor <= RECONSTITUTE_AT:
		_begin_reconstitute()


func _tendrils_alive() -> int:
	var n := 0
	for t in _tendrils:
		if is_instance_valid(t) and t.is_alive():
			n += 1
	return n


func _begin_reconstitute() -> void:
	_reconstituted = true
	_phase = Phase.RECONSTITUTING
	_reconst_t = 0.0
	reconstituted.emit()


func _finish_reconstitute() -> void:
	vigor = mini(MAX_VIGOR, vigor + RECONSTITUTE_HEAL)
	_refresh_hp()
	if vigor > 0:
		_phase = Phase.FIGHTING


func is_alive() -> bool:
	return vigor > 0


func _on_trigger_activated(_obj) -> void:
	if _phase != Phase.IDLE:
		return
	if game_state != null and game_state.has_method("get_flag"):
		if bool(game_state.get_flag(VICTORY_FLAG)):
			return
	_waiting_for_dialogue = true


func _begin_intro() -> void:
	_spawn_tendrils()
	_phase = Phase.INTRO
	fight_started.emit()
	await get_tree().create_timer(1.2).timeout
	if _phase == Phase.INTRO:
		_phase = Phase.FIGHTING


func _spawn_tendrils() -> void:
	_clear_tendrils()
	var offsets := [Vector2(-200, -160), Vector2(200, -160), Vector2(0, -280)]
	for off in offsets:
		var t: CharacterBody2D = TendrilScript.new()
		t.position = _arena_center + off
		# Tendrils belong to the fight, not the mirror — parent to the
		# fight's parent so they don't follow Harrow's transform.
		get_parent().add_child(t)
		t.died.connect(_on_tendril_died)
		_tendrils.append(t)


func _clear_tendrils() -> void:
	for t in _tendrils:
		if is_instance_valid(t):
			t.queue_free()
	_tendrils.clear()


func _on_tendril_died(_tendril) -> void:
	# The gate weakens as tendrils fall. Nothing else needed — the
	# invulnerability check reads the live count.
	pass


func _win() -> void:
	_phase = Phase.WON
	_clear_tendrils()
	if game_state != null and game_state.has_method("set_flag"):
		game_state.set_flag(VICTORY_FLAG, true)
	if _trigger != null:
		_trigger.set_deferred("monitoring", false)
		_trigger.set_deferred("monitorable", false)
	fight_won.emit()


func _on_player_died() -> void:
	if _phase != Phase.FIGHTING and _phase != Phase.INTRO and _phase != Phase.RECONSTITUTING:
		return
	# "It's a memory" — full reset, no game over.
	_phase = Phase.IDLE
	vigor = MAX_VIGOR
	_reconstituted = false
	_strike_cd = 0.0
	_clear_tendrils()
	_refresh_hp()
	fight_reset.emit()
	await get_tree().create_timer(1.5).timeout
	if _phase == Phase.IDLE:
		_begin_intro()


## Test hook.
func debug_start() -> void:
	_waiting_for_dialogue = false
	_begin_intro()


func is_fighting() -> bool:
	return _phase == Phase.FIGHTING or _phase == Phase.INTRO or _phase == Phase.RECONSTITUTING


func _refresh_hp() -> void:
	if _hp_label != null:
		var gate := " [GATED]" if _tendrils_alive() > 0 else ""
		_hp_label.text = "%d%s" % [vigor, gate]


func _draw() -> void:
	# Greybox: dark mirror-figure. Immune flash while gated.
	var col := Color(0.16, 0.14, 0.22)
	if _flash > 0.0:
		col = Color.WHITE.lerp(col, 1.0 - _flash)
	if _immune_flash > 0.0:
		col = col.lerp(Color(0.5, 0.7, 1.0), _immune_flash * 0.6)
	draw_colored_polygon(
		PackedVector2Array([Vector2(-16, 34), Vector2(16, 34), Vector2(10, -40), Vector2(-10, -40)]),
		col
	)
	# Hollow eyes — the mirror stares back.
	draw_circle(Vector2(-6, -22), 3.0, Color(0.7, 0.9, 1.0, 0.9))
	draw_circle(Vector2(6, -22), 3.0, Color(0.7, 0.9, 1.0, 0.9))
	# Reconstitute telegraph: rising rings.
	if _phase == Phase.RECONSTITUTING:
		var f := clampf(_reconst_t / 1.5, 0.0, 1.0)
		draw_arc(Vector2.ZERO, 30.0 + f * 90.0, 0.0, TAU, 32, Color(0.4, 1.0, 0.5, 0.7 * (1.0 - f)), 3.0)
