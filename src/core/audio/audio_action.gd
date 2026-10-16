class_name AudioAction
extends RefCounted
## Transition/voice result, including cancellation. Settles before deferred publication.

signal finished(action: AudioAction)
var completed := false
var succeeded := false
var reason := ""

func settle(ok: bool, message: String = "") -> void:
	if completed:
		return
	completed = true
	succeeded = ok
	reason = message
	_publish.call_deferred()

func _publish() -> void:
	finished.emit(self)
