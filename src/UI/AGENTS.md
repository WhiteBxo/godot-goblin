# UI 场景与交互规范

UI 使用 Godot 原生 Control、Container、Theme。总体接口见 [UI 系统](../../docs/systems/ui_system.md)，不因新增界面增加 autoload 或第三方 UI 插件。

## 层与生命周期

五个屏幕层均为 CanvasLayer，关闭 `follow_viewport_enabled`；层由宿主持有，不在弹窗打开时重建。

| 层 | layer | 内容 | process mode |
| --- | --- | --- | --- |
| HudLayer | 10 | 正式 HUD、入口与提示 | Always |
| PopupLayer | 20 | 背包、对话、制作等通用弹窗 | Always；覆盖状态由 UIManager 管理 |
| PauseLayer | 30 | 暂停界面 | WhenPaused |
| TransitionLayer | 40 | 屏幕转场 | Always |
| DebugLayer | 50 | 调试面板与覆盖显示 | Always |

- 空层不截获输入；非交互调试 Control 使用 `MOUSE_FILTER_IGNORE`。交互遮罩、焦点与鼠标过滤由对应界面和 UIManager 明确配置。
- UIManager 放 Systems 并使用 Always；普通 Systems 与 World 仍为 Pausable。玩家移动与交互锁由 MainGame 协调，UI 不能关闭时无条件恢复为 true。
- 界面放独立 Control 场景，复用现有 Theme / 字体，通过 signal 或公开接口提交业务请求；HUD 内不再持有待 reparent 的业务弹窗。
- 保持稳定 screen ID、打开 / 关闭和取消生命周期；模态堆叠、焦点、暂停与底层处理状态由 UIManager 统一管理，不让各弹窗各自维护竞争状态。
- 内容来自对应业务服务或资源；展示层不解析剧情步骤、修改任务事实、直接扣库存或发放奖励。

## 主题与组件

静态样式只来自 `src/resources/ui/game_theme.tres`，数值来源是 `src/resources/ui/ui_tokens.gd`；改 tokens 后运行 `godot --headless --path . --script res://tools/ui/build_theme.gd` 重建，不手改生成结果。正式 UI 根显式引用主题，不使用项目级全局主题。

- 场景和脚本用 `theme_type_variation` 表达 Title / H2 / Hint / Muted / Success / Warning / Danger / Badge / Keycap / PrimaryButton / GhostButton / ChipButton / IconButton / InsetPanel / HudPanel / CoinPanel / CardPanel / SunkenPanel 等语义，不写 per-node 颜色、字号或 `ListStyle` 覆盖。
- 悬停与按下的缩放反馈由 `components/ui_button_motion.gd` 统一注入，按钮不需要自带动画脚本；需要退出该反馈的整块热区在场景里写 `metadata/ui_motion = false`。
- 模态界面组合 `components/modal_shell.tscn`，内容页只做列表、详情与输入，不复制遮罩、Panel 边框、页脚或关闭按钮；新 screen 继承 `management/ui_screen.gd`，ID 使用 `ScreenIds` 常量。
- 新增控件类型必须补主题条目，并通过 `tests/verify_ui_theme.gd` 的类型、字号与 raw Color 审计。
- `src/debug/ui/ui_kit.tscn` 是 F6 主题画廊；新增可复用控件先在画廊展示，再接入正式界面。

## 按功能继续阅读

| 目录 / 内容 | 相关模块规范 |
| --- | --- |
| `management/`：注册、模态栈、焦点与暂停 | [management/AGENTS.md](management/AGENTS.md) |
| `components/`：ModalShell、页面壳与通用控件 | [components/AGENTS.md](components/AGENTS.md) |
| `handbook/`：统一手册入口、页签与共享模态 | [handbook/AGENTS.md](handbook/AGENTS.md)，业务另读 [任务规范](../core/tasks/AGENTS.md) 与 [见闻录规范](../core/chronicle/AGENTS.md) |
| `screen_transition/`：黑场与转场视觉 | [screen_transition/AGENTS.md](screen_transition/AGENTS.md) |
| `dialogue/`：逐字对白、选项与立绘 | [对话规范](../core/dialogue/AGENTS.md) |
| `milk_tea/`：制作与仓库界面 | [制作与库存规范](../gameplay/milk_tea/AGENTS.md) |
| `inventory/`：随身仓库入口（复用 `WarehousePanel`，B 键打开） | [制作与库存规范](../gameplay/milk_tea/AGENTS.md)、[仓库文档](../../docs/gameplay/warehouse_inventory.md) |
| `tasks/`：任务列表、详情与 HUD | [任务规范](../core/tasks/AGENTS.md) |
| `trade/`：酒馆购买与集市摊主货架 | [经济规范](../core/economy/AGENTS.md)；摊主数据来自 [章节业务](../core/story/AGENTS.md) |
| `chronicle/`：见闻录入口、列表与详情 | [见闻录规范](../core/chronicle/AGENTS.md) |
| `characters/`：人物记录列表与详情 | [人物记录规范](../core/characters/AGENTS.md) |
| `hud/`：业务阶段与交互提示 | 按实际显示内容读 [剧情规范](../core/story/AGENTS.md) 或 [交互规范](../gameplay/interaction/AGENTS.md) |
| `title/`、`pause/`：新游戏、返回标题与暂停 | [核心入口规范](../core/AGENTS.md)；暂停栈另读管理规范 |

候选验证：`tests/verify_ui_manager.gd` 与直接涉及的模块测试；主题或样式调整加 `tests/verify_ui_theme.gd`、`tests/verify_ui_kit.gd`。局部画面 / 参数调整只做目标界面检查和 F6 观察。按 [验证分级](../../tests/AGENTS.md) 选择，报告键鼠、关闭 / 取消与锁恢复的实际结果。
