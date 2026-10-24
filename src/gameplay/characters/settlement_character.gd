class_name SettlementCharacter
extends PlayerController
## Identity belongs to the scene. Story order and dialogue remain in StoryDirector data.

@export var actor_id: StringName
@export var display_name := ""
@export_multiline var story_role := ""
@export var side_faces_left := false
@export_enum("always", "day", "night") var active_phase := "always"
## Off for actors whose business is served by a shared point instead, e.g. the
## mansion pair: two bodies at one door would otherwise compete with the bribe.
@export var gives_interaction_point := true

## Bounds in character-local space, including the scene's visual scale and feet offset.
func get_interaction_feedback_rect() -> Rect2:
	var texture := animated_sprite.sprite_frames.get_frame_texture(animated_sprite.animation, animated_sprite.frame)
	if texture == null:
		return Rect2()
	var frame_size := texture.get_size()
	var origin := animated_sprite.offset - (frame_size * 0.5 if animated_sprite.centered else Vector2.ZERO)
	# Read once during interaction setup so transparent sprite padding is excluded.
	var image := texture.get_image()
	var artwork := Rect2(image.get_used_rect()) if image != null else Rect2(Vector2.ZERO, frame_size)
	if animated_sprite.flip_h:
		artwork.position.x = frame_size.x - artwork.end.x
	if animated_sprite.flip_v:
		artwork.position.y = frame_size.y - artwork.end.y
	var sprite_to_character := global_transform.affine_inverse() * animated_sprite.global_transform
	return sprite_to_character * Rect2(origin + artwork.position, artwork.size)

func refresh_phase(state: Node) -> void:
	if active_phase != "always":
		visible = DayPhase.get_phase(state) == active_phase

func _update_animation(moving: bool, movement_ratio: float = 1.0) -> void:
	super._update_animation(moving, movement_ratio)
	animated_sprite.flip_h = (facing == Facing.RIGHT and side_faces_left) or (facing == Facing.LEFT and not side_faces_left)
	var texture := animated_sprite.sprite_frames.get_frame_texture(animated_sprite.animation, animated_sprite.frame)
	if texture != null:
		# Both source grids retain their aspect ratio and produce a 128px frame canvas.
		# 像素画只能整数倍放大：帧高 64 → 2x、128 → 1x。若直接用 128/height，
		# 80 或 96 高的帧会得到 1.6 / 1.33 倍，边缘被重采样成半透明毛边。
		var frame_height := float(texture.get_height())
		var factor := maxf(1.0, roundf(128.0 / frame_height))
		animated_sprite.scale = Vector2.ONE * factor
		# offset 是缩放前的本地单位，乘 scale 后正好落到半个帧高处。
		animated_sprite.offset = Vector2(0, -frame_height * 0.5)
