extends SceneTree

func _initialize() -> void:
	call_deferred("_import_layout")

func _import_layout() -> void:
	var source := "res://src/levels/cave/cave_layout.json"
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--layout="):
			source = argument.trim_prefix("--layout=")
		elif argument.begins_with("--output="):
			output = argument.trim_prefix("--output=")
	if not output.begins_with("res://") or not output.ends_with(".tscn"):
		push_error("Specify --output=res://path/map.tscn; importing replaces the output scene's painted cells")
		quit(1)
		return
	var map: CaveMap = load("res://src/levels/cave/cave_map.tscn").instantiate()
	root.add_child(map)
	var error := map.load_layout(source)
	if error != OK:
		push_error("Could not import cave layout (error %d)" % error)
		quit(1)
		return
	await process_frame
	var output_uid := ResourceLoader.get_resource_uid(output) if FileAccess.file_exists(output) else ResourceUID.INVALID_ID
	var packed := PackedScene.new()
	error = packed.pack(map)
	if error == OK:
		error = ResourceSaver.save(packed, output)
	if error == OK and output_uid != ResourceUID.INVALID_ID:
		error = ResourceSaver.set_uid(output, output_uid)
	print("Import: %d ground cells, %d river cells; saved %s (error %d)" % [map.walkable_cells.size(), map.river_layer.get_used_cells().size(), output, error])
	map.queue_free()
	await process_frame
	quit(0 if error == OK else 1)
