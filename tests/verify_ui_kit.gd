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

func frames(count: int = 4) -> void:
	for index in range(count):
		await process_frame

func _run() -> void:
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	root.content_scale_size = Vector2i(640, 360)
	root.size = Vector2i(640, 360)
	var scene: PackedScene = load("res://src/debug/ui/ui_kit.tscn")
	check(scene != null, "UI kit scene loads")
	if scene == null:
		quit(1)
		return
	var kit := scene.instantiate()
	root.add_child(kit)
	await frames()
	check(kit.get_node_or_null("MarginContainer") != null or kit.get_child_count() > 0, "UI kit builds its layout")
	var lists := kit.find_children("*", "ItemList", true, false)
	var tabs := kit.find_children("*", "TabContainer", true, false)
	var bars := kit.find_children("*", "ProgressBar", true, false)
	var labels := kit.find_children("*", "Label", true, false)
	check(not lists.is_empty(), "Gallery shows ItemList")
	check(not tabs.is_empty(), "Gallery shows TabContainer")
	check(bars.size() >= 2, "Gallery shows regular and success progress bars")
	check(labels.size() >= 12, "Gallery shows typography and badges")
	await _capture()
	print("UI_KIT: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _capture() -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	var scrolls := root.find_children("*", "ScrollContainer", true, false)
	if scrolls.is_empty():
		return
	var scroll := scrolls[0] as ScrollContainer
	DirAccess.make_dir_recursive_absolute("res://.godot/ui_kit")
	for offset: int in [0, 300, 600, 900, 1200]:
		scroll.scroll_vertical = offset
		await frames()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/ui_kit/ui_kit_%03d.png" % offset)
