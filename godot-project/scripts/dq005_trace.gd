extends Node
## DQ-005 candidate-only disk trace; no gameplay decisions depend on this logger.
const PATH := "user://dq005-trace.txt"
var _file: FileAccess
var _last_source := ""
var _swing_id := 0
var _last_action := -1

func _ready() -> void:
	_file = FileAccess.open(PATH, FileAccess.WRITE)
	if _file == null:
		push_error("[DQ005_TRACE] cannot open app-private trace")
		return
	record("BOOT", "platform=%s time=%s" % [OS.get_name(), Time.get_datetime_string_from_system()])

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

func export_via_email() -> bool:
	# Temporary mobile handoff: launches installed mail handler, no ADB/desktop.
	# Mailto URI length can be limited: intentionally NOT a production-grade full-file export.
	var body := trace_text()
	if body.is_empty():
		return false
	var uri := "mailto:?subject=DQ005%%20trace&body=" + body.uri_encode()
	return OS.shell_open(uri) == OK
