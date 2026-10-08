extends Node2D
## 1v1 tactical battle scene for Reaper's Reaper (greybox, no art).
##
## Setup comes from battle_config (injected, e.g. headless tests) or from
## BattleManager.pending (autoload) in the live game:
##   {player_creature_id, player_level, player_hp, player_party_index,
##    enemy_creature_id, enemy_level, is_boss, victory_flag,
##    return_room, return_pos}
##
## Flow: intro -> command menu (FIGHT/CATCH/SWITCH/ITEM/FLEE) -> ability
## select -> player acts -> enemy AI acts -> end-of-turn (WILT ticks) ->
## repeat. CATCH is wild-only: a Soul Snare is thrown (consumed), the catch
## rate rises as the target's HP falls and with WILT. Bosses can't be caught.
## TRAINER mode: the foe fields a sequential roster (sent out in order as
## each faints, no AI switching); the player may SWITCH conscious party
## members mid-battle (costs the turn); no fleeing, no catching, reward
## Soul Credits on victory, one-time via victory_flag.
## Win: XP to the battler's party entry (level-ups apply), victory_flag
## set, battler HP synced back to the party, return to room. Lose: blackout
## -> respawn at last shrine, party healed. Flee works vs wild, fails vs boss
## and trainer battles.
##
## Catch formula (tuning placeholder, not canon):
##   rate = base_catch_rate * (1.5 - hp_fraction) + 0.15 (if wilted),
##   clamped to [0.01, 0.95]. Full HP -> 0.5x base; 1 HP -> ~1.5x base.
##
## NOTE: intentionally no class_name (project convention). UI is built in
## code (guarded against double _ready) so the .tscn stays trivial and the
## logic is fully testable headless. Inject game_state / battle_manager /
## scene_changer and set fast_mode=true in tests to skip tween waits.

const BattleUnit = preload("res://scripts/battle_unit.gd")
const CreatureData = preload("res://scripts/creature_data.gd")
const CreatureAI = preload("res://scripts/creature_ai.gd")
const PartyScript = preload("res://scripts/party.gd")
const StorageScript = preload("res://scripts/storage.gd")
const ContractsScript = preload("res://scripts/contracts.gd")
const SporeNeedleScript = preload("res://scripts/spore_needle.gd")

const ROOM_SCENES := {
	"p1": "res://scenes/room_p1.tscn",
	"p3": "res://scenes/room_p3.tscn",
	"c1": "res://scenes/room_c1.tscn",
}
const FALLBACK_SCENE := "res://scenes/room_p1.tscn"

enum State { INTRO, COMMAND, ABILITIES, ITEMS, ITEM_TARGET, SWITCH, BUSY, END }

## Inner placeholder critter: a colored circle. Art comes later.
class CreatureDot:
	extends Node2D
	var color := Color(0.6, 0.6, 0.6)
	var radius := 56.0

	func _draw() -> void:
		draw_circle(Vector2.ZERO, radius, color)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 32, Color(0, 0, 0, 0.6), 4.0)


## Battle creature visual: real sprite when assets/creatures/<id>.png exists,
## CreatureDot fallback otherwise (Snapling has no art yet — greybox).
## Returns a Node2D positioned at `pos`; caller sets .position like before.
const CREATURE_ART_DIR := "res://assets/creatures/"
static func make_creature_visual(creature_id: String, pos: Vector2, fallback_color: Color, fallback_radius: float) -> Node2D:
	var path := CREATURE_ART_DIR + creature_id + ".png"
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			var spr := Sprite2D.new()
			spr.texture = ImageTexture.create_from_image(img)
			# 384px cell, figure ~256px — scale to ~200px battle size.
			spr.scale = Vector2(0.55, 0.55)
			spr.position = pos
			return spr
	var dot := CreatureDot.new()
	dot.color = fallback_color
	dot.radius = fallback_radius
	dot.position = pos
	return dot


## Swap the player/enemy visual mid-battle (switches, trainer send-outs).
func _refresh_player_visual(creature_id: String) -> void:
	if _player_dot != null:
		_player_dot.queue_free()
	_player_dot = make_creature_visual(creature_id, Vector2(320, 380), Color(0.45, 0.65, 0.95), 56.0)
	add_child(_player_dot)


func _refresh_enemy_visual(creature_id: String) -> void:
	if _enemy_dot != null:
		_enemy_dot.queue_free()
	_enemy_dot = make_creature_visual(creature_id, Vector2(960, 340), Color(0.85, 0.45, 0.5) if _is_boss else Color(0.55, 0.75, 0.45), 72.0 if _is_boss else 56.0)
	add_child(_enemy_dot)

var game_state = null            # GameState autoload or injected
var battle_manager = null        # BattleManager autoload or injected stub
var battle_config: Dictionary = {}  # injected config wins over battle_manager
var scene_changer = null         # callable(path) override for tests
var fast_mode := false           # skip tween waits (headless tests)

var _built := false
var _state: int = State.INTRO
var _cfg: Dictionary = {}
var _player: RefCounted = null
var _enemy: RefCounted = null
var _is_boss := false
## Trainer mode: sequential foe roster, player switching, no flee/catch.
var _is_trainer := false
## Index into enemy_roster of the currently active foe (trainer mode).
var _roster_idx := 0
## True when the switch menu was forced by the player's creature fainting
## (no enemy turn afterwards); false for a voluntary mid-battle switch.
var _forced_switch := false

var _player_dot = null
var _enemy_dot = null
var _player_bar: ProgressBar = null
var _enemy_bar: ProgressBar = null
var _player_label: Label = null
var _enemy_label: Label = null
var _msg: Label = null
## Act 2 AI state: player's last ability (for Echomarrow's Echo).
var _foe_last_ability := ""
var _menu: VBoxContainer = null
var _busy := false
var _decoy_active := false  # Silver Bell Bloom: the foe's next attack is wasted
## Seamless (in-overworld) mode: instead of changing scenes on resolution,
## the battle emits battle_resolved and the host layer dismisses it.
## Set by the seamless battle host; default false = classic scene flow.
var embedded_mode := false
## Emitted in embedded mode when the battle resolves: "win", "flee", "lose".
signal battle_resolved(outcome: String)
## Outcome carried into _goto so embedded mode can report it.
var _pending_outcome := ""
## Daily Hunt wiring: set when pending/battle_config carries "daily_hunt"
## and a hunt is active in GameState. Tracks fight duration and damage
## taken; victory calls DailyHunts.complete_hunt, defeat abandons it.
var _hunt_active := false
var _hunt_start_msec := 0
var _hunt_damage := 0
var _hunt_turns := 0
var _daily_mods := {}


func _ready() -> void:
	if _built:
		return
	_built = true
	CreatureAI.reset_battle_state()
	_foe_last_ability = ""
	_resolve_refs()
	_read_config()
	_build_ui()
	_start_battle.call_deferred()


func _resolve_refs() -> void:
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	if battle_manager == null:
		battle_manager = get_node_or_null("/root/BattleManager")


func _read_config() -> void:
	if not battle_config.is_empty():
		_cfg = battle_config
	elif battle_manager != null:
		# battle_manager may be the autoload Node or a plain Dictionary stub.
		if battle_manager is Dictionary:
			_cfg = battle_manager.get("pending", {})
		elif battle_manager.get("pending") is Dictionary:
			_cfg = battle_manager.get("pending")
		else:
			_cfg = {}
	_cfg = {
		"player_creature_id": str(_cfg.get("player_creature_id", "snapling")),
		"player_level": int(_cfg.get("player_level", 5)),
		"player_hp": int(_cfg.get("player_hp", -1)),
		"player_party_index": int(_cfg.get("player_party_index", -1)),
		"enemy_creature_id": str(_cfg.get("enemy_creature_id", "bellowscap")),
		"enemy_level": int(_cfg.get("enemy_level", 3)),
		"is_boss": bool(_cfg.get("is_boss", false)),
		"is_trainer": bool(_cfg.get("is_trainer", false)),
		"trainer_id": str(_cfg.get("trainer_id", "")),
		"trainer_name": str(_cfg.get("trainer_name", "")),
		"enemy_roster": _cfg.get("enemy_roster", []),
		"reward_credits": int(_cfg.get("reward_credits", 0)),
		"post_dialogue": _cfg.get("post_dialogue", []),
		"post_dialogue_loss": _cfg.get("post_dialogue_loss", []),
		"spare_on_loss": bool(_cfg.get("spare_on_loss", false)),
		"rivalry_flag": str(_cfg.get("rivalry_flag", "")),
		"victory_flag": str(_cfg.get("victory_flag", "")),
		"daily_hunt": bool(_cfg.get("daily_hunt", false)),
		"return_room": str(_cfg.get("return_room", "p1")),
		"return_pos": _cfg.get("return_pos", Vector2.ZERO),
	}
	_is_boss = bool(_cfg["is_boss"])
	_is_trainer = bool(_cfg["is_trainer"])
	if _is_trainer and not (_cfg["enemy_roster"] is Array):
		_cfg["enemy_roster"] = []


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.03, 0.06)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_player_dot = make_creature_visual(str(_cfg["player_creature_id"]), Vector2(320, 380), Color(0.45, 0.65, 0.95), 56.0)
	add_child(_player_dot)

	_enemy_dot = make_creature_visual(str(_cfg["enemy_creature_id"]), Vector2(960, 340), Color(0.85, 0.45, 0.5) if _is_boss else Color(0.55, 0.75, 0.45), 72.0 if _is_boss else 56.0)
	add_child(_enemy_dot)

	_player_label = _make_label(Vector2(320, 500))
	_enemy_label = _make_label(Vector2(960, 470))
	_player_bar = _make_bar(Vector2(200, 540))
	_enemy_bar = _make_bar(Vector2(840, 510))

	# Message box (bottom).
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -220
	panel.offset_left = 40
	panel.offset_right = -40
	panel.offset_bottom = -40
	add_child(panel)
	_msg = Label.new()
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.add_theme_font_size_override("font_size", 26)
	panel.add_child(_msg)

	# Command menu (bottom-right, above the message box).
	_menu = VBoxContainer.new()
	_menu.position = Vector2(980, 470)
	_menu.add_theme_constant_override("separation", 6)
	add_child(_menu)


func _make_label(pos: Vector2) -> Label:
	var l := Label.new()
	l.position = pos - Vector2(120, 0)
	l.size = Vector2(240, 36)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 24)
	add_child(l)
	return l


func _make_bar(pos: Vector2) -> ProgressBar:
	var b := ProgressBar.new()
	b.position = pos
	b.size = Vector2(240, 22)
	b.show_percentage = false
	add_child(b)
	return b


# --- Battle setup ----------------------------------------------------------

func _start_battle() -> void:
	_player = BattleUnit.new(str(_cfg["player_creature_id"]), int(_cfg["player_level"]))
	# Restore the party member's runtime HP (the lead entered at its stored
	# HP, not full). -1 means "not a party battle" (tests) -> full HP.
	var php: int = int(_cfg["player_hp"])
	if php >= 0:
		_player.hp = mini(_player.max_hp, php)
	_enemy = BattleUnit.new(str(_cfg["enemy_creature_id"]), int(_cfg["enemy_level"]))
	_refresh_units()
	_init_daily_hunt()
	_init_twitch()
	var foe := "BOSS " if _is_boss else "Wild "
	if _is_trainer:
		await _say_wait(str(_cfg["trainer_name"]) + " wants to battle!")
		foe = ""
	await _say_wait(foe + _enemy.display_name + " appeared!")
	_show_commands()


## Daily Hunt setup: reads the modifier flags the board set and applies
## them to the player's unit. no_items and slow_start are enforced by the
## battle flow; no_armor/frail/heavy_hits ride on the unit's multipliers.
## bloom_double and invisible_foes need systems that don't exist yet.
func _init_daily_hunt() -> void:
	_hunt_active = false
	_daily_mods = {}
	if not bool(_cfg.get("daily_hunt", false)):
		return
	if game_state == null:
		return
	var DailyHunts = load("res://scripts/daily_hunts.gd")
	if not DailyHunts.is_active(game_state):
		return
	_hunt_active = true
	_hunt_start_msec = Time.get_ticks_msec()
	_hunt_damage = 0
	_hunt_turns = 0
	for mid in ["no_armor", "frail", "heavy_hits", "slow_start", "no_items"]:
		_daily_mods[mid] = DailyHunts.has_modifier(game_state, mid)
	if bool(_daily_mods.get("no_armor", false)):
		_player.mod_no_armor = true
	if bool(_daily_mods.get("frail", false)):
		_player.mod_incoming_mult = 2.0
	if bool(_daily_mods.get("heavy_hits", false)):
		_player.mod_outgoing_mult = 1.5
		_player.mod_incoming_mult = maxf(_player.mod_incoming_mult, 1.25)


## Twitch viewer-vote effects (one-shot flags from Twitch.apply_effect).
## heavy_handed rides on the enemy's outgoing multiplier for this fight.
## bonus_loot is consumed on victory in _win(); rare_spawn, hard_encounter
## and swarm are consumed by wild_zone at encounter time; full_heal applies
## immediately in Twitch.apply_effect (no flag).
func _init_twitch() -> void:
	if game_state == null or _enemy == null:
		return
	if bool(game_state.get_stat("twitch_heavy_handed", false)):
		game_state.set_stat("twitch_heavy_handed", false)
		_enemy.mod_outgoing_mult = 1.5
		print("[TWITCH] Heavy Hands: enemies hit 50% harder this fight")


## Twitch Rich Veins: read-and-clear the one-shot bonus-loot flag,
## returning the Soul Credit bonus for this victory (0 when unset).
## [WIRING] Wild victories don't normally pay credits — the blessing
## conjures level-scaled loot, doubled per the blessing's text. For
## trainers the bonus equals the base reward (the caller adds it, so
## the total is doubled).
func _consume_twitch_loot() -> int:
	if game_state == null:
		return 0
	if not bool(game_state.get_stat("twitch_bonus_loot", false)):
		return 0
	game_state.set_stat("twitch_bonus_loot", false)
	if _is_trainer:
		return int(_cfg.get("reward_credits", 0))
	if _enemy != null:
		return int(_enemy.level) * 10
	return 0


## Slow Start: for the first 3 turns of a hunt battle, the player acts
## last regardless of speed. Pure check so tests can hit it directly.
func _hunt_forces_last() -> bool:
	return _hunt_active and bool(_daily_mods.get("slow_start", false)) and _hunt_turns <= 3


func _refresh_units() -> void:
	_player_label.text = "%s  Lv%d" % [_player.display_name, _player.level]
	_enemy_label.text = "%s  Lv%d" % [_enemy.display_name, _enemy.level]
	_player_bar.max_value = _player.max_hp
	_player_bar.value = _player.hp
	_enemy_bar.max_value = _enemy.max_hp
	_enemy_bar.value = _enemy.hp


# --- Menus -----------------------------------------------------------------

func _clear_menu() -> void:
	for c in _menu.get_children():
		c.queue_free()


func _show_commands() -> void:
	if _state == State.END:
		return
	_state = State.COMMAND
	_clear_menu()
	_add_button("FIGHT", false, choose_fight)
	_add_button("CATCH", not _can_catch(), try_catch)
	_add_button("SWITCH", _switch_candidates().is_empty(), choose_switch)
	_add_button("ITEM", false, choose_item)
	_add_button("FLEE", false, try_flee)


## Party indices with HP > 0 that aren't the active battler. Empty when
## there is no GameState (tests without a party) or nobody else can fight.
func _switch_candidates() -> Array:
	var out: Array = []
	if game_state == null:
		return out
	var active := int(_cfg.get("player_party_index", -1))
	if active < 0:
		return out  # not a party-backed battle (tests): no switching
	var n := PartyScript.size(game_state)
	for i in n:
		if i == active:
			continue
		var e := PartyScript.get_entry(game_state, i)
		if e.is_empty():
			continue
		if int(e.get("current_hp", 0)) > 0:
			out.append(i)
	return out


func choose_switch() -> void:
	if _state != State.COMMAND or _busy:
		return
	if _switch_candidates().is_empty():
		return
	_state = State.SWITCH
	_clear_menu()
	_show_switch_menu()


func _show_switch_menu() -> void:
	for i in _switch_candidates():
		var e := PartyScript.get_entry(game_state, i)
		var nm := str(e.get("nickname", ""))
		if nm == "":
			nm = str(CreatureData.get_creature(str(e.get("creature_id", ""))).get("name", "?"))
		_add_button("%s  Lv%d  %d/%d" % [nm, int(e.get("level", 1)),
			int(e.get("current_hp", 0)), PartyScript.max_hp_for(e)],
			false, _on_switch_pick.bind(i))
	_add_button("BACK", false, _back_from_switch)


func _back_from_switch() -> void:
	if _forced_switch:
		return  # fainted battler must be replaced; no backing out
	_show_commands()


## Swap the active battler. Costs the turn (the foe acts afterwards) unless
## the switch was forced by the player's creature fainting.
func _on_switch_pick(idx: int) -> void:
	if _state != State.SWITCH or _busy:
		return
	if not _switch_candidates().has(idx):
		return
	_state = State.BUSY
	_busy = true
	_clear_menu()
	var forced := _forced_switch
	_forced_switch = false
	_sync_party_hp()
	var e := PartyScript.get_entry(game_state, idx)
	_player = BattleUnit.new(str(e.get("creature_id", "")), int(e.get("level", 1)))
	_player.hp = mini(_player.max_hp, int(e.get("current_hp", 0)))
	_cfg["player_party_index"] = idx
	_cfg["player_creature_id"] = str(e.get("creature_id", ""))
	_refresh_player_visual(str(e.get("creature_id", "")))
	_refresh_units()
	await _say_wait("Go, " + _player.display_name + "!")
	if forced:
		_busy = false
		_show_commands()
		return
	await _enemy_act()
	if _player.fainted:
		await _on_player_fainted()
		_busy = false
		return
	await _end_of_turn()
	_busy = false
	_show_commands()


## CATCH is offered only for wild battles, with a snare in hand. Bosses and
## trainers' creatures are uncatchable. A full party no longer refuses — the
## catch goes to the Soul Vault (storage); only a full vault refuses without
## consuming a snare.
func _can_catch() -> bool:
	if _is_boss or _is_trainer:
		return false
	if game_state == null:
		return false
	if not game_state.has_method("get_item_count"):
		return false
	if _snare_to_throw().is_empty():
		return false
	if PartyScript.size(game_state) < PartyScript.MAX_SIZE:
		return true
	return not StorageScript.is_full(game_state)


## Which snare to throw: moonlit first (strictly better catch bonus),
## else the plain soul snare. "" when the player has neither.
func _snare_to_throw() -> String:
	if game_state.get_item_count("moonlit_snare") > 0:
		return "moonlit_snare"
	if game_state.get_item_count("soul_snare") > 0:
		return "soul_snare"
	return ""


## Pure catch-rate math (static for headless tests):
##   rate = base * (1.5 - hp_fraction) + 0.15 if wilted, clamped [0.01, 0.95].
static func catch_rate_for(base: float, hp: int, max_hp: int, wilted: bool) -> float:
	var frac := clampf(float(hp) / float(maxi(1, max_hp)), 0.0, 1.0)
	var rate := base * (1.5 - frac)
	if wilted:
		rate += 0.15
	return clampf(rate, 0.01, 0.95)


func try_catch() -> void:
	if _state != State.COMMAND or _busy:
		return
	if not _can_catch():
		return
	_state = State.BUSY
	_busy = true
	_clear_menu()
	var snare_id := _snare_to_throw()
	game_state.use_item(snare_id)
	var snare: Dictionary = CreatureData.get_item(snare_id)
	var snare_name := str(snare.get("name", "Snare"))
	var foe_name: String = _enemy.display_name
	await _say_wait("You threw a " + snare_name + "!")
	_throw_snare_anim()
	await _wait(0.6)
	var c: Dictionary = CreatureData.get_creature(_enemy.creature_id)
	var base := float(c.get("catch_rate", 0.3))
	var wilted := int(_enemy.statuses.get("wilt", 0)) > 0
	var rate := catch_rate_for(base, _enemy.hp, _enemy.max_hp, wilted)
	rate = clampf(rate + float(snare.get("catch_bonus", 0.0)), 0.01, 0.95)
	if randf() < rate:
		await _catch_success(foe_name)
		return
	# Failed catch: the throw consumed the player's turn.
	_shake_free_anim()
	await _say_wait("Oh no! " + foe_name + " broke free!")
	await _enemy_act()
	if _player.fainted:
		await _on_player_fainted()
		_busy = false
		return
	await _end_of_turn()
	_busy = false
	_show_commands()


func _catch_success(foe_name: String) -> void:
	_state = State.END
	_clear_menu()
	_settle_anim()
	await _say_wait("Gotcha! " + foe_name + " was caught!")
	if not PartyScript.add_creature(game_state, _enemy.creature_id, _enemy.level):
		# Party full: the catch goes to the Soul Vault instead.
		var entry: Dictionary = PartyScript.make_entry(_enemy.creature_id, _enemy.level)
		StorageScript.deposit_entry(game_state, entry)
		await _say_wait("Sent to the " + StorageScript.VAULT_NAME + "!")
	var stats = get_node_or_null("/root/Stats")
	if stats != null and stats.has_method("record_catch"):
		stats.record_catch()
	if game_state != null and _enemy != null:
		ContractsScript.record_catch(game_state, str(_enemy.creature_id))
	# Catching the hunt target completes the hunt too.
	if _hunt_active:
		await _complete_daily_hunt()
	print("[BATTLE] caught ", _enemy.creature_id, " lv", _enemy.level)
	await _wait(0.8)
	_return_to_room()


func _add_button(text: String, disabled: bool, on_press: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = disabled
	b.custom_minimum_size = Vector2(240, 44)
	b.add_theme_font_size_override("font_size", 24)
	if not disabled:
		b.pressed.connect(on_press)
	_menu.add_child(b)
	if _menu.get_child_count() == 1 and not disabled:
		b.grab_focus()


func choose_fight() -> void:
	if _state != State.COMMAND or _busy:
		return
	_state = State.ABILITIES
	_clear_menu()
	var ids: Array = (_player.ability_ids as Array).slice(0, 4)
	if ids.is_empty():
		_say("No abilities! (this should not happen)")
		_show_commands()
		return
	for ab_id in ids:
		var ab: Dictionary = CreatureData.get_ability(str(ab_id))
		_add_button(str(ab.get("name", ab_id)), false, _on_ability.bind(str(ab_id)))
	_add_button("BACK", false, _show_commands)


func _on_ability(ab_id: String) -> void:
	if _state != State.ABILITIES or _busy:
		return
	_run_turn(ab_id)


func try_flee() -> void:
	if _state != State.COMMAND or _busy:
		return
	_busy = true
	_clear_menu()
	if _is_boss or _is_trainer:
		await _say_wait("Can't flee from this foe!")
		_busy = false
		_show_commands()
		return
	if int(_player.statuses.get("rootbound", 0)) > 0:
		await _say_wait("Held fast! Can't flee!")
		_busy = false
		_show_commands()
		return
	await _say_wait("Got away safely!")
	_busy = false
	_pending_outcome = "flee"
	_return_to_room()


# --- Items -------------------------------------------------------------------

## Canonical battle-item menu order (stable UI). Snares are excluded here —
## they live in the CATCH menu; Mollosar-vigor supplies aren't creature items.
const BATTLE_ITEM_ORDER := [
	"grave_moss_poultice", "sap_draught", "blossom_nectar",
	"mandrake_tea", "ashen_salt", "second_bell",
	"thorn_pod", "spore_sac", "gravebind_snare",
	"silver_bell_bloom", "ironwood_bark",
]


func choose_item() -> void:
	if _state != State.COMMAND or _busy:
		return
	# No Provisions (daily hunt modifier): items are disabled for the fight.
	if _hunt_active and bool(_daily_mods.get("no_items", false)):
		_say("No Provisions today — items are disabled.")
		return
	_back_to_items()


func _back_to_items() -> void:
	_state = State.ITEMS
	_clear_menu()
	_show_items()


## Pure context check for one item in this battle: {usable, reason}.
## Testable headless without touching the menu.
func _item_context(item_id: String) -> Dictionary:
	var item: Dictionary = CreatureData.get_item(item_id)
	var effect: Dictionary = item.get("effect", {})
	var etype := str(effect.get("type", ""))
	if game_state == null or not game_state.has_method("get_item_count"):
		return {"usable": false, "reason": "no pack"}
	if game_state.get_item_count(item_id) <= 0:
		return {"usable": false, "reason": "none left"}
	match etype:
		"heal_hp":
			if _player.hp >= _player.max_hp:
				return {"usable": false, "reason": "HP full"}
			return {"usable": true, "reason": ""}
		"heal_full_party":
			# Blossom Nectar: "it takes a full minute to drink" — docs §1.
			return {"usable": false, "reason": "out of combat only"}
		"cure_status":
			for sid in (effect.get("statuses", []) as Array):
				if _player.statuses.has(str(sid)):
					return {"usable": true, "reason": ""}
			return {"usable": false, "reason": "no such status"}
		"revive":
			if _fainted_party_indices().is_empty():
				return {"usable": false, "reason": "none fainted"}
			return {"usable": true, "reason": ""}
		"fixed_damage", "inflict_status", "stat_buff":
			return {"usable": true, "reason": ""}
		"decoy":
			if _decoy_active:
				return {"usable": false, "reason": "decoy already out"}
			return {"usable": true, "reason": ""}
	return {"usable": false, "reason": "unusable here"}


func _show_items() -> void:
	var any := false
	for item_id in BATTLE_ITEM_ORDER:
		if game_state.get_item_count(item_id) <= 0:
			continue
		var item: Dictionary = CreatureData.get_item(item_id)
		var ctx: Dictionary = _item_context(item_id)
		var label := "%s x%d" % [str(item.get("name", item_id)), game_state.get_item_count(item_id)]
		var usable := bool(ctx.get("usable", false))
		if not usable:
			label += " (" + str(ctx.get("reason", "unusable")) + ")"
		_add_button(label, not usable, _on_item.bind(item_id))
		any = true
	if not any:
		_say("The pack is empty.")
	_add_button("BACK", false, _show_commands)


func _on_item(item_id: String) -> void:
	if _state != State.ITEMS or _busy:
		return
	var ctx: Dictionary = _item_context(item_id)
	if not bool(ctx.get("usable", false)):
		return
	var effect: Dictionary = (CreatureData.get_item(item_id) as Dictionary).get("effect", {})
	if str(effect.get("type", "")) == "revive":
		_state = State.ITEM_TARGET
		_clear_menu()
		_show_revive_targets(item_id)
		return
	_use_item(item_id, -1)


## Fainted party members (excluding the active battler) for Second Bell.
func _fainted_party_indices() -> Array:
	var out: Array = []
	if game_state == null:
		return out
	var n := PartyScript.size(game_state)
	var active := int(_cfg.get("player_party_index", -1))
	for i in n:
		var e := PartyScript.get_entry(game_state, i)
		if e.is_empty() or i == active:
			continue
		if int(e.get("current_hp", 0)) <= 0:
			out.append(i)
	return out


func _show_revive_targets(item_id: String) -> void:
	for i in _fainted_party_indices():
		var e := PartyScript.get_entry(game_state, i)
		var nm := str(e.get("nickname", ""))
		if nm == "":
			nm = str(CreatureData.get_creature(str(e.get("creature_id", ""))).get("name", "?"))
		_add_button("%s  Lv%d" % [nm, int(e.get("level", 1))], false, _on_revive_target.bind(item_id, i))
	_add_button("BACK", false, _back_to_items)


func _on_revive_target(item_id: String, pidx: int) -> void:
	if _state != State.ITEM_TARGET or _busy:
		return
	_use_item(item_id, pidx)


## Use a battle item. Costs the turn: the enemy acts afterwards (unless the
## item ended the battle). Greybox flash + message for every effect.
func _use_item(item_id: String, target_idx: int) -> void:
	_state = State.BUSY
	_busy = true
	_clear_menu()
	var item: Dictionary = CreatureData.get_item(item_id)
	var effect: Dictionary = item.get("effect", {})
	if not game_state.use_item(item_id):
		_say("No " + str(item.get("name", item_id)) + " left!")
		_busy = false
		_show_commands()
		return
	await _say_wait("Used " + str(item.get("name", item_id)) + "!")
	_item_flash_anim()
	var etype := str(effect.get("type", ""))
	match etype:
		"heal_hp":
			var got: int = _player.heal(int(effect.get("amount", 0)))
			_update_bar(_player_bar, _player.hp)
			await _say_wait(_player.display_name + " recovered " + str(got) + " HP!")
		"cure_status":
			var n: int = _player.cure_statuses(effect.get("statuses", []))
			if n > 0:
				await _say_wait(_player.display_name + " was cured!")
			else:
				await _say_wait("It had no effect…")
		"revive":
			var e := PartyScript.get_entry(game_state, target_idx)
			var maxhp := PartyScript.max_hp_for(e)
			var to: int = maxi(1, int(round(float(maxhp) * float(effect.get("hp_fraction", 0.5)))))
			PartyScript.set_hp(game_state, target_idx, to)
			var nm := str(CreatureData.get_creature(str(e.get("creature_id", ""))).get("name", "?"))
			await _say_wait("The bell rings… " + nm + " stirs at " + str(to) + " HP!")
		"fixed_damage":
			var dealt: int = _enemy.take_fixed_damage(int(effect.get("amount", 25)))
			_damage_number(_enemy_dot.position, dealt)
			_update_bar(_enemy_bar, _enemy.hp)
			await _say_wait("The thorn pod bursts for " + str(dealt) + " damage!")
		"inflict_status":
			_enemy.apply_status(str(effect.get("status", "")), int(effect.get("turns", 3)))
			var what := str(effect.get("status", ""))
			if what == "spore_fever":
				what = "spore-fever"
			await _say_wait(_enemy.display_name + " is afflicted with " + what + "!")
		"decoy":
			_decoy_active = true
			await _say_wait("A Silver Bell Bloom shimmers — the foe's next attack will go wide!")
		"stat_buff":
			_player.temp_mods = {
				"atk_mult": float(effect.get("atk_mult", 1.0)),
				"def_mult": float(effect.get("def_mult", 1.0)),
				"spd_mult": float(effect.get("spd_mult", 1.0)),
				"turns": int(effect.get("turns", 3)),
			}
			await _say_wait(_player.display_name + " bites down on ironwood bark!")
	if _enemy.fainted:
		await _on_enemy_fainted()
		_busy = false
		return
	await _enemy_act()
	if _player.fainted:
		await _on_player_fainted()
		_busy = false
		return
	await _end_of_turn()
	_busy = false
	_show_commands()


## Greybox item-use flash on the player's creature. fast_mode skips it.
func _item_flash_anim() -> void:
	if fast_mode or _player_dot == null:
		return
	var flash := CreatureDot.new()
	flash.color = Color(0.5, 1.0, 0.6, 0.55)
	flash.radius = 95.0
	flash.position = _player_dot.position
	add_child(flash)
	var tw := create_tween()
	tw.tween_property(flash, "modulate:a", 0.0, 0.45)
	tw.tween_callback(flash.queue_free)


# --- Faint handling --------------------------------------------------------

## The foe went down. In trainer mode the next roster creature is sent out
## in order; otherwise (or on the last one) the battle is won. XP and the
## kill stat are granted once per fainted foe.
func _on_enemy_fainted() -> void:
	_state = State.BUSY
	_busy = true
	_clear_menu()
	await _say_wait(_enemy.display_name + " fainted!")
	await _grant_xp_for(_enemy)
	await _wait(1.0)  # let the XP message read before the send-out line
	var stats = get_node_or_null("/root/Stats")
	if stats != null and stats.has_method("record_kill"):
		stats.record_kill()
	# Spore Needle: an infected foe's faint grows a fruit plant (the spore
	# doesn't distinguish faint from death; see spore_needle.gd).
	SporeNeedleScript.on_creature_death(game_state, SporeNeedleScript.battle_snapshot(_enemy))
	if _is_trainer:
		var roster: Array = _cfg.get("enemy_roster", [])
		if _roster_idx + 1 < roster.size():
			_roster_idx += 1
			var nxt: Dictionary = roster[_roster_idx]
			_enemy = BattleUnit.new(str(nxt.get("creature_id", "")), int(nxt.get("level", 1)))
			_refresh_enemy_visual(str(nxt.get("creature_id", "")))
			_refresh_units()
			await _say_wait(str(_cfg["trainer_name"]) + " sent out " + _enemy.display_name + "!")
			_busy = false
			_show_commands()
			return
	await _win()


## The player's creature went down. When conscious party members remain the
## player must pick a replacement (forced switch, no foe turn); otherwise
## it's a blackout.
func _on_player_fainted() -> void:
	_sync_party_hp()
	if _switch_candidates().is_empty():
		await _lose()
		return
	_state = State.BUSY
	_busy = true
	_clear_menu()
	await _say_wait(_player.display_name + " fainted!")
	_forced_switch = true
	_state = State.SWITCH
	_clear_menu()
	_show_switch_menu()
	_busy = false


## XP for one fainted foe: level*10 to the active battler's party entry,
## level-ups applied. Shows the message directly when this battle isn't
## party-backed.
func _grant_xp_for(foe) -> void:
	var xp: int = int(foe.level) * 10
	var pidx: int = int(_cfg.get("player_party_index", -1))
	if game_state == null or pidx < 0:
		_say("Gained " + str(xp) + " XP!")
		return
	var msg := "Gained " + str(xp) + " XP!"
	for lv in PartyScript.gain_xp(game_state, pidx, xp):
		msg += " Grew to Lv" + str(lv) + "!"
	_say(msg)
	print("[BATTLE] xp ", xp, " vs ", foe.creature_id)


# --- Turn execution --------------------------------------------------------

func _run_turn(player_ab: String) -> void:
	_state = State.BUSY
	_busy = true
	_clear_menu()
	_hunt_turns += 1
	# Turn order by effective speed; player wins ties.
	# Slow Start (daily hunt): player acts last for the first 3 turns.
	var player_first: bool = _player.effective_speed() >= _enemy.effective_speed()
	if _hunt_forces_last():
		player_first = false
	if player_first:
		if not await _check_drowsy(_player):
			await _act(_player, _enemy, player_ab, _player_dot, _enemy_dot, _enemy_bar)
			if _enemy.fainted:
				await _on_enemy_fainted()
				return
		await _enemy_act()
		if _player.fainted:
			await _on_player_fainted()
			return
	else:
		await _enemy_act()
		if _player.fainted:
			await _on_player_fainted()
			return
		if not await _check_drowsy(_player):
			await _act(_player, _enemy, player_ab, _player_dot, _enemy_dot, _enemy_bar)
			if _enemy.fainted:
				await _on_enemy_fainted()
				return
	await _end_of_turn()
	_busy = false
	_show_commands()


## Spore-fever: the afflicted may be too drowsy to act (docs §1 glossary).
## Returns true when the unit's action is lost this turn.
func _check_drowsy(unit) -> bool:
	if int(unit.statuses.get("spore_fever", 0)) > 0 and randf() < unit.SPORE_FEVER_FAIL:
		await _say_wait(str(unit.display_name) + " is too drowsy to move!")
		return true
	return false


func _enemy_act() -> void:
	# Silver Bell Bloom decoy: one enemy attack goes wide, wasted (docs §1).
	if _decoy_active:
		_decoy_active = false
		await _say_wait("The Silver Bell Bloom drew the attack — wasted!")
		return
	if await _check_drowsy(_enemy):
		return
	var ids: Array = _enemy.ability_ids
	if ids.is_empty():
		return
	# Act 2 special AI: signature moves, docile temperament, turn counters.
	# Falls back to a damaging move for creatures without special logic.
	var provoked: bool = _enemy.statuses.has("provoked")
	var ab: String = CreatureAI.choose_action(_enemy, _foe_last_ability, provoked)
	if ab == "":
		await _say_wait(str(_enemy.display_name) + " is perfectly still.")
		return
	# Echo: use the foe's last ability if the AI chose it.
	var ctx := {"foe_last_ability": _foe_last_ability}
	if ab == "echo" and _foe_last_ability != "" and _enemy.can_use(_foe_last_ability):
		ab = _foe_last_ability
	await _act(_enemy, _player, ab, _enemy_dot, _player_dot, _player_bar, ctx)


func _act(attacker, target, ab_id: String, atk_dot, tgt_dot, tgt_bar: ProgressBar, ctx: Dictionary = {}) -> void:
	var ab: Dictionary = CreatureData.get_ability(ab_id)
	await _say(str(attacker.display_name) + " used " + str(ab.get("name", ab_id)) + "!")
	_lunge(atk_dot, tgt_dot)
	var dealt: int = attacker.use_ability(ab_id, target, ctx)
	# Daily Hunt: track damage taken for scoring.
	if _hunt_active and target == _player:
		_hunt_damage += dealt
	# Track foe's last ability for Echomarrow's Echo; mark enemy provoked
	# when the player lands a hit (docile Stillness breaks).
	if attacker == _player:
		_foe_last_ability = ab_id
		if dealt > 0 and target == _enemy:
			CreatureAI.mark_provoked(_enemy)
	_damage_number(tgt_dot.position, dealt)
	_update_bar(tgt_bar, target.hp)
	await _wait(0.45)
	var status := str(ab.get("status", ""))
	if status != "" and not target.fainted:
		await _say_wait(str(target.display_name) + " is wilting!")


func _end_of_turn() -> void:
	for unit in [_player, _enemy]:
		var before: int = unit.hp
		unit.tick_statuses()
		var drained: int = before - unit.hp
		if drained > 0:
			await _say(str(unit.display_name) + " wilted (-" + str(drained) + ")")
			_update_bar(_player_bar if unit == _player else _enemy_bar, unit.hp)
			await _wait(0.4)
	if _enemy.fainted:
		await _on_enemy_fainted()
	elif _player.fainted:
		await _on_player_fainted()


# --- Resolution ------------------------------------------------------------


## Daily Hunt victory: score the hunt from fight duration + damage taken,
## award the Soul Credit reward, record the local best / Hall of Fame.
## A catch of the hunt target counts — the bounty is the creature, dead
## or snared. Mismatched targets (shouldn't happen) fail safe: the hunt
## is abandoned, not scored.
func _complete_daily_hunt() -> void:
	var DailyHunts = load("res://scripts/daily_hunts.gd")
	var hunt: Dictionary = DailyHunts.active_hunt(game_state)
	var seconds := 0.0
	if _hunt_start_msec > 0:
		seconds = float(Time.get_ticks_msec() - _hunt_start_msec) / 1000.0
	var want: String = DailyHunts.battle_creature_id(str(hunt.get("target_id", "")))
	if hunt.is_empty() or (_enemy != null and str(_enemy.creature_id) != want):
		DailyHunts.abandon_hunt(game_state)
		_hunt_active = false
		return
	var result: Dictionary = DailyHunts.complete_hunt(game_state, seconds, _hunt_damage)
	var reward := int(hunt.get("reward", 0))
	if reward > 0 and game_state != null and game_state.has_method("add_soul_credits"):
		game_state.add_soul_credits(reward)
	var score := int(result.get("score", 0))
	var target_name := str(hunt.get("target_name", "the target"))
	if bool(result.get("is_best", false)):
		await _say_wait("Daily Hunt complete! %s down in %ds. Score %d — a new best! +%d Soul Credits." % [target_name, int(seconds), score, reward])
	else:
		await _say_wait("Daily Hunt complete! %s down in %ds. Score %d. +%d Soul Credits." % [target_name, int(seconds), score, reward])
	_hunt_active = false


## Daily Hunt defeat: the hunt is failed, not completed. "It's a memory"
## still applies — the player keeps their position and can retry the hunt
## from the bounty board (it re-arms as a fresh attempt).
func _fail_daily_hunt() -> void:
	if not _hunt_active:
		return
	var DailyHunts = load("res://scripts/daily_hunts.gd")
	DailyHunts.abandon_hunt(game_state)
	_hunt_active = false
	await _say_wait("The hunt slips away… failed. You can try again from the bounty board.")

func _win() -> void:
	_state = State.END
	_busy = true
	_clear_menu()
	# The fainted message + XP were already shown by _on_enemy_fainted.
	await _say_wait("You win!")
	_sync_party_hp()
	# Twitch Rich Veins (one-shot): bonus Soul Credits on victory.
	var loot_bonus := _consume_twitch_loot()
	if str(_cfg["victory_flag"]) != "" and game_state != null and game_state.has_method("set_flag"):
		game_state.set_flag(str(_cfg["victory_flag"]))
	# Rivalry flag: set on win too (rival fights are story-critical either way).
	if str(_cfg.get("rivalry_flag", "")) != "" and game_state != null and game_state.has_method("set_flag"):
		game_state.set_flag(str(_cfg["rivalry_flag"]))
	# Creature-system achievements.
	var ach := get_node_or_null("/root/Achievements")
	if ach != null and ach.has_method("unlock"):
		if _is_trainer:
			ach.unlock("trainer_win")
		if str(_cfg["victory_flag"]) == "bellmaw_defeated":
			ach.unlock("bellmaw_win")
	if _is_trainer:
		if game_state != null and game_state.has_method("add_soul_credits"):
			# loot_bonus equals the base reward when the flag was set,
			# so the total is doubled per the blessing's text.
			var rc := int(_cfg.get("reward_credits", 0)) + loot_bonus
			if rc > 0:
				game_state.add_soul_credits(rc)
				await _say_wait("Received " + str(rc) + " Soul Credits!")
		for line in (_cfg.get("post_dialogue", []) as Array):
			await _say_wait(str(line))
	elif game_state != null and _enemy != null:
		# Wild victory: feed bounty-contract reap objectives (trainers don't count).
		ContractsScript.record_reap(game_state, str(_enemy.creature_id))
		if loot_bonus > 0:
			game_state.add_soul_credits(loot_bonus)
			await _say_wait("Rich Veins! The viewers' blessing pays out: +%d Soul Credits!" % loot_bonus)
	# Daily Hunt: a victory (or a catch) against the hunt target scores it.
	if _hunt_active:
		await _complete_daily_hunt()
	print("[BATTLE] win vs ", _enemy.creature_id, " trainer=", _is_trainer)
	await _wait(1.0)
	_pending_outcome = "win"
	_return_to_room()


func _lose() -> void:
	_state = State.END
	_busy = true
	_clear_menu()
	# Rival fights (spare_on_loss): the rival spares you — no blackout.
	# The rivalry flag is set either way; he leaves, story continues.
	if bool(_cfg.get("spare_on_loss", false)):
		for line in (_cfg.get("post_dialogue_loss", []) as Array):
			await _say_wait(str(line))
		_sync_party_hp()
		if str(_cfg.get("rivalry_flag", "")) != "" and game_state != null and game_state.has_method("set_flag"):
			game_state.set_flag(str(_cfg["rivalry_flag"]))
		print("[BATTLE] spared by ", _cfg.get("trainer_id", "rival"))
		await _wait(1.0)
		_pending_outcome = "win"
		_return_to_room()
		return
	# Seamless wild battle: "it's a memory" — no blackout, no shrine trip.
	# Heal up, dissolve the layer, the player never left the room.
	if embedded_mode:
		await _say_wait("Your creature fainted… the memory dissolves.")
		if _hunt_active:
			await _fail_daily_hunt()
		if game_state != null:
			if game_state.has_method("heal_to_full"):
				game_state.heal_to_full()
			PartyScript.heal_all(game_state)
		_pending_outcome = "lose"
		if battle_manager != null and battle_manager.has_method("clear_pending"):
			battle_manager.clear_pending()
		print("[BATTLE] seamless defeat — memory dissolves, staying in room")
		battle_resolved.emit("lose")
		return
	await _say_wait("Your creature fainted… you black out!")
	if _hunt_active:
		await _fail_daily_hunt()
	var room := "p1"
	var pos := Vector2.ZERO
	if game_state != null and game_state.has_method("get_last_shrine"):
		var s: Dictionary = game_state.get_last_shrine()
		room = str(s.get("room", "p1"))
		pos = Vector2(float(s.get("x", 0.0)), float(s.get("y", 0.0)))
	if game_state != null:
		if game_state.has_method("heal_to_full"):
			game_state.heal_to_full()
		# Blackout is a full reset: the party wakes up healed at the shrine.
		PartyScript.heal_all(game_state)
		if game_state.has_method("set_position"):
			game_state.set_position(room, pos.x, pos.y)
	print("[BATTLE] blackout -> shrine in ", room)
	await _wait(1.0)
	_goto(str(ROOM_SCENES.get(room, FALLBACK_SCENE)))


func _return_to_room() -> void:
	_state = State.END
	_sync_party_hp()
	var room := str(_cfg["return_room"])
	var pos: Vector2 = _cfg["return_pos"]
	if game_state != null and game_state.has_method("set_position"):
		game_state.set_position(room, pos.x, pos.y)
	_goto(str(ROOM_SCENES.get(room, FALLBACK_SCENE)))


## Write the battler's remaining HP back to its party entry so damage
## persists across battles. No-op when this battle wasn't party-backed.
func _sync_party_hp() -> void:
	var pidx: int = int(_cfg.get("player_party_index", -1))
	if game_state != null and pidx >= 0 and _player != null:
		PartyScript.set_hp(game_state, pidx, _player.hp)
		PartyScript.set_statuses(game_state, pidx, _player.statuses.keys())


func _goto(path: String) -> void:
	if battle_manager != null and battle_manager.has_method("clear_pending"):
		battle_manager.clear_pending()
	if embedded_mode:
		# Seamless host dismisses the layer; no scene change.
		battle_resolved.emit(_pending_outcome)
		return
	if scene_changer != null and scene_changer.is_valid():
		scene_changer.call(path)
		return
	get_tree().change_scene_to_file(path)


# --- Presentation helpers --------------------------------------------------

## Greybox snare throw: a gold dot arcs from the player to the foe, then a
## flash on arrival. fast_mode skips the motion (tests).
func _throw_snare_anim() -> void:
	if fast_mode:
		return
	var dot := CreatureDot.new()
	dot.color = Color(1.0, 0.85, 0.35)
	dot.radius = 18.0
	dot.position = _player_dot.position
	add_child(dot)
	var mid: Vector2 = (_player_dot.position + _enemy_dot.position) * 0.5 + Vector2(0, -160)
	var tw := create_tween()
	tw.tween_property(dot, "position", mid, 0.3)
	tw.tween_property(dot, "position", _enemy_dot.position, 0.3)
	tw.tween_callback(dot.queue_free)
	# Arrival flash on the foe.
	var flash := CreatureDot.new()
	flash.color = Color(1.0, 0.9, 0.5, 0.7)
	flash.radius = 90.0
	flash.position = _enemy_dot.position
	add_child(flash)
	var ftw := create_tween()
	ftw.tween_interval(0.6)
	ftw.tween_property(flash, "modulate:a", 0.0, 0.25)
	ftw.tween_callback(flash.queue_free)


## Failed catch: the foe wobbles free.
func _shake_free_anim() -> void:
	if fast_mode or _enemy_dot == null:
		return
	var home: Vector2 = _enemy_dot.position
	var tw := create_tween()
	for i in range(3):
		tw.tween_property(_enemy_dot, "position", home + Vector2(14, 0), 0.09)
		tw.tween_property(_enemy_dot, "position", home + Vector2(-14, 0), 0.09)
	tw.tween_property(_enemy_dot, "position", home, 0.09)


## Successful catch: the foe's dot shrinks into the snare.
func _settle_anim() -> void:
	if fast_mode or _enemy_dot == null:
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_enemy_dot, "scale", Vector2(0.05, 0.05), 0.5)
	tw.tween_property(_enemy_dot, "modulate:a", 0.0, 0.5)

func _say(text: String) -> void:
	_msg.text = text


func _say_wait(text: String) -> void:
	_say(text)
	await _wait(1.1)


func _wait(sec: float) -> void:
	if fast_mode or sec <= 0.0:
		return
	await get_tree().create_timer(sec).timeout


func _update_bar(bar: ProgressBar, hp: int) -> void:
	if fast_mode:
		bar.value = hp
		return
	var tw := create_tween()
	tw.tween_property(bar, "value", float(hp), 0.4)


func _lunge(atk_dot, tgt_dot) -> void:
	if fast_mode:
		return
	var home: Vector2 = atk_dot.position
	var dir: Vector2 = (tgt_dot.position - home).normalized()
	var tw := create_tween()
	tw.tween_property(atk_dot, "position", home + dir * 60.0, 0.15)
	tw.tween_property(atk_dot, "position", home, 0.2)


func _damage_number(at: Vector2, amount: int) -> void:
	var l := Label.new()
	l.text = "-" + str(amount)
	l.add_theme_font_size_override("font_size", 32)
	l.add_theme_color_override("font_color", Color(1, 0.35, 0.3))
	l.position = at + Vector2(-30, -90)
	add_child(l)
	if fast_mode:
		l.queue_free()
		return
	var tw := create_tween().set_parallel(true)
	tw.tween_property(l, "position:y", l.position.y - 40.0, 0.8)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.chain().tween_callback(l.queue_free)
