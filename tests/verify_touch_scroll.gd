extends SceneTree
## 手指拖动契约：长文本（RichTextLabel）与长列表（ScrollContainer）都能滑动，
## 小幅移动仍按点击处理。

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
	var host := Control.new()
	host.name = "TouchScrollHost"
	host.size = Vector2(640, 360)
	root.add_child(host)

	# 纸条：shop_popup 运行时创建的 StoryNote 就是这种配置。
	var note := RichTextLabel.new()
	note.name = "StoryNote"
	note.scroll_active = true
	note.fit_content = false
	note.position = Vector2(20, 20)
	note.size = Vector2(300, 100)
	host.add_child(note)
	note.text = _long_note()
	await process_frame
	await process_frame
	var note_bar := note.get_v_scroll_bar()
	check(note_bar.max_value > note_bar.page, "long note overflows its frame")
	if note_bar.max_value <= note_bar.page:
		print("TOUCH_SCROLL: FAIL (note never overflows, fixture broken)")
		quit(1)
		return

	var scroller := TouchScroll.new()
	root.add_child(scroller)
	scroller.configure([host])

	await _touch_drag(Vector2(100.0, 90.0), Vector2(100.0, 40.0), 0)
	check(note_bar.value > 0.0,
		"finger drag scrolls a long note (value %.1f)" % note_bar.value)

	var before_tap := note_bar.value
	await _touch_drag(Vector2(100.0, 90.0), Vector2(100.0, 86.0), 1)
	check(is_equal_approx(note_bar.value, before_tap),
		"tiny movement stays a tap (value %.1f -> %.1f)" % [before_tap, note_bar.value])

	# 运行时才创建的纸条（shop_popup 的 StoryNote 就是 new 出来的），
	# 必须被 node_added 路径接住，否则赌场纸条这类长文本拖不动。
	var runtime_note := RichTextLabel.new()
	runtime_note.name = "RuntimeNote"
	runtime_note.scroll_active = true
	runtime_note.fit_content = false
	runtime_note.position = Vector2(20, 220)
	runtime_note.size = Vector2(300, 100)
	host.add_child(runtime_note)
	runtime_note.text = _long_note()
	await process_frame
	await process_frame
	var runtime_bar := runtime_note.get_v_scroll_bar()
	check(runtime_bar.max_value > runtime_bar.page, "runtime note overflows its frame")
	await _touch_drag(Vector2(100.0, 290.0), Vector2(100.0, 240.0), 3)
	check(runtime_bar.value > 0.0,
		"a note created after configure is watched too (value %.1f)" % runtime_bar.value)

	# 长列表：原有 ScrollContainer 行为不能回归。
	var list := ScrollContainer.new()
	list.name = "LongList"
	list.position = Vector2(360, 20)
	list.size = Vector2(260, 160)
	host.add_child(list)
	var rows := VBoxContainer.new()
	list.add_child(rows)
	for index: int in range(40):
		var row := Label.new()
		row.text = "第 %d 行配方" % index
		rows.add_child(row)
	await process_frame
	await process_frame
	var list_bar := list.get_v_scroll_bar()
	check(list_bar.max_value > list_bar.page, "long list overflows its frame")
	await _touch_drag(Vector2(480.0, 150.0), Vector2(480.0, 100.0), 2)
	check(list.scroll_vertical > 0,
		"finger drag still scrolls a ScrollContainer (offset %d)" % list.scroll_vertical)

	print("TOUCH_SCROLL: %s (%d checks, %d failures)" % [
		"PASS" if failures.is_empty() else "FAIL", checks, failures.size(),
	])
	quit(0 if failures.is_empty() else 1)


func _touch_drag(from: Vector2, to: Vector2, index: int) -> void:
	var press := InputEventScreenTouch.new()
	press.index = index
	press.pressed = true
	press.position = from
	root.push_input(press)
	await process_frame
	var drag := InputEventScreenDrag.new()
	drag.index = index
	drag.position = to
	drag.relative = to - from
	root.push_input(drag)
	await process_frame
	var release := InputEventScreenTouch.new()
	release.index = index
	release.pressed = false
	release.position = to
	root.push_input(release)
	await process_frame


func _long_note() -> String:
	var lines := PackedStringArray()
	for index: int in range(40):
		lines.append("第 %d 行：赌桌上的烈酒与酒渍纸条，发现手记与配方原文。" % index)
	return "\n".join(lines)
