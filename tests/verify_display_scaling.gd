extends SceneTree
## 整数缩放基准：非整数倍窗口不再留黑边，放不下 2 倍时退 1 倍整数而不是小数拉伸。

var checks := 0
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)


func _run() -> void:
	var scaling := root.get_node_or_null("DisplayScaling")
	check(scaling != null, "DisplayScaling autoload is registered")
	if scaling == null:
		quit(1)
		return

	_expect(scaling, Vector2i(1920, 1080), Vector2i(640, 360), 3, true,
		"1080p keeps the design resolution")
	_expect(scaling, Vector2i(2400, 1080), Vector2i(800, 360), 3, true,
		"20:9 phone widens the viewport like expand used to")
	_expect(scaling, Vector2i(3168, 1440), Vector2i(792, 360), 4, true,
		"2K phone stays integer")
	_expect(scaling, Vector2i(1600, 900), Vector2i(800, 450), 2, true,
		"1600x900 fills instead of letterboxing")
	_expect(scaling, Vector2i(1366, 768), Vector2i(683, 384), 2, true,
		"1366x768 laptop fills instead of letterboxing")
	_expect(scaling, Vector2i(3840, 2160), Vector2i(640, 360), 6, true,
		"4K keeps the design resolution")
	_expect(scaling, Vector2i(1280, 600), Vector2i(1280, 600), 1, true,
		"a window too short for 2x drops to 1x instead of stretching")
	_expect(scaling, Vector2i(640, 360), Vector2i(640, 360), 1, true,
		"the design size is served by 1x, not a fractional scale")
	_expect(scaling, Vector2i(2400, 1016), Vector2i(2400, 1016), 1, true,
		"a status-bar crop drops to 1x rather than sampling unevenly")

	# 退路必须是 1 倍整数：逻辑分辨率等于窗口，一个美术像素正好一个屏幕像素。
	# 非整数倍（1.5625）会把 12px 点阵字糊成灰边，那是不能接受的降级。
	var unit: Dictionary = scaling.plan_for(Vector2i(1280, 600))
	check(unit.stretch == Window.CONTENT_SCALE_STRETCH_INTEGER,
		"the fallback still uses integer stretching")
	check(unit.base == Vector2i(1280, 600),
		"the fallback puts one art pixel on one screen pixel")

	# 整数缩放的硬性不变式：base × scale 必须等于窗口，最多差 1px。
	for window_size: Vector2i in [Vector2i(1600, 900), Vector2i(1366, 768),
			Vector2i(1920, 1080), Vector2i(2400, 1080), Vector2i(2560, 1440),
			Vector2i(3840, 2160), Vector2i(1367, 769)]:
		var plan: Dictionary = scaling.plan_for(window_size)
		if not plan.integer:
			check(false, "expected an integer plan for %s" % window_size)
			continue
		var cover: Vector2i = plan.base * int(plan.scale)
		var gap: Vector2i = window_size - cover
		check(gap.x >= 0 and gap.x <= 1 and gap.y >= 0 and gap.y <= 1,
			"integer plan covers %s exactly (gap %s)" % [window_size, gap])

	print("DISPLAY_SCALING: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(),
	])
	quit(0 if failures.is_empty() else 1)


func _expect(scaling: Node, window_size: Vector2i, base: Vector2i, scale: int,
		integer: bool, description: String) -> void:
	var plan: Dictionary = scaling.plan_for(window_size)
	check(plan.base == base, "%s: base %s (got %s)" % [description, base, plan.base])
	check(plan.integer == integer,
		"%s: integer=%s (got %s)" % [description, integer, plan.integer])
	if not integer:
		return
	check(int(plan.scale) == scale, "%s: scale %d (got %d)" % [description, scale, plan.scale])
	var cover: Vector2i = plan.base * int(plan.scale)
	var gap: Vector2i = window_size - cover
	check(gap.x >= 0 and gap.x <= 1 and gap.y >= 0 and gap.y <= 1,
		"%s: covers the window (gap %s)" % [description, gap])
