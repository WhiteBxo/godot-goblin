extends SettlementCharacter
## Pick once on spawn; facing and movement never reroll the appearance.

enum Appearance { RANDOM, WITH_BACKPACK, WITHOUT_BACKPACK }

const BACKPACK_FRAMES: SpriteFrames = preload("res://src/gameplay/characters/common_goblin_frames.tres")
const UNPACKED_ACTIONS: SpriteFrames = preload("res://src/gameplay/goblin_actions/goblin_frames.tres")
const IDLE_FRAMES: SpriteFrames = preload("res://src/gameplay/characters/common_goblin_idle_frames.tres")

@export var appearance: Appearance = Appearance.RANDOM

static var _unpacked_frames: SpriteFrames
static var _backpack_frames: SpriteFrames

func _ready() -> void:
	if appearance == Appearance.RANDOM:
		appearance = Appearance.WITH_BACKPACK if randf() < 0.5 else Appearance.WITHOUT_BACKPACK
	side_faces_left = appearance == Appearance.WITH_BACKPACK
	animated_sprite.sprite_frames = _get_backpack_frames() if side_faces_left else _get_unpacked_frames()
	super._ready()

static func _get_backpack_frames() -> SpriteFrames:
	if _backpack_frames == null:
		_backpack_frames = BACKPACK_FRAMES.duplicate()
		_replace_idle(_backpack_frames, &"up", &"backpack_idle_up")
	return _backpack_frames

static func _replace_idle(frames: SpriteFrames, direction: StringName, source: StringName) -> void:
	var animation := StringName("idle_%s" % direction)
	frames.clear(animation)
	frames.set_animation_speed(animation, IDLE_FRAMES.get_animation_speed(source))
	frames.set_animation_loop_mode(animation, SpriteFrames.LOOP_LINEAR)
	for index in IDLE_FRAMES.get_frame_count(source):
		frames.add_frame(animation, IDLE_FRAMES.get_frame_texture(source, index), IDLE_FRAMES.get_frame_duration(source, index))

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
			# Side idle retains the matching walk's first frame; front/back are replaced below.
			var count := UNPACKED_ACTIONS.get_frame_count(source) if moving else 1
			for index in count:
				_unpacked_frames.add_frame(animation, UNPACKED_ACTIONS.get_frame_texture(source, index), UNPACKED_ACTIONS.get_frame_duration(source, index))
	for direction: StringName in [&"down", &"up"]:
		_replace_idle(_unpacked_frames, direction, StringName("unpacked_idle_%s" % direction))
	return _unpacked_frames
