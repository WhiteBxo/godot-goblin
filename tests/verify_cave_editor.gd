@tool
extends EditorScript

var failures: Array[String] = []
var checks := 0

func _check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)

func _settle(tree: SceneTree) -> void:
	for frame in range(4):
		await tree.process_frame

func _run() -> void:
	checks = 0
	failures.clear()
	EditorInterface.get_base_control().set_meta("codex_cave_editor_test", self)
	var tree := Engine.get_main_loop() as SceneTree
	var map: CaveMap = load("res://src/levels/cave/cave_map.tscn").instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	tree.root.add_child(map)
	map.hide()
	await _settle(tree)
	_check(Engine.is_editor_hint(), "Test runs in the real editor")
	_check(map.walls.north_edges.size() > 0, "Walls are initialized in the editor")
	var cell := Vector2i(200, 200)
	var undo := UndoRedo.new()
	undo.create_action("Paint regression ground")
	undo.add_do_method(map.floor_layer.set_cell.bind(cell, 0, Vector2i(15, 15)))
	undo.add_undo_method(map.floor_layer.erase_cell.bind(cell))
	undo.commit_action()
	await _settle(tree)
	_check(map.walkable_cells.has(cell), "Editor painting updates walkability without explicit refresh")
	_check(map.walls.north_edges.has(cell), "Editor painting updates walls")
	_check(map.floor_layer.get_cell_atlas_coords(cell) == Vector2i.ZERO, "Editor painting updates the floor variant")
	_check(map.border_layer.get_cell_source_id(cell + Vector2i.LEFT) == 0, "Editor painting creates the outside edge")
	undo.undo()
	await _settle(tree)
	_check(not map.walkable_cells.has(cell), "Undo removes painted walkability")
	_check(not map.walls.north_edges.has(cell), "Undo removes the painted wall")
	_check(map.border_layer.get_cell_source_id(cell + Vector2i.LEFT) == -1, "Undo removes the outside edge")
	undo.redo()
	await _settle(tree)
	_check(map.walkable_cells.has(cell), "Redo restores painted walkability")
	map.floor_layer.set_cells_terrain_connect([cell + Vector2i.RIGHT], 0, 0)
	await _settle(tree)
	_check(map.walkable_cells.has(cell + Vector2i.RIGHT), "Standard terrain brush paints adjacent ground")
	_check(not map.walls.east_edges.has(cell), "Terrain brush removes the shared wall")
	map.walls.wall_height = 32
	await _settle(tree)
	_check(map.walls.wall_height == 32 and not map.get("_refreshing"), "Wall settings update without a refresh loop")
	map.spawn_cell = Vector2i(-200, -200)
	await _settle(tree)
	_check(not map._get_configuration_warnings().is_empty(), "Editor warns when the spawn point is outside ground")
	map.spawn_cell = Vector2i(63, 76)
	await _settle(tree)
	_check(map._get_configuration_warnings().is_empty(), "Editor clears a corrected spawn warning")
	var packed := PackedScene.new()
	var output := "res://.godot/editable_map_verification/editor_roundtrip.tscn"
	DirAccess.make_dir_recursive_absolute("res://.godot/editable_map_verification")
	_check(packed.pack(map) == OK and ResourceSaver.save(packed, output) == OK, "Editor changes can be saved")
	var reopened: CaveMap = ResourceLoader.load(output, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE).instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	tree.root.add_child(reopened)
	reopened.hide()
	await _settle(tree)
	_check(reopened.walkable_cells.has(cell) and reopened.walkable_cells.has(cell + Vector2i.RIGHT), "Saved editor painting survives reopening")
	_check(reopened.walls.wall_height == 32, "Saved wall settings survive reopening")
	var report := {"checks": checks, "failures": failures}
	var file := FileAccess.open("res://.godot/editable_map_verification/editor_validation.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("Cave editor: %d checks; %d failures" % [checks, failures.size()])
	for failure in failures:
		push_error(failure)
	map.queue_free()
	reopened.queue_free()
