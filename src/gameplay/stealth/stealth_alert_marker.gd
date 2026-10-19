class_name StealthAlertMarker
extends Node2D
## A short "!" over the guard who caught the player. Presentation only; the
## failure fact is committed by Day1StealthService before this node is created.

const FEEDBACK_THEME = preload("res://src/resources/ui/game_theme.tres")

@export_range(0.2, 2.0, 0.05) var lifetime := 0.8
@export var color := Color("ff9a6b")

var _elapsed := 0.0

func _ready() -> void:
	z_index = 32

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()
		return
	queue_redraw()

func _draw() -> void:
	var progress := clampf(_elapsed / maxf(lifetime, 0.001), 0.0, 1.0)
	var alpha := 1.0 - smoothstep(0.55, 1.0, progress)
	var rise := 18.0 + 8.0 * (1.0 - pow(1.0 - minf(progress * 4.0, 1.0), 3.0))
	var font := FEEDBACK_THEME.default_font
	var text := "!"
	var size := Vector2(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30))
	var origin := Vector2(-size.x * 0.5, -rise).round()
	draw_string(font, origin + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(0.08, 0.03, 0.02, 0.8 * alpha))
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color(color, alpha))
