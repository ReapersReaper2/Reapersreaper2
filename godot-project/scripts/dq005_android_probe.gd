extends Node
## DQ-005 instrumented Android reproduction — diagnostic branch ONLY.
## Does not change the loader, approval rules, attack timing or animations.
var _elapsed: float = 0.0
var _done: bool = false

func _ready() -> void:
	if OS.has_feature("android"):
		print("[DQ005_ANDROID] boot platform=", OS.get_name())
		call_deferred("_enter_bridge")

func _enter_bridge() -> void:
	print("[DQ005_ANDROID] switching to opening bridge")
	var err := get_tree().change_scene_to_file("res://scenes/room_p1.tscn")
	print("[DQ005_ANDROID] change_scene status=", err)

func _process(delta: float) -> void:
	if not OS.has_feature("android") or _done:
		return
	_elapsed += delta
	if _elapsed < 2.5:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var player := scene.find_child("Player", true, false)
	if player == null:
		if _elapsed > 20.0:
			_done = true
			push_error("[DQ005_ANDROID] no Player node after 20 seconds")
		return
	_done = true
	var mgr = player.get("sprites")
	if mgr == null:
		push_error("[DQ005_ANDROID] Player has no sprite manager")
		return
	var clip_count: int = mgr._attack_clips.size()
	print("[DQ005_ANDROID] bridge form=", mgr._form, " clips=", clip_count)
	var rendered: bool = mgr._try_approved_attack(1, 0.5, Vector2.DOWN)
	print("[DQ005_ANDROID] approved slash displayed=", rendered,
		" texture=", mgr._sprite.texture.get_class() if mgr._sprite.texture != null else "<null>",
		" frames=", mgr._sprite.region_rect)
	print("[DQ005_ANDROID] RESULT ", "PASS" if rendered and clip_count == 20 else "FAIL")
