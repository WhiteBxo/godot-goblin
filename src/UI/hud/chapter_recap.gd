extends UIScreen
## Read-only chapter results. The scene service handles acknowledgement.
signal dismissed

var _manager: UIManager
var _id: StringName

func _ready() -> void:
	$ModalShell.close_requested.connect(func() -> void: close_requested.emit())
	close_requested.connect(func() -> void: _manager.close_screen(_id))
	$ModalShell.get_close_button().text = "继续 · 委托交接"

func bind_ui(manager: UIManager, id: StringName) -> void:
	_manager = manager
	_id = id

func present(summary: String) -> void:
	var content: Control = $ModalShell.get_content()
	var summary_label: Control = content.get_node("Summary")
	summary_label.text = summary
	# The tally arrives a beat after the shell, so the chapter closes on the
	# result landing rather than on a page that was already complete.
	UIFlourish.reveal(summary_label, 0.98)

func get_default_focus() -> Control:
	return $ModalShell.get_close_button()

func uses_native_gui_input() -> bool:
	return true

func on_ui_closed() -> void:
	dismissed.emit()
