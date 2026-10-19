class_name UIFlourish
extends RefCounted
## One-shot motion for "something just happened": a finished cup lifting off the
## counter, a refused press, a customer slip that changed hands.
##
## Presentation only. Nothing here touches layout size, focus or gameplay state,
## and every animation ends on the identity transform, so a tween that is killed
## by a screen closing can never leave a control distorted.

const CUP_ICON: Texture2D = preload("res://assets/ui/milk_tea/products/custom_drink.svg")
const CUP_SIZE := 18.0
const CUP_RISE := 18.0
const CUP_STAGGER := 0.04
const CUP_LIFE := 0.34
const CUP_FADE := 0.20
const CUP_OVERLAY_Z := 60
const FLOAT_RISE := 18.0
const FLOAT_LIFE := 0.7
const WORLD_Z := 120
const WORLD_ICON := 28.0
const WORLD_LIFE := 1.2
const TOSS_SECONDS := 0.30
const REFUSE_TINT := Color(1.0, 0.72, 0.66)
const SETTLE_META := &"ui_flourish_settle"
const REFUSE_META := &"ui_flourish_mark"
const STAMP_META := &"ui_flourish_stamp"


## A value landed: grows out of a smaller copy and stops. Safe to spam.
static func settle(control: Control, from := 0.88) -> void:
	if not _prepare(control):
		return
	control.set_meta(SETTLE_META, true)
	control.scale = Vector2(from, from)
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A container swapped its content: the replacement settles in instead of
## snapping. Used for tab pages and other in-place page changes.
static func reveal(control: Control, from := 0.985) -> void:
	if not _prepare(control):
		return
	control.set_meta(SETTLE_META, true)
	control.modulate.a = 0.0
	control.scale = Vector2(from, from)
	var tween := control.create_tween().set_parallel(true)
	tween.tween_property(control, "modulate:a", 1.0, 0.12)
	tween.tween_property(control, "scale", Vector2.ONE, 0.20).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## A number just changed by this much: "+3G" rises off [param anchor] and fades.
## The label lives on the nearest non-container ancestor, like the cups.
static func float_text(anchor: Control, text: String, color := Color.WHITE) -> void:
	if text.strip_edges().is_empty() or not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return
	var host := _overlay_host(anchor)
	if host == null:
		return
	var label := Label.new()
	label.name = "FloatText"
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.z_index = CUP_OVERLAY_Z
	label.add_theme_color_override("font_color", color)
	host.add_child(label)
	label.reset_size()
	var rect := anchor.get_global_rect()
	var center: Vector2 = host.get_global_transform().affine_inverse() * rect.get_center()
	label.position = center - label.size * 0.5
	var tween := host.create_tween().set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - FLOAT_RISE, FLOAT_LIFE).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, FLOAT_LIFE * 0.7).set_delay(FLOAT_LIFE * 0.4)
	tween.chain().tween_callback(label.queue_free)


## A status changed state: lands like a rubber stamp, slightly crooked.
static func stamp(control: Control) -> void:
	if not _prepare(control):
		return
	control.set_meta(STAMP_META, true)
	control.rotation = -0.10
	control.scale = Vector2(1.28, 1.28)
	var tween := control.create_tween().set_parallel(true)
	tween.tween_property(control, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(control, "rotation", 0.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## The press was refused: one short recoil and a warm flush, then normal.
static func refuse(control: Control) -> void:
	if not _prepare(control):
		return
	control.set_meta(REFUSE_META, true)
	var tween := control.create_tween()
	tween.tween_property(control, "scale", Vector2(0.97, 1.03), 0.06)
	tween.parallel().tween_property(control, "modulate", REFUSE_TINT, 0.06)
	tween.tween_property(control, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(control, "modulate", Color.WHITE, 0.20)


## The cups a press just produced lift off [param anchor] and fade. They leave
## from [param from], a normalised point inside the anchor, so they never cover
## the label the player is about to read. The overlay is parented to the nearest
## non-container ancestor so no layout pass can move it, and every cup frees
## itself in well under a second.
static func cups(anchor: Control, icon: Texture2D, count: int, from := Vector2(0.5, 0.5)) -> void:
	if count <= 0 or not is_instance_valid(anchor) or not anchor.is_inside_tree():
		return
	var host := _overlay_host(anchor)
	if host == null:
		return
	var rect := anchor.get_global_rect()
	var center := rect.position + rect.size * from
	var origin: Vector2 = host.get_global_transform().affine_inverse() * center
	var shown := mini(count, 3)
	var spacing := CUP_SIZE * 0.8
	var texture: Texture2D = icon if icon != null else CUP_ICON
	for index in range(shown):
		var cup := TextureRect.new()
		cup.name = "ProducedCup%d" % index
		cup.texture = texture
		cup.size = Vector2(CUP_SIZE, CUP_SIZE)
		cup.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cup.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cup.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		cup.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cup.z_index = CUP_OVERLAY_Z
		cup.pivot_offset = cup.size * 0.5
		cup.position = origin + Vector2(spacing * (index - (shown - 1) * 0.5) - CUP_SIZE * 0.5, -CUP_SIZE * 0.5)
		cup.scale = Vector2(0.45, 0.45)
		cup.modulate.a = 0.0
		host.add_child(cup)
		var delay := CUP_STAGGER * index
		var rise := host.create_tween().set_parallel(true)
		rise.tween_property(cup, "modulate:a", 1.0, 0.09).set_delay(delay)
		rise.tween_property(cup, "scale", Vector2.ONE, 0.22).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		rise.tween_property(cup, "position:y", cup.position.y - CUP_RISE, CUP_LIFE).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var fade := host.create_tween()
		fade.tween_interval(CUP_LIFE * 0.7 + delay)
		fade.tween_property(cup, "modulate:a", 0.0, CUP_FADE)
		fade.tween_callback(cup.queue_free)


## A hand-over: the cup leaves [param from], arcs to [param to] and the payout
## floats up where it landed. The overlay is a level child, not a control, so
## nothing in the UI can move it and it survives a popup opening.
static func world_toss(host: Node2D, from: Vector2, to: Vector2, icon: Texture2D,
		text := "", color := Color(1.0, 0.92, 0.66)) -> void:
	if not _world_ready(host):
		return
	var layer := _world_layer(host)
	var start: Vector2 = layer.to_local(from)
	var end: Vector2 = layer.to_local(to)
	var base := _icon_scale(icon)
	var cup := _world_icon(layer, start, icon)
	cup.scale = base * 0.6
	var apex := Vector2((start.x + end.x) * 0.5, minf(start.y, end.y) - WORLD_ICON)
	var fly := layer.create_tween()
	fly.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fly.tween_property(cup, "position", apex, TOSS_SECONDS * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fly.parallel().tween_property(cup, "scale", base, TOSS_SECONDS * 0.55)
	fly.parallel().tween_property(cup, "rotation", -0.22, TOSS_SECONDS * 0.55)
	fly.tween_property(cup, "position", end, TOSS_SECONDS * 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fly.parallel().tween_property(cup, "scale", base * 0.7, TOSS_SECONDS * 0.45)
	fly.parallel().tween_property(cup, "rotation", 0.08, TOSS_SECONDS * 0.45)
	fly.parallel().tween_property(cup, "modulate:a", 0.0, TOSS_SECONDS * 0.45)
	fly.tween_callback(cup.queue_free)
	if not text.is_empty():
		var label := _world_label(layer, end + Vector2(0.0, -WORLD_ICON * 1.4), text, color)
		var rise := label.create_tween()
		rise.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		rise.tween_interval(TOSS_SECONDS * 0.8)
		rise.tween_property(label, "position:y", label.position.y - FLOAT_RISE, FLOAT_LIFE * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		rise.tween_property(label, "modulate:a", 0.0, FLOAT_LIFE * 0.45)


## Something was picked up off the ground: the item pops out of [param at] and
## the count floats up. Used where the world is still visible (a counter payout).
static func world_pop(host: Node2D, at: Vector2, icon: Texture2D, count: int,
		text := "", color := Color(1.0, 0.94, 0.74)) -> void:
	if not _world_ready(host):
		return
	var layer := _world_layer(host)
	var origin: Vector2 = layer.to_local(at)
	var base := _icon_scale(icon)
	var shown := clampi(count, 1, 3)
	for index in range(shown):
		var item := _world_icon(layer, origin, icon)
		item.scale = base * 0.4
		item.modulate.a = 0.0
		var lean := float(index - (shown - 1) * 0.5) * WORLD_ICON * 0.7
		var delay := 0.045 * index
		var pop := item.create_tween()
		pop.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		pop.tween_interval(delay)
		pop.tween_property(item, "modulate:a", 1.0, 0.08)
		pop.parallel().tween_property(item, "scale", base, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pop.parallel().tween_property(item, "position", origin + Vector2(lean, -WORLD_ICON * 1.5), 0.42).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		pop.tween_property(item, "modulate:a", 0.0, 0.22)
		pop.tween_callback(item.queue_free)
	if not text.is_empty():
		var label := _world_label(layer, origin + Vector2(0.0, -WORLD_ICON * 2.0), text, color)
		var rise := label.create_tween()
		rise.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		rise.tween_property(label, "position:y", label.position.y - FLOAT_RISE, FLOAT_LIFE * 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		rise.tween_property(label, "modulate:a", 0.0, FLOAT_LIFE * 0.45)


## A one-off reaction above an actor: pops in, lifts, fades. It stays out of the
## actor director on purpose, so a delivery can never claim control that a story
## step on the same actor is about to need.
static func world_message(host: Node2D, at: Vector2, text: String,
		color := Color(1.0, 0.94, 0.74)) -> void:
	if text.is_empty() or not _world_ready(host):
		return
	var layer := _world_layer(host)
	var label := _world_label(layer, layer.to_local(at), text, color)
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2(0.62, 0.62)
	label.modulate.a = 0.0
	var pop := label.create_tween()
	pop.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	pop.tween_property(label, "modulate:a", 1.0, 0.06)
	pop.parallel().tween_property(label, "scale", Vector2(1.14, 1.14), 0.13).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(label, "scale", Vector2.ONE, 0.15)
	pop.parallel().tween_property(label, "position:y", label.position.y - WORLD_ICON * 0.7, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	pop.tween_property(label, "modulate:a", 0.0, 0.28)


static func _world_ready(host: Node2D) -> bool:
	return is_instance_valid(host) and host.is_inside_tree() and host.is_visible_in_tree()


## One short-lived level node owns every sprite of a single burst, so a burst
## that is interrupted can never leave stragglers behind.
static func _world_layer(host: Node2D) -> Node2D:
	var layer := Node2D.new()
	layer.name = "WorldFlourish"
	layer.z_index = WORLD_Z
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	host.add_child(layer)
	var life := layer.create_tween()
	life.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	life.tween_interval(WORLD_LIFE)
	life.tween_callback(layer.queue_free)
	return layer


static func _world_icon(layer: Node2D, at: Vector2, icon: Texture2D) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = icon if icon != null else CUP_ICON
	sprite.centered = true
	sprite.position = at
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.add_child(sprite)
	return sprite


static func _world_label(layer: Node2D, at: Vector2, text: String, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(0.09, 0.05, 0.03))
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)
	label.reset_size()
	label.position = at - label.size * 0.5
	return label


## The overlay works in world pixels, so icon art is normalised to one size
## instead of trusting whatever resolution an item icon was imported at.
static func _icon_scale(icon: Texture2D) -> Vector2:
	var art: Texture2D = icon if icon != null else CUP_ICON
	var side := maxf(art.get_width(), art.get_height())
	if side <= 0.0:
		side = WORLD_ICON
	return Vector2.ONE * (WORLD_ICON / side)


## Kills the previous run of the same flourish and clears its residual
## transform. A control shown in this very frame has no size yet, so the pivot
## falls back to its requested size instead of waiting a frame.
static func _prepare(control: Control) -> bool:
	if not is_instance_valid(control) or not control.is_inside_tree():
		return false
	var box := control.size
	if box == Vector2.ZERO:
		box = control.get_combined_minimum_size()
	if box == Vector2.ZERO:
		return false
	for key: StringName in [SETTLE_META, REFUSE_META, STAMP_META]:
		control.remove_meta(key)
	control.scale = Vector2.ONE
	control.rotation = 0.0
	control.pivot_offset = box * 0.5
	# Only a refused control owns its tint; a colour flash set by the caller
	# (the ticket's gold status) must survive.
	control.modulate = Color.WHITE
	return true


## Containers re-place every child on the next layout pass, so the cups live on
## the closest plain Control instead. Walking up from the anchor reaches the
## screen root before the scene tree does.
static func _overlay_host(start: Control) -> Control:
	var current: Node = start
	while current != null:
		if current is Control and not current is Container:
			return current
		current = current.get_parent()
	return null
