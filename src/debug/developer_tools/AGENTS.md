# 通用 Developer Console

功能、接线与验收见 [Developer Console](../../../docs/development/developer_console.md)。Debug / Release 门控继承 [上级规范](../AGENTS.md)。

- DebugRuntime 统一判断工具是否启用；F3 的 `debug_toggle_console` 仅在 Debug 工具创建时注册到内存 InputMap，不为 Console 改项目输入配置。
- controller 放 Systems，使用 Always；panel 放 DebugLayer（50），注册为 UIManager 模态屏幕。开关不能取得全局暂停，也不能穿透到底层玩法或专用调试操作。
- 状态、回出生点、重启、能力判定通过 context 注入的 Callable 与公开服务取得；缺失能力明确显示不可用并禁用操作，不直接改玩家、状态或剧情私有字段。
- 观察只读取快照和真实信号，不为填满面板加载事件、触发剧情或补造历史数据；日志保持现有有界长度，不强制打断用户滚动。
- 重启目标必须是实际当前宿主，并保持已有确认 / 取消交互；重启保留 GameState，不混入清空整局、作弊、存档或命令解释器。
- UI 覆盖、焦点、取消与恢复交给 [UIManager](../../UI/management/AGENTS.md)；关闭 Console 后保留原有暂停、剧情和移动禁用状态。
- 新增通用能力只面向公开接口，洞穴墙体、布局和截图仍留在洞穴专属组件。

候选验证：`tests/verify_developer_tools.gd`；涉及门控或接线再选择 `verify_debug_build.gd` 及目标宿主 F6，按 [验证分级](../../../tests/AGENTS.md) 控制范围。
