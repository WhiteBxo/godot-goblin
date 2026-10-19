class_name ThreatOverlay
extends Control
## Screen-space tension feedback for the Day 1 watch. Read-only: it never
## changes exposure, detection or any gameplay fact.

@export_range(0.0, 1.0, 0.01) var max_vignette_alpha := 0.42
@export var vignette_tint := Color(0.34, 0.04, 0.03)
@export_range(0.05, 1.0, 0.01) var flash_peak := 0.45

var _service: Day1StealthService
var _vignette: TextureRect
var _flash: ColorRect
var _alpha := 0.0
var _flash_tween: Tween

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette = $Vignette
	_flash = $Flash
	_vignette.texture = _build_vignette_texture()
	_vignette.modulate = Color(vignette_tint, 0.0)

func configure(service: Day1StealthService) -> void:
	_service = service
	_alpha = 0.0
	_apply()

func pulse() -> void:
	if not is_node_ready():
		return
	if _flash_tween != null:
		_flash_tween.kill()
	_flash.color.a = 0.0
	_flash_tween = create_tween().set_pause_mode(Tween.TWEEN_PAUSE_STOP)
	_flash_tween.tween_property(_flash, "color:a", flash_peak, 0.05)
	_flash_tween.tween_property(_flash, "color:a", 0.0, 0.22)

func get_vignette_alpha() -> float:
	return _alpha

func _process(delta: float) -> void:
	var target := 0.0
	if is_instance_valid(_service):
		target = smoothstep(0.08, 1.0, _service.get_alert_ratio()) * max_vignette_alpha
	_alpha = move_toward(_alpha, target, delta * 1.6)
	_apply()

func _apply() -> void:
	if not is_node_ready():
		return
	_vignette.visible = _alpha > 0.004
	_vignette.modulate = Color(vignette_tint, _alpha)

func _build_vignette_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0))
	gradient.set_color(1, Color(1, 1, 1, 1))
	gradient.add_point(0.58, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 144
	return texture
