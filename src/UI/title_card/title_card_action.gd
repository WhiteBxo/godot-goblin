class_name TitleCardAction
extends RefCounted
## Per-request result with the same settle contract as ActorAction.

signal finished(action: TitleCardAction)

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
