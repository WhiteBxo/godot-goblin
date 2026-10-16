class_name TransitionAction
extends RefCounted
## Retain this handle to await a terminal result even if the visual node is freed.

signal finished(action: TransitionAction)

enum Result { PENDING, COMPLETED, CANCELLED, FAILED }

var id: int
var effect: StringName
var result: Result = Result.PENDING
var reason := ""

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
