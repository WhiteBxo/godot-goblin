class_name InteractionFeedback
extends Node2D
## Scene-local world overlay. No material, texture or collision modifications.

@export var focus_color := Color(1.0, 0.86, 0.56, 0.85)
@export var success_color := Color(1.0, 0.96, 0.78)
@export_range(0.05, 0.5) var pulse_seconds := 0.18

var _interaction: ShopInteraction
var _audio: AudioManager
var _sound_player: Callable
var _focus: InteractionPoint
var _pulse: InteractionPoint
var _remaining := 0.0

func _ready() -> void:
	# World feedback must stay visible over foreground furniture and room roofs.
	z_index = 30

func configure(interaction: ShopInteraction, audio: AudioManager = null, sound_player: Callable = Callable()) -> void:
	if is_instance_valid(_interaction):
		_interaction.target_changed.disconnect(_on_target_changed)
		_interaction.interaction_succeeded.disconnect(_on_succeeded)
	_interaction = interaction
	_audio = audio
	_sound_player = sound_player
	_interaction.target_changed.connect(_on_target_changed)
	_interaction.interaction_succeeded.connect(_on_succeeded)
	_on_target_changed(interaction.get_target())

func _on_target_changed(point: InteractionPoint) -> void:
	_focus = point
	queue_redraw()

func _on_succeeded(point: InteractionPoint) -> void:
	_pulse = point
	_remaining = pulse_seconds
	if not point.success_sound.is_empty() and _sound_player.is_valid():
		_sound_player.call(point.success_sound, point.sound_bus)
	elif not point.success_sound.is_empty() and is_instance_valid(_audio) and _audio.sounds.has(point.success_sound):
		if point.sound_bus == "SFX":
			_audio.play_sfx(point.success_sound)
		else:
			_audio.play_ui(point.success_sound)
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED:
		_focus = null
		_pulse = null
		_remaining = 0.0
		queue_redraw()

func _process(delta: float) -> void:
	if not is_instance_valid(_interaction) or not _interaction.is_inside_tree():
		_focus = null
		_pulse = null
	if _remaining > 0.0:
		_remaining = maxf(0.0, _remaining - delta)
		if _remaining == 0.0:
			_pulse = null
	# Follow moving/removed objects without caching their world transforms.
	queue_redraw()

func _draw() -> void:
	if not is_inside_tree() or get_tree().paused:
		return
	if is_instance_valid(_focus) and _focus.is_available():
		_draw_brackets(_focus, focus_color, 0.0)
	if is_instance_valid(_pulse) and _pulse.is_inside_tree() and not _pulse.is_queued_for_deletion():
		_draw_brackets(_pulse, success_color, 2.0 if _remaining > pulse_seconds * 0.5 else 4.0)

func _draw_brackets(point: InteractionPoint, color: Color, expand: float) -> void:
	var rect := point.feedback_rect.grow(expand)
	var transform_to_local := global_transform.affine_inverse() * point.global_transform
	for corner: Vector2 in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var direction := (rect.get_center() - corner).sign()
		var origin := (transform_to_local * corner).round()
		# Hard pixel lines; no blur, filtering or subpixel tween.
		var end_x := (transform_to_local * (corner + Vector2(direction.x * 6, 0))).round()
		var end_y := (transform_to_local * (corner + Vector2(0, direction.y * 6))).round()
		draw_line(origin, end_x, color, 2.0, false)
		draw_line(origin, end_y, color, 2.0, false)
