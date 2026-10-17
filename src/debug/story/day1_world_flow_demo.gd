extends MainGame
## F6-only business walkthrough. Seed a night mission, then use the real hosts.

## The walkthrough alone supplies the uncompiled story handoff after real arrival.
class ReturnHandoff:
	extends Node
	var state: Node

	func _process(_delta: float) -> void:
		var scene := get_tree().current_scene
		if scene != null and not scene is MainGame:
			queue_free()
			return
		if state.get_flag("day1.s05.returned_shop") and Day1Access.at_stage(state, "day1.s05"):
			state.set_story_stage("day1.s06.wait_blood_drink")
			queue_free()

func _ready() -> void:
	if not OS.has_feature("debug"):
		return
	var state := get_node("/root/GameState")
	if state.start_new_game() != OK or state.select_business_profile("day1") != OK:
		push_error("Cannot initialize Day 1 world walkthrough")
		return
	state.apply_flags({"day1.stages_01_02_completed": true, "day1.s04.commission_accepted": true})
	state.set_story_stage("day1.s05.search")
	var handoff := ReturnHandoff.new()
	handoff.name = "Day1WorldWalkthroughHandoff"
	handoff.state = state
	get_tree().root.add_child.call_deferred(handoff)
	state.state_reset.connect(handoff.queue_free, CONNECT_ONE_SHOT)
	state.state_restored.connect(handoff.queue_free, CONNECT_ONE_SHOT)
	super._ready()
