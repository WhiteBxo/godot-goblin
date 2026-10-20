extends Node
## F6: compare NPC facing changes in the actual dialogue view.

const EXAMPLES := [
	["守卫", "res://assets/characters/dialogue/guard_portrait.png", false],
	["赌场侍卫", "res://assets/characters/npc/casino_sentry/portrait.png", false],
	["哥布林母亲", "res://assets/characters/npc/market_mother/portrait.png", false],
	["哥布林小孩", "res://assets/characters/npc/goblin_girl/portrait.png", false],
	["主角", "res://assets/characters/apron_man/player_talking_portrait.png", true],
	["同伴", "res://assets/characters/npc/prayer_woman/portrait.png", false],
	["胖哥布林", "res://assets/characters/fat_goblin/fat_goblin_smiling_portrait.png", false],
]
var _view: DialogueUI
var _right_facing: Array[Texture2D] = []
var _index := 0
var _before := false
var _status: Label
var _compare: Button

func _ready() -> void:
	if not OS.has_feature("debug"):
		return
	RenderingServer.set_default_clear_color(Color("343c46"))
	var layer := CanvasLayer.new()
	add_child(layer)
	_view = preload("res://src/UI/dialogue/dialogue_ui.tscn").instantiate()
	layer.add_child(_view)
	_right_facing.assign(_view.right_facing_portraits)
	_view.advance_requested.connect(_next)
	var controls := HBoxContainer.new()
	controls.position = Vector2(16, 12)
	controls.theme = preload("res://src/resources/ui/game_theme.tres")
	layer.add_child(controls)
	_status = Label.new()
	controls.add_child(_status)
	var next := Button.new()
	next.text = "下一个角色"
	next.pressed.connect(_next)
	controls.add_child(next)
	_compare = Button.new()
	_compare.pressed.connect(func() -> void:
		_before = not _before
		_show_example()
	)
	controls.add_child(_compare)
	_show_example()
	if "--capture" in OS.get_cmdline_user_args():
		_capture.call_deferred()

func _next() -> void:
	_index = (_index + 1) % EXAMPLES.size()
	_show_example()

func _show_example() -> void:
	var example: Array = EXAMPLES[_index]
	_view.right_facing_portraits.assign([] if _before else _right_facing)
	_view.present_line(example[0], "对话立绘朝向预览", load(example[1]), [], example[2])
	_view.reveal_all()
	_status.text = "%s · %s" % [example[0], "调整前" if _before else "调整后"]
	_compare.text = "查看调整后" if _before else "查看调整前"

func _capture() -> void:
	DirAccess.make_dir_recursive_absolute("res://.godot/portrait_facing")
	for index in EXAMPLES.size():
		_index = index
		for before: bool in [true, false]:
			_before = before
			_show_example()
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path := "res://.godot/portrait_facing/%d_%s.png" % [index, "before" if before else "after"]
			if get_viewport().get_texture().get_image().save_png(path) != OK:
				get_tree().quit(1)
				return
	print("PORTRAIT_FACING: captured seven characters before/after")
	get_tree().quit()
