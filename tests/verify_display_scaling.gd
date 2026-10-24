extends SceneTree
## 窗口缩放契约：倍率由窗口高度决定，UI 与世界层永远按同一个倍率绘制。
##
## - 高度接近 360 的整数倍（16:9 窗口、带标题栏的最大化窗口、20:9 手机）：
##   base = 窗口 / k，UI 物理尺寸与设计稿严格一致，宽出来的是额外视野。
## - 高度不是整数倍（1706×960、1600×900、16:10）：逻辑视口钉死 640×360，
##   整数倍居中、四周留边，构图与默认窗口完全一致。
## - 任何情况下都不做非整数拉伸。

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

	# 高度是整数倍：逻辑视口 = 窗口 / k，16:9 时正好 640×360 铺满。
	_expect_wide(scaling, Vector2i(1280, 720), Vector2i(640, 360), 2,
		"the default window is exactly 2x and full screen")
	_expect_wide(scaling, Vector2i(1920, 1080), Vector2i(640, 360), 3,
		"1080p full screen is exactly 3x")
	_expect_wide(scaling, Vector2i(2560, 1440), Vector2i(640, 360), 4,
		"1440p is exactly 4x")
	_expect_wide(scaling, Vector2i(3840, 2160), Vector2i(640, 360), 6,
		"4K is exactly 6x")
	# 桌面最大化时窗口高度被标题栏吃掉十几像素，仍然必须认作 3 倍——否则会
	# 掉进「不是整数倍」分支，把整间店缩到 2 倍再四周留边。
	_expect_wide(scaling, Vector2i(1920, 1061), Vector2i(640, 353), 3,
		"a maximized 1080p window (title bar) still counts as 3x")

	# 更宽的窗口：高度仍是整数倍，宽度多看到两侧（手机、超宽屏）。
	_expect_wide(scaling, Vector2i(2400, 1080), Vector2i(800, 360), 3,
		"20:9 phone widens the viewport")
	_expect_wide(scaling, Vector2i(2340, 1080), Vector2i(780, 360), 3,
		"19.5:9 phone widens the viewport")
	_expect_wide(scaling, Vector2i(3440, 1440), Vector2i(860, 360), 4,
		"21:9 ultrawide widens the viewport")

	# 高度不是整数倍：钉死 640×360 并居中留边。
	# 1706×960 是编辑器嵌入面板最常见的尺寸，曾经被面积上限打回 1 倍，于是 UI
	# 缩到一半、房间被撑到 1.07 倍——同一屏里两套倍率。
	_expect_keep(scaling, Vector2i(1706, 960), 2, "a non-multiple 16:9 panel stays 2x and letterboxes")
	_expect_keep(scaling, Vector2i(1600, 900), 2, "1600x900 letterboxes instead of rescaling the world")
	_expect_keep(scaling, Vector2i(1366, 768), 2, "1366x768 laptop letterboxes")
	_expect_keep(scaling, Vector2i(1680, 1050), 2, "16:10 letterboxes")
	_expect_keep(scaling, Vector2i(1920, 1200), 3, "16:10 at 3x keeps the design viewport")
	_expect_keep(scaling, Vector2i(2400, 1016), 2, "a status-bar crop letterboxes")

	# 放不下 2 倍时退 1 倍整数，绝不小数拉伸。逻辑分辨率等于窗口，
	# 一个美术像素正好一个屏幕像素。
	var short_window: Dictionary = scaling.plan_for(Vector2i(1280, 600))
	check(short_window.base == Vector2i(1280, 600) and int(short_window.scale) == 1,
		"a window too short for 2x drops to 1x instead of stretching")
	check(short_window.stretch == Window.CONTENT_SCALE_STRETCH_INTEGER,
		"the short-window fallback still uses integer stretching")
	var tiny: Dictionary = scaling.plan_for(Vector2i(640, 360))
	check(tiny.base == Vector2i(640, 360) and int(tiny.scale) == 1,
		"the design size is served by 1x")

	# 硬性不变式：两个分支都必须是整数缩放，画面按 base × scale 居中，绝不溢出窗口。
	for window_size: Vector2i in [Vector2i(1706, 960), Vector2i(1600, 900),
			Vector2i(1366, 768), Vector2i(1920, 1080), Vector2i(1920, 1061),
			Vector2i(2400, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
			Vector2i(2340, 1080), Vector2i(1680, 1050)]:
		var plan: Dictionary = scaling.plan_for(window_size)
		check(plan.integer, "expected an integer plan for %s" % window_size)
		check(plan.stretch == Window.CONTENT_SCALE_STRETCH_INTEGER,
			"plan for %s uses integer stretching" % window_size)
		var cover: Vector2i = plan.base * int(plan.scale)
		check(cover.x <= window_size.x and cover.y <= window_size.y,
			"plan for %s never overflows the window (covers %s)" % [window_size, cover])
		# expand 分支的余量只是整数除法的零头（最多 k-1 像素）；keep 分支的余量
		# 是刻意的信箱边，尺寸由设计视口决定，不在这里约束。
		if plan.aspect == Window.CONTENT_SCALE_ASPECT_EXPAND:
			check(window_size.x - cover.x < int(plan.scale) and window_size.y - cover.y < int(plan.scale),
				"plan for %s leaves at most a k-1 remainder (%s)" % [window_size, window_size - cover])

	# 「观感一致」的定义：UI 的屏幕尺寸只取决于倍率 k，与窗口多宽无关。
	# 1280×720 与 1706×960 都是 2 倍，逻辑视口必须完全相同。
	for window_size: Vector2i in [Vector2i(1280, 720), Vector2i(1706, 960)]:
		var plan: Dictionary = scaling.plan_for(window_size)
		check(int(plan.scale) == 2, "%s renders at 2x" % window_size)
		check(plan.base == Vector2i(640, 360),
			"%s keeps a 640x360 viewport" % window_size)

	print("DISPLAY_SCALING: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(),
	])
	quit(0 if failures.is_empty() else 1)


func _expect_keep(scaling: Node, window_size: Vector2i, scale: int, description: String) -> void:
	var plan: Dictionary = scaling.plan_for(window_size)
	check(plan.base == Vector2i(640, 360),
		"%s: base 640x360 (got %s)" % [description, plan.base])
	check(int(plan.scale) == scale, "%s: scale %d (got %d)" % [description, scale, plan.scale])
	check(plan.aspect == Window.CONTENT_SCALE_ASPECT_KEEP,
		"%s: uses KEEP aspect" % description)
	check(plan.stretch == Window.CONTENT_SCALE_STRETCH_INTEGER,
		"%s: uses integer stretching" % description)


func _expect_wide(scaling: Node, window_size: Vector2i, base: Vector2i, scale: int,
		description: String) -> void:
	var plan: Dictionary = scaling.plan_for(window_size)
	check(plan.base == base, "%s: base %s (got %s)" % [description, base, plan.base])
	check(int(plan.scale) == scale, "%s: scale %d (got %d)" % [description, scale, plan.scale])
	check(plan.aspect == Window.CONTENT_SCALE_ASPECT_EXPAND,
		"%s: uses EXPAND aspect" % description)
	check(plan.stretch == Window.CONTENT_SCALE_STRETCH_INTEGER,
		"%s: uses integer stretching" % description)
	# 整数除法的零头最多 k-1 像素（1920×1061 分成 3 份，高 353×3 = 1059，差 2）。
	var cover: Vector2i = plan.base * int(plan.scale)
	var gap: Vector2i = window_size - cover
	check(gap.x >= 0 and gap.x < scale and gap.y >= 0 and gap.y < scale,
		"%s: covers the window (gap %s)" % [description, gap])
