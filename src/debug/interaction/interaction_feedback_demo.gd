extends Node
## F6 host for real Area2D, ShopInteraction, ShopUI, DialogueManager and StoryDirector.

var player: ShopPlayer
var points: Array[InteractionPoint] = []
var interaction: ShopInteraction
var feedback: InteractionFeedback
var ui: ShopUI
var audio: AudioManager
var dialogue: DialogueManager
var story: StoryDirector
var _world: Node2D
var _menu: HBoxContainer
var _status: Label
var _manual_disabled := false

func _ready() -> void:
	DebugRuntime.apply_release_policy(get_tree())
	var systems := Node.new()
	systems.name = "Systems"
	systems.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(systems)
	_world = Node2D.new()
	_world.name = "World"
	_world.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(_world)
	var floor_art := Polygon2D.new()
	floor_art.polygon = PackedVector2Array([Vector2(40, 100), Vector2(600, 100), Vector2(600, 300), Vector2(40, 300)])
	floor_art.color = Color("302a32")
	_world.add_child(floor_art)
	player = preload("res://src/gameplay/player/shop_player.tscn").instantiate()
	_world.add_child(player)
	player.camera.enabled = false
	player.scale = Vector2(0.5, 0.5)
	player.speed = 110.0
	player.position = Vector2(320, 245)
	var hud := _layer("HudLayer", 10)
	var popup := _layer("PopupLayer", 20)
	ui = preload("res://src/UI/milk_tea/shop_ui.tscn").instantiate()
	hud.add_child(ui)
	ui.set_popup_layer(popup)
	ui.get_node("Header").hide()
	_reset_points()
	interaction = ShopInteraction.new()
	systems.add_child(interaction)
	interaction.configure(player, ui, points)
	audio = preload("res://src/core/audio/audio_manager.tscn").instantiate()
	systems.add_child(audio)
	AudioDemoTones.populate(audio)
	feedback = InteractionFeedback.new()
	_world.add_child(feedback)
	feedback.configure(interaction, audio)
	var dialogue_ui: DialogueUI = preload("res://src/UI/dialogue/dialogue_ui.tscn").instantiate()
	popup.add_child(dialogue_ui)
	dialogue = DialogueManager.new()
	systems.add_child(dialogue)
	dialogue.configure(dialogue_ui, func() -> bool: return not ui.is_open())
	dialogue.dialogue_started.connect(func(_id: String) -> void: _sync_lock())
	dialogue.dialogue_ended.connect(func(_id: String, _cancelled: bool) -> void: _sync_lock())
	story = StoryDirector.new()
	story.event_file = "res://src/debug/interaction/demo_story.json"
	systems.add_child(story)
	story.configure(dialogue, func() -> bool: return not ui.is_open())
	story.event_started.connect(func(_id: String) -> void: _sync_lock())
	story.event_finished.connect(func(_id: String, _ok: bool, _reason: String) -> void: _sync_lock())
	_menu = HBoxContainer.new()
	_menu.position = Vector2(12, 12)
	_menu.theme = Theme.new()
	_menu.theme.default_font = preload("res://assets/fonts/fusion_pixel/fusion-pixel-12px-monospaced-zh_hans.otf.woff2")
	_menu.theme.default_font_size = 12
	hud.add_child(_menu)
	_button("暂停", func() -> void: get_tree().paused = not get_tree().paused)
	_button("禁用", func() -> void:
		_manual_disabled = not _manual_disabled
		_sync_lock())
	_button("对白", func() -> void: dialogue.start_dialogue("demo.greeting"))
	_button("演出", func() -> void: story.request_event("feedback.wait"))
	_button("取消", func() -> void:
		story.cancel_event()
		dialogue.end_dialogue(true)
		ui.close())
	_button("删目标", func() -> void:
		if is_instance_valid(interaction.get_target()):
			interaction.get_target().queue_free())
	_button("重置", _reset_points)
	_status = Label.new()
	_status.position = Vector2(16, 55)
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status.add_theme_font_override("font", preload("res://assets/fonts/fusion_pixel/fusion-pixel-12px-monospaced-zh_hans.otf.woff2"))
	_status.add_theme_font_size_override("font_size", 12)
	hud.add_child(_status)

func _layer(layer_name: String, index: int) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = layer_name
	layer.layer = index
	layer.follow_viewport_enabled = false
	add_child(layer)
	return layer

func _button(text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	_menu.add_child(button)

func _reset_points() -> void:
	for point in points:
		if is_instance_valid(point):
			point.free()
	points.clear()
	for index in range(3):
		var point: InteractionPoint = preload("res://src/gameplay/interaction/interaction_point.tscn").instantiate()
		point.display_name = ["订单板", "仓库", "制作台"][index]
		point.interaction_id = [&"orders", &"storage", &"craft"][index]
		point.description = "复用原有弹窗。Esc 返回；没有新增玩法。"
		point.position = Vector2(230 + index * 90, 185)
		point.success_sound = "demo.ui"
		_world.add_child(point)
		point.get_node("Label").add_theme_font_override("font", preload("res://assets/fonts/fusion_pixel/fusion-pixel-12px-monospaced-zh_hans.otf.woff2"))
		point.get_node("Label").add_theme_font_size_override("font_size", 12)
		point.get_node("Label").position.y = -38
		points.append(point)
	if is_instance_valid(interaction):
		interaction.configure(player, ui, points)

func _sync_lock() -> void:
	var locked := _manual_disabled or dialogue.is_active() or story.is_busy()
	interaction.set_input_enabled(not locked)
	player.set_movement_enabled(not locked and not ui.is_open())

func _process(_delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(interaction):
		return
	player.position = player.position.clamp(Vector2(55, 120), Vector2(585, 290))
	var target := interaction.get_target()
	_status.text = "WASD 移动 · E 交互 · Esc 关闭弹窗\n目标：%s    暂停：%s    禁用：%s" % [target.display_name if target != null else "无", get_tree().paused, not interaction.is_input_enabled()]
	if "--demo-capture" in OS.get_cmdline_user_args():
		set_process(false)
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("/tmp/goblin_interaction_feedback.png")
		get_tree().quit()
