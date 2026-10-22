extends SceneTree

## L0 teaches walking and interacting exactly once, and only from the moment the
## player is actually allowed to act: an opening performance or a locked intro
## must not spend the lesson on keys nobody can press yet.

const HINT := preload("res://src/UI/hud/control_hint.tscn")

var checks := 0
var failures: Array[String] = []
var state: Node
var player: FakePlayer
var hint: Control

class FakePlayer:
	extends Node2D
	var movement_enabled := true
	var performing := false
	func is_performance_controlled() -> bool:
		return performing

class FakeHost:
	extends Node
	var subject: Node2D
	func get_player() -> Node2D:
		return subject

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)

func frames(count: int) -> void:
	for _i in range(count):
		await process_frame

func _run() -> void:
	state = root.get_node("GameState")
	state.reset_state()
	state.set_flag("ui.hint.l0.keyboard", false)
	state.set_flag("ui.hint.l0.touch", false)
	player = FakePlayer.new()
	root.add_child(player)
	var host := FakeHost.new()
	host.subject = player
	root.add_child(host)
	hint = HINT.instantiate()
	root.add_child(hint)
	await frames(2)

	# A locked start keeps the lesson in reserve.
	player.movement_enabled = false
	hint.bind(host)
	await frames(6)
	check(not hint.visible, "L0 stays hidden while the player cannot act")
	check(not state.get_flag("ui.hint.l0.keyboard"), "A locked start does not consume the lesson")

	# A performance owns the body even though movement is enabled.
	player.movement_enabled = true
	player.performing = true
	await frames(4)
	check(not hint.visible, "L0 waits for the performance to release the player")

	# The first frame of free control shows it.
	player.performing = false
	await frames(4)
	check(hint.visible, "L0 appears on the first frame the player can act")
	check(hint.get_node("Bar/Label").text.contains("移动"), "L0 names movement")

	# Space is free until the player walks; then the lesson retires itself.
	player.global_position += Vector2(8, 0)
	await frames(3)
	check(hint.visible, "Small corrections do not dismiss the lesson")
	player.global_position += Vector2(30, 0)
	await frames(8)
	check(not hint.get("_running"), "Walking retires L0")
	await frames(240)
	check(not hint.visible, "The retired bar fades out")
	check(state.get_flag("ui.hint.l0.keyboard"), "Retiring L0 records the lesson")
	await frames(2)

	# A second bind on the same save stays quiet.
	var again: Control = HINT.instantiate()
	root.add_child(again)
	again.bind(host)
	await frames(4)
	check(not again.visible, "A taught save never shows L0 again")

	print("CONTROL_HINT: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
