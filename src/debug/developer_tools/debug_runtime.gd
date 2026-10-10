class_name DebugRuntime
extends RefCounted

# 此开关仅用于开发时关闭工具；Release 不接受任何启用覆盖。
static func is_enabled() -> bool:
	return OS.has_feature("debug") and bool(ProjectSettings.get_setting("debug/developer_tools/enabled", true))

static func apply_release_policy(tree: SceneTree) -> void:
	if OS.has_feature("debug"):
		return
	# 保留第三方插件源码，在项目侧停止无 debugger 的逐帧注册轮询。
	var probe := tree.root.get_node_or_null("MCPRuntimeProbe")
	if probe != null:
		probe.set_process(false)
		probe.process_mode = Node.PROCESS_MODE_DISABLED
