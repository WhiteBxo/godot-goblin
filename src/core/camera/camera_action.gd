class_name CameraAction
extends RefCounted
## One request, one terminal result. Signals are deferred, including instant actions.

signal finished(action: CameraAction)

enum Result { PENDING, COMPLETED, CANCELLED, FAILED }

var id: int
var command: StringName
var result: Result = Result.PENDING
var reason: String = ""

func is_finished() -> bool:
	return result != Result.PENDING

func resolve(value: Result, message: String = "") -> void:
	if is_finished():
		return
	result = value
	reason = message
	_emit_finished.call_deferred()

func _emit_finished() -> void:
	finished.emit(self)
