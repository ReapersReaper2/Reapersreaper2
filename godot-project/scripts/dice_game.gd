extends RefCounted
## Dead Man's Dice — press-your-luck 5d6 vs an NPC (Murray's Bar back room).
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Pure logic: no scene deps, fully headless-testable. dice_ui.gd renders it.
##
## Rules (doc 05 §3): roll 5d6, bank the score or push (re-roll non-scoring
## dice). Scoring per roll: 1 = 100, 5 = 50, three-of-a-kind = face x 100
## (three 1s = 1000). A roll scoring < 50 is a bust: round score lost, turn
## passes. First to 5,000 banked wins the pot. Hot dice: when every die
## scores, the next push rolls a fresh 5.
##
## State lives in GameState.state["dice"] (lazy — old saves work):
##   {"copper_wins": n, "copper_losses": n, "blend_wins": n,
##    "blend_losses": n, "quiet_wins": n, "quiet_losses": n,
##    "wrath_beaten": bool, "latch_answers": [ids]}

const WIN_SCORE := 5000
const DICE_COUNT := 5
const COPPER_BUY_IN := 50
const COPPER_POT := 100
const BLEND_BUY_ITEM := "rare_herb"
const BLEND_POT_ITEM := "house_blend"
const HIGH_ROLLER_WINS := 10

## table_id -> config. ai_bank: opponent banks at/above this round score.
const TABLES := {
	"copper": {
		"name": "Copper Table", "stake": "credits", "ai_bank": 800,
		"hint": "Copper table. Murray deals — small stakes, honest dice.",
	},
	"blend": {
		"name": "Blend Table", "stake": "blend", "ai_bank": 1000,
		"hint": "Blend table. Bigger pots, sharper tongues.",
	},
	"quiet": {
		"name": "The Quiet Table", "stake": "info", "ai_bank": 1200,
		"hint": "The quiet table: no credits. Latch plays for answers.",
	},
}

## Blend-table rotating regulars. Story-bot text (2026-10-05, dice-table-text.md):
## herb traders, an off-duty reaper, one very suspicious botanist.
## loss_line: what the opponent says when the player takes the pot.
const BLEND_OPPONENTS := [
	{"name": "Gruff Trader", "ai_bank": 1000,
		"taunt": "GRUFF TRADER: \"You roll like you breed — hoping.\"",
		"loss_line": "GRUFF TRADER: \"...Lucky.\""},
	{"name": "Off-duty Reaper", "ai_bank": 1150,
		"taunt": "OFF-DUTY REAPER: \"I've reaped braver men than you. They all pushed.\"",
		"loss_line": "OFF-DUTY REAPER: \"Huh.\""},
	{"name": "Botanist", "ai_bank": 1300,
		"taunt": "BOTANIST: [sniffing the air] \"Nervous sweat. Good for the blend, bad for the dice.\"",
		"loss_line": "BOTANIST: [already writing] \"Fascinating.\""},
]

const WRATH_NAME := "Wrath"
const LATCH_NAME := "Latch"
## Wrath intro beat (copper table, Act 1) — story-bot text 2026-10-05.
## Paged by the dice UI on first copper sit.
const WRATH_INTRO_LINES := [
	{"type": "direction", "text": "[Wrath is already seated when Mollosar approaches. He doesn't look up from the dice.]"},
	{"type": "dialogue", "character": "WRATH", "text": "Sit. You're the new reaper. I've been waiting to take your credits."},
	{"type": "dialogue", "character": "MOLLOSAR", "text": "..."},
	{"type": "dialogue", "character": "WRATH", "text": "[finally looking up, grinning] That's the spirit. Roll."},
]
## Wrath table-flip beat — story-bot text 2026-10-05 (dice-table-text.md).
const WRATH_FLIP_LINES := [
	{"type": "direction", "text": "[Wrath stares at the dice for a long moment — then he flips the table. Dice everywhere. Silence. Then he laughs, loud and real, and buys two drinks.]"},
	{"type": "dialogue", "character": "WRATH", "text": "Luck. Yours. Not mine. Remember the difference."},
	{"type": "dialogue", "character": "LUNA", "text": "[quietly, as they leave] ...He let you win."},
	{"type": "dialogue", "character": "MOLLOSAR", "text": "I know."},
	{"type": "dialogue", "character": "LUNA", "text": "Why?"},
	{"type": "dialogue", "character": "MOLLOSAR", "text": "[beat] I don't think he knows either."},
]

## Murray's copper-table hints (tutorial-adjacent, his voice) — story-bot
## text 2026-10-05. One-shot events: first sit / first push / first bust.
const MURRAY_HINTS := {
	"sit": "MURRAY: \"Copper table. Low stakes, high lessons. Roll, bank, or push — that's the whole game. The dice don't care about your plans.\"",
	"push": "MURRAY: \"Pushing, eh? Bold. Stupid. Same thing, at this table.\"",
	"bust": "MURRAY: \"And that's why they call it Dead Man's Dice. Drink's on me. First one's always free.\"",
}

## Generic-flow re-cut lines — story-bot text (2026-10-05 re-cut). Keyed so
## tests assert BY KEY without pinning exact wording: the story bot re-cuts
## freely, and only the string values here change. dice_ui.gd reads them
## through flow_line(); no other code homes these keys.
const FLOW_LINES := {
	"bust_line": "Bust. Your round score is gone.",
	"opp_bust": "%s …busts. Round score gone.",
	"buyin_denied": "You cannot cover this table's stake.",
}


## Keyed lookup for a generic-flow line. "" for unknown keys.
static func flow_line(key: String) -> String:
	return str(FLOW_LINES.get(key, ""))

## One-shot story flags (Wrath intro, Murray hints). Returns true the first
## time key fires and marks it; false afterwards.
static func one_shot(gs, key: String) -> bool:
	if gs == null:
		return false
	var d := _data(gs)
	if bool(d.get(key, false)):
		return false
	d[key] = true
	return true

const ANSWERS_PATH := "res://data/dice_answers.json"
static var _answers_cache: Array = []


# --- Scoring ------------------------------------------------------------

## Score one roll. Returns {"score": int, "scoring": int} where scoring is
## the number of dice that contributed (the rest get re-rolled on push).
static func score_dice(dice: Array) -> Dictionary:
	var counts := {}
	for d in dice:
		var face := int(d)
		counts[face] = int(counts.get(face, 0)) + 1
	var score := 0
	var scoring := 0
	for face in counts:
		var c: int = counts[face]
		if c >= 3:
			score += 1000 if face == 1 else face * 100
			scoring += 3
			c -= 3
		if face == 1:
			score += c * 100
			scoring += c
		elif face == 5:
			score += c * 50
			scoring += c
	return {"score": score, "scoring": scoring}


static func is_bust(dice: Array) -> bool:
	return int(score_dice(dice)["score"]) < 50


# --- Game instance ------------------------------------------------------

var table_id := ""
var opponent_name := ""
var ai_bank := 800
var player_banked := 0
var opp_banked := 0
var round_score := 0
var dice_in_hand := DICE_COUNT
var phase := "idle"  # idle | player_turn | over
var winner := ""  # "" | "player" | "opponent"
var last_roll: Array = []
## Test hook: when non-empty, rolls pop from here instead of randi().
var test_rolls: Array = []


func setup(tid: String, opp_name: String = "") -> void:
	table_id = tid
	var cfg: Dictionary = TABLES.get(tid, TABLES["copper"])
	if opp_name != "":
		opponent_name = opp_name
	elif tid == "copper":
		opponent_name = WRATH_NAME
	elif tid == "quiet":
		opponent_name = LATCH_NAME
	else:
		opponent_name = "Regular"
	ai_bank = int(cfg.get("ai_bank", 800))
	player_banked = 0
	opp_banked = 0
	round_score = 0
	dice_in_hand = DICE_COUNT
	phase = "player_turn"
	winner = ""
	last_roll = []


func _roll(n: int) -> Array:
	var out: Array = []
	for i in n:
		if not test_rolls.is_empty():
			out.append(int(test_rolls.pop_front()))
		else:
			out.append(randi_range(1, 6))
	return out


## Player rolls. Returns {"dice": [...], "score": n, "bust": bool}.
func player_roll() -> Dictionary:
	if phase != "player_turn":
		return {"dice": [], "score": 0, "bust": true}
	var dice := _roll(dice_in_hand)
	last_roll = dice
	var s := score_dice(dice)
	if int(s["score"]) == 0:
		round_score = 0
		return {"dice": dice, "score": 0, "bust": true}
	round_score += int(s["score"])
	dice_in_hand = dice_in_hand - int(s["scoring"])
	if dice_in_hand <= 0:
		dice_in_hand = DICE_COUNT  # hot dice: everything scored
	return {"dice": dice, "score": int(s["score"]), "bust": false}


## Player banks the round score. Returns {"winner": "" | "player"}.
func player_bank() -> Dictionary:
	if phase != "player_turn":
		return {"winner": winner}
	player_banked += round_score
	round_score = 0
	if player_banked >= WIN_SCORE:
		winner = "player"
		phase = "over"
	return {"winner": winner}


## Push = roll again with the remaining dice (no-op marker; the next
## player_roll() uses dice_in_hand). Returns false when nothing to push.
func player_push() -> bool:
	return phase == "player_turn" and dice_in_hand > 0


## Opponent AI: rolls until bust or round_score >= ai_bank. Returns a log
## of rolls plus the outcome. Safety-capped at 25 rolls.
func play_opponent_turn() -> Dictionary:
	var log: Array = []
	var o_round := 0
	var o_hand := DICE_COUNT
	for i in 25:
		var dice := _roll(o_hand)
		var s := score_dice(dice)
		log.append({"dice": dice, "score": int(s["score"])})
		if int(s["score"]) == 0:
			return {"log": log, "bust": true, "winner": winner}
		o_round += int(s["score"])
		if o_round >= ai_bank:
			opp_banked += o_round
			if opp_banked >= WIN_SCORE:
				winner = "opponent"
				phase = "over"
			return {"log": log, "bust": false, "winner": winner}
		o_hand = o_hand - int(s["scoring"])
		if o_hand <= 0:
			o_hand = DICE_COUNT
	return {"log": log, "bust": false, "winner": winner}


# --- State / economy (static, merchants.gd pattern) ---------------------

static func _data(gs) -> Dictionary:
	var blank := {
		"copper_wins": 0, "copper_losses": 0,
		"blend_wins": 0, "blend_losses": 0,
		"quiet_wins": 0, "quiet_losses": 0,
		"wrath_beaten": false, "latch_answers": [],
	}
	if gs == null or gs.get("state") == null:
		return blank
	var st: Dictionary = gs.get("state")
	if not st.has("dice") or not (st["dice"] is Dictionary):
		st["dice"] = blank.duplicate(true)
	var d: Dictionary = st["dice"]
	for k in blank:
		if not d.has(k):
			d[k] = blank[k] if not (blank[k] is Array) else []
	return d


static func table_ids() -> Array:
	return TABLES.keys()


static func table_name(tid: String) -> String:
	return str(TABLES.get(tid, {}).get("name", tid))


static func table_hint(tid: String) -> String:
	return str(TABLES.get(tid, {}).get("hint", ""))


## Blend opponent for the night: rotates on blend wins.
static func blend_opponent(gs) -> Dictionary:
	var d := _data(gs)
	var idx := int(d.get("blend_wins", 0) + d.get("blend_losses", 0)) % BLEND_OPPONENTS.size()
	return BLEND_OPPONENTS[idx]


static func table_unlocked(gs, tid: String) -> bool:
	if gs == null:
		return false
	if not bool(gs.get_flag("m2_hub_unlocked")):
		return false
	var d := _data(gs)
	match tid:
		"copper":
			return true
		"blend":
			return int(d.get("copper_wins", 0)) >= 1
		"quiet":
			return bool(gs.get_flag("act2_unlocked"))
	return false


static func lock_reason(gs, tid: String) -> String:
	# Lock 1 (back room, all three tables): story-bot text 2026-10-05.
	if not bool(gs.get_flag("m2_hub_unlocked")):
		return "The back room is not open to you yet."
	# Lock 2 (blend table, needs 1+ copper win): story-bot text 2026-10-05.
	if tid == "blend":
		return "Win a hand at the copper table first."
	# Lock 3 (quiet table, Act 2 gate): already-live line — do not re-cut.
	if tid == "quiet":
		return "Latch isn't dealing until Act 2."
	return ""


## Take the buy-in. Returns false (no write) when the player can't pay.
static func pay_buy_in(gs, tid: String) -> bool:
	if gs == null:
		return false
	match tid:
		"copper":
			return gs.spend_soul_credits(COPPER_BUY_IN)
		"blend":
			return gs.use_item(BLEND_BUY_ITEM)
		"quiet":
			return true
	return false


## Record a finished game. Returns {"wrath_flip": bool, "answer": Dictionary}.
## wrath_flip: first copper win vs Wrath (table-flip + drink + flag).
## answer: the Latch answer unlocked by a quiet win ({} when none left).
static func record_win(gs, tid: String) -> Dictionary:
	var out := {"wrath_flip": false, "answer": {}}
	if gs == null:
		return out
	var d := _data(gs)
	d[tid + "_wins"] = int(d.get(tid + "_wins", 0)) + 1
	match tid:
		"copper":
			gs.add_soul_credits(COPPER_POT)
			if not bool(d.get("wrath_beaten", false)):
				d["wrath_beaten"] = true
				gs.set_flag("dice_beat_wrath", true)
				out["wrath_flip"] = true
			if int(d["copper_wins"]) >= HIGH_ROLLER_WINS:
				_unlock(gs, "high_roller")
		"blend":
			gs.add_item(BLEND_POT_ITEM, 1)
		"quiet":
			out["answer"] = _unlock_answer(gs)
			_unlock(gs, "quiet_wisdom")
			# Steam "drowned_dice" — trigger map: dice_won_max_stakes
			# flag. The Quiet Table is the highest tier (ai_bank 1200;
			# Latch plays for answers), so a quiet win == max stakes.
			if gs != null and gs.has_method("set_flag"):
				gs.set_flag("dice_won_max_stakes", true)
			else:
				_unlock(gs, "drowned_dice")
	return out


static func record_loss(gs, tid: String) -> void:
	if gs == null:
		return
	var d := _data(gs)
	d[tid + "_losses"] = int(d.get(tid + "_losses", 0)) + 1


static func _unlock(gs, achievement_id: String) -> void:
	if gs == null:
		return
	var ach = gs.get("achievements")
	if ach != null and ach.has_method("unlock"):
		ach.unlock(achievement_id)


static func wins(gs, tid: String) -> int:
	return int(_data(gs).get(tid + "_wins", 0))


static func wrath_beaten(gs) -> bool:
	return bool(_data(gs).get("wrath_beaten", false))


# --- Latch answers ------------------------------------------------------

static func load_answers() -> Array:
	if not _answers_cache.is_empty():
		return _answers_cache
	if not FileAccess.file_exists(ANSWERS_PATH):
		return []
	var f := FileAccess.open(ANSWERS_PATH, FileAccess.READ)
	if f == null:
		return []
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		_answers_cache = d.get("answers", [])
	return _answers_cache


static func unlocked_answers(gs) -> Array:
	return _data(gs).get("latch_answers", [])


## Unlock the next unanswered Latch answer. Returns the answer dict, or {}
## when all five are already unlocked.
static func _unlock_answer(gs) -> Dictionary:
	var d := _data(gs)
	var have: Array = d.get("latch_answers", [])
	for a in load_answers():
		var aid := str(a.get("id", ""))
		if aid != "" and not have.has(aid):
			have.append(aid)
			d["latch_answers"] = have
			return a
	return {}


static func answer_text(answer_id: String) -> String:
	for a in load_answers():
		if str(a.get("id", "")) == answer_id:
			return str(a.get("answer", ""))
	return ""
