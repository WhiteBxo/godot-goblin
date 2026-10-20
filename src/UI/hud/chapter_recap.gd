extends UIScreen
## Read-only chapter results. The scene service handles acknowledgement.
signal dismissed

var _manager: UIManager
var _id: StringName

func _ready() -> void:
	$ModalShell.close_requested.connect(func() -> void: close_requested.emit())
	close_requested.connect(func() -> void: _manager.close_screen(_id))
	$ModalShell.get_close_button().text = "结束本版"

func bind_ui(manager: UIManager, id: StringName) -> void:
	_manager = manager
	_id = id

func present(summary: String) -> void:
	var content: Control = $ModalShell.get_content()
	var summary_label: Control = content.get_node("Summary")
	summary_label.text = _markup(summary)
	# The tally arrives a beat after the shell, so the chapter closes on the
	# result landing rather than on a page that was already complete.
	UIFlourish.reveal(summary_label, 0.98)

## 分节标题取强调色，未解之谜收成次要色：一段结算读起来像报表而不是流水。
func _markup(summary: String) -> String:
	var lines := PackedStringArray()
	var muted := false
	for line: String in summary.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.is_empty():
			lines.append("")
			continue
		if trimmed in ChapterGameplay.RECAP_SECTIONS:
			muted = trimmed == "未解之谜"
			lines.append(_paint(trimmed, UITokens.ACCENT))
			continue
		lines.append(_paint(line, UITokens.TEXT_MUTED if muted else UITokens.TEXT))
	return "\n".join(lines)

func _paint(text: String, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), text.replace("[", "[lb]")]

func get_default_focus() -> Control:
	return $ModalShell.get_close_button()

func uses_native_gui_input() -> bool:
	return true

func on_ui_closed() -> void:
	dismissed.emit()
