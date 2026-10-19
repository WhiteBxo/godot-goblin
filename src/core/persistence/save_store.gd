class_name SaveStore
extends RefCounted
## One complete Variant document. No live state, signals, scene navigation or UI.

const StateData = preload("res://src/core/game_state.gd")
const DEFAULT_DIRECTORY := "user://saves"
const FORMAT_VERSION := 2
const MAGIC := "GOBLIN_SAVE\n"
const MAX_FILE_BYTES := 16 * 1024 * 1024
var directory: String
var checkpoints: SaveCheckpoints
var last_error := ""
static var _last_order := 0

func _init(path: String = DEFAULT_DIRECTORY, catalog: SaveCheckpoints = null) -> void:
	directory = path
	checkpoints = catalog if catalog != null else SaveCheckpoints.new()

func has_files() -> bool:
	return FileAccess.file_exists(_path("autosave.dat")) or FileAccess.file_exists(_path("autosave.bak"))

func save(snapshot: Dictionary, checkpoint_id: String, saved_at: int = -1, saved_order: int = -1) -> Error:
	if saved_order < 0:
		_last_order = maxi(_last_order + 1, int(Time.get_unix_time_from_system() * 1000000.0))
		saved_order = _last_order
	var document := {"format_version": FORMAT_VERSION, "game_state": snapshot.duplicate(true),
		"checkpoint_id": checkpoint_id, "saved_at": int(Time.get_unix_time_from_system()) if saved_at < 0 else saved_at, "saved_order": saved_order}
	if validate_document(document) != OK:
		return _fail(ERR_INVALID_DATA, "当前阶段没有可用的完整存档检查点。")
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		return _fail(error, "无法创建存档目录。")
	var temporary := _path("autosave.tmp")
	error = _write_file(temporary, document)
	if error != OK or _read_file(temporary).error != OK:
		return _fail(error if error != OK else ERR_FILE_CORRUPT, "存档写入或回读校验失败，原有进度已保留。")
	# A corrupt primary must never displace the last valid backup.
	if _read_file(_path("autosave.dat")).error == OK:
		var backup_temporary := _path("autosave.bak.tmp")
		error = DirAccess.copy_absolute(_path("autosave.dat"), backup_temporary)
		if error == OK and _read_file(backup_temporary).error != OK:
			error = ERR_FILE_CORRUPT
		if error == OK:
			error = _rename_file(backup_temporary, _path("autosave.bak"))
		if error != OK:
			return _fail(error, "无法更新存档备份，原有进度已保留。")
	error = _rename_file(temporary, _path("autosave.dat"))
	if error != OK:
		return _fail(error, "无法替换存档，原有进度已保留。")
	last_error = ""
	return OK

func load_save(preflight: Callable = Callable()) -> Dictionary:
	var primary := _read_file(_path("autosave.dat"))
	if primary.error == OK and preflight.is_valid():
		primary.error = preflight.call(primary.data)
	if primary.error == OK:
		last_error = ""
		return primary
	var backup := _read_file(_path("autosave.bak"))
	if backup.error == OK and preflight.is_valid():
		backup.error = preflight.call(backup.data)
	if backup.error == OK:
		backup.used_backup = true
		last_error = "正式存档不可用，已读取上一份有效备份。"
		return backup
	last_error = "存档无法读取或与当前版本不兼容。" if has_files() else "尚无可继续的存档。"
	return {"error": primary.error if has_files() else ERR_FILE_NOT_FOUND, "data": {}, "used_backup": false}

func validate_document(value: Variant) -> Error:
	if not value is Dictionary or not value.has_all(["format_version", "game_state", "checkpoint_id", "saved_at"]):
		return ERR_INVALID_DATA
	if not value.format_version is int or value.format_version not in [1, FORMAT_VERSION] or not value.game_state is Dictionary or not value.checkpoint_id is String or not value.saved_at is int or value.saved_at < 0:
		return ERR_INVALID_DATA
	if value.format_version == 1 and value.size() != 4:
		return ERR_INVALID_DATA
	if value.format_version == FORMAT_VERSION and (value.size() != 5 or not value.get("saved_order") is int or value.saved_order < 0):
		return ERR_INVALID_DATA
	var candidate := StateData.new()
	var error: Error = candidate.validate_snapshot(value.game_state)
	candidate.free()
	if error != OK:
		return error
	return checkpoints.validate_checkpoint(value.checkpoint_id, value.game_state)

func _write_file(path: String, document: Dictionary) -> Error:
	var payload := var_to_bytes(document)
	if payload.size() > MAX_FILE_BYTES - MAGIC.length() - 32:
		return ERR_OUT_OF_MEMORY
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var written := file.store_buffer(MAGIC.to_ascii_buffer()) and file.store_buffer(_digest(payload)) and file.store_buffer(payload)
	file.flush()
	var error := file.get_error()
	file.close()
	return error if written else ERR_FILE_CANT_WRITE

func _read_file(path: String) -> Dictionary:
	var result := {"error": ERR_FILE_CORRUPT, "data": {}, "used_backup": false}
	if not FileAccess.file_exists(path):
		result.error = ERR_FILE_NOT_FOUND
		return result
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		result.error = FileAccess.get_open_error()
		return result
	var length := file.get_length()
	var header := MAGIC.to_ascii_buffer()
	if length <= header.size() + 32 or length > MAX_FILE_BYTES or file.get_buffer(header.size()) != header:
		file.close()
		return result
	var digest := file.get_buffer(32)
	var payload := file.get_buffer(length - header.size() - 32)
	file.close()
	if _digest(payload) != digest:
		return result
	# bytes_to_var excludes objects; never use bytes_to_var_with_objects here.
	var document: Variant = bytes_to_var(payload)
	result.error = validate_document(document)
	if result.error == OK:
		result.data = document
	return result

func _digest(bytes: PackedByteArray) -> PackedByteArray:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish()

func _rename_file(from: String, to: String) -> Error:
	return DirAccess.rename_absolute(from, to)

func _path(filename: String) -> String:
	return directory.path_join(filename)

func _fail(error: Error, message: String) -> Error:
	last_error = message
	return error
