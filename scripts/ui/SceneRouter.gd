class_name SceneRouter
extends RefCounted

## The meta-UI side of the handoff to the gameplay screen.
##
## INTEGRATION CONTRACT (agreed with the Gameplay agent):
##   GameplayController.pending_level_number = <int>
##   get_tree().change_scene_to_file("res://scenes/Gameplay.tscn")
##
## GameplayController.gd is being written in parallel, so this file must not
## reference the `GameplayController` identifier directly: an unresolved global
## class name is a *parse* error in GDScript, which would take every meta screen
## down with it while the other agent's work is still landing. Instead the
## script is looked up at runtime (global class cache first, then the known
## candidate paths) and the static var is assigned through Object.set(), which
## is exactly equivalent to `GameplayController.pending_level_number = n` for a
## GDScript `static var`.
##
## Once both branches are merged this indirection can be collapsed to the plain
## static assignment; it is kept defensive because a missing gameplay scene
## should downgrade to "button does nothing + warning", never to a crash.

const PENDING_LEVEL_PROPERTY := "pending_level_number"
const GAMEPLAY_CLASS := "GameplayController"
const CANDIDATE_PATHS: Array[String] = [
	"res://scripts/gameplay/GameplayController.gd",
	"res://scripts/GameplayController.gd",
	"res://scripts/board/GameplayController.gd",
	"res://scenes/GameplayController.gd",
]


static func _find_gameplay_script() -> GDScript:
	for entry in ProjectSettings.get_global_class_list():
		if entry.get("class") == GAMEPLAY_CLASS:
			var p: String = entry.get("path", "")
			if p != "" and ResourceLoader.exists(p):
				return load(p) as GDScript
	for path in CANDIDATE_PATHS:
		if ResourceLoader.exists(path):
			return load(path) as GDScript
	return null


## Sets the pending level on GameplayController (if it exists yet) and fades
## into the gameplay scene. Returns false when the gameplay side isn't merged
## in yet, so callers can surface a placeholder instead of dead-ending.
static func play_level(from: Node, level_number: int) -> bool:
	var script := _find_gameplay_script()
	if script != null:
		script.set(PENDING_LEVEL_PROPERTY, level_number)
	else:
		push_warning("SceneRouter: %s not found — level %d not handed off." % [GAMEPLAY_CLASS, level_number])

	# LevelManager is the pre-existing runtime-state owner; priming it here means
	# the gameplay screen can rely on either mechanism.
	if Engine.has_singleton("LevelManager") or from.get_tree().root.has_node("LevelManager"):
		var lm := from.get_tree().root.get_node_or_null("LevelManager")
		if lm != null and lm.has_method("load_level"):
			lm.call("load_level", level_number)

	return UITheme.go_to_scene(from, UITheme.SCENE_GAMEPLAY)


static func level_id(level_number: int) -> String:
	return "level_%03d" % level_number


static func level_exists(level_number: int) -> bool:
	return ResourceLoader.exists("res://levels/level_%03d.tres" % level_number)
