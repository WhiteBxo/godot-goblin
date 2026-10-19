class_name InteractionAudio
extends Node
## Scene-local feedback configuration. Observes results; never changes gameplay state.

@export var library: SoundLibrary = preload("res://src/resources/audio/sound_library.tres")
@export var event_sounds: Dictionary[String, String] = {
	"craft_success": "shop.sealer",
	"craft_failure": "ui.failure",
	"gather_success": "ui.confirm",
	"delivery_success": "shop.coins",
	"delivery_failure": "ui.failure",
	"transaction_success": "shop.coins",
	"transaction_failure": "ui.failure",
	"order_accepted": "ui.confirm",
	"order_failure": "ui.failure",
	"interaction_failure": "ui.failure",
	"dialogue_line": "ui.dialogue",
	"dialogue_choice": "ui.confirm",
	"throw_impact": "story.impact",
}
@export_range(-48.0, 0.0) var sfx_volume_db := -6.0
@export_range(-48.0, 0.0) var ui_volume_db := -6.0
@export_range(-48.0, 0.0) var hover_volume_db := -14.0
## World focus changes and dialogue ticks stay below the UI click so they read as texture.
@export_range(-48.0, 0.0) var focus_volume_db := -20.0
@export_range(-48.0, 0.0) var blip_volume_db := -26.0
@export_range(0, 500) var repeat_guard_ms := 80
@export_range(0, 500) var focus_guard_ms := 90
@export_range(0, 500) var blip_guard_ms := 70

var _audio: AudioManager
var _owner := RefCounted.new()
var _previous: Dictionary[String, String] = {}
var _last_played: Dictionary[String, int] = {}


func configure(audio: AudioManager) -> PackedStringArray:
	if is_instance_valid(_audio):
		_audio.stop_owned(_owner)
	_audio = audio
	_previous.clear()
	_last_played.clear()
	return library.register_all(audio)


func play_event(event: String) -> int:
	return play_sound(event_sounds.get(event, ""))


## [param volume_db] overrides the bus default when finite; NAN keeps the existing mapping.
func play_sound(id: String, bus: String = "", volume_db: float = NAN) -> int:
	if id.is_empty() or not is_instance_valid(_audio) or not _audio.is_inside_tree():
		return AudioManager.INVALID_HANDLE
	var now := Time.get_ticks_msec()
	if _last_played.has(id) and now - _last_played[id] < repeat_guard_ms:
		return AudioManager.INVALID_HANDLE
	var variant := library.choose_variant(id, _previous.get(id, ""))
	if variant.is_empty():
		variant = id
	if not _audio.sounds.has(variant):
		return AudioManager.INVALID_HANDLE
	var volume := hover_volume_db if id == "ui.hover" else ui_volume_db
	if is_finite(volume_db):
		volume = volume_db
	var handle := _audio.play_ui(variant, _owner, volume) if bus == "UI" or (bus.is_empty() and id.begins_with("ui.")) else _audio.play_sfx(variant, _owner, sfx_volume_db)
	if handle != AudioManager.INVALID_HANDLE:
		_previous[id] = variant
		_last_played[id] = now
	return handle

## Quiet tick when the nearby interaction target changes; never a business result.
func play_focus() -> int:
	return _play_texture("ui.hover", focus_volume_db, blip_guard_ms + 10)

## Very quiet per-character dialogue texture, thinned by the caller's stride.
func play_blip() -> int:
	return _play_texture("ui.dialogue", blip_volume_db, blip_guard_ms)

func _play_texture(id: String, volume_db: float, guard_ms: int) -> int:
	if not is_instance_valid(_audio) or not _audio.is_inside_tree():
		return AudioManager.INVALID_HANDLE
	var key := "texture." + id
	var now := Time.get_ticks_msec()
	if _last_played.has(key) and now - _last_played[key] < guard_ms:
		return AudioManager.INVALID_HANDLE
	var variant := library.choose_variant(id, _previous.get(key, ""))
	if variant.is_empty() or not _audio.sounds.has(variant):
		return AudioManager.INVALID_HANDLE
	var handle := _audio.play_ui(variant, _owner, volume_db)
	if handle != AudioManager.INVALID_HANDLE:
		_previous[key] = variant
		_last_played[key] = now
	return handle


func on_transaction_finished(result: Dictionary) -> void:
	if result.get("ok", false):
		if int(result.get("money_delta", 0)) != 0 or not result.get("items", {}).is_empty():
			play_event("transaction_success")
	else:
		play_event("transaction_failure")


func _exit_tree() -> void:
	if is_instance_valid(_audio):
		_audio.stop_owned(_owner)
