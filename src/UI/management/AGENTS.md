# UIManager 与模态生命周期

本目录负责场景级界面注册、模态栈、输入路由与焦点管理。完整 API 以 [UI 系统](../../../docs/systems/ui_system.md) 和当前源码为准。

- 由 MainGame 注入 layer 映射并注册独立界面；管理器保存注册和栈，CanvasLayer 持有视图，不为方便管理改动业务节点归属。
- 新 screen 继承 `ui_screen.gd`（`bind_ui` / `get_default_focus` / `on_ui_closed` / `uses_native_gui_input` / `handle_ui_input`），生命周期契约放基类，具体界面只覆盖需要的回调；管理器保留 duck typing 兼容旧场景。
- screen ID 使用 `screen_ids.gd` 常量（含 `tasks` / `chronicle` / `drinks` 别名），不在宿主、管理器和场景里重复字符串。模态界面组合 `components/modal_shell.tscn`，壳不注册、不持有业务状态。
- 保留重复打开 / 关闭无副作用、未知或已释放视图明确失败，以及 popup 冲突的现有返回语义。
- 被模态覆盖时保存并恢复底层可处理状态、鼠标与焦点；退出栈、隐藏视图之后再执行关闭回调，回调须可重复安全调用。对话关闭通过取消接口结束 session。
- 暂停只释放管理器自己取得的暂停，不能解除外部已有暂停；模态信号是要求调用方重新查询的通知，不能仅按信号名字推测当前是否锁定。
- 栈顶输入、Tab 导航与返回操作沿用统一路由，不能穿透至底层玩法。管理器报告模态 / 暂停状态，玩家权限仍由 MainGame 合并协调。
- 调试 Console 同样注册为 DebugLayer 模态屏幕；额外能力与 Release 边界见 [开发工具规范](../../debug/developer_tools/AGENTS.md)。

候选验证：`tests/verify_ui_manager.gd` 加直接受影响的对白 / 暂停 / Console 最小验证；检查打开、覆盖、取消、释放和焦点恢复，按 [分级规范](../../../tests/AGENTS.md) 选范围。
