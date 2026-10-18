class_name SaveCoordinator
extends Node
## Scene-local scheduler. Signal callbacks only mark dirty; commits happen idle.

signal status_changed(text: String)

var _state: Node
var _store: SaveStore
var _checkpoint: Callable
var _safe: Callable
var _finish_startup: Callable
var _initializing := false
var _new_game := false
var _dirty := true
var _quiet_frames := 0
var _startup_frames := 0
var _signature := PackedByteArray()
var _status := ""
var _retry_at := 0

func configure(state: Node, store: SaveStore, checkpoint: Callable, safe: Callable, finish_startup: Callable = Callable(), new_game: bool = false) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_state = state
	_store = store
	_checkpoint = checkpoint
	_safe = safe
	_finish_startup = finish_startup
	_initializing = finish_startup.is_valid()
	_new_game = new_game
	_state.state_changed.connect(_mark_dirty)
	_status = _saved_text(GameEntry.get_last_saved_at())

func get_status_text() -> String:
	return _status

func _mark_dirty() -> void:
	_dirty = true
	_quiet_frames = 0

func _process(_delta: float) -> void:
	if get_tree().paused or not is_instance_valid(_state) or not _state.can_take_snapshot():
		return
	if _initializing:
		_startup_frames += 1
		if _startup_frames > 180:
			_initializing = false
			_finish_startup.call(ERR_UNCONFIGURED)
			set_process(false)
			return
	elif not _dirty or not GameEntry.is_save_session_active():
		return
	if not _safe.call():
		_quiet_frames = 0
		return
	_quiet_frames += 1
	if _quiet_frames < 2 or Time.get_ticks_msec() < _retry_at:
		return
	var checkpoint: Dictionary = _checkpoint.call()
	if checkpoint.is_empty():
		return
	var snapshot: Dictionary = _state.to_dict()
	var signature := var_to_bytes([checkpoint.id, snapshot])
	if _initializing and not _new_game:
		# Loading must not rotate the backup or write before the scene is rebuilt.
		_signature = signature
		_dirty = false
		_initializing = false
		_finish_startup.call(OK)
		return
	if signature == _signature:
		_dirty = false
		return
	var saved_at := int(Time.get_unix_time_from_system())
	var error := _store.save(snapshot, checkpoint.id, saved_at)
	if error == OK:
		_signature = signature
		_dirty = false
		GameEntry.record_saved_at(saved_at)
		_set_status(_saved_text(saved_at))
	else:
		_retry_at = Time.get_ticks_msec() + 5000
		_set_status("自动保存失败，原存档已保留。")
		push_warning("Autosave: %s (%s)" % [_store.last_error, error_string(error)])
	if _initializing:
		_initializing = false
		_finish_startup.call(OK)

func _set_status(text: String) -> void:
	if _status == text:
		return
	_status = text
	status_changed.emit(text)

func _saved_text(timestamp: int) -> String:
	if timestamp <= 0:
		return "尚未自动保存；将在安全检查点保存。"
	# Unix save times are UTC; format in the player's local timezone.
	var local_time := timestamp + int(Time.get_time_zone_from_system().bias) * 60
	var date := Time.get_datetime_dict_from_unix_time(local_time)
	return "最近保存 %02d-%02d %02d:%02d · 安全检查点" % [date.month, date.day, date.hour, date.minute]

func _exit_tree() -> void:
	if is_instance_valid(_state) and _state.state_changed.is_connected(_mark_dirty):
		_state.state_changed.disconnect(_mark_dirty)
