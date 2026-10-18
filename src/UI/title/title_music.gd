class_name TitleMusic
extends AudioStreamPlayer
## Title-local playback: a complete track, a quiet gap, then a fresh fade-in.

@export_range(-40.0, 0.0) var target_volume_db: float = -8.0
@export_range(0.1, 5.0) var fade_in_seconds: float = 2.0
@export_range(0.1, 2.0) var fade_out_seconds: float = 0.45

@onready var _replay_timer: Timer = $ReplayTimer
var _fade: Tween
var _leaving := false


func _ready() -> void:
	finished.connect(_on_finished)
	_replay_timer.timeout.connect(play_from_start)
	play_from_start()


func play_from_start() -> void:
	_leaving = false
	_replay_timer.stop()
	_kill_fade()
	volume_linear = 0.0
	play()
	_fade = create_tween().set_ignore_time_scale(true)
	_fade.tween_property(self, "volume_linear", db_to_linear(target_volume_db), fade_in_seconds)


func fade_out() -> void:
	_leaving = true
	_replay_timer.stop()
	_kill_fade()
	if not playing:
		return
	_fade = create_tween().set_ignore_time_scale(true)
	_fade.tween_property(self, "volume_linear", 0.0, fade_out_seconds)
	await _fade.finished
	stop()


func _on_finished() -> void:
	if not _leaving:
		_kill_fade()
		_replay_timer.start()


func _kill_fade() -> void:
	if _fade != null:
		_fade.kill()
		_fade = null


func _exit_tree() -> void:
	_leaving = true
	_replay_timer.stop()
	_kill_fade()
	stop()
