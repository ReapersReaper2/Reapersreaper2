@tool
extends EditorPlugin
var exporter: EditorExportPlugin
func _enter_tree() -> void:
	exporter = ShareExport.new()
	add_export_plugin(exporter)
func _exit_tree() -> void:
	remove_export_plugin(exporter)
	exporter = null
class ShareExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "DQ005Share"
	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid
	func _get_android_dependencies(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:\n\t\treturn PackedStringArray(["androidx.core:core:1.12.0"])\n\tfunc _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		return PackedStringArray(["res://addons/dq005_share/DQ005Share.aar"])
