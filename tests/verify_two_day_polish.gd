extends SceneTree
## Presentation and optional play must leave the mandatory two-day route intact.

var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error(message)

func frames(count := 3) -> void:
	for index in range(count):
		await process_frame

func _run() -> void:
	var hud: ChapterActionsHUD = load("res://src/UI/hud/chapter_actions_hud.tscn").instantiate()
	root.add_child(hud)
	await frames()
	var detail := "代购专款 35G · 跑腿途中\n\n七日祭食材\n苔痕青 2/2 · 缺0\n已齐备，第三天交付。"
	var summary := "代购 · 跑腿途中\n七日祭 · 已齐备，第三天交付"
	hud.show_actions([], detail, true, summary)
	check(hud.get_node("Content/NoticePanel/Notice").text == summary, "Optional HUD starts compact")
	hud.get_node("Content/Details").pressed.emit()
	check(hud.get_node("Content/NoticePanel/Notice").text == detail, "Details remain available on demand")
	hud.show_actions([], detail, false, summary)
	check(hud.get_node("Content/Details").disabled, "World HUD cannot change while a modal owns input")
	hud.show_actions([], "", true)
	check(not hud.get_node("Content/NoticePanel").visible and not hud.get_node("Content/Details").visible, "Finished optional work leaves no empty card")
	hud.show_actions([], detail, true, summary)
	hud.get_node("Content/Details").pressed.emit()
	await frames()
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://.godot/two_day_polish")
		root.get_texture().get_image().save_png("res://.godot/two_day_polish/hud.png")
	hud.free()
	print("TWO_DAY_POLISH: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
