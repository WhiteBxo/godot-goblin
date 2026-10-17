# 见闻录状态

公开接口与接入见 [见闻录模块](../../../docs/gameplay/chronicle.md)。

- ChronicleJournal 管理解锁、追加记录和已读状态，通过已有 GameState 保存事实；服务跟随场景，由宿主注入，不增加 autoload 或第二份进度。
- 保持稳定 entry / record ID、重复调用的既有幂等语义与完整通知顺序；重新配置依赖时断开旧订阅。
- ChroniclePanel 与 ChronicleHUD 只展示列表、详情和未读数，按 [UI 规范](../../UI/AGENTS.md) 注册到 UIManager，不直接修改底层状态容器。
- 剧情使用已有 `chronicle_unlock` / `chronicle_append` 指令，标题和正文来自 Markdown；内容编排读 [剧情源稿规范](../../../docs/design/AGENTS.md)。

候选验证：`tests/verify_chronicle.gd` 与直接相关 UI 的 F6，按 [验证分级](../../../tests/AGENTS.md) 选择。
