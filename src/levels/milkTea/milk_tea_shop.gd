class_name MilkTeaShop
extends Node2D

## 相机边界相对背景图四边的内缩（美术像素）。
##
## 背景 1376×768 美术像素、节点 scale 1.25；镜头 zoom 0.4 时一个美术像素正好占
## 一个屏幕像素，1280×720 的屏幕正好装下 1280×720 美术像素。四边各裁 48/24 之后
## 整间店刚好铺满一屏——镜头因此没有横向移动的余地，跟拍在店里变成静止画（本来
## 也全在屏内）；受击摇屏改用「允许溢出边界」的写法保住手感，见 _apply_shake。
@export var camera_insets := Vector4(48.0, 24.0, 48.0, 24.0)

## 镜头为「整间店一屏」退到 0.4，小人同步放大 1.25 倍才能保住 2 屏幕像素/美术
## 像素；不乘的话每个美术像素落在 0.8 个屏幕像素上，整只哥布林都在抖。
const ACTOR_VISUAL_SCALE := 1.25

var _character_root: Node2D
var _foreground: Array[DoorframeForeground] = []

func _ready() -> void:
	process_physics_priority = 2
	for point: InteractionPoint in get_interaction_points():
		point.hide_development_markers()
	for container: Node2D in [$Doorframes, $EquipmentForeground]:
		for foreground: DoorframeForeground in container.get_children():
			_foreground.append(foreground)
	_foreground.sort_custom(func(a: DoorframeForeground, b: DoorframeForeground) -> bool: return a.get_baseline_position().y < b.get_baseline_position().y)
	# Even layers belong to furniture; odd layers between them belong to actors.
	# All seven foreground baselines stay below the existing room roofs at Z 20.
	for index in _foreground.size():
		_foreground[index].z_index = (index + 1) * 2

func configure_depth_sort(character_root: Node2D) -> void:
	_character_root = character_root
	_character_root.y_sort_enabled = true
	_refresh_depth_sort()

func _physics_process(_delta: float) -> void:
	_refresh_depth_sort()

func _refresh_depth_sort() -> void:
	if not is_instance_valid(_character_root):
		return
	for character in _character_root.get_children():
		if not character is PlayerController:
			continue
		# 剧情里临时进店的哥布林也挂在这一层：逐帧对齐，进店当帧就归位。
		var actor := character as SettlementCharacter
		if actor != null and not is_equal_approx(actor.visual_scale, ACTOR_VISUAL_SCALE):
			actor.visual_scale = ACTOR_VISUAL_SCALE
			actor.refresh_visual_scale()
		var layer := 1
		for foreground: DoorframeForeground in _foreground:
			if character.global_position.y >= foreground.get_baseline_position().y:
				layer += 2
		character.z_index = layer

func get_world_bounds() -> Rect2:
	var background: Sprite2D = $Background
	return background.global_transform * background.get_rect()

func get_camera_bounds() -> Rect2:
	var background: Sprite2D = $Background
	var bounds: Rect2 = background.transform * background.get_rect()
	bounds.position += Vector2(camera_insets.x, camera_insets.y)
	bounds.size -= Vector2(camera_insets.x + camera_insets.z, camera_insets.y + camera_insets.w)
	return global_transform * bounds

func get_spawn_position() -> Vector2:
	return $Spawn.global_position

func get_scene_entrance(id: StringName) -> SceneEntrance:
	for child in $SceneEntrances.get_children():
		if child is SceneEntrance and child.entrance_id == id:
			return child
	return null

func get_scene_exits() -> Array[SceneExit]:
	var exits: Array[SceneExit] = []
	for child in $SceneExits.get_children():
		if child is SceneExit:
			exits.append(child)
	return exits

func get_interaction_points() -> Array[InteractionPoint]:
	var points: Array[InteractionPoint] = []
	for child in $InteractionPoints.get_children():
		if child is InteractionPoint:
			points.append(child)
	return points

func get_story_positions() -> Array[Marker2D]:
	var positions: Array[Marker2D] = []
	for marker in $StoryPositions.get_children():
		positions.append(marker as Marker2D)
	return positions
