class_name FatGoblin
extends SettlementCharacter
## 胖哥布林在剧情中的身体状态与情绪姿势。喝下格里芬之血倒地后改用受难集图集，
## 第二天起是坐地休养，救治成功（signature.S06.rescued_in_time）后回到常态；
## 第一天委托流程里另有拜托、苦恼、吃饱三套站姿图集。
## 状态由 Day1WorldController 按剧情事实投影，角色自身不判断剧情。

enum Health {
	NORMAL,
	COLLAPSED,
	RESTING,
}

enum Mood {
	NEUTRAL,
	HAPPY,
	PLEADING,
	WORRIED,
}

const SICK_FRAMES: SpriteFrames = preload("res://src/gameplay/characters/fat_goblin_sick_frames.tres")
const MOOD_FRAMES: SpriteFrames = preload("res://src/gameplay/characters/fat_goblin_mood_frames.tres")

var health := Health.NORMAL
var mood := Mood.NEUTRAL
var _normal_frames: SpriteFrames

func _ready() -> void:
	_normal_frames = animated_sprite.sprite_frames
	super._ready()

func set_health(value: Health) -> void:
	if value == health:
		return
	health = value
	_apply_pose()

func set_mood(value: Mood) -> void:
	if value == mood:
		return
	mood = value
	_apply_pose()

func _apply_pose() -> void:
	animated_sprite.sprite_frames = _frames_for_pose()
	animated_sprite.frame = 0
	_update_animation(false)

## 身体状态优先于情绪：倒地与坐地休养期间不摆情绪姿势。
func _frames_for_pose() -> SpriteFrames:
	if health != Health.NORMAL:
		return SICK_FRAMES
	if mood != Mood.NEUTRAL:
		return MOOD_FRAMES
	return _normal_frames

func _state_animation() -> StringName:
	match health:
		Health.COLLAPSED:
			return &"sick_retch"
		Health.RESTING:
			return &"sick_sit"
	match mood:
		Mood.HAPPY:
			return &"happy"
		Mood.PLEADING:
			return &"pleading"
		Mood.WORRIED:
			return &"worried"
	return &""

func _update_animation(moving: bool, movement_ratio: float = 1.0) -> void:
	if health == Health.NORMAL and mood == Mood.NEUTRAL:
		super(moving, movement_ratio)
		return
	# 受难集与情绪图集都没有朝向，播放时也不参与走路 / 朝向切换。
	var animation := _state_animation()
	if animation == &"":
		super(moving, movement_ratio)
		return
	var texture := animated_sprite.sprite_frames.get_frame_texture(animation, 0)
	animated_sprite.flip_h = false
	animated_sprite.speed_scale = animation_speed
	if texture != null:
		var frame_height := float(texture.get_height())
		animated_sprite.scale = Vector2.ONE * (128.0 / frame_height)
		animated_sprite.offset = Vector2(0, -frame_height * 0.5)
	animated_sprite.play(animation)
