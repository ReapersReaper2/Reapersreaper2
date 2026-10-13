extends SceneTree
## Confirm exact debug APK git identity is visible without changing release UI.
## --headless --path godot-project --script res://scripts/build_identity_test.gd
const Title := preload("res://scripts/title_screen.gd")

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var commit := "cf64114552de997b774cb8522dd881a8b7acc8ee"
	check(Title.debug_build_caption(commit) == "DEV BUILD  cf641145",
		"40-digit Git commit reduces to recognizable short build ID")
	check(Title.debug_build_caption(" " + commit.to_upper() + "\n") ==
		"DEV BUILD  cf641145", "uppercase and newline normalized safely")
	check(Title.debug_build_caption("") == "", "missing commit shows no guessed version")
	check(Title.debug_build_caption("unknown") == "", "invalid commit hidden")
	check(Title.debug_build_caption("z".repeat(40)) == "", "nonhex commit hidden")

	var old_dev: Variant = ProjectSettings.get_setting("reaper/dev_shortcuts", false)
	var old_sha: Variant = ProjectSettings.get_setting("reaper_build/source_commit", "")
	ProjectSettings.set_setting("reaper/dev_shortcuts", true)
	ProjectSettings.set_setting("reaper_build/source_commit", commit)
	var title = Title.new()
	root.add_child(title)
	title._ready()
	var stamp = title.get_node_or_null("DebugBuildIdentity") as Label
	check(stamp != null and stamp.text == "DEV BUILD  cf641145",
		"dev title prints exact build SHA for phone bug reports")
	check(stamp != null and stamp.mouse_filter == Control.MOUSE_FILTER_IGNORE,
		"build stamp never steals touch from menu buttons")
	title.queue_free()

	ProjectSettings.set_setting("reaper_build/source_commit", "")
	var unknown = Title.new()
	root.add_child(unknown)
	unknown._ready()
	check(unknown.get_node_or_null("DebugBuildIdentity") == null,
		"editor/game without injected build ID never invents identity")
	unknown.queue_free()
	ProjectSettings.set_setting("reaper_build/source_commit", old_sha)
	ProjectSettings.set_setting("reaper/dev_shortcuts", old_dev)

	if failures == 0:
		print("[BUILD IDENTITY] PASS %d checks" % checks)
	else:
		push_error("[BUILD IDENTITY] FAIL %d/%d" % [failures, checks])
	quit(1 if failures > 0 else 0)

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("[BUILD IDENTITY] " + message)
