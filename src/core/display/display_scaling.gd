extends Node
## 位图 UI 只有在整数倍缩放下才清晰；而「逻辑视口随窗口伸缩」会让 UI 和世界各自
## 按不同倍率绘制——窗口一放大，人物变大、UI 变小，两张截图看着像两个游戏。
##
## 所以核心判据是「窗口高度是否接近 360 的整数倍」，而不是宽高比：
##
## - **高度是整数倍**（1280×720 / 1920×1080 / 1920×1061 带标题栏 / 20:9 手机）：
##   倍率 k 由高度定，宽度按 window/k 给逻辑视口。16:9 时 base 正好 640×360 铺满；
##   更宽的手机多看到两侧。这条分支下 UI 的物理尺寸与设计稿严格一致。
## - **高度不是整数倍**（1706×960、1600×900、1366×768、16:10）：逻辑视口钉死
##   640×360，按整数倍居中、四周留边。构图、字号、人物大小与 1280×720 完全一致。
##
## 任何情况下都不做非整数拉伸：12px 点阵字一旦落在半个屏幕上就是一片灰边。

const BASE_SIZE := Vector2i(640, 360)
## 低于这个倍数就没有整数缩放可用，改用 1 倍整数（不是小数）。
const MIN_INTEGER_SCALE := 2
## 窗口与「整数倍高度」的允许偏差。标题栏、任务栏会吃掉几十像素：
## 1920×1061 相对 3 倍（1080）只差 1.8%，必须仍然认作 3 倍。
const HEIGHT_TOLERANCE := 0.04
## 逻辑视口最宽放到设计宽度的这么多倍（32:9 超宽屏正好 2 倍）。
const WIDE_MAX := 2.0
## 拖动窗口时尺寸连续变化，等停稳再重排界面。
const RESIZE_DEBOUNCE := 0.12

var _window: Window
var _applied_size := Vector2i.ZERO
var _debounce: Timer


func _ready() -> void:
	# headless 下没有真实窗口，改缩放只会影响测试里对 viewport 尺寸的断言。
	if DisplayServer.get_name() == "headless":
		return
	_window = get_window()
	if _window == null:
		return
	# 低于 1280×720 就不存在 2 倍整数缩放（640×360 是设计底线），而 1.5625 这类
	# 非整数倍会把 12px 点阵字糊成一片灰边。把窗口最小尺寸钉在这里，比事后
	# 降级更能保住"铺满且锐利"。屏幕更小时按屏幕尺寸封顶，免得窗口撑出边界。
	var screen := DisplayServer.screen_get_size()
	_window.min_size = Vector2i(
		mini(BASE_SIZE.x * MIN_INTEGER_SCALE, screen.x),
		mini(BASE_SIZE.y * MIN_INTEGER_SCALE, screen.y),
	)
	_debounce = Timer.new()
	_debounce.one_shot = true
	_debounce.wait_time = RESIZE_DEBOUNCE
	_debounce.timeout.connect(_apply_now)
	add_child(_debounce)
	_apply_now()


## 轮询而不是只听 `size_changed`：窗口属性先变、渲染尺寸后跟上的那一帧里，
## 信号给出的尺寸可能还是旧的，那次应用会被当成"没变化"跳过且不再补发。
## 每帧比对一次很便宜，读到滞后值时下一拍会自己再补一次。
func _process(_delta: float) -> void:
	if _window == null or not is_instance_valid(_window):
		return
	if _window.size == _applied_size:
		return
	if _debounce != null and _debounce.is_stopped():
		_debounce.start()


## 给定窗口尺寸，算出该用的基准分辨率与缩放模式。
## 返回 {base: Vector2i, scale: int, stretch: int, aspect: int, integer: bool}。
func plan_for(window_size: Vector2i) -> Dictionary:
	# 倍率由高度定。高度落在 360 的整数倍上，才谈得上「UI 与世界层同一个倍率」；
	# 这时宽度多出来的部分才是真正值得扩展的视野（手机、超宽屏）。
	var k := roundi(float(window_size.y) / float(BASE_SIZE.y))
	var ideal_height := BASE_SIZE.y * k
	var height_ok := k >= MIN_INTEGER_SCALE and absf(float(window_size.y - ideal_height)) <= float(ideal_height) * HEIGHT_TOLERANCE
	@warning_ignore("integer_division")
	var base := Vector2i(window_size.x / maxi(1, k), window_size.y / maxi(1, k))
	if height_ok and base.x >= BASE_SIZE.x and float(base.x) <= float(BASE_SIZE.x) * WIDE_MAX:
		return {
			"base": base,
			"scale": k,
			"stretch": Window.CONTENT_SCALE_STRETCH_INTEGER,
			"aspect": Window.CONTENT_SCALE_ASPECT_EXPAND,
			"integer": true,
		}
	return _fixed_plan(window_size)


func apply_to(window: Window, window_size: Vector2i) -> void:
	var plan := plan_for(window_size)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = plan.aspect
	window.content_scale_stretch = plan.stretch
	window.content_scale_size = plan.base
	_applied_size = window_size


## 高度不是整数倍：逻辑视口钉死 640×360，按整数倍居中，四周留边。
##
## 1706×960 这类窗口最容易翻车：它是 16:9，只是不是 1280 的整数倍。若按
## 「窗口 ÷ 整数倍」动态推基准，逻辑视口会被撑到 853×480 —— 世界层为了铺满把
## 房间放大约 33%，而 UI 仍是固定逻辑尺寸、相对屏幕小了 25%，于是同一屏里
## 人物偏大、字偏小。宁可留边也不让两套倍率并存。
##
## 1280×720 / 1920×1080 / 2560×1440 这些真·整数倍窗口在这里是 100% 铺满的，
## 留边只发生在窗口被拖成任意尺寸时。
func _fixed_plan(window_size: Vector2i) -> Dictionary:
	@warning_ignore("integer_division")
	var k := mini(window_size.x / BASE_SIZE.x, window_size.y / BASE_SIZE.y)
	if k < MIN_INTEGER_SCALE:
		return _unit_plan(window_size)
	return {
		"base": BASE_SIZE,
		"scale": k,
		"stretch": Window.CONTENT_SCALE_STRETCH_INTEGER,
		"aspect": Window.CONTENT_SCALE_ASPECT_KEEP,
		"integer": true,
	}


## 放不下 2 倍时的退路：不缩，逻辑分辨率直接等于窗口，每个美术像素正好对应
## 一个屏幕像素。字会变小，但**不会再被非整数拉伸**——1.5625 倍会把 12px 点阵
## 字糊成一片灰边，那是像素 UI 最不能接受的降级。`min_size` 才是真正拦住小窗口
## 的那道闸。
func _unit_plan(window_size: Vector2i) -> Dictionary:
	return {
		"base": window_size.max(BASE_SIZE),
		"scale": 1,
		"stretch": Window.CONTENT_SCALE_STRETCH_INTEGER,
		"aspect": Window.CONTENT_SCALE_ASPECT_EXPAND,
		"integer": true,
	}


func _apply_now() -> void:
	if _window == null or not is_instance_valid(_window):
		return
	apply_to(_window, _window.size)
