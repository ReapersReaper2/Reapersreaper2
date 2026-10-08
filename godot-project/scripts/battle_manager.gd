extends Node
## BattleManager — entry point for tactical battles (autoload).
##
## Rooms call:
##   BattleManager.start_wild_battle("bellowscap", 3, room_id, player_pos)
##   BattleManager.start_boss_battle("bellmaw", 12, room_id, player_pos)
##
## WILD battles are SEAMLESS (locked design): the battle layer spawns in
## the current room — no scene change. `pending` stays set for the whole
## battle (WildZone uses it to block re-triggers) and is cleared on
## resolution by the embedded battle. Boss and trainer battles keep the
## staged battle.tscn transition: the manager stashes the config in
## `pending`, then switches scenes; the battle scene reads it back in
## _ready and returns the player to `return_room` at `return_pos` after.
##
## Player creature comes from the party lead (first conscious member);
## set_player_creature() overrides it (persisted in-memory only) for the
## headless/test path where no GameState is available.

const BATTLE_SCENE := "res://scenes/battle.tscn"
const PartyScript := preload("res://scripts/party.gd")
const TrainerData := preload("res://scripts/trainer_data.gd")
const SeamlessBattleScript := preload("res://scripts/seamless_battle.gd")
const TwitchScript := preload("res://scripts/twitch.gd")

var pending: Dictionary = {}
## Msec timestamp of the last battle resolution (stamped in clear_pending).
## WildZone reads this for its post-battle anti-frustration cooldown.
## -1 = no battle has ended yet (no cooldown at boot).
var last_battle_end_msec: int = -1
var player_creature_id := "snapling"
var player_creature_level := 5
var game_state = null  # GameState autoload, or injected (headless tests)
var scene_changer = null  # callable(path) override for headless tests
## Test hook: forwarded to the seamless wild-battle host (skips tween waits).
var seamless_fast_mode := false


func _ready() -> void:
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")


func _resolve_game_state() -> void:
	if game_state == null and is_inside_tree():
		game_state = get_node_or_null("/root/GameState")


## The party's battle-ready lead (first conscious member), or {} when the
## party can't fight. Empty when there is no GameState (headless tests) —
## callers then fall back to player_creature_id/player_creature_level.
func _player_lead() -> Dictionary:
	_resolve_game_state()
	if game_state == null:
		return {}
	return PartyScript.lead_for_battle(game_state)


func set_player_creature(creature_id: String, level: int) -> void:
	player_creature_id = creature_id
	player_creature_level = maxi(1, level)


## Wild battles are SEAMLESS (locked design decision): no scene change.
## The battle layer spawns in the current room over the overworld; the
## player never leaves. Boss battles keep the staged battle.tscn arena.
func start_wild_battle(creature_id: String, level: int, return_room: String, return_pos: Vector2) -> bool:
	if not _build_pending(creature_id, level, false, "", return_room, return_pos):
		return false
	return _launch_wild_seamless()


## Daily Hunt battle: spawns today's hunt target as a real encounter.
## Wild targets use the seamless in-room layer (locked design); boss
## targets keep the staged battle.tscn arena. pending carries
## daily_hunt=true so battle.gd tracks duration/damage and completes the
## hunt on victory. No victory_flag — the hunt is repeatable by design.
func start_daily_hunt_battle(creature_id: String, level: int, is_boss: bool, return_room: String, return_pos: Vector2) -> bool:
	if not _build_pending(creature_id, level, is_boss, "", return_room, return_pos):
		return false
	pending["daily_hunt"] = true
	print("[BATTLE] start daily-hunt ", "boss" if is_boss else "wild", " ", creature_id, " lv", level)
	if is_boss:
		return _launch_staged()
	return _launch_wild_seamless()


func _launch_wild_seamless() -> bool:
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		var seamless = SeamlessBattleScript.new()
		seamless.name = "SeamlessBattle"
		seamless.setup(pending, self, game_state)
		seamless.battle_fast_mode = seamless_fast_mode
		tree.current_scene.add_child(seamless)
		return true
	# No live room (headless tests): legacy scene-transition fallback.
	print("[BATTLE] start wild ", str(pending.get("enemy_creature_id", "?")), " lv", int(pending.get("enemy_level", 0)), " (no current scene — scene fallback)")
	if scene_changer != null and scene_changer.is_valid():
		scene_changer.call(BATTLE_SCENE)
		return true
	get_tree().change_scene_to_file(BATTLE_SCENE)
	return true


## Staged battle.tscn transition (bosses, trainers, hunt bosses).
func _launch_staged() -> bool:
	if scene_changer != null and scene_changer.is_valid():
		scene_changer.call(BATTLE_SCENE)
		return true
	get_tree().change_scene_to_file(BATTLE_SCENE)
	return true


func start_boss_battle(creature_id: String, level: int, return_room: String, return_pos: Vector2, victory_flag: String = "") -> bool:
	return _start(creature_id, level, true, victory_flag, return_room, return_pos)


## Trainer battle: the opponent fields a sequential roster (sent out in
## order as each faints, no AI switching). No fleeing, no catching a
## trainer's creatures. One-time via the defeat flag (rooms/NPCs check it).
func start_trainer_battle(trainer_id: String, return_room: String, return_pos: Vector2) -> bool:
	var t: Dictionary = TrainerData.get_trainer(trainer_id)
	if t.is_empty():
		push_warning("BattleManager: unknown trainer '%s'" % trainer_id)
		return false
	if not pending.is_empty():
		push_warning("BattleManager: battle already pending, ignoring start")
		return false
	var lead := _player_lead()
	if game_state != null and lead.is_empty():
		push_warning("BattleManager: no conscious party creature — cannot start battle")
		return false
	var pid := player_creature_id
	var plv := player_creature_level
	var php := -1
	var pidx := -1
	if game_state != null:
		pid = str(lead.get("creature_id", pid))
		plv = int(lead.get("level", plv))
		php = int(lead.get("current_hp", -1))
		pidx = int(lead.get("index", -1))
	var roster: Array = t.get("roster", [])
	if roster.is_empty():
		push_warning("BattleManager: trainer '%s' has an empty roster" % trainer_id)
		return false
	var first: Dictionary = roster[0]
	pending = {
		"player_creature_id": pid,
		"player_level": plv,
		"player_hp": php,
		"player_party_index": pidx,
		"enemy_creature_id": str(first.get("creature_id", "snapling")),
		"enemy_level": int(first.get("level", 1)),
		"is_boss": false,
		"is_trainer": true,
		"trainer_id": trainer_id,
		"trainer_name": str(t.get("name", trainer_id)),
		"enemy_roster": roster,
		"reward_credits": int(t.get("reward_credits", 0)),
		"post_dialogue": t.get("post_dialogue", []),
		"post_dialogue_loss": t.get("post_dialogue_loss", []),
		"spare_on_loss": bool(t.get("spare_on_loss", false)),
		"rivalry_flag": str(t.get("rivalry_flag", "")),
		"victory_flag": TrainerData.defeat_flag(trainer_id),
		"return_room": return_room,
		"return_pos": return_pos,
	}
	print("[BATTLE] start trainer ", trainer_id, " roster=", roster.size())
	# Twitch votes happen between encounters only — never mid-fight.
	TwitchScript.set_in_battle(true)
	if scene_changer != null and scene_changer.is_valid():
		scene_changer.call(BATTLE_SCENE)
		return true
	get_tree().change_scene_to_file(BATTLE_SCENE)
	return true


func _start(creature_id: String, level: int, is_boss: bool, victory_flag: String, return_room: String, return_pos: Vector2) -> bool:
	if not _build_pending(creature_id, level, is_boss, victory_flag, return_room, return_pos):
		return false
	print("[BATTLE] start ", "boss" if is_boss else "wild", " ", creature_id, " lv", level)
	if scene_changer != null and scene_changer.is_valid():
		scene_changer.call(BATTLE_SCENE)
		return true
	get_tree().change_scene_to_file(BATTLE_SCENE)
	return true


## Builds `pending` (and marks the creature seen in the Journal ledger).
## Returns false when the start is refused: a battle is already active
## (seamless or staged), or the party has no conscious lead.
func _build_pending(creature_id: String, level: int, is_boss: bool, victory_flag: String, return_room: String, return_pos: Vector2) -> bool:
	if not pending.is_empty():
		push_warning("BattleManager: battle already pending, ignoring start")
		return false
	# The player's battler comes from the party lead (first conscious
	# member) whenever a GameState is available; a fainted lead is never
	# sent out. With no GameState (headless tests), fall back to the
	# legacy player_creature_id/player_creature_level fields.
	var lead := _player_lead()
	var pid := player_creature_id
	var plv := player_creature_level
	var php := -1
	var pidx := -1
	if game_state != null:
		if lead.is_empty():
			push_warning("BattleManager: no conscious party creature — cannot start battle")
			return false
		pid = str(lead.get("creature_id", pid))
		plv = int(lead.get("level", plv))
		php = int(lead.get("current_hp", -1))
		pidx = int(lead.get("index", -1))
	pending = {
		"player_creature_id": pid,
		"player_level": plv,
		"player_hp": php,
		"player_party_index": pidx,
		"enemy_creature_id": creature_id,
		"enemy_level": level,
		"is_boss": is_boss,
		"victory_flag": victory_flag,
		"return_room": return_room,
		"return_pos": return_pos,
	}
	# Journal ledger: encountering a creature marks it "seen".
	if game_state != null and game_state.has_method("mark_seen"):
		game_state.mark_seen(creature_id)
	# Twitch votes happen between encounters only — never mid-fight.
	TwitchScript.set_in_battle(true)
	return true


## Called by the battle scene when it resolves (win/lose/flee).
func clear_pending() -> void:
	pending = {}
	last_battle_end_msec = Time.get_ticks_msec()
	# The fight is over — viewer votes may open again.
	TwitchScript.set_in_battle(false)
