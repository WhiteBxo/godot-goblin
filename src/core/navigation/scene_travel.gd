class_name SceneTravel
extends Node
## Scene-local travel. GameState retains the session; no pending global arrival state.

signal busy_changed
signal travel_failed(point: SceneExit, error: Error)

@export_range(0.0, 2.0) var fade_seconds := 0.18

var _visual: ScreenTransition
var _can_travel: Callable
var _busy := false
var _destination: Node
var _requested_exit: SceneExit

func configure(visual: ScreenTransition, can_travel: Callable) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_visual = visual
	_can_travel = can_travel

func is_busy() -> bool:
	return _busy

func request_exit(point: SceneExit) -> Error:
	if _busy or not _can_travel.is_valid() or not _can_travel.call():
		return ERR_BUSY
	if not is_instance_valid(point) or point.destination_entrance == &"":
		return ERR_INVALID_PARAMETER
	if not ResourceLoader.exists(point.destination_scene, "PackedScene"):
		return ERR_FILE_NOT_FOUND
	_busy = true
	_requested_exit = point
	busy_changed.emit()
	_depart.call_deferred(point.destination_scene, point.destination_entrance)
	return OK

func begin_arrival() -> void:
	_busy = true
	busy_changed.emit()
	_visual.get_parent().show()
	# Set black synchronously, before the destination's first rendered frame.
	_visual.fade_out(0.0)
	_reveal.call_deferred()

func _depart(path: String, entrance: StringName) -> void:
	if not is_inside_tree():
		return
	var packed := ResourceLoader.load(path, "PackedScene") as PackedScene
	if packed == null or not packed.can_instantiate():
		_fail(ERR_CANT_CREATE)
		return
	_destination = packed.instantiate()
	if not is_instance_valid(_destination) or not _destination.has_method("prepare_scene_arrival"):
		_fail(ERR_UNCONFIGURED)
		return
	var error: Error = _destination.prepare_scene_arrival(entrance)
	if error != OK:
		_fail(error)
		return
	_visual.get_parent().show()
	var action := _visual.fade_out(fade_seconds)
	if not action.is_finished():
		await action.finished
	if not is_inside_tree():
		return
	if action.result != TransitionAction.Result.COMPLETED:
		_fail(ERR_SKIP)
		return
	# A pause/modal/performance may have started while fading. Keep the source intact.
	if not _can_travel.call():
		_fail(ERR_BUSY)
		return
	var destination := _destination
	_destination = null
	error = GameEntry.travel_to_scene(get_tree(), destination)
	if error != OK:
		_destination = destination
		_fail(error)
		return

func _reveal() -> void:
	var action := _visual.fade_in(fade_seconds)
	if not action.is_finished():
		await action.finished
	if not is_inside_tree():
		return
	_visual.cancel_all()
	_visual.get_parent().hide()
	_busy = false
	busy_changed.emit()

func _fail(error: Error) -> void:
	if is_instance_valid(_destination):
		_destination.free()
	_destination = null
	_visual.cancel_all()
	_visual.get_parent().hide()
	_busy = false
	busy_changed.emit()
	travel_failed.emit(_requested_exit, error)

func _exit_tree() -> void:
	if is_instance_valid(_destination):
		_destination.free()
	_destination = null
