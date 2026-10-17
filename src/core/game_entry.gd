class_name GameEntry
extends RefCounted
## Entry navigation only. Ordinary scene changes must not reset the session.

const TITLE_SCENE := "res://src/UI/title/title_menu.tscn"
const GAME_SCENE := "res://src/core/main.tscn"

static var _changing_scene := false

## Call from a deferred UI handler, outside physics/GUI notification dispatch.
static func start_new_game(tree: SceneTree) -> Error:
	return _navigate(tree, GAME_SCENE, true)

static func return_to_title(tree: SceneTree) -> Error:
	return _navigate(tree, TITLE_SCENE, false)

## The caller validates and prepares the detached destination before leaving the source.
## Shares the title/new-game navigation slot, but never resets or unpauses the session.
static func travel_to_scene(tree: SceneTree, destination: Node) -> Error:
	if tree == null or not is_instance_valid(destination):
		return ERR_INVALID_PARAMETER
	if _changing_scene or tree.paused:
		return ERR_BUSY
	if destination.is_inside_tree() or destination.get_parent() != null:
		return ERR_UNCONFIGURED
	_changing_scene = true
	tree.scene_changed.connect(_on_scene_changed, CONNECT_ONE_SHOT)
	var error := tree.change_scene_to_node(destination)
	if error != OK:
		tree.scene_changed.disconnect(_on_scene_changed)
		_changing_scene = false
	return error

static func _navigate(tree: SceneTree, path: String, reset_session: bool) -> Error:
	if tree == null:
		return ERR_INVALID_PARAMETER
	if _changing_scene:
		return ERR_BUSY
	if not ResourceLoader.exists(path, "PackedScene"):
		return ERR_FILE_NOT_FOUND
	var scene := ResourceLoader.load(path) as PackedScene
	if scene == null or not scene.can_instantiate():
		return ERR_INVALID_DATA
	var state := tree.root.get_node_or_null("GameState")
	if reset_session and (state == null or not state.has_method("start_new_game")):
		return ERR_UNCONFIGURED
	_changing_scene = true
	var previous: Dictionary = {}
	if reset_session:
		previous = state.to_dict()
		var reset_error: Error = state.start_new_game()
		if reset_error != OK:
			_changing_scene = false
			return reset_error
	tree.scene_changed.connect(_on_scene_changed, CONNECT_ONE_SHOT)
	var error := tree.change_scene_to_packed(scene)
	if error != OK:
		tree.scene_changed.disconnect(_on_scene_changed)
		_changing_scene = false
		if reset_session:
			var restore_error: Error = state.restore_state(previous)
			if restore_error != OK:
				push_error("Could not restore session after navigation failed: %s" % error_string(restore_error))
		return error
	# Includes returning from pause; title and the next game must be interactive.
	tree.paused = false
	return OK

static func _on_scene_changed() -> void:
	_changing_scene = false
