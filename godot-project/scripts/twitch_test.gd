extends SceneTree
## Headless Twitch Integration verification: opt-in config, chat-vote
## tallying, Blessing/Trial application, mid-fight blocking, and graceful
## offline degradation. The Twitch API is fully mocked — no real endpoints.
##
## Run: Godot --headless --path <project> -s res://scripts/twitch_test.gd

const GameStateScript = preload("res://scripts/game_state.gd")
const TwitchScript = preload("res://scripts/twitch.gd")
const VoteUIScript = preload("res://scripts/twitch_vote_ui.gd")


class MockChat extends RefCounted:
	var connect_ok := true
	var connected := false
	var inbox: Array = []

	func connect_chat(_channel: String, _nick: String, _token: String) -> bool:
		if connect_ok:
			connected = true
			return true
		return false

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


func _check(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		print("[FAIL] twitch: ", label)


func _initialize() -> void:
	_gs = root.get_node_or_null("GameState")
	if _gs == null:
		_gs = GameStateScript.new()
		_gs.name = "GameState"
		root.add_child(_gs)
		_gs._ready()
	_gs.new_game()
	# Never touch the real config in tests.
	TwitchScript.set_config_path("user://twitch_test.cfg")
	TwitchScript.set_enabled(false)
	TwitchScript.configure("", "")
	TwitchScript.cancel_vote()
	TwitchScript.set_in_battle(false)
	_run()
	_report()
	quit()


func _report() -> void:
	print("[twitch_test] done: ", _passed, " passed, ", _failed, " failed")


func _go_online() -> void:
	TwitchScript.configure("reapersreaper", "secrettoken123")
	TwitchScript.set_enabled(true)
	_mock = MockChat.new()
	TwitchScript.set_transport(_mock)
	_check(TwitchScript.connect_chat() == true, "connect succeeds with mock transport")
	_check(TwitchScript.is_chat_connected() == true, "is_connected true after mock connect")


func _go_offline() -> void:
	TwitchScript.disconnect_chat()
	TwitchScript.cancel_vote()
	TwitchScript.set_in_battle(false)


func _run() -> void:
	_test_opt_in()
	_test_voting_gates()
	_test_tallying()
	_test_results()
	_test_degradation()
	_test_ui()


func _test_opt_in() -> void:
	_check(TwitchScript.is_enabled() == false, "opt-in: disabled by default")
	_check(TwitchScript.is_active() == false, "opt-in: not active without channel/token")
	TwitchScript.set_enabled(true)
	_check(TwitchScript.is_enabled() == true, "opt-in: enable persists")
	_check(TwitchScript.is_active() == false, "opt-in: still inactive without channel+token")
	TwitchScript.configure("reapersreaper", "secrettoken123")
	_check(TwitchScript.get_channel() == "reapersreaper", "config: channel stored")
	_check(TwitchScript.is_active() == true, "config: active once enabled + channel + token")
	# oauth: prefix and # prefix are stripped, never stored raw.
	TwitchScript.configure("#SomeChannel", "oauth:abc")
	_check(TwitchScript.get_channel() == "somechannel", "config: channel normalized")
	_go_offline()
	TwitchScript.configure("reapersreaper", "secrettoken123")


func _test_voting_gates() -> void:
	_go_online()
	_check(TwitchScript.open_vote("blessing") == true, "gate: vote opens when active+connected")
	_check(TwitchScript.open_vote("trial") == false, "gate: double-open refused")
	TwitchScript.cancel_vote()
	_check(TwitchScript.open_vote("bogus") == false, "gate: invalid kind refused")
	TwitchScript.set_in_battle(true)
	_check(TwitchScript.open_vote("blessing") == false, "gate: voting blocked mid-fight")
	TwitchScript.set_in_battle(false)
	_go_offline()
	_check(TwitchScript.open_vote("blessing") == false, "gate: voting blocked while offline")
	_check(TwitchScript.is_vote_open() == false, "gate: no vote open after offline refusal")


func _test_tallying() -> void:
	_go_online()
	_check(TwitchScript.open_vote("blessing", 60.0) == true, "tally: blessing vote opens")
	_mock.say("alice", "!vote 1")
	_mock.say("bob", "!vote 2")
	_mock.say("carol", "!vote 3")
	_mock.say("dave", "hello everyone")          # not a command: ignored
	_mock.say("erin", "!vote 99")                # out of range: ignored
	_mock.say("frank", "!VOTE 1")                # case-insensitive
	_mock.say("grace", "!vote rare")            # name fragment
	_mock.say("alice", "!vote 2")                # latest vote wins per user
	TwitchScript.poll()
	var st: Dictionary = TwitchScript.get_vote_state()
	_check(st["kind"] == "blessing", "tally: kind reported")
	_check(int(st["total_votes"]) == 5, "tally: 5 valid ballots counted")
	var opts: Array = st["options"]
	_check(int(opts[0]["votes"]) == 2, "tally: option 1 has 2 (frank, grace fragment)")
	_check(int(opts[1]["votes"]) == 2, "tally: option 2 has 2 (bob, alice latest)")
	_check(int(opts[2]["votes"]) == 1, "tally: option 3 has 1 (carol)")
	_check(float(st["seconds_left"]) > 0.0, "tally: countdown running")
	TwitchScript.cancel_vote()


func _test_results() -> void:
	_go_online()
	# Clear winner applies its effect.
	_check(TwitchScript.open_vote("blessing", 60.0) == true, "result: vote opens")
	_mock.say("a", "!vote 1")
	_mock.say("b", "!vote 1")
	_mock.say("c", "!vote 2")
	TwitchScript.poll()
	var res: Dictionary = TwitchScript.close_and_apply(_gs)
	_check(str(res["winner_id"]) == "rare_spawn", "result: most votes wins")
	_check(bool(res["applied"]) == true, "result: applied flag true")
	_check(bool(_gs.get_stat("twitch_rare_spawn", false)) == true, "result: rare_spawn flag set")
	_check(TwitchScript.is_vote_open() == false, "result: vote closed after close")
	# Tie goes to the earliest option (deterministic).
	_check(TwitchScript.open_vote("trial", 60.0) == true, "result: trial vote opens")
	_mock.say("a", "!vote 2")
	_mock.say("b", "!vote 1")
	TwitchScript.poll()
	res = TwitchScript.close_and_apply(_gs)
	_check(str(res["winner_id"]) == "hard_encounter", "result: tie breaks to earliest option")
	_check(bool(_gs.get_stat("twitch_hard_encounter", false)) == true, "result: hard_encounter flag set")
	# Zero votes: no winner, nothing applied.
	_check(TwitchScript.open_vote("trial", 60.0) == true, "result: empty vote opens")
	res = TwitchScript.close_and_apply(_gs)
	_check(str(res["winner_id"]) == "", "result: no winner on zero votes")
	_check(bool(res["applied"]) == false, "result: nothing applied on zero votes")
	# Cancel applies nothing.
	_check(TwitchScript.open_vote("blessing", 60.0) == true, "result: vote opens for cancel")
	_mock.say("a", "!vote 3")
	TwitchScript.poll()
	TwitchScript.cancel_vote()
	_check(TwitchScript.is_vote_open() == false, "result: cancel closes vote")
	_check(_gs.get_stat("twitch_bonus_loot", null) == null, "result: cancel applies nothing")
	# full_heal blessing heals the party for real.
	_check(TwitchScript.apply_effect(_gs, "full_heal") == true, "result: full_heal applies")
	_check(TwitchScript.apply_effect(_gs, "bogus_id") == false, "result: unknown effect refused")
	_go_offline()


func _test_degradation() -> void:
	# Everything is a safe no-op when disabled / offline / idle.
	_check(TwitchScript.poll() == "", "degrade: poll with no vote is safe")
	var res: Dictionary = TwitchScript.close_vote()
	_check(str(res.get("winner_id", "x")) == "", "degrade: close with no vote is safe")
	_check(TwitchScript.is_chat_connected() == false, "degrade: not connected while offline")
	# Failed connection never breaks gameplay.
	TwitchScript.configure("reapersreaper", "badtoken")
	TwitchScript.set_enabled(true)
	var bad := MockChat.new()
	bad.connect_ok = false
	TwitchScript.set_transport(bad)
	_check(TwitchScript.connect_chat() == false, "degrade: failed connect returns false")
	_check(TwitchScript.is_chat_connected() == false, "degrade: still offline after failed connect")
	_check(TwitchScript.open_vote("blessing") == false, "degrade: no vote after failed connect")
	TwitchScript.disconnect_chat()
	_check(TwitchScript.is_chat_connected() == false, "degrade: disconnect clears state")
	# Expiry auto-closes: zero-duration vote closes on first poll.
	_go_online()
	_check(TwitchScript.open_vote("trial", 0.0) == true, "degrade: zero-duration vote opens")
	_mock.say("a", "!vote 3")
	var closed_id: String = TwitchScript.poll()
	_check(closed_id == "swarm", "degrade: expired vote auto-closes with winner")
	_check(TwitchScript.is_vote_open() == false, "degrade: expired vote is closed")
	_go_offline()


func _test_ui() -> void:
	_go_online()
	_check(TwitchScript.open_vote("blessing", 60.0) == true, "ui: vote opens")
	_mock.say("a", "!vote 1")
	TwitchScript.poll()
	var ui = VoteUIScript.new()
	root.add_child(ui)
	ui._ready()
	ui.show_vote(TwitchScript.get_vote_state())
	_check(ui.visible == true, "ui: overlay visible during vote")
	ui.refresh(TwitchScript.get_vote_state())
	ui.show_result("Rare Sighting")
	ui.hide_ui()
	_check(ui.visible == false, "ui: overlay hides cleanly")
	ui.queue_free()
	TwitchScript.cancel_vote()
	_go_offline()
