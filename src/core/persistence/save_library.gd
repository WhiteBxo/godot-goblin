class_name SaveLibrary
extends RefCounted
## Fixed slots; no separate index that can disagree with the save documents.

const AUTOMATIC_IDS := ["auto", "auto_2", "auto_3"]
const MANUAL_IDS := ["manual_1", "manual_2", "manual_3", "manual_4", "manual_5", "manual_6"]
var directory: String

func _init(path: String = SaveStore.DEFAULT_DIRECTORY) -> void:
	directory = path

func get_store(id: String, catalog: SaveCheckpoints = null) -> SaveStore:
	if id == "auto":
		return SaveStore.new(directory, catalog) # Preserve the original autosave and its backup.
	if id in AUTOMATIC_IDS or id in MANUAL_IDS:
		return SaveStore.new(directory.path_join(id), catalog)
	return null

func get_entries(preflight: Callable = Callable()) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for id: String in AUTOMATIC_IDS + MANUAL_IDS:
		var store := get_store(id)
		var loaded := store.load_save(preflight)
		var entry := {"id": id, "manual": id in MANUAL_IDS, "occupied": store.has_files(),
			"valid": loaded.error == OK, "used_backup": loaded.used_backup,
			"label": "手动存档 %d" % (MANUAL_IDS.find(id) + 1) if id in MANUAL_IDS else "自动存档 %d" % (AUTOMATIC_IDS.find(id) + 1),
			"saved_at": 0, "saved_order": 0, "day": 0, "phase": "", "scene": "", "stage": ""}
		if entry.valid:
			var document: Dictionary = loaded.data
			var checkpoint := store.checkpoints.get_checkpoint(document.checkpoint_id)
			entry.saved_at = document.saved_at
			entry.saved_order = document.get("saved_order", 0)
			entry.day = document.game_state.current_day
			entry.phase = document.game_state.variables.get("world.phase", "day")
			entry.scene = checkpoint.scene
			entry.stage = document.game_state.story_stage
		entries.append(entry)
	return entries

func newest_valid_id(preflight: Callable = Callable()) -> String:
	var newest := ""
	var timestamp := -1
	var order := -1
	for entry in get_entries(preflight):
		if entry.valid and (entry.saved_at > timestamp or (entry.saved_at == timestamp and entry.saved_order > order)):
			newest = entry.id
			timestamp = entry.saved_at
			order = entry.saved_order
	return newest

func has_files() -> bool:
	for id: String in AUTOMATIC_IDS + MANUAL_IDS:
		if get_store(id).has_files():
			return true
	return false

func save_manual(id: String, snapshot: Dictionary, checkpoint_id: String, overwrite: bool = false, saved_at: int = -1) -> Error:
	if id not in MANUAL_IDS:
		return ERR_INVALID_PARAMETER
	var store := get_store(id)
	if store.has_files() and not overwrite:
		return ERR_ALREADY_EXISTS
	return store.save(snapshot, checkpoint_id, saved_at)

## Archive only validated documents. An archival failure leaves the primary intact.
func save_automatic(store: SaveStore, snapshot: Dictionary, checkpoint_id: String, saved_at: int) -> Error:
	if store.validate_document({"format_version": SaveStore.FORMAT_VERSION, "game_state": snapshot, "checkpoint_id": checkpoint_id, "saved_at": saved_at, "saved_order": 0}) != OK:
		store.last_error = "当前阶段没有可用的完整存档检查点。"
		return ERR_INVALID_DATA
	var previous := store.load_save()
	if previous.error == OK:
		var second := get_store("auto_2", store.checkpoints).load_save()
		if second.error == OK:
			var error := _copy_document(second.data, get_store("auto_3", store.checkpoints))
			if error != OK:
				store.last_error = "无法保留自动存档历史，原有进度已保留。"
				return error
		var error := _copy_document(previous.data, get_store("auto_2", store.checkpoints))
		if error != OK:
			store.last_error = "无法保留自动存档历史，原有进度已保留。"
			return error
	return store.save(snapshot, checkpoint_id, saved_at)

func _copy_document(document: Dictionary, target: SaveStore) -> Error:
	return target.save(document.game_state, document.checkpoint_id, document.saved_at, document.get("saved_order", 0))
