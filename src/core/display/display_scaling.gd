extends Node
## Render native pixels at integer scale and use spare window space as extra view.
## Small windows retain the design layout with fractional scaling for readability.

const BASE_SIZE := Vector2i(640, 360)
const MIN_INTEGER_SCALE := 2
## A maximized window can lose a title bar while still fitting the same UI scale.
const HEIGHT_TOLERANCE := 0.04
const WIDE_MAX := 2.0
const RESIZE_DEBOUNCE := 0.12

var _window: Window
var _applied_size := Vector2i.ZERO
var _debounce: Timer

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_window = get_window()
	if _window == null:
		return
	var screen := DisplayServer.screen_get_size()
	_window.min_size = BASE_SIZE.min(screen)
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = RESIZE_DEBOUNCE
	_debounce.timeout.connect(_apply_now)
	add_child(_debounce)
	_apply_now()

func _process(_delta: float) -> void:
	if not is_instance_valid(_window) or _window.size == _applied_size:
		return
	if _debounce.is_stopped():
		_debounce.start()

## {base: Vector2i, scale: float, stretch: int, aspect: int, integer: bool}.
func plan_for(window_size: Vector2i) -> Dictionary:
	window_size = window_size.max(Vector2i.ONE)
	@warning_ignore("integer_division")
	var k := mini(window_size.x / BASE_SIZE.x, window_size.y / BASE_SIZE.y)
	var nearest := roundi(float(window_size.y) / BASE_SIZE.y)
	var ideal_height := nearest * BASE_SIZE.y
	if (nearest >= MIN_INTEGER_SCALE and window_size.x >= nearest * BASE_SIZE.x
			and absf(window_size.y - ideal_height) <= ideal_height * HEIGHT_TOLERANCE):
		k = nearest
	if k < MIN_INTEGER_SCALE:
		return _small_plan(window_size)
	@warning_ignore("integer_division")
	var base := Vector2i(window_size.x / k, window_size.y / k)
	var capped := Vector2i(mini(base.x, int(BASE_SIZE.x * WIDE_MAX)),
		mini(base.y, BASE_SIZE.y * 2))
	return {
		"base": capped, "scale": k,
		"stretch": Window.CONTENT_SCALE_STRETCH_INTEGER,
		"aspect": Window.CONTENT_SCALE_ASPECT_KEEP if capped != base else Window.CONTENT_SCALE_ASPECT_EXPAND,
		"integer": true,
	}

func apply_to(window: Window, window_size: Vector2i) -> void:
	var plan := plan_for(window_size)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = plan.aspect
	window.content_scale_stretch = plan.stretch
	window.content_scale_size = plan.base
	_applied_size = window_size

func _small_plan(window_size: Vector2i) -> Dictionary:
	return {
		"base": BASE_SIZE,
		"scale": minf(float(window_size.x) / BASE_SIZE.x, float(window_size.y) / BASE_SIZE.y),
		"stretch": Window.CONTENT_SCALE_STRETCH_FRACTIONAL,
		"aspect": Window.CONTENT_SCALE_ASPECT_EXPAND,
		"integer": false,
	}

func _apply_now() -> void:
	if is_instance_valid(_window):
		apply_to(_window, _window.size)
