extends SceneTree
## Repack ImageGen sheets into native 64px cells; run with --headless --script.

const DEST := "res://assets/characters/npc/common_goblin/idle_generated/"
const RESOURCE := "res://src/gameplay/characters/common_goblin_idle_frames.tres"
const SOURCES := {
	"backpack_idle_up": "res://assets/characters/npc/common_goblin/walk_sheet_03.png",
	"unpacked_idle_down": "res://assets/characters/goblin_actions/goblin_walk_down.png",
	"unpacked_idle_up": "res://assets/characters/goblin_actions/goblin_walk_up.png",
}

func _initialize() -> void:
	for animation: String in SOURCES:
		var sheet := Image.load_from_file(ProjectSettings.globalize_path(DEST + "source/" + animation + ".png"))
		var reference := Image.load_from_file(ProjectSettings.globalize_path(SOURCES[animation])).get_region(Rect2i(0, 0, 64, 64))
		var target := reference.get_used_rect()
		var cells: Array[Image] = []
		for index in 8:
			# Fractional boundaries also support non-power-of-two ImageGen output.
			var start := Vector2i(roundi(index % 4 * sheet.get_width() / 4.0), roundi(index / 4 * sheet.get_height() / 2.0))
			var end := Vector2i(roundi((index % 4 + 1) * sheet.get_width() / 4.0), roundi((index / 4 + 1) * sheet.get_height() / 2.0))
			var cell := sheet.get_region(Rect2i(start, end - start))
			# Remove faint generated matte speckles before measuring the character.
			for y in cell.get_height():
				for x in cell.get_width():
					var color := cell.get_pixel(x, y)
					color.a = 1.0 if color.a >= 0.5 else 0.0
					cell.set_pixel(x, y, color)
			cells.append(cell)
		# One aspect-preserving scale for the entire sequence, anchored to source art.
		var scale_factor := float(target.size.y) / cells[0].get_used_rect().size.y
		var packed := Image.create(256, 128, false, Image.FORMAT_RGBA8)
		for index in cells.size():
			var cell := cells[index]
			cell.resize(roundi(cell.get_width() * scale_factor), roundi(cell.get_height() * scale_factor), Image.INTERPOLATE_NEAREST)
			var bounds := cell.get_used_rect()
			var position := Vector2i(roundi(target.get_center().x - bounds.size.x / 2.0), target.end.y - bounds.size.y)
			assert(Rect2i(0, 0, 64, 64).encloses(Rect2i(position, bounds.size)), animation + " frame must fit native canvas")
			packed.blit_rect(cell, bounds, Vector2i(index % 4 * 64, index / 4 * 64) + position)
		_lock_palette(packed, Image.load_from_file(ProjectSettings.globalize_path(SOURCES[animation])), animation == "unpacked_idle_down")
		assert(packed.save_png(DEST + animation + ".png") == OK)
	# Text serialization keeps rebuilding independent of imported texture caches.
	var lines := PackedStringArray(['[gd_resource type="SpriteFrames" format=3]', ''])
	for animation: String in SOURCES:
		lines.append('[ext_resource type="Texture2D" path="%s%s.png" id="%s"]' % [DEST, animation, animation])
	lines.append('')
	for animation: String in SOURCES:
		for index in 8:
			lines.append('[sub_resource type="AtlasTexture" id="%s_%d"]' % [animation, index])
			lines.append('atlas = ExtResource("%s")' % animation)
			lines.append('region = Rect2(%d, %d, 64, 64)' % [index % 4 * 64, index / 4 * 64])
			lines.append('filter_clip = true\n')
	lines.append('[resource]\nanimations = [')
	for animation: String in SOURCES:
		var entries := PackedStringArray()
		for index in 8:
			entries.append('{"duration": 1.0, "texture": SubResource("%s_%d")}' % [animation, index])
		lines.append('{"frames": [%s], "loop": 1, "name": &"%s", "speed": 6.0},' % [', '.join(entries), animation])
	lines.append(']\n')
	var file := FileAccess.open(RESOURCE, FileAccess.WRITE)
	file.store_string('\n'.join(lines))
	print("Built 3 idle sheets, 24 frames; source front-facing backpack idle is retained.")
	quit()

func _material(color: Color, preserve_eye_whites: bool) -> String:
	if color.v < 0.12:
		return "outline"
	# Original eye whites are warm cream, while generated whites are neutral.
	# Match them before hue/saturation grouping so the neutral darks cannot erase eyes.
	if preserve_eye_whites and color.v >= 0.75 and color.s < 0.4:
		return "highlight"
	if color.s < 0.15:
		return "neutral"
	if color.h >= 0.12 and color.h < 0.28:
		return "skin" if color.v >= 0.36 else "pants"
	return "leather"

func _color_groups(image: Image, preserve_eye_whites: bool) -> Dictionary:
	var groups: Dictionary = {}
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a < 0.5:
				continue
			color.a = 1.0
			var material := _material(color, preserve_eye_whites)
			if not groups.has(material):
				groups[material] = {}
			groups[material][color] = groups[material].get(color, 0) + 1
	return groups

func _dominant_color(colors: Dictionary) -> Color:
	# Quantized frequency avoids JPEG-like tiny RGB variations splitting one shade.
	var buckets: Dictionary = {}
	for color: Color in colors:
		var bucket := Vector3i(color.r8 / 8, color.g8 / 8, color.b8 / 8)
		buckets[bucket] = buckets.get(bucket, 0) + colors[color]
	var best := Vector3i.ZERO
	for bucket: Vector3i in buckets:
		if buckets[bucket] > buckets.get(best, 0):
			best = bucket
	var sum := Vector3.ZERO
	var total := 0
	for color: Color in colors:
		if Vector3i(color.r8 / 8, color.g8 / 8, color.b8 / 8) == best:
			sum += Vector3(color.r, color.g, color.b) * colors[color]
			total += colors[color]
	return Color(sum.x / total, sum.y / total, sum.z / total)

func _lock_palette(image: Image, reference: Image, preserve_eye_whites: bool) -> void:
	var source_groups := _color_groups(reference, preserve_eye_whites)
	var generated_groups := _color_groups(image, preserve_eye_whites)
	var mapped: Dictionary = {}
	for material: String in generated_groups:
		var palette: Dictionary = source_groups.get(material, source_groups["outline"])
		var offset := _dominant_color(palette) - _dominant_color(generated_groups[material])
		# Keep black outlines and eye whites at the original value; match material bases.
		if material in ["outline", "neutral", "highlight"]:
			offset = Color(0, 0, 0, 0)
		for color: Color in generated_groups[material]:
			var target: Color = color + offset
			var closest := Color.BLACK
			var distance := INF
			for candidate: Color in palette:
				var delta := Vector3(candidate.r - target.r, candidate.g - target.g, candidate.b - target.b)
				if delta.length_squared() < distance:
					distance = delta.length_squared()
					closest = candidate
			mapped[color] = closest
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a >= 0.5:
				image.set_pixel(x, y, mapped[color])
