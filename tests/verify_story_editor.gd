extends SceneTree

const PROJECT := "res://docs/story_authoring/day1_stages_01_02_project.json"
var _failures: Array[String] = []
var _checks := 0
var _files: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
		printerr("FAIL: " + message)

func _run() -> void:
	var project := StoryProject.new()
	check(project.open_project(PROJECT) == OK, "Canonical project opens")
	var original := project.snapshot()
	var compiled := project.compile()
	check(not compiled.is_empty(), "Original runtime loaders accept compiled products")
	check(JSON.parse_string(FileAccess.get_file_as_string(original.manifest.story)) == JSON.parse_string(JSON.stringify(compiled.story)), "Import preserves runtime story exactly")
	check(JSON.parse_string(FileAccess.get_file_as_string(original.manifest.dialogue)) == JSON.parse_string(JSON.stringify(compiled.dialogue)), "Import preserves runtime dialogue exactly")
	var beat: Dictionary = original.beats[0]
	var stable: String = beat.steps[0].id
	check(project.insert_step(beat.id, 1, {"command": "wait", "seconds": 0.1}) == OK, "Insert a step")
	var changed := project.compile()
	check(changed.manifest.beats[1].start == compiled.manifest.beats[1].start + 1, "Later Beat offsets are generated")
	check(project.move_step(beat.id, 0, 1) == OK, "Move a step")
	check(project.snapshot().beats[0].steps[1].id == stable, "Reordering preserves stable step ID")
	check(project.undo() and project.undo() and project.snapshot() == original, "Undo returns to original document")
	check(project.redo(), "Redo restores edit")
	var before := project.snapshot()
	check(project.set_step(beat.id, 0, {"command": "dialogue", "id": "missing"}) != OK, "Missing dialogue is rejected")
	check(project.snapshot() == before, "Rejected edit preserves draft")
	var missing_binding := before.duplicate(true)
	missing_binding.beats[0].steps[0].data = {"command": "actor_move", "actor": "player", "target": "missing_marker"}
	check(project.replace_document(missing_binding) != OK, "Undeclared Marker is rejected")
	var broken_binding := before.duplicate(true)
	broken_binding.manifest.markers = []
	check(project.replace_document(broken_binding) != OK, "Malformed binding metadata is rejected without crashing")
	var invalid_fixture := before.duplicate(true)
	invalid_fixture.previews["day1.opening"].actors.player.marker = "not_registered"
	check(project.replace_document(invalid_fixture) != OK, "Invalid preview Marker is rejected before launching")
	invalid_fixture = before.duplicate(true)
	invalid_fixture.previews["day1.opening"]["flags"] = {"day1.example": "yes"}
	check(project.replace_document(invalid_fixture) != OK, "Preview flags require actual booleans")
	check(project.import_manifest(original.manifest.manifest_path, PROJECT) != OK, "Re-import cannot overwrite an existing authoring source")
	var duplicate := before.duplicate(true)
	duplicate.beats[0].steps[1].id = duplicate.beats[0].steps[0].id
	check(project.replace_document(duplicate) != OK, "Duplicate step ID is rejected")
	var wrong_type := before.duplicate(true)
	wrong_type.next_step_id = -1
	check(project.replace_document(wrong_type) != OK, "Invalid step serial is rejected")
	var fork := original.duplicate(true)
	var suffix := "story_editor_test_%d" % OS.get_process_id()
	fork.manifest.story = "res://src/resources/story/" + suffix + ".json"
	fork.manifest.dialogue = "res://src/resources/dialogue/" + suffix + ".json"
	fork.manifest.phases = "res://src/resources/story/" + suffix + "_phases.json"
	fork.manifest.manifest_path = "res://docs/story_authoring/" + suffix + "_mapping.json"
	var source := "res://docs/story_authoring/" + suffix + ".json"
	_files = [source, fork.manifest.story, fork.manifest.dialogue, fork.manifest.manifest_path, fork.manifest.phases]
	_write(source, JSON.stringify(fork))
	var session := StoryProject.new()
	check(session.open_project(source) == OK and session.save() == OK, "Save project and all three products")
	var mapping: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(fork.manifest.manifest_path))
	check(mapping.authoring_sha256 == FileAccess.get_sha256(source), "Generated manifest records actual project hash")
	var disk_before := {}
	for file: String in _files:
		disk_before[file] = FileAccess.get_file_as_string(file)
	var backup: String = fork.manifest.manifest_path + ".story_editor_backup"
	_write(backup, "recovery fixture")
	check(session.set_step(beat.id, 0, {"command": "wait", "seconds": 0.15}) == OK, "Prepare changed draft before interrupted save")
	check(session.save() != OK, "Existing recovery backup stops replacement")
	var restored := true
	for file: String in _files:
		restored = restored and FileAccess.get_file_as_string(file) == disk_before[file]
	check(restored, "Later save failure rolls back all earlier replaced files")
	check(not DirAccess.dir_exists_absolute(source + ".story_editor_lock"), "Failed save releases its lock")
	DirAccess.remove_absolute(backup)
	var peer := StoryProject.new()
	check(peer.open_project(source) == OK, "Concurrent editor opens same project")
	check(session.set_step(beat.id, 0, {"command": "wait", "seconds": 0.2}) == OK and session.save() == OK, "First editor saves")
	check(peer.save() != OK and peer.last_error.contains("外部修改"), "Stale editor cannot overwrite newer work")
	var disk := FileAccess.get_file_as_string(source)
	check(peer.snapshot() == fork, "Conflict preserves unsaved document")
	check(FileAccess.get_file_as_string(source) == disk, "Conflict leaves disk unchanged")
	ProjectSettings.set_setting("debug/developer_tools/enabled", false)
	check(session.save() != OK, "Disabled debug tools cannot write files")
	ProjectSettings.set_setting("debug/developer_tools/enabled", null)
	await _verify_view()
	for file: String in _files:
		if FileAccess.file_exists(file):
			DirAccess.remove_absolute(file)
	print("Story editor: %d checks; %d failures" % [_checks, _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _write(file: String, content: String) -> void:
	var handle := FileAccess.open(file, FileAccess.WRITE)
	handle.store_string(content)
	handle.close()

func _verify_view() -> void:
	var panel: DeveloperPanel = load("res://src/debug/developer_tools/developer_panel.tscn").instantiate()
	root.add_child(panel)
	await process_frame
	var editor := panel.story_editor
	check(editor != null, "F3 panel includes authoring tab")
	editor._open()
	check(editor.project.path == PROJECT and editor._steps.item_count > 0, "View opens actual project and lists steps")
	editor._select_step(1)
	var field: LineEdit = editor._field_controls.volume_db.control
	field.text = "-8"
	field.text_changed.emit(field.text)
	check(editor.apply_current(), "Parameter form applies a changed value")
	check(editor.project.snapshot().beats[0].steps[1].data.volume_db == -8, "Form updates canonical draft")
	editor._details.current_tab = 1
	editor._raw_step.text = "{broken"
	editor._raw_step.text_changed.emit()
	check(not editor.apply_current(), "Invalid JSON stays editable and unapplied")
	editor._details.current_tab = 2
	check(editor._details.current_tab == 1, "Switching views cannot lose pending input")
	editor._undo()
	editor._details.current_tab = 2
	var old_dialogue := editor._dialogue_id
	var old_line := editor._line_id
	editor._text.text = "手动编排测试。"
	editor._text.text_changed.emit()
	check(editor.apply_current(), "Dialogue editor applies text")
	check(editor.project.snapshot().dialogues[old_dialogue].lines[old_line].text == "手动编排测试。", "Dialogue edit is shared with JSON view")
	var tabs: TabContainer = panel.get_node("Panel/Margin/Tools/Tabs")
	tabs.current_tab = tabs.get_tab_count() - 1
	panel.show()
	await process_frame
	check(panel.get_node("Panel").offset_left < -312, "Authoring tab expands console width")
	check(panel.get_node("Panel").get_global_rect().position.x >= 0, "Authoring controls fit inside the viewport")
	var closed := [false]
	panel.close_requested.connect(func() -> void: closed[0] = true)
	if not InputMap.has_action(DeveloperTools.TOGGLE_ACTION):
		InputMap.add_action(DeveloperTools.TOGGLE_ACTION)
	var key := InputEventAction.new()
	key.action = DeveloperTools.TOGGLE_ACTION
	key.pressed = true
	editor._beat_selector.get_popup().window_input.emit(key)
	check(closed[0], "F3 reaches the console from authoring dropdowns")
	editor._discard()
	check(editor.project.dirty, "First discard click retains unsaved draft")
	editor._discard()
	check(not editor.project.dirty and editor.project.snapshot().dialogues[old_dialogue].lines[old_line].text != "手动编排测试。", "Confirmed discard reloads latest disk content")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/story_editor.png")
	panel.queue_free()
	await process_frame
