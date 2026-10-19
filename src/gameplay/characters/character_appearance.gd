class_name CharacterAppearance
extends RefCounted
## A saved session seed and stable identity keep appearances through reconstruction.

static func choose(actor: Node, actor_id: StringName, family: String, count: int) -> int:
	if not GameEntry.is_save_session_active():
		return randi_range(0, count - 1)
	var state := actor.get_node_or_null("/root/GameState")
	if state == null:
		return randi_range(0, count - 1)
	# Older saves use a stable fallback without changing their snapshot while loading.
	var session_seed: Variant = state.get_variable("visuals.appearance_seed", 0)
	var identity := "%s:%s:%s:%d" % [session_seed, family, actor_id, state.current_day]
	return int(identity.sha256_buffer().decode_u32(0) % count)
