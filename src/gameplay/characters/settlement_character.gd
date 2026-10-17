class_name SettlementCharacter
extends PlayerController
## Identity belongs to the scene. Story order and dialogue remain in StoryDirector data.

@export var actor_id: StringName
@export var display_name := ""
@export_multiline var story_role := ""
@export var side_faces_left := false
@export_enum("always", "day", "night") var active_phase := "always"

func refresh_phase(state: Node) -> void:
	if active_phase != "always":
		visible = DayPhase.get_phase(state) == active_phase

func _ready() -> void:
	super._ready()
	_sync_solid_body()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_sync_solid_body()

## Story shows and hides actors in place; an off-stage body must never block the player.
func _sync_solid_body() -> void:
	set_collision_layer_value(NPC_LAYER, is_visible_in_tree())

func _update_animation(moving: bool, movement_ratio: float = 1.0) -> void:
	super._update_animation(moving, movement_ratio)
	animated_sprite.flip_h = (facing == Facing.RIGHT and side_faces_left) or (facing == Facing.LEFT and not side_faces_left)
	var texture := animated_sprite.sprite_frames.get_frame_texture(animated_sprite.animation, animated_sprite.frame)
	if texture != null:
		# Both source grids retain their aspect ratio and produce a 128px frame canvas.
		var frame_height := float(texture.get_height())
		animated_sprite.scale = Vector2.ONE * (128.0 / frame_height)
		animated_sprite.offset = Vector2(0, -frame_height * 0.5)
