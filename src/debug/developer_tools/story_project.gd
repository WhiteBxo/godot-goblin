class_name StoryProject
extends RefCounted
## Development-only authoring document. Runtime schemas remain unchanged.

const FORMAT := "goblin_story_project"
var last_error := ""
var path := ""
var dirty := false
var _document: Dictionary = {}
var _disk_hashes: Dictionary = {}
var _undo: Array[Dictionary] = []
var _redo: Array[Dictionary] = []

func snapshot() -> Dictionary:
	return _document.duplicate(true)

func open_project(source: String) -> Error:
	if not FileAccess.file_exists(source):
		return _fail("剧情工程不存在：" + source)
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(source)) != OK or not parser.data is Dictionary:
		return _fail("剧情工程 JSON 无效：" + parser.get_error_message())
	var previous := _document
	_document = parser.data
	if compile().is_empty():
		_document = previous
		return ERR_INVALID_DATA
	path = source
	dirty = false
	_undo.clear()
	_redo.clear()
	_remember_disk()
	return OK

## Explicit one-time import; no source files are written here.
func import_manifest(source: String, destination: String) -> Error:
	if FileAccess.file_exists(destination):
		return _fail("目标工程已存在；导入不能覆盖手调内容：" + destination)
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
	if not manifest is Dictionary or not manifest.has_all(["story", "dialogue", "beats"]):
		return _fail("编排清单缺少 story / dialogue / beats")
	var story: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest.story))
	var dialogue: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest.dialogue))
	if not story is Dictionary or not dialogue is Dictionary:
		return _fail("不能读取原有演出或对白")
	var events: Dictionary = story.events.duplicate(true)
	for event: Dictionary in events.values():
		event.erase("steps")
	var beats: Array = []
	var serial := 1
	for original: Dictionary in manifest.beats:
		var beat := original.duplicate(true)
		if beat.has("event"):
			beat["steps"] = []
			for index in range(int(beat.start), int(beat.start + beat.count)):
				beat.steps.append({"id": "step_%04d" % serial, "data": story.events[beat.event].steps[index].duplicate(true)})
				serial += 1
			for key: String in ["start", "count", "dialogues"]:
				beat.erase(key)
		beats.append(beat)
	var metadata: Dictionary = manifest.duplicate(true)
	metadata.erase("beats")
	metadata.erase("authoring_project")
	metadata.erase("authoring_sha256")
	metadata["manifest_path"] = source
	var previous := _document
	_document = {"version": 1, "format": FORMAT, "next_step_id": serial,
		"manifest": metadata, "events": events, "beats": beats,
		"dialogues": dialogue.dialogues, "previews": {}}
	if compile().is_empty():
		_document = previous
		return ERR_INVALID_DATA
	path = destination
	dirty = true
	_undo.clear()
	_redo.clear()
	_remember_disk()
	return OK

func _fail(message: String) -> Error:
	last_error = message
	return ERR_INVALID_DATA

## Also used by CLI/tests: the same loaders validate manual and generated content.
func compile() -> Dictionary:
	last_error = ""
	if _document.get("format") != FORMAT or _document.get("version") != 1:
		_fail("不支持的剧情工程版本")
		return {}
	for key: String in ["manifest", "events", "dialogues", "previews"]:
		if not _document.get(key) is Dictionary:
			_fail("剧情工程缺少字典：" + key)
			return {}
	var serial: Variant = _document.get("next_step_id")
	if not _document.get("beats") is Array or typeof(serial) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(serial) or serial < 1 or floor(serial) != serial:
		_fail("剧情工程缺少 beats / next_step_id")
		return {}
	var metadata: Dictionary = _document.manifest
	for key: String in ["actors", "markers", "audio"]:
		if metadata.has(key) and not metadata[key] is Dictionary:
			_fail("绑定清单必须是字典：" + key)
			return {}
	for key: String in ["markers", "audio"]:
		if metadata.has(key) and not metadata[key].get("ids") is Array:
			_fail("绑定清单缺少 ids：" + key)
			return {}
		for id: Variant in metadata.get(key, {}).get("ids", []):
			if not id is String or id.is_empty():
				_fail("绑定 ID 必须是非空字符串：" + key)
				return {}
	for id: Variant in metadata.get("actors", {}):
		var scene: Variant = metadata.actors[id]
		if not id is String or id.is_empty() or not scene is String or not ResourceLoader.exists(scene, "PackedScene"):
			_fail("角色绑定或场景不存在：" + str(id))
			return {}
	for key: String in ["story", "dialogue", "scene", "manifest_path"]:
		if not metadata.get(key) is String or not str(metadata[key]).begins_with("res://") or ".." in str(metadata[key]):
			_fail("工程路径无效：" + key)
			return {}
	if metadata.has("phases") and (not metadata.phases is String or not metadata.phases.begins_with("res://src/resources/story/") or ".." in metadata.phases):
		_fail("phases 输出路径无效")
		return {}
	var story := {"version": 1, "events": _document.events.duplicate(true)}
	for id: Variant in story.events:
		if not story.events[id] is Dictionary or story.events[id].has("steps"):
			_fail("事件元数据不能包含 steps：" + str(id))
			return {}
		story.events[id]["steps"] = []
	var mapping: Array = []
	var beat_ids: Array = []
	var step_ids: Array = []
	var phases := {"version": 2, "phases": []}
	for beat: Variant in _document.beats:
		if not beat is Dictionary or not beat.get("id") is String or beat.id.is_empty() or beat.id in beat_ids:
			_fail("Beat ID 缺失或重复")
			return {}
		beat_ids.append(beat.id)
		if not beat.has("event"):
			if not beat.get("phase") is Dictionary:
				_fail("玩家 Beat 缺少 phase：" + beat.id)
				return {}
			mapping.append(beat.duplicate(true))
			phases.phases.append(beat.phase.duplicate(true))
			continue
		if not story.events.has(beat.event) or not beat.get("steps") is Array:
			_fail("Beat 事件或步骤无效：" + beat.id)
			return {}
		var steps: Array = story.events[beat.event].steps
		var row := {"id": beat.id, "mode": beat.get("mode", "自动演出"),
			"event": beat.event, "start": steps.size(), "count": beat.steps.size(), "dialogues": []}
		for entry: Variant in beat.steps:
			if not entry is Dictionary or not entry.get("id") is String or entry.id.is_empty() or entry.id in step_ids or not entry.get("data") is Dictionary:
				_fail("步骤 ID 缺失、重复或 data 无效：" + beat.id)
				return {}
			step_ids.append(entry.id)
			var step: Dictionary = entry.data
			if step.get("command") == "dialogue":
				if not _document.dialogues.has(step.get("id", "")):
					_fail("对白引用不存在：" + str(step.get("id")))
					return {}
				if step.id not in row.dialogues:
					row.dialogues.append(step.id)
			steps.append(step.duplicate(true))
		mapping.append(row)
	var library := StoryLibrary.new()
	var dialogues := {"version": 1, "dialogues": _document.dialogues.duplicate(true)}
	var dialogue_library := DialogueLibrary.new()
	if library.load_json(JSON.stringify(story)) != OK:
		_fail(library.last_error)
		return {}
	if dialogue_library.load_json(JSON.stringify(dialogues)) != OK:
		_fail(dialogue_library.last_error)
		return {}
	if not _validate_references(story, metadata):
		return {}
	if not phases.phases.is_empty() and (not metadata.get("phases") is String or not str(metadata.phases).begins_with("res://src/resources/story/") or ".." in str(metadata.phases)):
		_fail("玩家 Beat 需要合法的 phases 输出路径")
		return {}
	if not _validate_phases(phases, story.events):
		return {}
	var manifest := metadata.duplicate(true)
	manifest.erase("manifest_path")
	manifest["beats"] = mapping
	manifest["authoring_project"] = path
	return {"story": story, "dialogue": dialogues, "manifest": manifest, "phases": phases}

func _validate_phases(catalog: Dictionary, events: Dictionary) -> bool:
	var used: Dictionary = {}
	for phase: Dictionary in catalog.phases:
		if phase.size() != 6 or not phase.has_all(["id", "after_event", "stage", "completion", "completion_flag", "next_event"]):
			_fail("工程玩家 Beat 仅支持 Bridge v2 的六字段 phase")
			return false
		for key: String in ["id", "stage", "after_event", "completion_flag", "next_event"]:
			if not phase[key] is String or phase[key].is_empty() or (key != "stage" and not StoryLibrary.is_namespaced(phase[key])) or used.has(key + ":" + str(phase[key])):
				_fail("Phase 字段无效或重复：" + key)
				return false
			used[key + ":" + phase[key]] = true
		var condition: Variant = phase.completion
		if not condition is Dictionary or condition.size() != 2 or not condition.has_all(["flag", "allow_existing"]) or not StoryLibrary.is_namespaced(condition.flag) or not condition.allow_existing is bool or condition.flag == phase.completion_flag:
			_fail("Phase completion 必须声明独立 flag 与 allow_existing")
			return false
		if not events.has(phase.after_event) or not events.has(phase.next_event) or phase.after_event == phase.next_event:
			_fail("Phase 前后事件无效：" + phase.id)
			return false
	return true

func _validate_references(story: Dictionary, metadata: Dictionary) -> bool:
	for id: String in story.events:
		var actors: Array = metadata.get("actors", {}).keys()
		for step: Dictionary in story.events[id].steps:
			if step.command == "actor_spawn":
				actors.append(step.actor)
			elif step.has("actor") and not actors.is_empty() and step.actor not in actors:
				_fail("%s 引用了未声明角色：%s" % [id, step.actor])
				return false
			if step.get("target") is String and metadata.has("markers") and step.target not in metadata.markers.ids:
				_fail("%s 引用了未声明 Marker：%s" % [id, step.target])
				return false
			if step.command in ["play_bgm", "play_sfx"] and step.has("id") and metadata.has("audio") and step.id not in metadata.audio.ids:
				_fail("%s 引用了未声明音频：%s" % [id, step.id])
				return false
	for id: Variant in _document.previews:
		var fixture: Variant = _document.previews[id]
		if not story.events.has(id) or not fixture is Dictionary or not fixture.get("actors", {}) is Dictionary or not fixture.get("flags", {}) is Dictionary:
			_fail("预览现场格式无效：" + str(id))
			return false
		for placement: Variant in fixture.get("actors", {}).values():
			if not placement is Dictionary or not placement.get("marker") is String or not placement.get("visible", true) is bool:
				_fail("预览角色需要 marker 和可选 visible：" + str(id))
				return false
			if metadata.has("markers") and placement.marker not in metadata.markers.ids:
				_fail("预览 Marker 未声明：" + placement.marker)
				return false
		for flag: Variant in fixture.get("flags", {}):
			if not StoryLibrary.is_namespaced(flag) or not fixture.flags[flag] is bool:
				_fail("预览 flag 需要命名空间 ID 与 bool 值")
				return false
	return true

func replace_document(candidate: Dictionary) -> Error:
	var previous := _document
	_document = candidate.duplicate(true)
	if compile().is_empty():
		_document = previous
		return ERR_INVALID_DATA
	_undo.append(previous.duplicate(true))
	if _undo.size() > 50:
		_undo.pop_front()
	_redo.clear()
	dirty = true
	return OK

func undo() -> bool:
	if _undo.is_empty():
		return false
	_redo.append(_document)
	_document = _undo.pop_back()
	dirty = true
	return true

func redo() -> bool:
	if _redo.is_empty():
		return false
	_undo.append(_document)
	_document = _redo.pop_back()
	dirty = true
	return true

func set_step(beat_id: String, index: int, data: Dictionary) -> Error:
	var candidate := snapshot()
	for beat: Dictionary in candidate.beats:
		if beat.id == beat_id and beat.has("steps") and index >= 0 and index < beat.steps.size():
			beat.steps[index].data = data.duplicate(true)
			return replace_document(candidate)
	return _fail("没有选中有效步骤")

func insert_step(beat_id: String, index: int, data: Dictionary) -> Error:
	var candidate := snapshot()
	for beat: Dictionary in candidate.beats:
		if beat.id == beat_id and beat.has("steps"):
			var used: Array[String] = []
			for other: Dictionary in candidate.beats:
				for entry: Dictionary in other.get("steps", []):
					used.append(entry.id)
			var id := "step_%04d" % int(candidate.next_step_id)
			while id in used:
				candidate.next_step_id = int(candidate.next_step_id) + 1
				id = "step_%04d" % int(candidate.next_step_id)
			candidate.next_step_id = int(candidate.next_step_id) + 1
			beat.steps.insert(clampi(index, 0, beat.steps.size()), {"id": id, "data": data.duplicate(true)})
			return replace_document(candidate)
	return _fail("玩家操作 Beat 使用真实玩法 phase，不包含演出步骤")

func move_step(beat_id: String, index: int, offset: int) -> Error:
	var candidate := snapshot()
	for beat: Dictionary in candidate.beats:
		if beat.id == beat_id and beat.has("steps") and index >= 0 and index < beat.steps.size() and index + offset >= 0 and index + offset < beat.steps.size():
			var entry: Dictionary = beat.steps.pop_at(index)
			beat.steps.insert(index + offset, entry)
			return replace_document(candidate)
	return _fail("步骤已到边界")

func remove_step(beat_id: String, index: int) -> Error:
	var candidate := snapshot()
	for beat: Dictionary in candidate.beats:
		if beat.id == beat_id and beat.has("steps") and index >= 0 and index < beat.steps.size():
			beat.steps.remove_at(index)
			return replace_document(candidate)
	return _fail("没有选中有效步骤")

func _output_paths() -> Array[String]:
	var meta: Dictionary = _document.manifest
	var paths: Array[String] = [path, meta.story, meta.dialogue, meta.manifest_path]
	if meta.has("phases"):
		paths.append(meta.phases)
	return paths

func _remember_disk() -> void:
	_disk_hashes.clear()
	for file: String in _output_paths():
		_disk_hashes[file] = FileAccess.get_sha256(file) if FileAccess.file_exists(file) else ""

## Stage all files before replacing any; reject stale editor sessions, retain a
## recoverable backup and roll back earlier replacements if a later one fails.
func save() -> Error:
	if not DebugRuntime.is_enabled() or not OS.has_feature("editor"):
		return _fail("仅在 Godot 开发环境中保存工程")
	if not path.begins_with("res://docs/story_authoring/") or ".." in path:
		return _fail("工程必须保存在 docs/story_authoring 下")
	var compiled := compile()
	if compiled.is_empty():
		return ERR_INVALID_DATA
	var meta: Dictionary = _document.manifest
	if not str(meta.story).begins_with("res://src/resources/story/") or not str(meta.dialogue).begins_with("res://src/resources/dialogue/") or not str(meta.manifest_path).begins_with("res://docs/story_authoring/"):
		return _fail("输出必须位于对应的剧情、对白和编排目录")
	var contents := {}
	contents[path] = JSON.stringify(_document, "\t", false) + "\n"
	compiled.manifest.authoring_sha256 = str(contents[path]).sha256_text()
	contents[meta.story] = _runtime_text(compiled.story, meta.story)
	contents[meta.dialogue] = _runtime_text(compiled.dialogue, meta.dialogue)
	var ordered: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta.manifest_path)) if FileAccess.file_exists(meta.manifest_path) else {}
	if not ordered is Dictionary:
		ordered = {}
	for key: String in ordered.keys():
		if not compiled.manifest.has(key):
			ordered.erase(key)
	ordered.merge(compiled.manifest, true)
	contents[meta.manifest_path] = JSON.stringify(_integer_numbers(ordered), "  ", false) + "\n"
	if meta.has("phases"):
		contents[meta.phases] = _runtime_text(compiled.phases, meta.phases)
	if contents.size() != _output_paths().size():
		return _fail("工程和输出路径不能相同")
	var lock := path + ".story_editor_lock"
	if DirAccess.make_dir_absolute(lock) != OK:
		return _fail("工程正被保存或上次保存被中断，请检查锁目录：" + lock)
	var result := _save_outputs(contents)
	DirAccess.remove_absolute(lock)
	if result == OK:
		dirty = false
		_remember_disk()
	return result

func _save_outputs(contents: Dictionary) -> Error:
	for file: String in contents:
		var current := FileAccess.get_sha256(file) if FileAccess.file_exists(file) else ""
		if not _disk_hashes.has(file) or current != _disk_hashes[file]:
			return _fail("文件已被外部修改，请先保留草稿并重新打开：" + file)
	var staged: Array[String] = []
	for file: String in contents:
		var temp := file + ".story_editor_tmp"
		var handle := FileAccess.open(temp, FileAccess.WRITE)
		if handle == null:
			_clean_temps(staged)
			return _fail("无法写入：" + file)
		handle.store_string(contents[file])
		handle.flush()
		var error := handle.get_error()
		handle.close()
		staged.append(file)
		if error != OK:
			_clean_temps(staged)
			return _fail("写入失败：" + file)
	var replaced: Array[String] = []
	for file: String in staged:
		var backup := file + ".story_editor_backup"
		if FileAccess.file_exists(backup):
			_rollback(replaced)
			_clean_temps(staged)
			return _fail("发现上次保存的备份，请先恢复或移走：" + backup)
		var existed := FileAccess.file_exists(file)
		if existed and DirAccess.rename_absolute(file, backup) != OK:
			_rollback(replaced)
			_clean_temps(staged)
			return _fail("不能备份：" + file)
		if DirAccess.rename_absolute(file + ".story_editor_tmp", file) != OK:
			if existed:
				DirAccess.rename_absolute(backup, file)
			_rollback(replaced)
			_clean_temps(staged)
			return _fail("不能替换：" + file)
		replaced.append(file)
	for file: String in replaced:
		if FileAccess.file_exists(file + ".story_editor_backup"):
			DirAccess.remove_absolute(file + ".story_editor_backup")
	return OK

func _runtime_text(data: Dictionary, file: String) -> String:
	var original := FileAccess.get_file_as_string(file) if FileAccess.file_exists(file) else ""
	# JSON numbers parse as floats; normalize both sides before comparing.
	if not original.is_empty() and JSON.parse_string(original) == JSON.parse_string(JSON.stringify(data)):
		return original
	return JSON.stringify(data, "  ", false) + "\n"

func _integer_numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: String in value:
			result[key] = _integer_numbers(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_integer_numbers(item))
		return result
	if value is float and is_finite(value) and abs(value) < 9007199254740992 and floor(value) == value:
		return int(value)
	return value

func _clean_temps(files: Array[String]) -> void:
	for file: String in files:
		DirAccess.remove_absolute(file + ".story_editor_tmp")

func _rollback(files: Array[String]) -> void:
	for file: String in files:
		DirAccess.remove_absolute(file)
		if FileAccess.file_exists(file + ".story_editor_backup"):
			DirAccess.rename_absolute(file + ".story_editor_backup", file)
