@tool
extends TileMapLayer

signal cells_changed

# changed does not cover scripted set_cell/erase_cell in this engine.
# The batched hook also covers brushes, UndoRedo and editor tools.
func _update_cells(coords: Array[Vector2i], _forced_cleanup: bool) -> void:
	if Engine.is_editor_hint() and not coords.is_empty():
		cells_changed.emit()
