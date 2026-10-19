class_name FatGoblin
extends SettlementCharacter
## 胖哥布林在剧情中的身体状况。喝下格里芬之血倒地后改用受难集图集，
## 第二天起是坐地休养，救治成功（signature.S06.rescued_in_time）后回到常态。
## 状态由 Day1WorldController 按剧情事实投影，角色自身不判断剧情。

enum Health {
	NORMAL,
	COLLAPSED,
	RESTING,
}

const SICK_FRAMES: SpriteFrames = preload("res://src/gameplay/characters/fat_goblin_sick_frames.tres")

var health := Health.NORMAL
var _normal_frames: SpriteFrames

func _ready() -> void:
	_normal_frames = animated_sprite.sprite_frames
	super._ready()

func set_health(value: Health) -> void:
	if value == health:
		return
	health = value
	animated_sprite.sprite_frames = _normal_frames if value == Health.NORMAL else SICK_FRAMES
	animated_sprite.frame = 0
	_update_animation(false)

func _update_animation(moving: bool, movement_ratio: float = 1.0) -> void:
	if health == Health.NORMAL:
		super(moving, movement_ratio)
		return
	# 坐在原地的受难帧没有朝向，播放时也不参与走路 / 朝向切换。
	var animation := &"sick_retch" if health == Health.COLLAPSED else &"sick_sit"
	var texture := animated_sprite.sprite_frames.get_frame_texture(animation, 0)
	animated_sprite.flip_h = false
	animated_sprite.speed_scale = animation_speed
	if texture != null:
		var frame_height := float(texture.get_height())
		animated_sprite.scale = Vector2.ONE * (128.0 / frame_height)
		animated_sprite.offset = Vector2(0, -frame_height * 0.5)
	animated_sprite.play(animation)
