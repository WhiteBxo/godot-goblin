extends Node2D
## Inspect independent PackedScenes; no baked room backgrounds are loaded here.

const CATALOG := "res://assets/map/settlement/modular/catalog.json"
@export var initial_pack := "tavern"
var _packs: Array = []
var _index := 0
@onready var _objects: Node2D = $Objects
@onready var _camera: Camera2D = $Camera2D
@onready var _title: Label = $DebugLayer/Panel/Content/Title

func _ready() -> void:
	if not DebugRuntime.is_enabled():
		set_process(false)
		set_process_unhandled_input(false)
		return
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	_packs = catalog.packs
	for index in range(_packs.size()):
		if _packs[index].id == initial_pack:
			_index = index
	show_pack(_index)
	get_viewport().size_changed.connect(fit_pack)

func show_pack(index: int) -> void:
	_index = posmod(index, _packs.size())
	for child: Node in _objects.get_children():
		_objects.remove_child(child)
		child.queue_free()
	var pack: Dictionary = _packs[_index]
	_title.text = "%s  ·  %d / %d  ·  每件均为独立场景" % [pack.title, _index + 1, _packs.size()]
	var font: Font = load("res://assets/fonts/fusion_pixel/fusion-pixel-12px-monospaced-zh_hans.otf.woff2")
	for item_index in range(pack.assets.size()):
		var asset: Dictionary = pack.assets[item_index]
		var object: Node2D = load(asset.scene).instantiate()
		object.position = Vector2(item_index % 4 * 512 + 256, floori(item_index / 4.0) * 512 + 488)
		_objects.add_child(object)
		var label := Label.new()
		label.text = "%s\n%d × %d px" % [asset.id, asset.native_size[0], asset.native_size[1]]
		label.add_theme_font_override("font", font)
		label.add_theme_font_size_override("font_size", 20)
		label.position = object.position + Vector2(-210, 16)
		_objects.add_child(label)
	var player: ShopPlayer = load("res://src/gameplay/player/shop_player.tscn").instantiate()
	player.accepts_player_input = false
	player.collision_layer = 0
	player.collision_mask = 0
	player.get_node("Camera2D").enabled = false
	player.position = Vector2(2210, 600)
	_objects.add_child(player)
	player.set_movement_enabled(false)
	var reference := Label.new()
	reference.text = "主角参考\n约 110 px 高"
	reference.add_theme_font_override("font", font)
	reference.add_theme_font_size_override("font_size", 20)
	reference.position = Vector2(2080, 630)
	_objects.add_child(reference)
	fit_pack()

func fit_pack() -> void:
	var available := get_viewport_rect().size - Vector2(32, 80)
	_camera.position = Vector2(1170, 570)
	_camera.zoom = Vector2.ONE * minf(available.x / 2360, available.y / 1160)
	_camera.make_current()

func _process(delta: float) -> void:
	_camera.position += Input.get_vector("move_left", "move_right", "move_up", "move_down") * delta * 500 / _camera.zoom.x

func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("debug_settlement_routes"):
		show_pack(_index + 1)
	elif event.is_action_pressed("debug_toggle_overview"):
		fit_pack()
	elif event.is_action_pressed("ui_page_up"):
		_camera.zoom = (_camera.zoom * 1.25).min(Vector2(2, 2))
	elif event.is_action_pressed("ui_page_down"):
		_camera.zoom = (_camera.zoom * 0.8).max(Vector2(0.05, 0.05))
	else:
		return
	get_viewport().set_input_as_handled()

func get_pack_count() -> int:
	return _packs.size()

func get_pack_index() -> int:
	return _index
