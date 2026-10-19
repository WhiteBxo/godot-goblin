extends SettlementCharacter
## Choose once per instance; both appearances retain the same gameplay identity.

enum Appearance { RANDOM, MALE, FEMALE }

const MALE_FRAMES: SpriteFrames = preload("res://src/gameplay/characters/human_customer_frames.tres")
const FEMALE_FRAMES: SpriteFrames = preload("res://src/gameplay/characters/human_customer_female_frames.tres")

@export var appearance: Appearance = Appearance.RANDOM

func _ready() -> void:
	if appearance == Appearance.RANDOM:
		appearance = Appearance.MALE if randf() < 0.5 else Appearance.FEMALE
	animated_sprite.sprite_frames = MALE_FRAMES if appearance == Appearance.MALE else FEMALE_FRAMES
	super._ready()
