extends SceneTree
## Approved creature masters must fit the same 210px combat space without
## editing their source pixels, blocking battle UI, or requiring LFS smudge.
## godot --headless --path godot-project --script res://scripts/battle_art_fit_test.gd

const Battle := preload("res://scripts/battle.gd")
var _checks := 0
var _failed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var painting := Image.create(1120, 2240, false, Image.FORMAT_RGBA8)
	painting.fill(Color(0.7, 0.25, 0.18, 1.0))
	var big := ImageTexture.create_from_image(painting)
	var factor := Battle.battle_art_scale(big)
	_check(is_equal_approx(factor, 210.0 / 2240.0),
		"2240px master is scaled to the existing battle display limit")
	_check(factor * 1120.0 < Battle.BATTLE_ART_MAX_DIM,
		"portrait master preserves aspect ratio and horizontal breathing room")

	var sheet := Image.create(384, 384, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.WHITE)
	var small := ImageTexture.create_from_image(sheet)
	_check(is_equal_approx(Battle.battle_art_scale(small), 210.0 / 384.0),
		"384px master keeps the previous battle readability")
	_check(Battle.battle_art_scale(null) == 1.0,
		"null image never triggers a divide-by-zero")
	# Integrate with real source/bundled art, including 2,240px painting
	# masters and transparent 384px cells.
	for species in ["dragonthorn", "gloomcap", "spinehopper", "bellmaw", "wispwillow"]:
		var visual := Battle.make_creature_visual(
			species, Vector2(960, 340), Color(0.5, 0.5, 0.5), 64.0)
		_check(visual is Sprite2D, species + " loads approved combat art")
		if visual is Sprite2D:
			var sprite := visual as Sprite2D
			var source := sprite.texture
			var width := source.get_width() * absf(sprite.scale.x)
			var height := source.get_height() * absf(sprite.scale.y)
			_check(maxf(width, height) <= Battle.BATTLE_ART_MAX_DIM + 0.1,
				species + " never overflows the 210px combat art bounds")
			_check(sprite.scale.x == sprite.scale.y,
				species + " source art keeps its aspect ratio")
			_check(sprite.position == Vector2(960, 340),
				species + " uses the requested battle anchor")
			# Reserve's three opaque-paper masters should not appear as white
			# rectangles in combat. The two native-alpha sources stay raw.
			var paper: bool = species in ["dragonthorn", "gloomcap", "spinehopper"]
			_check((sprite.material is ShaderMaterial) == paper,
				species + " applies the Reserve paper mask only when needed")
		visual.free()
	var fallback := Battle.make_creature_visual(
		"unapproved-art-test-id", Vector2(100, 200), Color.RED, 45.0)
	_check(Battle.paper_mat_for("bellmaw") == null,
		"native-alpha Bellmaw receives no white-paper shader")
	var first := Battle.paper_mat_for("dragonthorn") as ShaderMaterial
	var second := Battle.paper_mat_for("gloomcap") as ShaderMaterial
	_check(first != null and second != null and first != second,
		"each painting gets an independent material instance")
	_check(first.shader == second.shader,
		"painting sprites reuse the exact same approved shader")
	_check(not (fallback is Sprite2D),
		"creature with no approved image retains the visible greybox")
	_check(fallback.position == Vector2(100, 200),
		"greybox fallback preserves the battle anchor")
	fallback.free()

	if _failed == 0:
		print("[BATTLE ART FIT] PASS %d checks" % _checks)
	else:
		push_error("[BATTLE ART FIT] FAIL %d/%d" % [_failed, _checks])
	quit(1 if _failed > 0 else 0)

func _check(ok: bool, description: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		push_error("[BATTLE ART FIT] " + description)
