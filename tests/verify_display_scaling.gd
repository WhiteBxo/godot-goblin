extends SceneTree

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
	for sample: Array in [
		[Vector2i(1280, 720), Vector2i(640, 360), 2],
		[Vector2i(1366, 768), Vector2i(683, 384), 2],
		[Vector2i(1600, 900), Vector2i(800, 450), 2],
		[Vector2i(1706, 960), Vector2i(853, 480), 2],
		[Vector2i(1680, 1050), Vector2i(840, 525), 2],
		[Vector2i(1920, 1080), Vector2i(640, 360), 3],
		[Vector2i(1920, 1061), Vector2i(640, 353), 3],
		[Vector2i(1920, 1200), Vector2i(640, 400), 3],
		[Vector2i(2400, 1080), Vector2i(800, 360), 3],
		[Vector2i(2400, 1016), Vector2i(1200, 508), 2],
		[Vector2i(2560, 1440), Vector2i(640, 360), 4],
		[Vector2i(3440, 1440), Vector2i(860, 360), 4],
		[Vector2i(3840, 2160), Vector2i(640, 360), 6],
	]:
		var size: Vector2i = sample[0]
		var plan: Dictionary = scaling.plan_for(size)
		check(plan.base == sample[1] and plan.scale == sample[2], "Expected native layout at %s: %s" % [size, plan])
		check(plan.integer and plan.stretch == Window.CONTENT_SCALE_STRETCH_INTEGER, "Integer pixels at %s" % size)
		check(plan.aspect == Window.CONTENT_SCALE_ASPECT_EXPAND, "Extra space becomes view at %s" % size)
		var gap: Vector2i = size - plan.base * int(plan.scale)
		check(gap.x >= 0 and gap.y >= 0 and gap.x < plan.scale and gap.y < plan.scale, "No large black border at %s" % size)
	for size: Vector2i in [Vector2i(1024, 600), Vector2i(1280, 600), Vector2i(800, 600), Vector2i(640, 360)]:
		var plan: Dictionary = scaling.plan_for(size)
		check(plan.base == Vector2i(640, 360), "Small windows retain the readable design layout: %s" % size)
		check(not plan.integer and plan.scale >= 1.0 and plan.stretch == Window.CONTENT_SCALE_STRETCH_FRACTIONAL, "Small windows avoid the tiny 1x UI fallback: %s" % size)
	var extreme: Dictionary = scaling.plan_for(Vector2i(6000, 1080))
	check(extreme.base.x <= 1280 and extreme.aspect == Window.CONTENT_SCALE_ASPECT_KEEP, "Extreme aspect ratios cap extra view")
	var window := Window.new()
	scaling.apply_to(window, Vector2i(1600, 900))
	check(window.content_scale_size == Vector2i(800, 450) and window.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER, "Apply uses the planned native canvas")
	window.free()
	print("DISPLAY_SCALING: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
