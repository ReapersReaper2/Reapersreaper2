extends Area2D
## Generic stationary NPC for Reaper's Reaper (M1).
##
## NOTE: intentionally no class_name (project convention).
## Greybox visual only (colored circle + name label). E to talk when the
## player is in range: builds DialogueBox entries from `lines` and plays
## them through the room's DialogueBox (group "dialogue_box").
## Sets `talk_flag` in GameState on first conversation; after that,
## `repeat_lines` play instead of `lines`.

@export var npc_name: String = "NPC"
@export var lines: PackedStringArray = PackedStringArray()
@export var repeat_lines: PackedStringArray = PackedStringArray()
## GameState flag set when first talked to ("" = none).
@export var talk_flag: String = ""
## Body tint for the greybox circle.
@export var tint: Color = Color(0.55, 0.6, 0.75)
## Shopkeeper mode: E opens the shop UI (shop_id) instead of dialogue.
## Greybox prompt switches to "[E] shop".
@export var is_shopkeeper: bool = false
@export var shop_id: String = ""
## Stall mode: E opens the player-owned stall UI instead of dialogue.
## Greybox prompt switches to "[E] stall".
@export var is_stall: bool = false
## Trainer mode: E plays pre-battle dialogue, then starts a trainer battle
## (trainer_id in data/trainers.json). One-time via the defeat flag.
## Greybox prompt switches to "[E] battle".
## Voice lines come from trainers.json (wiring placeholders — the story bot
## owns trainer voice).
@export var is_trainer: bool = false
@export var trainer_id: String = ""
## NPC art: id of the master PNG in res://assets/npc/ (without extension).
## "" = auto-resolve from npc_name via NPC_ART; unlisted names stay greybox.
## Shopkeepers and trainers have no art yet — they keep the greybox.
@export var art_id: String = ""

## npc_name -> art file stem in res://assets/npc/.
const NPC_ART := {
	"MIRA": "mira",
	"SOLDIER": "wounded_soldier",
	"STYX": "styx",
	"FERRY_STALL_KEEPER": "ferry_stall_keeper",
	"SHORE_SCAVENGER": "shore_scavenger",
	"TIDE_HUNTER": "tide_hunter",
	"MURRAY": "murray",
	"FENNA": "fenna",
	"IVY": "ivy",
	"MARROW": "marrow",
	"HARROW": "harrow",
	"ORIGINATOR": "originator",
}
const ART_DIR := "res://assets/npc/"
## Masters are 1024x1536; 120px tall matches Mollosar's ~96-128px scale.
const ART_TARGET_H := 120.0

var _art_sprite: Sprite2D = null

const ShopScene := preload("res://scenes/shop.tscn")
const StallScene := preload("res://scenes/stall.tscn")
const TrainerData := preload("res://scripts/trainer_data.gd")

var _player_in_range: bool = false
var _dialogue_open: bool = false
## Set when the just-finished dialogue was a trainer pre-battle intro:
## the battle launches from _on_dialogue_finished.
var _trainer_battle_armed := false


func _ready() -> void:
	($Name as Label).text = npc_name
	($Body as Polygon2D).color = tint
	_apply_art()
	if is_shopkeeper:
		($Prompt as Label).text = "[E] shop"
	elif is_stall:
		($Prompt as Label).text = "[E] stall"
	elif is_trainer:
		($Prompt as Label).text = "[E] battle"
	if not is_inside_tree():
		return  # headless -s: tree services unavailable until inside tree
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	if not body_exited.is_connected(_on_body_exited):
		body_exited.connect(_on_body_exited)
	var box = get_tree().get_first_node_in_group("dialogue_box")
	if box != null and box.has_signal("dialogue_finished"):
		if not box.dialogue_finished.is_connected(_on_dialogue_finished):
			box.dialogue_finished.connect(_on_dialogue_finished)


## Headless-safe texture load: FileAccess + ImageTexture, because
## ResourceLoader needs the editor import cache (absent for files
## dropped in via the filesystem and in headless runs).
## Same pattern as mollosar_sprites.gd.
static func _load_tex(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


## Resolve which art file this NPC uses ("" = none / greybox).
func resolve_art_id() -> String:
	if art_id != "":
		return art_id
	return str(NPC_ART.get(npc_name, ""))


## Swap the greybox body for the real master art when available.
## Static pose (NPCs don't walk) — single master image, feet at y=0.
## If "<art_id>_idle.png" exists (sheet-spec 2-frame horizontal strip),
## an AnimatedSprite2D loops the idle instead. Safe to call outside
## the tree (headless tests).
func _apply_art() -> void:
	var aid := resolve_art_id()
	if aid == "":
		return
	var idle_tex := _load_tex(ART_DIR + aid + "_idle.png")
	if idle_tex != null:
		_apply_idle_art(idle_tex)
		return
	var tex := _load_tex(ART_DIR + aid + ".png")
	if tex == null:
		return
	var h := tex.get_height()
	if h <= 0:
		return
	var s := ART_TARGET_H / float(h)
	if _art_sprite == null:
		_art_sprite = Sprite2D.new()
		_art_sprite.name = "Art"
		add_child(_art_sprite)
		_hide_greybox_body()
	_art_sprite.texture = tex
	_art_sprite.scale = Vector2(s, s)
	_art_sprite.position = Vector2(0, -ART_TARGET_H * 0.5)


## Idle-sheet path: 2-frame horizontal strip (sheet spec v1, 384x384
## cells). Loops at 2fps. Murray is the first NPC with one.
func _apply_idle_art(sheet: Texture2D) -> void:
	var sheet_w := sheet.get_width()
	var sheet_h := sheet.get_height()
	if sheet_h <= 0:
		return
	var frames := SpriteFrames.new()
	frames.set_animation_speed("default", 2.0)
	frames.set_animation_loop("default", true)
	var cell := Vector2(sheet_h, sheet_h)
	var count := int(sheet_w / sheet_h)
	if count < 1:
		count = 1
	for i in count:
		var at := AtlasTexture.new()
		at.atlas = sheet
		at.region = Rect2(Vector2(cell.x * i, 0), cell)
		frames.add_frame("default", at)
	var s := ART_TARGET_H / float(sheet_h)
	var anim := AnimatedSprite2D.new()
	anim.name = "Art"
	anim.sprite_frames = frames
	anim.scale = Vector2(s, s)
	anim.position = Vector2(0, -ART_TARGET_H * 0.5)
	add_child(anim)
	if _art_sprite != null:
		_art_sprite.queue_free()
		_art_sprite = null
	_hide_greybox_body()
	if is_inside_tree():
		anim.play()


func _hide_greybox_body() -> void:
	# Greybox body hides once real art is showing; labels move up
	# so they sit above the taller figure.
	($Body as Polygon2D).visible = false
	var name_l := $Name as Label
	name_l.offset_top = -ART_TARGET_H - 50.0
	name_l.offset_bottom = -ART_TARGET_H - 26.0
	var prompt_l := $Prompt as Label
	prompt_l.offset_top = -ART_TARGET_H - 90.0
	prompt_l.offset_bottom = -ART_TARGET_H - 66.0


## True when this NPC is showing real art instead of the greybox.
func has_art() -> bool:
	if _art_sprite != null and _art_sprite.texture != null:
		return true
	return get_node_or_null("Art") is AnimatedSprite2D


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		$Prompt.visible = true


func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		$Prompt.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if _dialogue_open or not _player_in_range:
		return
	if event.is_action_pressed("interact"):
		# Swallow the press so the dialogue box doesn't instantly advance.
		get_viewport().set_input_as_handled()
		_talk.call_deferred()


func _talk() -> void:
	if is_shopkeeper:
		_open_shop()
		return
	if is_stall:
		_open_stall()
		return
	if is_trainer:
		_trainer_interact()
		return
	var box = get_tree().get_first_node_in_group("dialogue_box")
	if box == null or not box.has_method("start_dialogue"):
		push_warning("npc.gd: no dialogue box for " + npc_name)
		return
	_dialogue_open = true
	$Prompt.visible = false
	var use_lines := lines
	var gs = get_node_or_null("/root/GameState")
	if talk_flag != "" and gs != null and gs.has_method("get_flag") and bool(gs.get_flag(talk_flag)):
		if not repeat_lines.is_empty():
			use_lines = repeat_lines
	var entries: Array = []
	for line in use_lines:
		entries.append({"type": "dialogue", "character": npc_name, "text": line})
	box.start_dialogue(entries)


func _on_dialogue_finished() -> void:
	if not _dialogue_open:
		return
	_dialogue_open = false
	if talk_flag != "":
		var gs = get_node_or_null("/root/GameState")
		if gs != null and gs.has_method("set_flag"):
			gs.set_flag(talk_flag)
	if _trainer_battle_armed:
		_trainer_battle_armed = false
		_launch_trainer_battle.call_deferred()
		return
	if _player_in_range:
		$Prompt.visible = true


## Trainer branch: E on a trainer NPC. Defeated trainers replay their
## post-battle lines; otherwise the pre-battle intro plays and the battle
## launches when it finishes.
func _trainer_interact() -> void:
	var t: Dictionary = TrainerData.get_trainer(trainer_id)
	if t.is_empty():
		push_warning("npc.gd: unknown trainer '" + trainer_id + "'")
		return
	var gs = get_node_or_null("/root/GameState")
	var defeated := false
	if gs != null and gs.has_method("get_flag"):
		defeated = bool(gs.get_flag(TrainerData.defeat_flag(trainer_id)))
	var box = get_tree().get_first_node_in_group("dialogue_box")
	if box == null or not box.has_method("start_dialogue"):
		push_warning("npc.gd: no dialogue box for trainer " + npc_name)
		return
	_dialogue_open = true
	$Prompt.visible = false
	var key := "post_dialogue" if defeated else "pre_dialogue"
	var entries: Array = []
	for line in (t.get(key, []) as Array):
		entries.append({"type": "dialogue", "character": npc_name, "text": str(line)})
	if entries.is_empty():
		# No lines: skip straight to the battle (or back to idle).
		_dialogue_open = false
		if not defeated:
			_launch_trainer_battle.call_deferred()
		elif _player_in_range:
			$Prompt.visible = true
		return
	_trainer_battle_armed = not defeated
	box.start_dialogue(entries)


## Start the trainer battle from the room the NPC lives in. The room root
## carries room_id; the player node is in the "player" group.
func _launch_trainer_battle() -> void:
	if not is_inside_tree():
		return
	var bm = get_node_or_null("/root/BattleManager")
	if bm == null or not bm.has_method("start_trainer_battle"):
		push_warning("npc.gd: BattleManager missing, trainer battle skipped")
		_dialogue_open = false
		if _player_in_range:
			$Prompt.visible = true
		return
	var room_id := ""
	var node: Node = self
	while node != null:
		if "room_id" in node:
			room_id = str(node.get("room_id"))
			break
		node = node.get_parent()
	var pos := Vector2.ZERO
	var player = get_tree().get_first_node_in_group("player")
	if player is Node2D:
		pos = (player as Node2D).position
	if room_id == "":
		push_warning("npc.gd: trainer NPC has no room_id ancestor")
		_dialogue_open = false
		if _player_in_range:
			$Prompt.visible = true
		return
	print("[NPC] trainer battle: ", trainer_id, " in ", room_id)
	bm.start_trainer_battle(trainer_id, room_id, pos)


## Shopkeeper branch: instance the shop overlay instead of dialogue.
func _open_shop() -> void:
	if not is_inside_tree():
		return
	if get_tree().get_first_node_in_group("shop") != null:
		return  # already open
	var shop = ShopScene.instantiate()
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		shop.game_state = gs
	get_tree().root.add_child(shop)
	$Prompt.visible = false
	if shop.has_signal("closed"):
		shop.closed.connect(_on_shop_closed)
	if not shop.open_shop(shop_id):
		shop.queue_free()
		if _player_in_range:
			$Prompt.visible = true


func _on_shop_closed() -> void:
	if _player_in_range:
		$Prompt.visible = true


## Stall branch: instance the stall management UI instead of dialogue.
func _open_stall() -> void:
	if not is_inside_tree():
		return
	if get_tree().get_first_node_in_group("stall") != null:
		return  # already open
	var stall_ui = StallScene.instantiate()
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		stall_ui.game_state = gs
	get_tree().root.add_child(stall_ui)
	$Prompt.visible = false
	if stall_ui.has_signal("closed"):
		stall_ui.closed.connect(_on_shop_closed)
	if not stall_ui.open_stall():
		stall_ui.queue_free()
		if _player_in_range:
			$Prompt.visible = true
