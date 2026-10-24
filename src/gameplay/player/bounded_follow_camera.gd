class_name BoundedFollowCamera
extends Camera2D
## The only writer of camera transforms. Director tweens call the methods below.

signal focus_target_lost

enum Mode { FOLLOW, CINEMATIC }

@export_range(0.1, 4.0, 0.05) var preferred_zoom := 0.5
## 世界像素 / 美术像素：房间节点 scale 1.25 就填 1.25。它把「整数屏幕像素」的
## 栅格从「屏幕倍率的倒数」换算成「屏幕倍率 × 房间密度 的倒数」——奶茶店在
## 1280×720 下的合法 zoom 因此是 0.4 / 0.8 / 1.2，而不是 0.5 / 1.0。
## 角色贴图本身还有一层密度（精灵 scale 2 就是每 texel 2 世界像素），它才是
## 玩家真正盯着看的那个栅格：聚落用 rpg_player 时美术密度是 1.0，一旦误填成
## 奶茶店的 1.25，preferred_zoom 1.0 会被量化到 0.8，角色每 texel 落到 3.2 个
## 屏幕像素上——背景是画的还能忍，人物立刻糊成一团。
@export_range(0.25, 4.0, 0.05) var art_scale := 1.0
@export var cinematic_pixel_snap := true
## Leads the follow target in its movement direction, in world pixels. Zero
## keeps the original centred follow for hosts that do not opt in.
@export_range(0.0, 24.0, 1.0) var follow_look_ahead := 0.0

var mode: Mode = Mode.FOLLOW
var _world_bounds := Rect2()
var _follow_offset := Vector2.ZERO
var _follow_position := Vector2.ZERO
var _follow_smoothing := false
var _settled := false
var _requested_zoom: float
var _cinematic_position := Vector2.ZERO
var _focus_target: WeakRef
var _focus_offset := Vector2.ZERO
var _shake_pixels := Vector2.ZERO
var _look_ahead := Vector2.ZERO

@onready var _follow_target := get_parent() as Node2D

func _ready() -> void:
	_follow_offset = position
	_follow_position = position
	_follow_smoothing = position_smoothing_enabled
	_requested_zoom = preferred_zoom
	top_level = true
	process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	process_physics_priority = 1
	get_viewport().size_changed.connect(_update_zoom)
	zoom = Vector2.ONE * _floor_aligned(preferred_zoom)

func _process(_delta: float) -> void:
	if _focus_target != null:
		var target := _focus_target.get_ref() as Node2D
		if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion():
			_focus_target = null
			reset_camera()
			focus_target_lost.emit()
			return
		_cinematic_position = target.global_position + _focus_offset
	if mode == Mode.CINEMATIC:
		_apply_cinematic_position()
	if not _shake_pixels.is_zero_approx():
		_apply_shake()

func _physics_process(_delta: float) -> void:
	if mode == Mode.FOLLOW:
		_advance_look_ahead(_delta)
		_update_follow_target()
		# End the smoothing tail exactly; pixel snapping can expose floating-point drift.
		if not _settled and get_screen_center_position().distance_squared_to(global_position) < 0.0001:
			reset_smoothing()
			_settled = true

## Looks ahead only while the target actually moves, so stopping recentres.
func _advance_look_ahead(delta: float) -> void:
	if follow_look_ahead <= 0.0 or not is_instance_valid(_follow_target):
		_look_ahead = Vector2.ZERO
		return
	var desired := Vector2.ZERO
	var body := _follow_target as CharacterBody2D
	if body != null:
		var speed := body.velocity.length()
		if speed > 8.0:
			desired = body.velocity / speed * follow_look_ahead
	_look_ahead = _look_ahead.move_toward(desired, follow_look_ahead * 6.0 * delta)

func configure(world_bounds: Rect2) -> void:
	_world_bounds = world_bounds
	limit_left = ceili(world_bounds.position.x)
	limit_top = ceili(world_bounds.position.y)
	limit_right = floori(world_bounds.end.x)
	limit_bottom = floori(world_bounds.end.y)
	_update_zoom()
	make_current()
	reset_smoothing()
	force_update_scroll()

func get_follow_position() -> Vector2:
	return _clamp_center(_follow_target.global_position + _follow_offset + _look_ahead)

func begin_cinematic() -> void:
	_focus_target = null
	if mode == Mode.CINEMATIC:
		return
	_look_ahead = Vector2.ZERO
	force_update_scroll()
	_cinematic_position = get_screen_center_position() - offset
	mode = Mode.CINEMATIC
	position_smoothing_enabled = false
	top_level = true
	_apply_cinematic_position()

func set_cinematic_position(value: Vector2) -> void:
	_cinematic_position = value
	_apply_cinematic_position()

func hold_focus(target: Node2D, target_offset: Vector2 = Vector2.ZERO) -> void:
	_focus_target = weakref(target)
	_focus_offset = target_offset
	set_cinematic_position(target.global_position + target_offset)

func restore_follow() -> void:
	_focus_target = null
	mode = Mode.FOLLOW
	top_level = true
	position_smoothing_enabled = _follow_smoothing
	_look_ahead = Vector2.ZERO
	reset_smoothing()
	_update_follow_target()
	force_update_scroll()

func reset_camera() -> void:
	set_shake_pixels(Vector2.ZERO)
	_look_ahead = Vector2.ZERO
	_requested_zoom = preferred_zoom
	_update_zoom()
	restore_follow()

func set_directed_zoom(value: float) -> void:
	_requested_zoom = value
	_update_zoom()

func get_directed_zoom() -> float:
	return _requested_zoom

func set_shake_pixels(value: Vector2) -> void:
	_shake_pixels = value.round()
	if value.is_zero_approx():
		offset = Vector2.ZERO
		force_update_scroll()
	else:
		_apply_shake()

func _apply_cinematic_position() -> void:
	var value := _cinematic_position
	if cinematic_pixel_snap:
		value = (value * zoom).round() / zoom
	global_position = _clamp_center(value)
	force_update_scroll()

func _clamp_center(value: Vector2) -> Vector2:
	if not _world_bounds.has_area():
		return value
	var half_view := get_viewport_rect().size / (zoom * 2.0)
	var minimum := Vector2(limit_left, limit_top) + half_view
	var maximum := Vector2(limit_right, limit_bottom) - half_view
	# 房间比视口还小的时候没有可滚动的余地：两头钳制会互相穿过，把镜头顶到
	# 房间一角（画面偏一边）。这种情况直接居中，房间自己铺满一屏。
	var center := _world_bounds.get_center()
	if _world_bounds.size.x <= half_view.x * 2.0:
		value.x = center.x
	if _world_bounds.size.y <= half_view.y * 2.0:
		value.y = center.y
	return value.clamp(minimum, maximum.max(minimum))

func _apply_shake() -> void:
	# offset bypasses Camera2D limits. Restrict it for BOTH the smoothed center
	# and destination, so the next built-in smoothing tick also remains safe.
	var base_center := get_screen_center_position() - offset
	var destination := _clamp_center(global_position)
	var desired := _shake_pixels / zoom
	var safe_current := _clamp_center(base_center + desired) - base_center
	var safe_destination := _clamp_center(destination + desired) - destination
	var half_view := get_viewport_rect().size / (zoom * 2.0)
	# Intersection of the permitted ranges, with whole viewport-pixel offsets.
	for axis in range(2):
		# 房间比视口还小的那根轴（奶茶店：整间店正好一屏）没有可移动的余地，
		# 钳制会把摇屏整条抹平。这里宁可让画面探出边界几个像素——边界外面是
		# 画框，不是虚空。
		if _world_bounds.size[axis] <= half_view[axis] * 2.0:
			continue
		if desired[axis] > 0.0:
			desired[axis] = maxf(0.0, minf(safe_current[axis], safe_destination[axis]))
		else:
			desired[axis] = minf(0.0, maxf(safe_current[axis], safe_destination[axis]))
	# Rounding toward zero avoids crossing a fractional boundary.
	offset = Vector2(int(desired.x * zoom.x), int(desired.y * zoom.y)) / zoom
	force_update_scroll()

func _update_zoom() -> void:
	# 像素画只有在 zoom 恰好等于「整数个屏幕像素 / 美术像素」时才不会被重采样。
	# 房间密度由 art_scale 给出：奶茶店是 1.25，所以在 2 倍窗口下合法 zoom 是
	# 0.4 / 0.8 / 1.2……；1.15 会让每个美术像素落在 2.3 个屏幕像素上，边缘出现
	# 宽窄不一的毛边——演出推近时小人一团糊就是这么来的。
	var requested := _floor_aligned(_requested_zoom)
	if not _world_bounds.has_area():
		zoom = Vector2.ONE * requested
		return
	var viewport_size := get_viewport_rect().size
	# 「必须铺满」的那一侧不做对齐：它决定能不能看到整间店，为锐利把视野裁掉
	# 是笔亏本买卖。（奶茶店的 camera_insets 就是按 fit_zoom 反推出来的。）
	var minimum_zoom := maxf(viewport_size.x / _world_bounds.size.x, viewport_size.y / _world_bounds.size.y)
	zoom = Vector2.ONE * maxf(requested, minimum_zoom)
	if mode == Mode.CINEMATIC:
		_apply_cinematic_position()
	else:
		_update_follow_target()
	if not _shake_pixels.is_zero_approx():
		_apply_shake()
	force_update_scroll()

## 一个美术像素对应的屏幕像素数（1280×720 窗口对 640×360 逻辑视口是 2）。
## 注意 `Window.content_scale_factor` 是玩家的额外缩放偏好，默认 1，不是这个比值。
##
## 取整是必须的：`stretch=integer` 下 1706×960 的窗口只按 2 倍画 640×360 逻辑视口
## 并居中留边，直接相除会得到 2.666 —— 那是个并不存在的倍率，栅格步长会算错、
## 相机以为自己能对齐到 1/3 像素。
func _screen_factor() -> float:
	var window := get_window()
	if window == null:
		return 1.0
	var logical := get_viewport_rect().size
	if logical.x <= 0.0:
		return 1.0
	var factor := minf(float(window.size.x) / logical.x, float(window.size.y) / logical.y)
	if window.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_FRACTIONAL:
		return factor
	return maxf(1.0, floorf(factor + 0.0001))

func _floor_aligned(value: float) -> float:
	# Small windows keep the authored framing instead of rounding far out.
	if get_window().content_scale_stretch == Window.CONTENT_SCALE_STRETCH_FRACTIONAL:
		return value
	# 一美术像素 → 整数屏幕像素的最小 zoom 步长。房间密度是 1.25 时步长是 0.4
	# （1.25 × 0.4 × 2 倍窗口 = 1.0），密度是 1 时仍是 0.5。
	var step := 1.0 / (maxf(1.0, _screen_factor()) * maxf(0.25, art_scale))
	return maxf(step, floorf(value / step + 0.0001) * step)

func _update_follow_target() -> void:
	if not _world_bounds.has_area():
		return
	var target := _clamp_center(_follow_target.global_position + _follow_offset + _look_ahead)
	if global_position.distance_squared_to(target) > 0.000001:
		global_position = target
		_settled = false
