extends RefCounted
## Reaper's Reaper — Twitch vote coordinator (gameplay wiring).
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Static; game code passes the GameState node in.
##
## Opens viewer Blessing/Trial votes BETWEEN encounters (never mid-fight),
## drives the twitch_vote_ui overlay, and applies the winner. Wild zones
## call maybe_open() on player entry and after each battle; process() is
## called every frame while the player is in a zone to poll chat, refresh
## the overlay, and close/apply finished votes.
##
## Blessing and Trial votes alternate so viewers get both kinds over time.
## A cooldown (VOTE_COOLDOWN_SEC) keeps votes from spamming back-to-back.
## Everything no-ops safely when Twitch is disabled or offline.

const TwitchScript = preload("res://scripts/twitch.gd")
const VoteUIScript = preload("res://scripts/twitch_vote_ui.gd")

const VOTE_DURATION_SEC := 30.0
const VOTE_COOLDOWN_SEC := 300.0
const RESULT_BANNER_SEC := 4.0

static var _ui = null  # twitch_vote_ui CanvasLayer instance
static var _result_until_msec: int = 0


## Test hook: drop static state so tests start clean.
static func reset_for_tests() -> void:
	if _ui != null and is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null
	_result_until_msec = 0


static func _ensure_ui(host: Node) -> void:
	if _ui != null and is_instance_valid(_ui):
		return
	_ui = VoteUIScript.new()
	_ui.name = "TwitchVoteUI"
	host.add_child(_ui)


## Try to open a viewer vote. Returns true when a vote actually opened.
## Gates: Twitch enabled+configured, chat connected, not mid-vote, not
## in battle (Twitch.open_vote enforces), cooldown elapsed.
static func maybe_open(gs, host: Node) -> bool:
	if gs == null or host == null:
		return false
	if not TwitchScript.is_active():
		return false
	if not TwitchScript.is_chat_connected():
		return false
	if TwitchScript.is_vote_open():
		return false
	if not host.is_inside_tree():
		return false
	var now := Time.get_ticks_msec()
	var last := int(gs.get_stat("twitch_last_vote_msec", -1000000))
	if float(now - last) / 1000.0 < VOTE_COOLDOWN_SEC:
		return false
	# Alternate blessing/trial so both kinds get airtime.
	var kind := "blessing"
	if str(gs.get_stat("twitch_last_kind", "trial")) == "blessing":
		kind = "trial"
	if not TwitchScript.open_vote(kind, VOTE_DURATION_SEC):
		return false
	gs.set_stat("twitch_last_kind", kind)
	gs.set_stat("twitch_last_vote_msec", now)
	_ensure_ui(host)
	_ui.show_vote(TwitchScript.get_vote_state())
	print("[TWITCH] viewer vote opened: ", kind)
	return true


## Drive an open vote: poll chat, refresh the overlay, and when the vote
## closes, apply the winner and show the result banner. Returns the
## winning effect id when a vote just closed, else "". The host is used
## to (re)create the overlay if the player changed rooms mid-vote.
static func process(gs, host: Node = null) -> String:
	if not TwitchScript.is_vote_open():
		_hide_result_if_expired()
		return ""
	if (_ui == null or not is_instance_valid(_ui)) and host != null and host.is_inside_tree():
		_ensure_ui(host)
		_ui.show_vote(TwitchScript.get_vote_state())
	var winner: String = TwitchScript.poll()
	if _ui != null and is_instance_valid(_ui):
		_ui.refresh(TwitchScript.get_vote_state())
	if winner != "":
		if gs != null:
			TwitchScript.apply_effect(gs, winner)
		_show_result(winner)
		return winner
	return ""


static func _show_result(winner_id: String) -> void:
	if _ui == null or not is_instance_valid(_ui):
		return
	var label := winner_id
	for o in TwitchScript.BLESSINGS:
		if str(o.get("id", "")) == winner_id:
			label = str(o.get("name", winner_id))
	for o in TwitchScript.TRIALS:
		if str(o.get("id", "")) == winner_id:
			label = str(o.get("name", winner_id))
	_ui.show_result(label)
	_result_until_msec = Time.get_ticks_msec() + int(RESULT_BANNER_SEC * 1000.0)
	print("[TWITCH] viewers chose: ", label)


static func _hide_result_if_expired() -> void:
	if _result_until_msec <= 0:
		return
	if Time.get_ticks_msec() >= _result_until_msec:
		_result_until_msec = 0
		if _ui != null and is_instance_valid(_ui):
			_ui.hide_ui()
