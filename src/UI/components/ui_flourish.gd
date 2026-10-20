class_name UIFlourish
extends RefCounted
## One-shot motion for "something just happened": a finished cup lifting off the
## counter, a refused press, a customer slip that changed hands.
##
## Presentation only. Nothing here touches layout size, focus or gameplay state,
## and every animation ends on the identity transform, so a tween that is killed
## by a screen closing can never leave a control distorted.

const CUP_ICON: Texture2D = preload("res://assets/ui/milk_tea/products/custom_drink.svg")
const COIN_ICON: Texture2D = preload("res://assets/ui/coin.svg")
const COIN_SIZE := 12.0
const COIN_RISE := 24.0
const COIN_STAGGER := 0.055
const COIN_LAUNCH := 0.16
const COIN_FALL := 0.24
const CUP_SIZE := 18.0
const CUP_RISE := 18.0
const CUP_STAGGER := 0.04
const CUP_LIFE := 0.34
const CUP_FADE := 0.20
const CUP_OVERLAY_Z := 60
const OVERLAY_SURFACE := &"FXOverlay"
const FLOAT_RISE := 18.0
const FLOAT_LIFE := 0.7
const REFUSE_TINT := UITokens.REFUSE_TINT
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


## Money just landed: coins arc from [param from_global] (a viewport point, e.g.
## above the player) into [param target] and fade on arrival. The target takes one
## settle when the last coin lands, so the number reacts after the coins do.
static func coins_to_wallet(from_global: Vector2, target: Control, count: int) -> void:
	if count <= 0 or not is_instance_valid(target) or not target.is_inside_tree():
		return
	# HUD chips live straight under a CanvasLayer, where no Control ancestor exists
	# to host the flight; a dedicated full-rect surface keeps viewport coordinates.
	var host := _overlay_surface(target)
	if host == null:
		return
	var start := from_global
	var end := target.get_global_rect().get_center()
	var shown := mini(count, 6)
	var last_land := 0.0
	for index in range(shown):
		var coin := TextureRect.new()
		coin.name = "PaidCoin%d" % index
		coin.texture = COIN_ICON
		coin.size = Vector2(COIN_SIZE, COIN_SIZE)
		coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		coin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		coin.z_index = CUP_OVERLAY_Z
		coin.pivot_offset = coin.size * 0.5
		coin.position = start - coin.size * 0.5
		coin.scale = Vector2(0.5, 0.5)
		coin.modulate.a = 0.0
		host.add_child(coin)
		# Deterministic fan-out: a fixed golden angle keeps runs reproducible.
		var angle := float(index) * 2.399963
		var peak := start.lerp(end, 0.32) + Vector2(cos(angle), sin(angle)) * 7.0 - Vector2(0.0, COIN_RISE)
		var delay := COIN_STAGGER * index
		var tween := host.create_tween().set_parallel(true).set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		tween.tween_property(coin, "modulate:a", 1.0, 0.06).set_delay(delay)
		tween.tween_property(coin, "scale", Vector2.ONE, 0.14).set_delay(delay).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(coin, "position", peak, COIN_LAUNCH).set_delay(delay).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(coin, "position", end - coin.size * 0.5, COIN_FALL).set_delay(delay + COIN_LAUNCH).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tween.tween_property(coin, "scale", Vector2(0.72, 0.72), COIN_FALL).set_delay(delay + COIN_LAUNCH)
		tween.tween_property(coin, "modulate:a", 0.0, 0.08).set_delay(delay + COIN_LAUNCH + COIN_FALL)
		tween.chain().tween_callback(coin.queue_free)
		last_land = maxf(last_land, delay + COIN_LAUNCH + COIN_FALL)
	if target.has_method("pop"):
		var settle := host.create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
		settle.tween_interval(last_land)
		settle.tween_callback(func() -> void: target.call("pop", shown))


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


## HUD chips sit directly under a CanvasLayer, so there is no Control ancestor to
## parent a flight onto. A single full-rect surface keeps viewport coordinates and
## is reused across payments.
static func _overlay_surface(target: Control) -> Control:
	var parent := target.get_parent()
	if parent == null:
		return null
	for child: Node in parent.get_children():
		if child is Control and child.name == OVERLAY_SURFACE:
			return child
	var surface := Control.new()
	surface.name = OVERLAY_SURFACE
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(surface)
	return surface
