class_name ActorAction
extends RefCounted
## A per-request result. Retain this handle to wait, inspect failure or cancel safely.

signal finished(action: ActorAction)

var id: int
var actor_id: StringName
var command: StringName
var completed := false
var succeeded := false
var error: Error = OK
var reason := ""

func wait() -> ActorAction:
	if not completed:
		await finished
	return self

## Director-only: settle once, then notify after the public request has returned.
func settle(result: Error, message: String = "") -> void:
	if completed:
		return
	completed = true
	error = result
	succeeded = result == OK
	reason = message
	_publish.call_deferred()

func _publish() -> void:
	finished.emit(self)
