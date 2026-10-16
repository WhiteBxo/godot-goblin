extends Node
## Explicitly isolated fixture. No reset or autoplay in the production host.
@export var autoplay := true
@onready var game: MainGame = $MainGame

func _ready() -> void:
	if not OS.has_feature("debug"):
		return
	# Reuse the declared synthetic audio fixture, not a production soundtrack.
	AudioDemoTones.populate(game.get_audio_manager())
	var error := game.get_dialogue_manager().load_dialogues("res://src/resources/dialogue/gameplay_bridge_demo.json")
	if error == OK:
		error = game.get_story_director().load_events("res://src/resources/story/gameplay_bridge_demo.json")
	if error == OK:
		error = game.get_gameplay_bridge().load_phases("res://src/resources/story/gameplay_bridge_demo_phases.json")
	if error != OK:
		push_error("Gameplay Bridge demo load failed: %d" % error)
		return
	if autoplay:
		game.get_story_director().request_event("bridge.intro")
