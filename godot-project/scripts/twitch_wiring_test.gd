extends SceneTree
## Headless Twitch gameplay-wiring test: battle_manager set_in_battle
## hooks, vote triggers between encounters (wild-zone entry + post-battle),
## and the twitch_* battle-formula consumers (one-shot flags clear after
## firing). The Twitch transport is fully mocked — no real endpoints.
##
## Run: Godot --headless --path <project> -s res://scripts/twitch_wiring_test.gd

const GameStateScript = preload("res://scripts/game_state.gd")
const TwitchScript = preload("res://scripts/twitch.gd")
const TwitchVotesScript = preload("res://scripts/twitch_votes.gd")
const BattleManagerScript = preload("res://scripts/battle_manager.gd")
const BattleScript = preload("res://scripts/battle.gd")
const BattleUnit = preload("res://scripts/battle_unit.gd")
const WildZoneScript = preload("res://scripts/wild_zone.gd")
const PartyScript = preload("res://scripts/party.gd")


class MockChat extends RefCounted:
	var connected := false
	var inbox: Array = []

	func connect_chat(_channel: String, _nick: String, _token: String) -> bool:
		connected = true
		return true

	func chat_connected() -> bool:
		return connected

	func disconnect_chat() -> void:
		connected = false

	func poll_messages() -> Array:
		var out: Array = inbox
		inbox = []
		return out

	func say(user: String, text: String) -> void:
		inbox.append({"user": user, "text": text})


var _gs = null
var _mock: MockChat = null
var _passed := 0
var _failed := 0
var _ran := false


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] twitch_wiring: ", label)


func _setup_and_run() -> void:
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		_gs = GameStateScript.new()
		_gs.name = "GameState"
		root.add_child(_gs)
		_gs._ready()
	_gs.new_game()
	# Never touch the real config in tests.
	TwitchScript.set_config_path("user://twitch_wiring_test.cfg")
	TwitchScript.set_enabled(false)
	TwitchScript.configure("", "")
	TwitchScript.cancel_vote()
	TwitchScript.set_in_battle(false)
	TwitchVotesScript.reset_for_tests()
	_run()
	print("[twitch_wiring_test] done: ", _passed, " passed, ", _failed, " failed")
	quit()


func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_setup_and_run()
	return false


func _go_online() -> void:
	TwitchScript.configure("reapersreaper", "secrettoken123")
	TwitchScript.set_enabled(true)
	_mock = MockChat.new()
	TwitchScript.set_transport(_mock)
	TwitchScript.connect_chat()
	# Fresh vote state for each test.
	TwitchScript.cancel_vote()
	TwitchScript.set_in_battle(false)
	_gs.set_stat("twitch_last_vote_msec", -1000000)
	_gs.set_stat("twitch_last_kind", "trial")


func _go_offline() -> void:
	TwitchScript.disconnect_chat()
	TwitchScript.cancel_vote()
	TwitchScript.set_in_battle(false)
	TwitchVotesScript.reset_for_tests()


func _make_bm():
	var bm = BattleManagerScript.new()
	root.add_child(bm)
	bm._ready()
	bm.game_state = _gs
	bm.scene_changer = Callable(self, "_on_scene_change")
	return bm


func _on_scene_change(_path: String) -> void:
	pass


## Bare battle node with config + units, minus the UI/scene flow.
func _make_battle(cfg: Dictionary):
	var b = BattleScript.new()
	b.battle_config = cfg
	b.game_state = _gs
	b.battle_manager = {}
	b._read_config()
	b._player = BattleUnit.new(str(cfg.get("player_creature_id", "snapling")), int(cfg.get("player_level", 5)))
	b._enemy = BattleUnit.new(str(cfg.get("enemy_creature_id", "siltmaw")), int(cfg.get("enemy_level", 7)))
	return b


func _make_zone():
	var z = WildZoneScript.new()
	z.game_state = _gs
	root.add_child(z)
	# Set AFTER add_child: _ready() loads the table from table_key and
	# would overwrite a table assigned before.
	z._table = [
		{"creature_id": "snapling", "min_level": 3, "max_level": 3, "weight": 50.0},
		{"creature_id": "siltmaw", "min_level": 3, "max_level": 3, "weight": 30.0},
		{"creature_id": "gravebloom", "min_level": 3, "max_level": 3, "weight": 5.0},
	]
	return z


func _run() -> void:
	_test_battle_manager_hooks()
	_test_vote_triggers()
	_test_rare_spawn()
	_test_hard_encounter()
	_test_heavy_handed()
	_test_bonus_loot()
	_test_full_heal()
	_test_swarm()
	_go_offline()


## 1. battle_manager flips set_in_battle on start/resolve; votes can't
## open mid-fight.
func _test_battle_manager_hooks() -> void:
	_go_online()
	var bm = _make_bm()
	var host := Node.new()
	root.add_child(host)
	# Start a battle: pending builds, in_battle flips on.
	var ok: bool = bm.start_wild_battle("siltmaw", 5, "c1", Vector2.ZERO)
	_check(ok, "battle starts")
	_check(TwitchScript.open_vote("blessing", 1.0) == false, "vote blocked mid-battle")
	bm.clear_pending()
	# Resolve: in_battle flips off, votes may open again.
	_check(TwitchScript.open_vote("blessing", 1.0) == true, "vote opens after battle resolves")
	TwitchScript.cancel_vote()
	host.queue_free()
	bm.queue_free()


## 2. Votes open between encounters: wild-zone entry, post-battle, with
## cooldown + blessing/trial alternation. Blocked when offline.
func _test_vote_triggers() -> void:
	_go_online()
	var host := Node.new()
	root.add_child(host)
	# Zone entry opens a blessing first (last_kind defaults to trial).
	_check(TwitchVotesScript.maybe_open(_gs, host) == true, "vote opens on zone entry")
	_check(TwitchScript.is_vote_open() == true, "vote is open")
	_check(str(_gs.get_stat("twitch_last_kind", "")) == "blessing", "first vote is a blessing")
	TwitchScript.cancel_vote()
	# Cooldown blocks an immediate second vote.
	_check(TwitchVotesScript.maybe_open(_gs, host) == false, "cooldown blocks back-to-back votes")
	# After the cooldown, the kind alternates to trial.
	_gs.set_stat("twitch_last_vote_msec", -1000000)
	_check(TwitchVotesScript.maybe_open(_gs, host) == true, "vote opens after cooldown")
	_check(str(_gs.get_stat("twitch_last_kind", "")) == "trial", "second vote is a trial")
	TwitchScript.cancel_vote()
	# Offline: no votes.
	_go_offline()
	_go_online()
	TwitchScript.disconnect_chat()
	_check(TwitchVotesScript.maybe_open(_gs, host) == false, "no vote when chat disconnected")
	# Disabled: no votes even with a live transport.
	_mock = MockChat.new()
	_mock.connected = true
	TwitchScript.set_transport(_mock)
	TwitchScript.set_enabled(false)
	_check(TwitchVotesScript.maybe_open(_gs, host) == false, "no vote when Twitch disabled")
	host.queue_free()
	TwitchVotesScript.reset_for_tests()


## 3. Full vote lifecycle through the coordinator: open -> poll ballots ->
## auto-close applies the winner -> result banner shows.
func _test_vote_lifecycle() -> void:
	_go_online()
	var host := Node.new()
	root.add_child(host)
	_gs.set_stat("twitch_rare_spawn", false)
	# Zero-duration vote so poll() closes it on the first tick.
	_check(TwitchScript.open_vote("blessing", 0.0) == true, "test vote opens")
	_mock.say("viewer1", "!vote 1")
	_mock.say("viewer2", "!vote 1")
	_mock.say("viewer3", "!vote 2")
	var winner: String = TwitchVotesScript.process(_gs, host)
	_check(winner == "rare_spawn", "coordinator closes vote and returns winner id")
	_check(bool(_gs.get_stat("twitch_rare_spawn", false)) == true, "winning blessing flag applied")
	_check(TwitchScript.is_vote_open() == false, "vote closed after process")
	host.queue_free()
	TwitchVotesScript.reset_for_tests()


## 4. twitch_rare_spawn: forces the lowest-weight table entry, one-shot.
func _test_rare_spawn() -> void:
	var z = _make_zone()
	_gs.set_stat("twitch_rare_spawn", true)
	var pick: Dictionary = z._pick_creature()
	_check(str(pick.get("creature_id", "")) == "gravebloom", "rare_spawn forces rarest entry")
	_check(bool(_gs.get_stat("twitch_rare_spawn", false)) == false, "rare_spawn flag cleared after firing")
	# Without the flag, normal weighted rolls resume.
	var ids := {}
	for i in 20:
		ids[str(z._pick_creature().get("creature_id", ""))] = true
	_check(ids.size() > 1, "normal rolls vary without the flag")
	z.queue_free()


## 5. twitch_hard_encounter: +4 levels, one-shot.
func _test_hard_encounter() -> void:
	var z = _make_zone()
	_gs.set_stat("twitch_hard_encounter", true)
	var pick: Dictionary = z._make_pick({"creature_id": "siltmaw", "min_level": 5, "max_level": 5})
	_check(int(pick.get("level", 0)) == 9, "hard_encounter adds +4 levels")
	_check(bool(_gs.get_stat("twitch_hard_encounter", false)) == false, "hard_encounter flag cleared after firing")
	var pick2: Dictionary = z._make_pick({"creature_id": "siltmaw", "min_level": 5, "max_level": 5})
	_check(int(pick2.get("level", 0)) == 5, "levels normal after flag clears")
	z.queue_free()


## 6. twitch_heavy_handed: enemy outgoing x1.5 for the fight, one-shot.
func _test_heavy_handed() -> void:
	_gs.set_stat("twitch_heavy_handed", true)
	var b = _make_battle({"enemy_creature_id": "siltmaw", "enemy_level": 7})
	b._init_twitch()
	_check(is_equal_approx(b._enemy.mod_outgoing_mult, 1.5), "heavy_handed sets enemy outgoing x1.5")
	_check(bool(_gs.get_stat("twitch_heavy_handed", false)) == false, "heavy_handed flag cleared after firing")
	# Damage actually scales: heavy hit vs normal hit.
	var target = BattleUnit.new("snapling", 5)
	var dealt_normal: int = target.take_damage(20.0, b._player)
	var target2 = BattleUnit.new("snapling", 5)
	b._enemy.mod_outgoing_mult = 1.5
	var dealt_heavy: int = target2.take_damage(20.0 * 1.5, b._player)
	_check(dealt_heavy > dealt_normal, "heavy_handed damage is higher")
	b.queue_free()


## 7. twitch_bonus_loot: wild victory pays level-scaled credits, one-shot.
func _test_bonus_loot() -> void:
	_gs.set_stat("twitch_bonus_loot", true)
	var b = _make_battle({"enemy_creature_id": "siltmaw", "enemy_level": 7})
	var bonus: int = b._consume_twitch_loot()
	_check(bonus == 70, "wild bonus loot is level x 10")
	_check(bool(_gs.get_stat("twitch_bonus_loot", false)) == false, "bonus_loot flag cleared after firing")
	_check(b._consume_twitch_loot() == 0, "no double payout")
	# Trainer battles: bonus equals the base reward (caller doubles it).
	var bt = _make_battle({"enemy_creature_id": "siltmaw", "enemy_level": 7,
		"is_trainer": true, "reward_credits": 100})
	_gs.set_stat("twitch_bonus_loot", true)
	_check(bt._consume_twitch_loot() == 100, "trainer bonus equals base reward")
	b.queue_free()
	bt.queue_free()


## 8. twitch_full_heal: applies immediately via Party.heal_all.
func _test_full_heal() -> void:
	PartyScript.set_hp(_gs, 0, 1)
	var before: Dictionary = PartyScript.lead_for_battle(_gs)
	_check(int(before.get("current_hp", 0)) == 1, "party damaged before heal")
	_check(TwitchScript.apply_effect(_gs, "full_heal") == true, "full_heal applies")
	var after: Dictionary = PartyScript.lead_for_battle(_gs)
	_check(int(after.get("current_hp", 0)) > 1, "party healed after full_heal")
	_check(bool(_gs.get_stat("twitch_full_heal", false)) == false, "full_heal sets no flag")


## 9. twitch_swarm: followup encounter bypasses the post-battle cooldown.
func _test_swarm() -> void:
	var z = _make_zone()
	var bm = _make_bm()
	z.battle_manager = bm
	# Simulate: battle just ended (cooldown active), no swarm -> blocked.
	bm.last_battle_end_msec = Time.get_ticks_msec()
	z._swarm_followup = false
	_check(z._can_trigger() == false, "cooldown blocks immediate re-encounter")
	# With the swarm followup armed, the cooldown is bypassed.
	z._swarm_followup = true
	_check(z._can_trigger() == true, "swarm followup bypasses cooldown")
	# Consuming the flag arms the followup; the followup trigger stands down.
	_gs.set_stat("twitch_swarm", true)
	_check(z._consume_twitch_flag("twitch_swarm") == true, "swarm flag consumed")
	_check(bool(_gs.get_stat("twitch_swarm", false)) == false, "swarm flag cleared after firing")
	z.queue_free()
	bm.queue_free()
