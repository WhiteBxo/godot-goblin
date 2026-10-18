extends SceneTree
## Shared CLI entry: -- <project.json> [--save] or -- --import <manifest> <project>.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var project := StoryProject.new()
	var error := ERR_INVALID_PARAMETER
	if args.size() == 3 and args[0] == "--import":
		error = project.import_manifest(args[1], args[2])
		if error == OK:
			error = project.save()
	elif args.size() in [1, 2]:
		error = project.open_project(args[0])
		if error == OK and args.size() == 2:
			error = project.save() if args[1] == "--save" else ERR_INVALID_PARAMETER
		if error == OK:
			var compiled := project.compile()
			var products: Array = [["story", compiled.story], ["dialogue", compiled.dialogue]]
			if project.snapshot().manifest.has("phases"):
				products.append(["phases", compiled.phases])
			for pair: Array in products:
				var file: String = project.snapshot().manifest[pair[0]]
				if JSON.parse_string(FileAccess.get_file_as_string(file)) != JSON.parse_string(JSON.stringify(pair[1])):
					project.last_error = "运行时产物与工程不同，请 --save：" + file
					error = ERR_INVALID_DATA
			var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(project.snapshot().manifest.manifest_path))
			if not manifest is Dictionary or manifest.get("authoring_sha256") != FileAccess.get_sha256(project.path) or manifest.get("beats") != JSON.parse_string(JSON.stringify(compiled.manifest.beats)):
				project.last_error = "Beat 清单或工程散列过期，请 --save"
				error = ERR_INVALID_DATA
	if error != OK:
		printerr("STORY_PROJECT: ", error_string(error), " ", project.last_error)
		quit(1)
		return
	print("STORY_PROJECT: OK · %s · %d Beats" % [project.path, project.snapshot().beats.size()])
	quit(0)
