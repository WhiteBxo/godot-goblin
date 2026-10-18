class_name GameEntry
extends RefCounted
## Entry navigation only. Ordinary scene changes must not reset the session.

const TITLE_SCENE := "res://src/UI/title/title_menu.tscn"
const GAME_SCENE := "res://src/core/main.tscn"

static var _changing_scene := false
static var _save_session_active := false
static var _last_saved_at := 0
static var _startup_previous: Dictionary = {}
static var _startup_active := false
static var _startup_saved_at := 0
static var _notice := ""

static func create_save_store() -> SaveStore:
	return SaveStore.new(str(ProjectSettings.get_setting("persistence/save_directory", SaveStore.DEFAULT_DIRECTORY)))

static func is_save_session_active() -> bool:
	return _save_session_active

static func get_last_saved_at() -> int:
	return _last_saved_at

static func record_saved_at(timestamp: int) -> void:
	_last_saved_at = timestamp

static func take_notice() -> String:
	var text := _notice
	_notice = ""
	return text

static func preflight_save(document: Dictionary) -> Error:
	var checkpoint := SaveCheckpoints.new().get_checkpoint(document.checkpoint_id)
	if checkpoint.is_empty() or not ResourceLoader.exists(checkpoint.scene, "PackedScene"):
		return ERR_FILE_NOT_FOUND
	var packed := ResourceLoader.load(checkpoint.scene, "PackedScene") as PackedScene
	if packed == null or not packed.can_instantiate():
		return ERR_INVALID_DATA
	var node := packed.instantiate()
	var error := node.prepare_saved_checkpoint(checkpoint, document.game_state) as Error if node is MainGame else ERR_INVALID_DATA
	node.free()
	return error

## Preflight a detached destination while the title and previous session survive.
static func continue_game(tree: SceneTree) -> Error:
	if tree == null:
		return ERR_INVALID_PARAMETER
	if _changing_scene or tree.paused:
		return ERR_BUSY
	var state := tree.root.get_node_or_null("GameState")
	if state == null or not state.can_take_snapshot():
		return ERR_BUSY
	var store := create_save_store()
	var loaded := store.load_save(preflight_save)
	if loaded.error != OK:
		return loaded.error
	var checkpoint := store.checkpoints.get_checkpoint(loaded.data.checkpoint_id)
	var packed := ResourceLoader.load(checkpoint.scene, "PackedScene") as PackedScene
	if packed == null or not packed.can_instantiate():
		return ERR_FILE_NOT_FOUND
	var instance := packed.instantiate()
	if not instance is MainGame:
		instance.free()
		return ERR_INVALID_DATA
	var destination := instance as MainGame
	var error := destination.prepare_saved_checkpoint(checkpoint, loaded.data.game_state)
	if error != OK:
		destination.free()
		return error
	_reserve_startup(state)
	error = state.restore_state(loaded.data.game_state)
	if error != OK:
		_changing_scene = false
		_startup_previous = {}
		destination.free()
		return error
	_save_session_active = true
	_last_saved_at = loaded.data.saved_at
	_notice = store.last_error if loaded.used_backup else ""
	destination.session_initialized.connect(_on_session_initialized.bind(tree), CONNECT_ONE_SHOT)
	error = tree.change_scene_to_node(destination)
	if error != OK:
		destination.free()
		_rollback_startup(state)
	return error

static func _reserve_startup(state: Node) -> void:
	_changing_scene = true
	_startup_previous = state.to_dict()
	_startup_active = _save_session_active
	_startup_saved_at = _last_saved_at

static func _rollback_startup(state: Node) -> void:
	var error: Error = state.restore_state(_startup_previous)
	if error != OK:
		push_error("Could not roll back failed save navigation: %s" % error_string(error))
	_save_session_active = _startup_active
	_last_saved_at = _startup_saved_at
	_startup_previous = {}
	_changing_scene = false

static func _on_session_initialized(error: Error, tree: SceneTree) -> void:
	if error != OK:
		_rollback_startup(tree.root.get_node("GameState"))
		_notice = "恢复现场失败，原存档已保留。"
		return_to_title(tree)
		return
	_startup_previous = {}
	_changing_scene = false

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
	if reset_session:
		return _start_saved_session(tree, scene, state)
	_changing_scene = true
	tree.scene_changed.connect(_on_scene_changed, CONNECT_ONE_SHOT)
	var error := tree.change_scene_to_packed(scene)
	if error != OK:
		tree.scene_changed.disconnect(_on_scene_changed)
		_changing_scene = false
		return error
	# Includes returning from pause; title and the next game must be interactive.
	tree.paused = false
	return OK

static func _on_scene_changed() -> void:
	_changing_scene = false

static func _start_saved_session(tree: SceneTree, scene: PackedScene, state: Node) -> Error:
	var instance := scene.instantiate()
	if not instance is MainGame:
		instance.free()
		return ERR_INVALID_DATA
	var destination := instance as MainGame
	destination.prepare_new_session()
	_reserve_startup(state)
	var error: Error = state.start_new_game()
	if error != OK:
		_changing_scene = false
		_startup_previous = {}
		destination.free()
		return error
	_save_session_active = true
	_last_saved_at = 0
	destination.session_initialized.connect(_on_session_initialized.bind(tree), CONNECT_ONE_SHOT)
	error = tree.change_scene_to_node(destination)
	if error != OK:
		destination.free()
		_rollback_startup(state)
		return error
	tree.paused = false
	return OK
