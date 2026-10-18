class_name StoryTriggerZone
extends Area2D
## Walk-in story trigger. Entering the area requests the same story route as pressing E
## on an interaction point with this ID, so Story JSON uses `"trigger": "<trigger_id>"`.
## Holds no story state: a rejected request retries while the player stays inside,
## and leaving re-arms the zone. Event `once` and conditions remain the only gate.

const RETRY_SECONDS := 0.25

@export var trigger_id: StringName
## Any one listed stage (or its sub-stage) admits the zone; empty means every stage.
@export var required_stages: Array[String] = []
## Every listed flag must be true.
@export var required_flags: Array[StringName] = []

var _state: Node
var _player: Node2D
var _request: Callable
var _inside := false
var _fired := false
var _cooldown := 0.0

func _ready() -> void:
	monitorable = false
	collision_mask = 1 << (PlayerController.PLAYER_LAYER - 1)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

## `request` receives the trigger ID and returns an Error; OK consumes this visit.
func configure(state: Node, player: Node2D, request: Callable) -> void:
	_state = state
	_player = player
	_request = request

func is_admitted() -> bool:
	if trigger_id.is_empty() or not is_instance_valid(_state):
		return false
	for flag: StringName in required_flags:
		if not _state.get_flag(String(flag)):
			return false
	if required_stages.is_empty():
		return true
	for stage: String in required_stages:
		if Day1Access.at_stage(_state, stage):
			return true
	return false

func is_player_inside() -> bool:
	return _inside

func _on_body_entered(body: Node2D) -> void:
	if body == _player:
		_inside = true
		_fired = false
		_cooldown = 0.0

func _on_body_exited(body: Node2D) -> void:
	if body == _player:
		_inside = false
		_fired = false

func _physics_process(delta: float) -> void:
	if not _inside or _fired or not _request.is_valid():
		return
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	_cooldown = RETRY_SECONDS
	if is_admitted() and _request.call(String(trigger_id)) == OK:
		_fired = true
