extends RefCounted
## Reaper's Reaper — Demo Mode.
##
## NOTE: intentionally no class_name (project convention — see save_system.gd).
## Static manager; game code passes the GameState node in.
##
## The demo is Chapter 1 free: prologue through the tentacle boss (room_c1).
## Demo rules (per spec):
##   - No time limit.
##   - Demo saves transfer to the full game (same SAVE_VERSION, same format).
##   - Ends on the Wrath cliffhanger: the bounty board turns over and shows
##     that Wrath has taken the Kanryu bounty.
##
## Implementation: IS_DEMO is a ProjectSettings flag set by the demo export
## preset (or a command-line arg). When true:
##   - Room transitions beyond Ch1 are blocked (demo_boundary in room.gd).
##   - After the tentacle boss, the bounty board shows the Wrath cliffhanger.
##   - The title screen shows "DEMO" and a "buy the full game" prompt (stub).

const DEMO_END_ROOM := "c1"
const DEMO_END_FLAG := "demo_complete"
const WRATH_CLIFFHANGER_FLAG := "wrath_took_kanryu"


static func is_demo() -> bool:
	# Project setting (set by the demo export preset's build script).
	if bool(ProjectSettings.get_setting("reaper/demo_mode", false)):
		return true
	# Marker file next to the executable (demo build ships one).
	var exe_dir := OS.get_executable_path().get_base_dir()
	if FileAccess.file_exists(exe_dir.path_join(".demo")):
		return true
	return false


static func is_demo_complete(gs) -> bool:
	if gs == null or not gs.has_method("get_flag"):
		return false
	return bool(gs.get_flag(DEMO_END_FLAG))


## Demo boundary: rooms beyond Ch1 (c2+) are locked in demo mode.
## Chapter prefixes: p1-p3 (prologue), c1-c2 (ch1), then h1+ (ch2+).
static func room_allowed(room_id: String) -> bool:
	if not is_demo():
		return true
	# Demo allows prologue (p*) and Ch1 (c1, c2) rooms only.
	if room_id.begins_with("p") or room_id == "c1" or room_id == "c2":
		return true
	return false


## Called when the tentacle boss is defeated in demo mode.
## Sets the cliffhanger: Wrath has taken the Kanryu bounty.
static func on_tentacle_down(gs) -> void:
	if gs == null or not gs.has_method("set_flag"):
		return
	if not is_demo():
		return
	gs.set_flag(WRATH_CLIFFHANGER_FLAG, true)
	gs.set_flag(DEMO_END_FLAG, true)


## The bounty board checks this to render the Wrath cliffhanger entry.
static func wrath_took_kanryu(gs) -> bool:
	if gs == null or not gs.has_method("get_flag"):
		return false
	return bool(gs.get_flag(WRATH_CLIFFHANGER_FLAG))


## Demo saves use the exact same format and SAVE_VERSION as the full game,
## so they transfer directly. This stamps the save as demo-originated for
## the "continue in full game" prompt.
static func stamp_demo_save(data: Dictionary) -> void:
	data["demo_origin"] = true
	data["demo_complete"] = true
