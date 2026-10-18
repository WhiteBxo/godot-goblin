class_name SceneSoundscape
extends Node
## Scene-owned ambient bed and distance-based footsteps, using the existing pool.
## These are presentation sounds: they never influence guard hearing or story state.

const PROFILES := {
	"shop": {"ambience": "ambience.shop", "step": "player.step_wood", "volume": -25.0},
	"cave": {"ambience": "ambience.cave", "step": "player.step_stone", "volume": -23.0},
	"interior": {"ambience": "ambience.cave", "step": "player.step_stone", "volume": -31.0},
}
const STEP_DISTANCE := 62.0

var _audio: AudioManager
var _player: PlayerController
var _state: Node
var _library: SoundLibrary
var _profile: Dictionary = {}
var _owner := RefCounted.new()
var _ambient_handle := AudioManager.INVALID_HANDLE
var _last_position := Vector2.ZERO
var _distance := 0.0
var _step_cooldown := 0.0
var _previous_step := ""
var _night := false
var _retry_seconds := 0.0

func configure(audio: AudioManager, player: PlayerController, state: Node, library: SoundLibrary, profile: String) -> void:
	_disconnect()
	_audio = audio
	_player = player
	_state = state
	_library = library
	_profile = PROFILES.get(profile, {})
	if _profile.is_empty() or not is_instance_valid(player):
		set_physics_process(false)
		return
	_last_position = player.global_position
	_night = DayPhase.is_night(state)
	_state.state_changed.connect(_refresh_phase)
	_audio.sound_finished.connect(_on_sound_finished)
	set_physics_process(true)
	_start_ambience()

func _start_ambience() -> void:
	if _profile.is_empty() or not is_instance_valid(_audio) or not _audio.is_inside_tree():
		return
	var volume: float = _profile.volume - (4.0 if _night else 0.0)
	_ambient_handle = _audio.play_sfx(_profile.ambience, _owner, volume)
	_retry_seconds = 1.0

func _refresh_phase() -> void:
	var night := DayPhase.is_night(_state)
	if night == _night:
		return
	_night = night
	# Explicitly release our old voice; leave music and story-owned voices alone.
	var old_handle := _ambient_handle
	_ambient_handle = AudioManager.INVALID_HANDLE
	_audio.stop_sound(old_handle, 0.4)
	_start_ambience()

func _on_sound_finished(handle: int, _cancelled: bool) -> void:
	if handle == _ambient_handle:
		_ambient_handle = AudioManager.INVALID_HANDLE

func _physics_process(delta: float) -> void:
	if _profile.is_empty() or not is_instance_valid(_player):
		return
	_retry_seconds -= delta
	if _ambient_handle == AudioManager.INVALID_HANDLE and _retry_seconds <= 0.0:
		_start_ambience()
	_step_cooldown = maxf(0.0, _step_cooldown - delta)
	var travelled := _player.global_position.distance_to(_last_position)
	_last_position = _player.global_position
	# Teleports, collisions, modal locks and performed movement are not player steps.
	if not _player.movement_enabled or _player.is_performance_controlled() or not _player.is_visible_in_tree() or travelled < 0.01 or travelled > maxf(32.0, _player.get_movement_speed() * delta * 2.0):
		_distance = 0.0
		return
	_distance += travelled
	if _distance < STEP_DISTANCE or _step_cooldown > 0.0:
		return
	_distance = fmod(_distance, STEP_DISTANCE)
	_step_cooldown = 0.18
	var sound := _library.choose_variant(_profile.step, _previous_step)
	if sound.is_empty():
		return
	var quiet := _player.locomotion_mode == PlayerController.Locomotion.SNEAK
	if _audio.play_sfx(sound, _owner, -25.0 if quiet else -17.0) != AudioManager.INVALID_HANDLE:
		_previous_step = sound

func _disconnect() -> void:
	if is_instance_valid(_state) and _state.state_changed.is_connected(_refresh_phase):
		_state.state_changed.disconnect(_refresh_phase)
	if is_instance_valid(_audio):
		if _audio.sound_finished.is_connected(_on_sound_finished):
			_audio.sound_finished.disconnect(_on_sound_finished)
		_audio.stop_owned(_owner)
	_ambient_handle = AudioManager.INVALID_HANDLE
	_distance = 0.0
	_step_cooldown = 0.0

func _exit_tree() -> void:
	_disconnect()
