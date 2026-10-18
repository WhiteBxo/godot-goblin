extends SettlementCharacter
## Pick once on spawn; facing and movement never reroll the appearance.

enum Appearance { RANDOM, WITH_BACKPACK, WITHOUT_BACKPACK }

const BACKPACK_FRAMES: SpriteFrames = preload("res://src/gameplay/characters/common_goblin_frames.tres")
const UNPACKED_ACTIONS: SpriteFrames = preload("res://src/gameplay/goblin_actions/goblin_frames.tres")

@export var appearance: Appearance = Appearance.RANDOM

static var _unpacked_frames: SpriteFrames

func _ready() -> void:
	if appearance == Appearance.RANDOM:
		appearance = Appearance.WITH_BACKPACK if randf() < 0.5 else Appearance.WITHOUT_BACKPACK
	side_faces_left = appearance == Appearance.WITH_BACKPACK
	animated_sprite.sprite_frames = BACKPACK_FRAMES if side_faces_left else _get_unpacked_frames()
	super._ready()

static func _get_unpacked_frames() -> SpriteFrames:
	if _unpacked_frames != null:
		return _unpacked_frames
	_unpacked_frames = SpriteFrames.new()
	_unpacked_frames.remove_animation(&"default")
	for direction: StringName in DIRECTION_NAMES:
		var source := StringName("walk_%s" % (&"side" if direction in [&"left", &"right"] else direction))
		for moving: bool in [false, true]:
			var animation := StringName("%s_%s" % ["run" if moving else "idle", direction])
			_unpacked_frames.add_animation(animation)
			_unpacked_frames.set_animation_speed(animation, 8.0 if moving else 6.0)
			# No separate idle artwork: hold the matching walk animation's first frame.
			var count := UNPACKED_ACTIONS.get_frame_count(source) if moving else 1
			for index in count:
				_unpacked_frames.add_frame(animation, UNPACKED_ACTIONS.get_frame_texture(source, index), UNPACKED_ACTIONS.get_frame_duration(source, index))
	return _unpacked_frames
