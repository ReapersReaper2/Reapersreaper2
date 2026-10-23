extends Node
## DQ-005 candidate-only disk trace; no gameplay decisions depend on this logger.
const PATH := "user://dq005-trace.txt"
var _file: FileAccess
var _last_source := ""
var _swing_id := 0
var _last_action := 0
var _share_node: Node

func _ready() -> void:
	_file = FileAccess.open(PATH, FileAccess.WRITE)
	if _file == null:
		push_error("[DQ005_TRACE] cannot open app-private trace")
		return
	record("BOOT", "platform=%s time=%s" % [OS.get_name(), Time.get_datetime_string_from_system()])
	if OS.has_feature("android"):
		var share_script: Script = load("res://addons/SharePlugin/Share.gd")
		if share_script == null:
			record("SHARE_PLUGIN_MISSING", "Share.gd could not be loaded")
			return
		_share_node = share_script.new()
		_share_node.name = "DQ005Share"
		add_child(_share_node)
		if _share_node.has_signal("share_completed"):
			_share_node.share_completed.connect(_on_share_completed)
		if _share_node.has_signal("share_canceled"):
			_share_node.share_canceled.connect(_on_share_canceled)
		if _share_node.has_signal("share_failed"):
			_share_node.share_failed.connect(_on_share_failed)
		record("SHARE_READY", "prebuilt Share addon node created")

func record(step: String, detail: String) -> void:
	var line := "[DQ005] %s ms=%d %s %s" % [Time.get_datetime_string_from_system(), Time.get_ticks_msec(), step, detail.replace("\n", " ")]
	if _file != null:
		_file.store_line(line)
		_file.flush()
	print(line)

func source(action: int, source_name: String, details: String) -> void:
	if action > 0 and _last_action == 0:
		_swing_id += 1
	if action != _last_action or source_name != _last_source:
		record("SOURCE", "swing=%d action=%d from=%s to=%s %s" % [_swing_id, action, _last_source, source_name, details])
		_last_action = action
		_last_source = source_name

func trace_text() -> String:
	if _file != null:
		_file.flush()
	return FileAccess.get_file_as_string(PATH)

func export_native() -> bool:
	var body := trace_text()
	if body.is_empty() or _share_node == null or not Engine.has_singleton("SharePlugin"):
		record("SHARE_UNAVAILABLE", "trace empty, Share node absent, or SharePlugin singleton missing")
		return false
	var absolute_path := ProjectSettings.globalize_path(PATH)
	if not FileAccess.file_exists(absolute_path):
		record("SHARE_FILE_MISSING", "path=" + absolute_path)
		return false
	var byte_count := body.to_utf8_buffer().size()
	record("SHARE_REQUEST", "path=user://dq005-trace.txt mime=text/plain bytes=%d" % byte_count)
	_share_node.share_file(absolute_path, "text/plain", "Export DQ005 trace file", "DQ005 trace", "Complete DQ-005 diagnostic trace attached.")
	return true

func _on_share_completed(activity_type: String) -> void:
	record("SHARE_COMPLETED", "target=" + activity_type)

func _on_share_canceled() -> void:
	record("SHARE_CANCELED", "share chooser dismissed")

func _on_share_failed(error_message: String) -> void:
	record("SHARE_FAILED", error_message)

func export_via_email() -> bool:
	# Temporary fallback only when the native Share plugin is unavailable.
	var body := trace_text()
	if body.is_empty():
		return false
	var uri := "mailto:?subject=DQ005%20trace&body=" + body.uri_encode()
	return OS.shell_open(uri) == OK
