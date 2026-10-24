extends Node
## 让整数缩放在任意窗口尺寸下都能铺满：基准分辨率跟着窗口走。
##
## 问题：`scale_mode = integer` 会把缩放倍数向下取整，而 `aspect = expand`
## 只扩展逻辑视口、取整后不会回填。于是 1600×900（2.5 倍）、1366×768（2.13 倍）
## 这类窗口四周会留下黑边，1280×600 更是被钳到 1 倍、只占屏幕一小块。
##
## 做法：把基准分辨率改成「窗口尺寸 ÷ 能放大的整数倍」，倍数因此总是整数，
## 画面铺满且每个逻辑像素都是整齐的 N×N。
##
## 放不下 2 倍时（窗口小于 1280×720，或比例离谱到基准会超出设计面积）不再退
## 小数缩放，改为 1 倍整数：逻辑分辨率等于窗口，铺满但字变小。**任何情况下都
## 不做非整数拉伸**——像素字和像素美术一旦落在半个屏幕像素上就是一片灰边，
## 那比字小得多难受。窗口最小尺寸也因此钉在 1280×720。
##
## 主流手机（1080p / 2K 横屏）算出来就是 800×360 / 792×360，与 expand
## 原本的行为一致，所以手机端不会有任何变化。

const BASE_SIZE := Vector2i(640, 360)
const BASE_AREA := 640.0 * 360.0
## 低于这个倍数就没有整数缩放可用，改用 1 倍整数（不是小数）。
const MIN_INTEGER_SCALE := 2
## 动态基准最多允许比设计分辨率大这么多（面积倍数）。超过它说明窗口比例
## 离谱（导航栏占位后的 2400×1016、折叠屏内屏等），硬撑整数倍会把视野放到
## 设计范围之外，同样退回 1 倍整数。
const MAX_AREA_RATIO := 1.6
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
## 返回 {base: Vector2i, scale: int, stretch: int, integer: bool}。
func plan_for(window_size: Vector2i) -> Dictionary:
	if window_size.x < BASE_SIZE.x or window_size.y < BASE_SIZE.y:
		return _unit_plan(window_size)
	var k := mini(
		floori(float(window_size.x) / float(BASE_SIZE.x)),
		floori(float(window_size.y) / float(BASE_SIZE.y)),
	)
	if k < MIN_INTEGER_SCALE:
		return _unit_plan(window_size)
	# 整数除法：k 能整除时 base × k 正好等于窗口，余数最多 1px。
	@warning_ignore("integer_division")
	var base := Vector2i(window_size.x / k, window_size.y / k)
	if float(base.x * base.y) > BASE_AREA * MAX_AREA_RATIO:
		return _unit_plan(window_size)
	return {
		"base": base,
		"scale": k,
		"stretch": Window.CONTENT_SCALE_STRETCH_INTEGER,
		"integer": true,
	}


func apply_to(window: Window, window_size: Vector2i) -> void:
	var plan := plan_for(window_size)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_stretch = plan.stretch
	window.content_scale_size = plan.base
	_applied_size = window_size


## 放不下 2 倍时的退路：不缩，逻辑分辨率直接等于窗口，每个美术像素正好对应
## 一个屏幕像素。字会变小，但**不会再被非整数拉伸**——1.5625 倍会把 12px 点阵
## 字糊成一片灰边，那是像素 UI 最不能接受的降级。铺满与锐利之间只能二选一，
## 这里选锐利；`min_size` 才是真正拦住小窗口的那道闸。
func _unit_plan(window_size: Vector2i) -> Dictionary:
	return {
		"base": window_size.max(BASE_SIZE),
		"scale": 1,
		"stretch": Window.CONTENT_SCALE_STRETCH_INTEGER,
		"integer": true,
	}


func _apply_now() -> void:
	if _window == null or not is_instance_valid(_window):
		return
	apply_to(_window, _window.size)
