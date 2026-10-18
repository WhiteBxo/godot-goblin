extends SceneTree

const THEME_PATH := "res://src/resources/ui/game_theme.tres"
const UI_ROOT := "res://src/UI"
const ALLOWED_UNTHEMED := ["Control", "ColorRect", "TextureRect", "CenterContainer", "BoxContainer", "HFlowContainer"]
const REQUIRED_STYLES := {
	"Button": ["normal", "hover", "pressed", "disabled", "focus"],
	"ItemList": ["panel", "focus", "selected", "selected_focus"],
	"TabContainer": ["tab_selected", "tab_unselected", "tab_hovered", "tab_disabled", "panel"],
	"TabBar": ["tab_selected", "tab_unselected"],
	"LineEdit": ["normal", "focus"],
	"SpinBox": ["up_background", "down_background"],
	"PopupMenu": ["panel", "hover"],
	"TooltipPanel": ["panel"],
	"ProgressBar": ["background", "fill"],
	"PanelContainer": ["panel"],
	"HSeparator": ["separator"],
}
const REQUIRED_VARIATIONS := [
	"Title", "HeroTitle", "H2", "Speaker", "Hint", "Muted", "Subtitle", "Value",
	"Success", "Warning", "Danger", "Badge", "BadgeMain", "BadgeDone", "BadgeMuted",
	"Keycap", "PrimaryButton", "GhostButton", "DangerButton", "IconButton",
	"InsetPanel", "CardPanel", "SunkenPanel", "ShadePanel", "SuccessBar",
]
const ALLOWED_FONT_SIZES := [12, 24, 36]
const THEME_ALLOWLIST := ["res://src/UI/screen_transition/screen_transition.tscn"]

var checks := 0
var failures: Array[String] = []
var theme: Theme

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error(description)

func _run() -> void:
	theme = load(THEME_PATH) as Theme
	check(theme != null, "Shared theme loads")
	if theme == null:
		quit(1)
		return
	check(theme.default_font != null, "Theme has the pixel font")
	check(theme.default_font_size == 12, "Theme body text is 12px")
	for type: String in REQUIRED_STYLES:
		for item: String in REQUIRED_STYLES[type]:
			check(theme.get_stylebox(item, type) != null, "%s/styles/%s exists" % [type, item])
	for variation: String in REQUIRED_VARIATIONS:
		check(theme.get_type_variation_base(variation) != &"", "Variation %s is registered" % variation)
	check(theme.get_font_size("font_size", "Title") == 24, "Title uses 24px")
	check(theme.get_font_size("font_size", "H2") == 12, "H2 uses 12px")
	check(theme.get_color("font_color", "Hint") != theme.get_color("font_color", "Label"), "Hint is visually distinct")

	var scenes: Array[String] = []
	_scan(UI_ROOT, scenes, ".tscn")
	check(scenes.size() >= 12, "UI scenes discovered")
	var seen_types := {}
	for path: String in scenes:
		var source := FileAccess.get_file_as_string(path)
		check(not source.is_empty(), "Scene readable: " + path)
		if path not in THEME_ALLOWLIST:
			check(source.contains("type=\"Theme\""), "UI root references the shared theme: " + path)
		check(not source.contains("SubResource(\"ListStyle\")"), "No duplicated ListStyle in " + path)
		for type: String in _node_types(source):
			seen_types[type] = true
	for type: String in seen_types:
		if not ClassDB.is_parent_class(type, &"Control"):
			continue
		if type in ALLOWED_UNTHEMED:
			continue
		var has_item := (not theme.get_stylebox_list(type).is_empty()
			or not theme.get_color_list(type).is_empty()
			or not theme.get_constant_list(type).is_empty()
			or not theme.get_font_size_list(type).is_empty()
			or not theme.get_icon_list(type).is_empty())
		check(has_item, "Theme covers control type: " + type)

	var scripts: Array[String] = []
	_scan(UI_ROOT, scripts, ".gd")
	for path: String in scripts:
		var source := FileAccess.get_file_as_string(path)
		check(not source.contains("Color("), "No raw Color() in UI script: " + path)
		for size: int in _font_sizes(source):
			check(size in ALLOWED_FONT_SIZES, "Font size %d uses the type scale: %s" % [size, path])

	print("UI_THEME: %s (%d checks, %d failures)" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _scan(path: String, out: Array[String], extension: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not name.begins_with("."):
			var full := path.path_join(name)
			if dir.current_is_dir():
				_scan(full, out, extension)
			elif name.ends_with(extension):
				out.append(full)
		name = dir.get_next()
	dir.list_dir_end()

func _node_types(source: String) -> Array[String]:
	var result: Array[String] = []
	var regex := RegEx.new()
	regex.compile("\\[node[^\\]]*type=\"([A-Za-z0-9_]+)\"")
	for match: RegExMatch in regex.search_all(source):
		result.append(match.get_string(1))
	return result

func _font_sizes(source: String) -> Array[int]:
	var result: Array[int] = []
	var scene_regex := RegEx.new()
	scene_regex.compile("font_size\\s*=\\s*([0-9]+)")
	for match: RegExMatch in scene_regex.search_all(source):
		result.append(int(match.get_string(1)))
	var override_regex := RegEx.new()
	override_regex.compile("font_size\"\\s*,\\s*([0-9]+)")
	for match: RegExMatch in override_regex.search_all(source):
		result.append(int(match.get_string(1)))
	return result
