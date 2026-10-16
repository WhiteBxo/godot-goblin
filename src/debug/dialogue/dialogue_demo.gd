extends Node
## Standalone host: no MainGame, shop interaction, or GameState dependency.

@onready var _manager: DialogueManager = $Systems/DialogueManager
@onready var _ui: DialogueUI = $PopupLayer/DialogueUI
@onready var _player: PlayerController = $World/Player
@onready var _menu: VBoxContainer = $HudLayer/Screen/Menu
@onready var _status: Label = $HudLayer/Screen/Status
var _selection: String = "尚未选择"


func _ready() -> void:
	DebugRuntime.apply_release_policy(get_tree())
	_manager.configure(_ui)
	_manager.dialogue_started.connect(_on_started)
	_manager.dialogue_ended.connect(_on_ended)
	_manager.choice_selected.connect(_on_choice)
	$HudLayer/Screen/Menu/Greeting.pressed.connect(func() -> void: _manager.start_dialogue("demo.greeting"))
	$HudLayer/Screen/Menu/Branching.pressed.connect(func() -> void: _manager.start_dialogue("demo.first_shift"))
	$HudLayer/Screen/Menu/Portraits.pressed.connect(func() -> void: _manager.start_dialogue("demo.speaker_portraits"))
	_manager.start_dialogue("demo.first_shift")


func _process(_delta: float) -> void:
	_player.position = _player.position.clamp(Vector2(380, 110), Vector2(590, 260))


func _on_started(_id: String) -> void:
	_player.set_movement_enabled(false)
	_menu.hide()


func _on_ended(id: String, cancelled: bool) -> void:
	_player.set_movement_enabled(true)
	_menu.show()
	_status.text = "%s · %s\n选项结果：%s" % [id, "已中止" if cancelled else "已完成", _selection]
	$HudLayer/Screen/Menu/Greeting.grab_focus()


func _on_choice(_id: String, _line: String, choice: String) -> void:
	_selection = choice
