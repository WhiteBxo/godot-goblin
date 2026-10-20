class_name TaskText
extends RefCounted
## 任务文案的语义标记：类型、状态与分节标题在这里统一决定颜色，
## 手册、任务页和订单记录因此不会各自发明一套写法。
##
## 详情页是 RichTextLabel，方括号状态词（[已完成] / [未完成]）是玩家认得的
## 老写法，所以只在外面套颜色，不改词本身。

const Tokens := preload("res://src/resources/ui/ui_tokens.gd")

static func escape(text: String) -> String:
	return text.replace("[", "[lb]")

static func paint(text: String, color: Color) -> String:
	return "[color=#%s]%s[/color]" % [color.to_html(false), escape(text)]

## 分节标题：标题本身取强调色，注解留在次要色，一眼分得清“标题 / 进度”。
static func section(title: String, note := "") -> String:
	var line := paint(title, Tokens.ACCENT)
	if not note.is_empty():
		line += "   " + paint(note, Tokens.TEXT_MUTED)
	return line

static func status(completed: bool) -> String:
	if completed:
		return paint("[已完成]", Tokens.SUCCESS)
	return paint("[未完成]", Tokens.ACCENT)

## 已完成的目标整行降温，未完成的留在正文亮度上：进度一眼可见。
static func objective(completed: bool, text: String, optional := false, progress := "") -> String:
	var line := status(completed) + "  " + paint(text, Tokens.TEXT_MUTED if completed else Tokens.TEXT)
	if optional:
		line += paint("（可选）", Tokens.TEXT_MUTED)
	if not progress.is_empty():
		line += "   " + paint(progress, Tokens.ACCENT_STRONG)
	return line

static func hint(text: String) -> String:
	return paint("　指引：" + text, Tokens.TEXT_MUTED)

## 字段行：标签取强调色，值留在正文色；strong 让报酬这类数值站出来。
static func field(label: String, value: String, strong := false) -> String:
	return paint(label + "：", Tokens.ACCENT) + paint(value, Tokens.ACCENT_STRONG if strong else Tokens.TEXT)

## 终态、结算这类整行结论用完成色，读完不用再找。
static func verdict(text: String) -> String:
	return paint(text, Tokens.SUCCESS)
