extends SceneTree

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		_failures.append(message)
		push_error(message)

func _run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/map/settlement/modular/catalog.json"))
	_check(data.count == 208 and data.packs.size() == 26, "Expected 208 standalone assets in 26 packs")
	var images := 0
	for pack: Dictionary in data.packs:
		for asset: Dictionary in pack.assets:
			var object: Node2D = load(asset.scene).instantiate()
			root.add_child(object)
			var visual: Sprite2D = object.get_node("Visual")
			_check(object.scale == Vector2.ONE and visual.scale == Vector2.ONE, "Asset must preserve its native proportions: " + str(asset.id))
			_check(visual.texture.get_size() == Vector2(asset.native_size[0], asset.native_size[1]), "Scene must reference the individual cropped PNG")
			_check(not visual.region_enabled, "Scene must not depend on a crop of the old room background")
			_check(object.has_node("GroundAnchor"), "Every asset needs an editable placement anchor")
			var image := visual.texture.get_image()
			_check(image.get_pixel(0, 0).a == 0, "Asset corner must be genuinely transparent")
			images += 1
			object.free()
	var gallery: Node2D = load("res://src/debug/modular_assets/modular_assets_gallery.tscn").instantiate()
	root.add_child(gallery)
	current_scene = gallery
	await process_frame
	_check(gallery.get_pack_count() == 26, "Gallery must expose all packs")
	gallery.show_pack(1)
	_check(gallery.get_pack_index() == 1, "Gallery selection must switch independent objects")
	if "--capture" in OS.get_cmdline_user_args():
		var dest := ProjectSettings.globalize_path("res://docs/assets/modular_assets/captures")
		DirAccess.make_dir_recursive_absolute(dest)
		for shot: Array in [[0, "tavern_godot"], [1, "casino_godot"], [17, "stone_walls_godot"]]:
			gallery.show_pack(shot[0])
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(dest + "/" + shot[1] + ".png")
	gallery.queue_free()
	await process_frame
	print("MODULAR_ASSETS: %d independent PNG/PackedScene pairs checked; %d failures" % [images, _failures.size()])
	quit(0 if _failures.is_empty() else 1)
