extends RefCounted
## Reaper's Reaper — Twitch Integration (viewer voting).
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Static manager; game code passes the GameState node in.
##
## Streamers opt in via the `enabled` flag (default OFF — always opt-in).
## Channel name + OAuth token live in user://twitch.cfg, never hardcoded.
## Chat is read over Twitch IRC (irc.chat.twitch.tv:6667) through an
## injected transport; tests inject a mock, so no real endpoints are hit.
##
## Voting happens BETWEEN encounters only — never mid-fight. Game code:
##   Twitch.set_in_battle(true/false)   # battle_manager hooks
##   if Twitch.open_vote("blessing"):   # wild_zone / room triggers this
##       ...show TwitchVoteUI, call Twitch.poll() each frame...
##       var result: Dictionary = Twitch.close_vote()  # on countdown end
##
## Blessings (positive viewer events):
##   rare_spawn   — next wild encounter rolls a rare creature
##   bonus_loot   — next battle's Soul Credit reward x2
##   full_heal    — party healed to full immediately (Party.heal_all)
## Trials (challenge, never punishment):
##   hard_encounter — next wild encounter is +4 levels
##   heavy_handed   — enemies deal +50% damage next fight
##   swarm          — next wild encounter adds an extra enemy
##
## Effect application sets `twitch_<id>` stat flags on GameState, consumed by:
##   twitch_rare_spawn    — wild_zone.gd: force rare roll on next encounter (consumed)
##   twitch_bonus_loot    — battle.gd: Soul Credit reward x2 on next victory (consumed)
##   twitch_hard_encounter— wild_zone.gd: +4 levels on next encounter (consumed)
##   twitch_heavy_handed  — battle_unit.gd: incoming damage x1.5 next fight (consumed)
##   twitch_swarm         — wild_zone.gd: spawn one extra enemy next encounter (consumed)
##   (full_heal applies immediately via Party.heal_all — no flag needed)
##
## Graceful degradation: every public function no-ops safely when disabled,
## unconfigured, or disconnected. Connection failures never break gameplay.

const PartyScript = preload("res://scripts/party.gd")

const CONFIG_PATH := "user://twitch.cfg"
const IRC_HOST := "irc.chat.twitch.tv"
const IRC_PORT := 6667
const VOTE_PREFIX := "!vote"

## Blessing definitions: id -> {name, desc}.
const BLESSINGS: Array = [
	{"id": "rare_spawn", "name": "Rare Sighting", "desc": "Next wild encounter is a rare creature"},
	{"id": "bonus_loot", "name": "Rich Veins", "desc": "Next battle pays double Soul Credits"},
	{"id": "full_heal", "name": "Second Wind", "desc": "Party healed to full, right now"},
]

## Trial definitions: id -> {name, desc}.
const TRIALS: Array = [
	{"id": "hard_encounter", "name": "Trial by Fire", "desc": "Next encounter is much stronger"},
	{"id": "heavy_handed", "name": "Heavy Hands", "desc": "Enemies hit 50% harder next fight"},
	{"id": "swarm", "name": "The Swarm", "desc": "Next encounter brings an extra enemy"},
]

static var _config_path: String = CONFIG_PATH
static var _enabled: bool = false
static var _channel: String = ""
static var _token: String = ""
static var _loaded: bool = false
static var _transport = null  # injected chat transport (real IRC or mock)
static var _in_battle: bool = false
static var _vote: Dictionary = {}  # active vote state, empty when idle


## ---------------------------------------------------------------- config ---

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	_enabled = false
	_channel = ""
	_token = ""
	var cfg := ConfigFile.new()
	if cfg.load(_config_path) != OK:
		return
	_enabled = bool(cfg.get_value("twitch", "enabled", false))
	_channel = str(cfg.get_value("twitch", "channel", ""))
	_token = str(cfg.get_value("twitch", "token", ""))


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("twitch", "enabled", _enabled)
	cfg.set_value("twitch", "channel", _channel)
	cfg.set_value("twitch", "token", _token)
	cfg.save(_config_path)


## Test hook: redirect the config file so tests never touch the real one.
static func set_config_path(path: String) -> void:
	_config_path = path
	_loaded = false


## Store channel + OAuth token. Never hardcoded; lives in user://twitch.cfg.
static func configure(channel: String, token: String) -> void:
	_ensure_loaded()
	_channel = channel.strip_edges().trim_prefix("#").to_lower()
	_token = token.strip_edges().trim_prefix("oauth:")
	_save()


static func set_enabled(on: bool) -> void:
	_ensure_loaded()
	_enabled = on
	_save()


static func is_enabled() -> bool:
	_ensure_loaded()
	return _enabled


static func get_channel() -> String:
	_ensure_loaded()
	return _channel


## True only when the streamer opted in AND supplied channel + token.
static func is_active() -> bool:
	_ensure_loaded()
	return _enabled and _channel != "" and _token != ""


## ------------------------------------------------------------- transport ---

## Real Twitch IRC chat transport. Only constructed on connect() — never in tests.
class TwitchIRC extends RefCounted:
	var _peer: StreamPeerTCP = null
	var _channel: String = ""
	var _buf: String = ""
	var _connected: bool = false

	func connect_chat(channel: String, nick: String, token: String) -> bool:
		_channel = channel
		_peer = StreamPeerTCP.new()
		var err: Error = _peer.connect_to_host(IRC_HOST, IRC_PORT)
		if err != OK:
			_connected = false
			return false
		# Wait briefly for the TCP handshake (non-blocking game loop would
		# normally spread this out; keep it short and failure-safe here).
		var tries := 0
		while tries < 40 and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTING:
			_peer.poll()
			OS.delay_msec(50)
			tries += 1
		if _peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_connected = false
			return false
		_send("PASS oauth:" + token)
		_send("NICK " + nick)
		_send("JOIN #" + channel)
		_send("CAP REQ :twitch.tv/tags")
		_connected = true
		return true

	func chat_connected() -> bool:
		return _connected and _peer != null and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED

	func disconnect_chat() -> void:
		_connected = false
		if _peer != null:
			_peer.disconnect_from_host()
			_peer = null

	func _send(line: String) -> void:
		if _peer != null and _peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			_peer.put_data((line + "\r\n").to_utf8_buffer())

	## Drain available bytes, return parsed chat messages: [{user, text}].
	func poll_messages() -> Array:
		var out: Array = []
		if not chat_connected():
			return out
		_peer.poll()
		var avail: int = _peer.get_available_bytes()
		if avail > 0:
			var chunk: PackedByteArray = _peer.get_data(avail)[1]
			_buf += chunk.get_string_from_utf8()
		while "\r\n" in _buf:
			var idx: int = _buf.find("\r\n")
			var line: String = _buf.substr(0, idx)
			_buf = _buf.substr(idx + 2)
			var msg: Dictionary = _parse_line(line)
			if not msg.is_empty():
				out.append(msg)
		return out

	func _parse_line(line: String) -> Dictionary:
		if line.begins_with("PING"):
			_send("PONG" + line.substr(4))
			return {}
		# :user!user@user.tmi.twitch.tv PRIVMSG #channel :message text
		if " PRIVMSG #" not in line:
			return {}
		var bang: int = line.find("!")
		var msgmark: int = line.find(" :", line.find("PRIVMSG"))
		if bang < 1 or msgmark < 0:
			return {}
		return {
			"user": line.substr(1, bang - 1).to_lower(),
			"text": line.substr(msgmark + 2),
		}


## Test hook: inject a mock transport (must implement connect_chat,
## poll_messages, chat_connected, disconnect_chat).
static func set_transport(t) -> void:
	_transport = t


static func connect_chat() -> bool:
	_ensure_loaded()
	if not is_active():
		return false
	if _transport == null:
		_transport = TwitchIRC.new()
	var nick: String = _channel  # use channel name as nick; fine for read-only chat
	var ok: bool = _transport.connect_chat(_channel, nick, _token)
	if not ok:
		_transport = null  # drop the dead transport; gameplay unaffected
		return false
	return true


static func disconnect_chat() -> void:
	if _transport != null:
		_transport.disconnect_chat()
		_transport = null
	cancel_vote()


static func is_chat_connected() -> bool:
	return _transport != null and _transport.chat_connected()


## ----------------------------------------------------------------- voting ---

static func set_in_battle(b: bool) -> void:
	_in_battle = b


static func is_vote_open() -> bool:
	return not _vote.is_empty()


static func _options_for(kind: String) -> Array:
	if kind == "blessing":
		return BLESSINGS
	if kind == "trial":
		return TRIALS
	return []


## Open a viewer vote. Only between encounters — never mid-fight.
## Returns false (game continues normally) when disabled, offline,
## already voting, or given a bad kind.
static func open_vote(kind: String, duration_sec: float = 60.0) -> bool:
	_ensure_loaded()
	if kind != "blessing" and kind != "trial":
		return false
	if not is_active():
		return false
	if not is_chat_connected():
		return false
	if _in_battle:
		return false
	if is_vote_open():
		return false
	var opts: Array = []
	for o in _options_for(kind):
		opts.append({"id": o["id"], "name": o["name"], "desc": o["desc"], "votes": 0})
	_vote = {
		"kind": kind,
		"options": opts,
		"ballots": {},  # user -> option index (latest vote wins)
		"started_msec": Time.get_ticks_msec(),
		"duration_msec": int(duration_sec * 1000.0),
	}
	return true


## Parse one chat message into an option index, or -1 if not a valid vote.
static func _parse_vote(text: String, options: Array) -> int:
	var t: String = text.strip_edges().to_lower()
	if not t.begins_with(VOTE_PREFIX):
		return -1
	var arg: String = t.substr(VOTE_PREFIX.length()).strip_edges()
	if arg == "":
		return -1
	# Numeric: !vote 1
	if arg.is_valid_int():
		var n: int = int(arg) - 1
		if n >= 0 and n < options.size():
			return n
		return -1
	# By id or name fragment: !vote rare_spawn / !vote rare
	for i in options.size():
		var oid: String = str(options[i]["id"]).to_lower()
		var oname: String = str(options[i]["name"]).to_lower()
		if arg == oid or arg in oname or oname.begins_with(arg):
			return i
	return -1


## Called each frame by game code while a vote is open. Tallies chat votes;
## auto-closes when the countdown expires (applies the winner).
## Returns the winning effect id when a vote just closed, else "".
static func poll() -> String:
	if not is_vote_open():
		return ""
	if _transport != null and _transport.chat_connected():
		for msg in _transport.poll_messages():
			var idx: int = _parse_vote(str(msg.get("text", "")), _vote["options"])
			if idx >= 0:
				_vote["ballots"][str(msg.get("user", ""))] = idx
	_recount()
	var elapsed: int = int(Time.get_ticks_msec()) - int(_vote["started_msec"])
	if elapsed >= int(_vote["duration_msec"]):
		var res: Dictionary = close_vote()
		return str(res.get("winner_id", ""))
	return ""


static func _recount() -> void:
	for o in _vote["options"]:
		o["votes"] = 0
	for user in _vote["ballots"]:
		var idx: int = int(_vote["ballots"][user])
		if idx >= 0 and idx < _vote["options"].size():
			_vote["options"][idx]["votes"] = int(_vote["options"][idx]["votes"]) + 1


## Snapshot of the active vote for the UI overlay. Empty dict when idle.
static func get_vote_state() -> Dictionary:
	if not is_vote_open():
		return {}
	_recount()
	var elapsed: int = int(Time.get_ticks_msec()) - int(_vote["started_msec"])
	var left: float = maxf(0.0, (float(_vote["duration_msec"]) - float(elapsed)) / 1000.0)
	var opts: Array = []
	for o in _vote["options"]:
		opts.append({"id": o["id"], "name": o["name"], "desc": o["desc"], "votes": int(o["votes"])})
	var total := 0
	for o in opts:
		total += int(o["votes"])
	return {
		"kind": _vote["kind"],
		"options": opts,
		"seconds_left": left,
		"total_votes": total,
	}


## Close the vote, apply the winning Blessing/Trial, return the result.
## Most votes wins; ties go to the earliest option; zero votes = no winner.
static func close_vote() -> Dictionary:
	if not is_vote_open():
		return {"winner_id": "", "applied": false}
	_recount()
	var best := -1
	var best_votes := 0
	for i in _vote["options"].size():
		var v: int = int(_vote["options"][i]["votes"])
		if v > best_votes:
			best_votes = v
			best = i
	var winner_id := ""
	var applied := false
	if best >= 0:
		winner_id = str(_vote["options"][best]["id"])
		applied = true
	_vote = {}
	return {"winner_id": winner_id, "applied": applied}


## Close without applying anything (e.g. streamer cancelled).
static func cancel_vote() -> void:
	_vote = {}


## Apply a winning effect id to the game state. Returns false for unknown ids.
static func apply_effect(gs, effect_id: String) -> bool:
	match effect_id:
		"rare_spawn":
			gs.set_stat("twitch_rare_spawn", true)
			return true
		"bonus_loot":
			gs.set_stat("twitch_bonus_loot", true)
			return true
		"full_heal":
			PartyScript.heal_all(gs)
			return true
		"hard_encounter":
			gs.set_stat("twitch_hard_encounter", true)
			return true
		"heavy_handed":
			gs.set_stat("twitch_heavy_handed", true)
			return true
		"swarm":
			gs.set_stat("twitch_swarm", true)
			return true
	return false


## Full close: tally, apply the winner to game state, return the result.
## Convenience for game code: winner effect is live when this returns.
static func close_and_apply(gs) -> Dictionary:
	var res: Dictionary = close_vote()
	if bool(res.get("applied", false)):
		apply_effect(gs, str(res.get("winner_id", "")))
	return res
