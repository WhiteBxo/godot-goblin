extends SceneTree
## Exercise real host music bindings, map areas and ending ownership.

var _checks := 0
var _failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		push_error(message)

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	for entry: Array in [
		["main", "music.daily_milk_tea"], ["settlement", "music.cave"],
		["casino", "music.casino"], ["tavern", "music.tavern"], ["elder_house", "music.elder_house"]]:
		var state := root.get_node("GameState")
		state.reset_state()
		var game: MainGame = load("res://src/core/%s.tscn" % entry[0]).instantiate()
		# Prevent chapter events from racing the music checks; scene configuration
		# and all map/audio/player assembly remain the production versions.
		game.day1_story_enabled = false
		if entry[0] == "settlement":
			check(game.prepare_scene_arrival(&"shop_door") == OK, "Prepare actual shop-front arrival")
		root.add_child(game)
		await process_frame
		await process_frame
		var audio := game.get_audio_manager()
		var soundscape := game.get_node_or_null("Systems/SceneSoundscape") as SceneSoundscape
		check(soundscape != null, "Host creates its soundscape: " + entry[0])
		if soundscape == null:
			game.free()
			continue
		var player := game.get_player() as Node2D
		if entry[0] == "settlement":
			check(game.get_active_level().is_in_market(player.global_position), "Shop frontage belongs to market music zone")
			check(audio.get_bgm_state().id == "music.market", "Leaving shop starts market music immediately")
			check(soundscape._ambient_handle == AudioManager.INVALID_HANDLE, "Cave ambience does not overlap market music")
			# Move into the public cave after checking the real arrival.
			player.global_position = Vector2(1100, 1200)
			await create_timer(2.5).timeout
		check(audio.get_bgm_state().id == entry[1] and audio.get_bgm_state().playing, "Host plays configured music: " + entry[0])
		if entry[0] == "settlement":
			player.global_position = Vector2(1000, 2450)
			await create_timer(.25).timeout
			check(audio.get_bgm_state().id == "music.cave", "Brief boundary crossing does not switch music")
			player.global_position = Vector2(1100, 1200)
			await create_timer(.1).timeout
			player.global_position = Vector2(1000, 2450)
			await create_timer(2.5).timeout
			check(audio.get_bgm_state().id == "music.market", "Entering authored market switches cue")
			check(soundscape._ambient_handle == AudioManager.INVALID_HANDLE, "Returning to market releases the cave ambient voice")
			player.global_position = Vector2(1100, 1200)
			await create_timer(2.5).timeout
			check(audio.get_bgm_state().id == "music.cave", "Leaving market restores cave cue")
			audio.play_bgm("music.two_days_end", 0.0)
			player.global_position = Vector2(1000, 2450)
			await create_timer(2.0).timeout
			check(audio.get_bgm_state().id == "music.two_days_end", "Area changes respect story-owned music")
			soundscape.stop_ambience(0.0)
			check(not soundscape._music_enabled, "Ending disables regional music updates")
		game.free()
		await process_frame
	print("Scene Music: %d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures else 0)
