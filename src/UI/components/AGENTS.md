# UI 组件

本目录保存跨界面复用的壳与控件场景，不承载业务逻辑。完整主题与生命周期见 [UI 规范](../AGENTS.md) 和 [UI 系统](../../../docs/systems/ui_system.md)。

- `modal_shell.tscn` 是弹窗的唯一壳：遮罩、外边距、Panel 边框、标题、关闭按钮和页脚都在这里；内容页不得再复制 Dim / Panel / Header / Close。
- 壳通过 `content_scene` 组合内容页，暴露 `get_content()`、`get_close_button()`、`get_panel_rect()`、`get_default_focus()`；屏幕脚本负责把 `close_requested` 转给宿主。
- 组件样式只使用主题 variation 与 tokens，不写 raw Color、字号或场景级 StyleBox；新增状态先补 `src/resources/ui/ui_tokens.gd` 与 `tools/ui/build_theme.gd`。
- 新增组件提供可独立 F6 的场景，并先接入 `src/debug/ui/ui_kit.tscn`；只在一处使用的布局不要提前抽象。
