extends Node
## A fixed demonstration, deliberately not a JSON/story scheduler.

signal demo_finished(succeeded: bool)

@export var autoplay := true
@onready var director: ActorDirector = $Systems/ActorDirector
@onready var _status: Label = $DebugLayer/Panel/Content/Status
var running := false
var completed := false
var _cancelled := false

func _ready() -> void:
	director.configure($World/EntityRoot)
	director.actor_register(&"player", $World/EntityRoot/Player)
	director.register_position(&"door", $World/LevelRoot/Door)
	director.register_position(&"counter", $World/LevelRoot/CounterTarget)
	$DebugLayer/Panel/Content/Buttons/Replay.pressed.connect(play)
	$DebugLayer/Panel/Content/Buttons/Cancel.pressed.connect(cancel)
	if autoplay:
		play.call_deferred()

func cancel() -> void:
	_cancelled = true
	director.cancel_all("Demo cancelled")

func play() -> void:
	if running:
		return
	running = true
	completed = false
	_cancelled = false
	var old_customer := director.get_actor(&"customer_01")
	if old_customer != null:
		director.actor_unregister(&"customer_01")
		old_customer.queue_free()
	var player := director.get_actor(&"player")
	player.set_movement_enabled(false)
	await director.actor_face(&"player", &"up").wait()
	var ok := await _perform(director.actor_spawn(&"customer_01", preload("res://src/debug/actors/demo_actor.tscn"), &"door"), "1 / 5  Customer appears at the door")
	if ok:
		director.get_actor(&"customer_01").modulate = Color(1.0, 0.75, 0.5)
		ok = await _perform(director.actor_move(&"customer_01", &"counter", 70.0), "2 / 5  Customer walks to the counter")
	if ok:
		ok = await _perform(director.actor_face(&"player", &"left"), "3 / 5  Player turns to the customer")
	if ok:
		ok = await _perform(director.actor_emote(&"customer_01", "!", 1.2), "4 / 5  Customer reacts: !")
	if ok:
		ok = await _perform(director.actor_face(&"customer_01", &"down"), "5 / 5  Customer turns and leaves")
	if ok:
		ok = await _perform(director.actor_move(&"customer_01", &"door", 85.0), "5 / 5  Customer walks back to the door")
	if ok:
		ok = await _perform(director.actor_hide(&"customer_01"), "5 / 5  Customer disappears")
	if not is_inside_tree():
		return
	player.set_movement_enabled(true)
	running = false
	completed = ok
	if ok:
		_status.text = "Complete. WASD: move player. Replay to watch again."
	demo_finished.emit(ok)

func _perform(action: ActorAction, description: String) -> bool:
	_status.text = description
	if _cancelled:
		director.cancel_action(action, "Demo cancelled")
	await action.wait()
	if not is_inside_tree():
		return false
	if not action.succeeded or _cancelled:
		_status.text = "Stopped: " + (action.reason if not action.reason.is_empty() else "Demo cancelled")
		return false
	return true

func _exit_tree() -> void:
	_cancelled = true
