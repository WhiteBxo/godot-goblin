# 项目 UI 系统

UI 使用 Godot 4.7 原生 Control、Container 和 Theme，不增加 autoload 或第三方 UI 插件。`MainGame.get_ui_manager()` 返回当前场景的 UIManager。MainGame 负责玩法锁；DialogueManager 和 StoryDirector 继续负责对白与剧情内容。

## 层与生命周期

| 层 | 内容 | process mode |
| --- | --- | --- |
| HudLayer / 10 | 交互提示、单行 TaskHUD、右上角菜单入口、短暂收支及潜入状态 | Always |
| PopupLayer / 20 | 游戏菜单、ShopPopup、DialogueUI、HandbookPanel、聚落地图及菜单设置 | Always；被覆盖时 Disabled |
| PauseLayer / 30 | PauseMenu | WhenPaused |
| TransitionLayer / 40 | SceneTravel 的 ScreenTransition 与 Story TitleCard，由宿主合并显隐 | Always |
| DebugLayer / 50 | 调试显示和 UI demo 按钮 | Always |

UIManager 在 Systems 下使用 Always；World 和其他普通 Systems 保持 Pausable。界面节点由其 CanvasLayer 持有，管理器保存注册和模态栈。店铺 HUD 和弹窗通过独立场景实例化，不再从 HUD 内部 reparent 弹窗。

右上角 `handbook_hud` 现在显示“菜单”及未读圆点，打开 `chapter_actions`（PopupLayer 的按需游戏菜单）。完整目标、钱包、存档时间、支线与经营动作在菜单查看；奶茶订单、雇佣系统（暂未开放）、任务日志、异闻录、饮品图鉴、人物记录、背包、地图和设置从这里进入，子页返回菜单，再返回游戏。原“委托”入口拆为三处：`奶茶订单`（`order_history`，经营订单的进行中／可接取与历史）、`任务日志 [J]`（`tasks`，主线与支线）和置灰的`雇佣系统`（`hiring`）。手册本体仍使用 `handbook`（PopupLayer 的统一模态窗口）。奶茶订单页常驻可打开，任务日志、异闻录与饮品图鉴按解锁隐藏页签；除奶茶订单外全部未解锁时手册不可打开，基础菜单仍可使用。`MainGame.open_handbook()` 选择上次页签，首次优先任务日志；`open_tasks()` / J 键、`open_chronicle()` 与 `open_drinks()` 选择对应页。饮品图鉴首次自由制作后开放。`tasks`、`order_history`、`chronicle`、`drinks` 保留为手册别名，复用弹窗互斥、操作锁、Esc 关闭和 P 暂停；ItemList 使用原生方向键、Enter 和鼠标输入，Tab 继续由原生 Control 导航及管理器焦点约束处理。详见 [见闻录模块](../gameplay/chronicle.md) 与 [奶茶订单](../gameplay/order_system.md)。

## 接入接口

`configure(layers)` 接收 StringName 到 CanvasLayer 的映射，目前使用 `hud`、`popup`、`pause`、`debug`。MainGame 创建、注入并注册暂停菜单。

| API | 行为 |
| --- | --- |
| `register_screen(id, view, layer, modal) -> Error` | 添加无父节点的界面或迁至指定层；初始隐藏。重复 ID 或同一 view 返回 ERR_ALREADY_EXISTS；空 ID、无效 view 或未知层返回 ERR_INVALID_PARAMETER |
| `register_screen_alias(id, target, prepare) -> Error` | 别名指向已注册的正式 screen，prepare 为返回 Error 的 Callable；通过准入检查后调用它选择内容。重复 ID 返回 ERR_ALREADY_EXISTS，空 ID、未知正式目标或无效 Callable 返回 ERR_INVALID_PARAMETER；不支持别名链 |
| `unregister_screen(id)` | 关闭并注销界面，断开原 view 的离树回调；供工具替换面板使用，旧 view 随后离树不会注销新 view；注销别名仅移除路由，注销正式 screen 同时清理其全部别名 |
| `open_screen(id) -> Error` | 显示界面，模态入栈；已打开则无副作用。未知 ID 返回 ERR_DOES_NOT_EXIST，待删除/离树 view 返回 ERR_UNCONFIGURED；popup 冲突或暂停中打开 popup 返回 ERR_BUSY |
| `close_screen(id)` | 关闭界面；未打开则无副作用。对白经过取消接口结束活动 session；关闭 pause 同时恢复管理器取得的暂停 |
| `request_back()` | 恢复暂停，或关闭栈顶，或在无模态时打开暂停 |
| `is_open(id)` / `has_modal()` | 查询打开状态和是否存在模态 |
| `set_paused(value)` | 暂停并覆盖现有 UI，或恢复；不解除外部已有暂停 |

别名的 `open_screen` 先检查目标生命周期、暂停和 popup 冲突，再调用 prepare；prepare 失败不打开窗口。窗口已打开时，别名只切换内容，不重入模态栈或触发 modal_changed。`is_open` 和 `close_screen` 对别名均查询/关闭同一个正式窗口；多个业务别名可同时报告 true。`screen_closed` 仅发送正式 screen ID。

信号为 `modal_changed()`、`pause_changed(paused)`、`screen_closed(id)`。非模态显示改变也可能触发 modal_changed，订阅者应重新查询状态。

新增界面继承 `src/UI/management/ui_screen.gd`，把内容放在独立 Control 场景，根节点引用共享 Theme；screen ID 使用 `src/UI/management/screen_ids.gd` 常量。业务请求以 signal 交给宿主处理，宿主将关闭请求接到 `close_screen`。`UIScreen` 已提供以下默认实现，按需覆盖：

- `get_default_focus() -> Control`：打开和恢复时的默认焦点；没有可选项可返回 null。
- `bind_ui(manager, id)`：切换为管理器输入路由；未绑定时保留独立场景输入。
- `uses_native_gui_input() -> bool`：返回 true 时由原生 Control 处理确认、方向和 Tab；用于 Developer Console 的 OptionButton 和只读 TextEdit，其他界面的输入分发不变。
- `handle_ui_input(event)`：处理栈顶的确认和方向输入，当前用于对白。Tab 导航由管理器处理。
- `on_ui_closed()`：同步结束业务生命周期；对白在此请求 DialogueManager 取消。此回调发生在界面已出栈、隐藏之后，应可重复安全调用。

模态界面组合 `src/UI/components/modal_shell.tscn`：壳负责遮罩、外边距、Panel 边框、标题、关闭按钮与页脚，内容场景只提供列表、详情和输入。手册由 `ModalShell + HandbookBody`（`TabContainer` + `TaskPage` / `ChroniclePage` / `Drinks`）组成，店铺由 `ModalShell + ShopPage`（订单板 / 按单制作、CraftingPanel / FreeCraftingPanel / WarehousePanel 为内容组件）组成，`TaskPopup` 仅用于测试与 F6 预览。内容页不得再复制 Dim、Panel、Header 或 Close；`ModalShell.get_panel_rect()` 与 `get_close_button()` 供测试和宿主使用。底部交互提示使用 `PromptBar`（Keycap + 卡片面板），不再在各 HUD 里手写颜色。

当前 `popup` 层模态互斥，`pause` 可覆盖 popup；通用 HUD 使用非模态注册。`pause` 是管理器保留 ID；通过 open_screen("pause") 或 set_paused(true) 均会取得暂停。不要在 pause 层注册其他业务界面。

## 输入、焦点与操作锁

- Esc 关闭店铺弹窗或取消对白；无弹窗时暂停；暂停时返回。P 使用独立 `pause_game` action 切换暂停。
- Enter、空格、E 确认；方向键和 Tab/Shift+Tab 在顶部界面导航，过滤按键 echo。确认与返回的 release 同样消费，避免关闭后穿透到世界交互。鼠标使用 Godot GUI 控件原生事件。
- 覆盖下层时保存其 Control 的 mouse_filter、focus_mode 和根 process_mode，禁用处理、鼠标与焦点；恢复后还原。打开时保存原焦点的弱引用；关闭时恢复仍有效可见的焦点。
- MainGame 将模态、对白、剧情 busy 和 Actor 控制合并为一个操作锁。在第一个锁进入时保存玩家移动与交互原状态，最后一个锁解除时恢复；ShopInteraction 不修改玩家移动状态。
- 暂停冻结 World、剧情执行和被覆盖对白的打字机；恢复保留对白内容、选项和滚动位置。继续按钮只恢复游戏，不取消对白。
- 节点离树自动注销，移除模态和失效焦点引用；UIManager 销毁会关闭界面、结束活动对白并释放其取得的暂停。外部已有暂停不会被取得或解除。
- 独立 interaction demo 由宿主监听 ShopUI opened/closed 管理操作锁；独立 DialogueUI demo 保留本地输入，不依赖 MainGame。

## 主题、组件与 F6 验收

共享主题是 `src/resources/ui/game_theme.tres`，各正式 UI 根显式引用，独立预览也能使用；项目级 `gui/theme/custom` 保持未设置，Debug 与第三方面板不被统一换皮。主题由 `src/resources/ui/ui_tokens.gd` 生成，颜色、字号、间距、圆角与控件高度只在 tokens 定义。修改 tokens 后运行：

```sh
godot --headless --path . --script res://tools/ui/build_theme.gd
```

主题覆盖 Button、Label、Panel/PanelContainer、ItemList、TabContainer/TabBar、LineEdit、SpinBox、VScrollBar/HScrollBar、PopupMenu、Tooltip、CheckBox、ProgressBar、HSeparator、RichTextLabel 和容器间距。正文 12px，弹窗标题 24px，标题画面 36px，不使用 14/18。静态样式全部来自主题，场景和脚本用 `theme_type_variation`（Title/H2/Speaker/Hint/Muted/Subtitle/Value/Success/Warning/Danger/Badge/Keycap/PrimaryButton/GhostButton/ChipButton/DangerButton/IconButton/InsetPanel/HudPanel/CoinPanel/CardPanel/SunkenPanel/ShadePanel/SuccessBar）表达语义，不写 per-node 颜色或字号覆盖。

视觉层级按“表面”分工：普通 Panel 只留 1px 暗边和投影，用于 HUD 与对白；`InsetPanel` 是弹窗唯一的金色细边表面；`HudPanel` 用左侧 3px 铜色导轨强调当前目标；`CoinPanel` 是圆角金币药丸；`ChipButton` 用于“菜单”这类需要在小地图/场景上保持可发现的入口。正文 Label 带 1px 暗色投影，纸色订单笺的墨色文字则关闭投影。

`UIButtonMotion`（`src/UI/components/ui_button_motion.gd`）与 `UIAudioFeedback` 并列挂在宿主 Systems 下，扫过 Hud/Popup/Pause 层内的按钮：悬停轻微放大、按下回缩、松开回弹、键盘焦点微抬。它只改 `scale` 与 `pivot_offset`，不动布局、焦点和按钮信号；覆盖整张卡片的透明热区用 `metadata/ui_motion = false` 退出，避免悬停底框溢出卡片。弹窗打开、交互提示出现、任务目标/余额变化与标题画面另有各自的一次性缓动，全部由对应脚本在展示层完成。

`UIFlourish`（`src/UI/components/ui_flourish.gd`）收纳“刚刚发生了什么”的一次性动效：`settle()` 数值落地、`stamp()` 状态改判、`refuse()` 操作被拒、`cups()` 产出物离开台面、`reveal()` 就地换页后的落定、`float_text()` 金额变化浮字。它只动 `scale`/`rotation`/`modulate`，结束时回到单位变换；`cups()` 与 `float_text()` 的浮层挂到最近的非 Container 祖先上，绝不进入任何容器的布局，也不吃鼠标。同一控件重复触发会先杀掉上一段同类型缓动，因此可以随手调用。按钮本体的按压反馈仍归 `UIButtonMotion`，这里只负责“结果”。

`src/debug/ui/ui_kit.tscn` 是主题画廊，F6 检查字体层级、按钮状态、面板、ItemList 选中、页签、输入框、进度条与长文本。`tests/verify_ui_theme.gd` 审计场景使用的控件类型、字号范围和 UI 脚本中的 raw Color；`tests/verify_ui_kit.gd` 冒烟加载画廊并输出截图。

打开 `src/debug/ui/ui_demo.tscn`，F6：

1. 点击“店铺弹窗”，确认暖棕面板和统一按钮；Tab 不离开弹窗，Esc 关闭。
2. 点击“对白”，E 显示全文/继续，选项支持方向键、Tab 和鼠标。
3. 对白逐字显示或选项选中时按 P，确认暂停菜单覆盖对白；按 Esc 或“继续游戏”，从原进度、原焦点继续。
4. 关闭对白后按 Esc，打开暂停；再次 Esc 只恢复游戏，不触发交互。
5. 调整为 640×360、1280×720 和 1440×720。整数缩放保持像素尺寸，宽窗口保持游戏内容比例；店铺长说明与对白长文本/选项在内部滚动。

Demo 的测试按钮只在 Debug 创建；正式 UI 和暂停功能不依赖 Debug。

## 自动化与执行记录

引擎：Godot 4.7.2。使用以下入口；将 `<name>` 替换为测试名。

```sh
godot --headless --path . --log-file .godot/ui-test.log --script res://tests/verify_<name>.gd
```

相关测试为 `ui_manager`、`ui_theme`、`ui_kit`、`handbook`、`task_panel`、`chronicle`、`main_game`、`milk_tea_shop`、`dialogue`、`story_director`、`cinematic_integration`、`interaction_feedback`、`screen_transition`。主场景架构测试显式构建洞穴 fixture 保留开发工具覆盖，默认店铺的实际交互由 milk_tea_shop 与 ui_manager 验证。

窗口版 UI 验证同时输出三种尺寸的店铺、对白和暂停截图至 `.godot/ui-captures/goblin-ui-{shop,dialogue,pause}-<width>x<height>.png`：

```sh
godot --path . --log-file .godot/ui-visual.log --script res://tests/verify_ui_manager.gd -- --capture
```

统一手册与任务面板的截图分别写入 `.godot/handbook/` 与 `.godot/task_panel/`；主题画廊写入 `.godot/ui_kit/`。窗口截图来自游戏 viewport，不包含宽窗口的比例留白。验收同时断言实际 Window 尺寸，避免只修改截图文件名。

历史主题化、壳重构与店铺界面批次通过（非本轮文档实测）：ui_theme 152 项、ui_kit 6 项、ui_manager 47 项（窗口版含尺寸断言 50 项）、handbook 44 项、task_panel 92 项、chronicle 64 项、dialogue 154 项、main_game 73 项、day1_stages_01_02 255 项，以及 milk_tea_shop、warehouse_inventory、business_session、tea_production、tea_recipes、gameplay_bridge、task_delivery、task_system、gathering、interaction_feedback 的对应检查。F6 与 640×360、1280×720 截图已人工检查。

历史 UI 验收（统一手册接入前）：ui_manager 47 项（窗口版含尺寸断言共 50 项）、main_game 72 项、dialogue 75 项、story_director 147 项、cinematic_integration 286 项、interaction_feedback 46 项、screen_transition 54 项，以及 milk_tea_shop 的移动/碰撞/交互检查。窗口版在项目默认 Metal Forward+ 下完成三种尺寸截图检查；Compatibility 渲染器也通过同一 UI 回归。

核心回归覆盖重复开关、互斥、顶部输入、焦点循环/恢复、初始移动禁用、剧情/Actor 交叠锁、暂停保留打字机与选项、节点释放以及外部暂停所有权。窗口版额外检查三种窗口尺寸并人工检查截图。

## 官方 API 依据

- [Godot 4.7 Theme 与局部覆盖](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_skinning.html)：外部 Theme 共享及局部 override 的优先级。
- [焦点和导航](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_navigation.html)：初始化焦点、隐藏时丢失焦点、显式导航。
- [暂停与 process mode](https://docs.godotengine.org/en/4.7/tutorials/scripting/pausing_games.html)：Always、WhenPaused、Pausable 及 Disabled 的作用。
- [输入事件传播](https://docs.godotengine.org/en/4.7/tutorials/inputs/inputevent.html)：在 _input 阶段消费模态事件，阻止后续 GUI/世界分发。
- [Control](https://docs.godotengine.org/en/4.7/classes/class_control.html)：anchors、mouse_filter、focus_mode 和 grab_focus。

## 统一手册验证

`tests/verify_handbook.gd` 覆盖解锁组合、旧状态迁移、任务清空、重建与重置、别名路由、焦点恢复、暂停和未读语义。窗口运行加 `-- --capture` 时，将店铺和聚落的截图保存到 `.godot/handbook/`；覆盖 640×360 与 1280×720。

使用 [Godot 4.7 TabContainer](https://docs.godotengine.org/en/4.7/classes/class_tabcontainer.html) 的 `set_tab_hidden()` 隐藏未解锁页签。结构参考 [ESO 官方任务指南](https://www.elderscrollsonline.com/en-us/newplayerguide/questing) 的任务与 Lore Library 统一 Journal，以及 [Guild Wars 2 官方 Story Journal 介绍](https://www.guildwars2.com/en/news/introducing-the-story-journal/) 的主面板集中浏览。图标 `assets/ui/handbook.svg` 为项目内原创矢量图形。

## 正式聚落地图

`src/UI/map/map_panel.tscn` 使用 `UIScreen + ModalShell`，由聚落 MainGame 装配。`MainGame.unlock_map()` 在地图和玩家已装配、screen 注册成功后才写入 `day1.s04.map_available`；重复调用安全。它是供后续 S04 接线的公开能力，当前正式剧情没有调用，初始化和打开地图均不补写这个事实。已有事实在宿主重建时恢复入口；reset / restore 撤销事实会注销并关闭地图。

解锁后菜单的“地图 [M]”或 M 调用 `open_map()`；未解锁返回 `ERR_UNAVAILABLE`，暂停、演出、其他模态、潜行拦截或现有移动锁期间返回 `ERR_BUSY`。Esc / 关闭按钮退出，P 暂停覆盖，焦点和玩家锁沿用 UIManager / MainGame。Debug 全图改为 F7，Tab 路线在模态期间不响应。独立店内及洞穴宿主未装配聚落地图，不能解锁或打开它。

`SettlementMap.get_map_data(known_locations)` 只返回世界边界、保存场景中的区域 footprint 和真实外部入口位置的值副本；不返回节点、内部贴图、文书、血液、书柜、隐藏石盖或路线。`SettlementMap.MAP_LOCATIONS` 是唯一的 `location_id → zone_id → *_entrance` 映射：`settlement.shop/muster/vestibule/training/lodging/kitchen/tavern/casino/dining/ritual/elder/growing/warehouse/yard/hearth/workshop`。`RpgWorldMapData.LOCATIONS` 在聚落章节图里补充 `settlement.residential`（东侧居民区），并作为 `references.locations` 的校验来源之一。

正式展示使用用户提供的实际洞窟全图 `assets/map/cartography/cavern_floor_overview.png`（1200 × 1320）作为底图。世界范围 2400 × 2640 与图片等比对应，区域名称、玩家圆点与目标圆环由 `SettlementMapCanvas` 实时绘制；地名落在区域中心，玩家和目标使用实际外景位置。未知区域不画标签；`map_data.illustrated` 为假时回退到编号轮廓图。打开面板标题为“哥布林洞窟地图”。

奶茶店是当前唯一默认已知地点。其他地点须由剧情或真实探索业务写入 `ui.map.known.<location_id>`（例如 `ui.map.known.settlement.elder`）；地图不擅自推断认知，也不写探索完成事实。即使取得长老住处知识，也只显示建筑轮廓和外部入口。当前尚无正式 S04 知识发布及查看完成条件接线，不能将地图能力视为 P14 整项完成。

地图只读 `TaskJournal.get_current_main_task()` 及已揭示的 `current_objective`，优先采用目标 `location_id`，为空时采用明确配置的任务级位置。没有配置 `location_id` 的目标不附加地点文字；已配置但未映射、未揭示或未知区域不画目标，并显示“地图上未标注”，不会用交付对象或剧情文本猜位置。当前正式目录已为第二天五项主线任务和 `day1.s04.order` 配置地点，MainGame 用 `RpgWorldMapData.location_ids()` 作为 `references.locations` 校验；其余任务保持未配置，未修改任务 Schema。位置能力另由隔离测试夹具在真实聚落宿主中验证。

`SettlementMapCanvas.world_to_map()` 统一处理世界原点、等比缩放和居中。打开时读取最新地图/玩家/投影；打开期间只逐帧检查玩家位置，任务与知识变化按信号刷新。隐藏时停止处理，暂停覆盖时由管理器禁用处理。

## 小地图与目标箭头

`src/UI/map/navigation_hud.tscn`（`NavigationHUD`，注册为 `navigation_hud` 的 HUD 屏，不进入模态栈）在聚落章节图右上角显示小地图与目标箭头。它在 `day1` 业务档案、已出店（或后续阶段／第二天起）且宿主为 `RpgChapterMap` 时出现；打开弹窗、演出、潜行拦截等输入锁期间隐藏，`set_display_enabled` 由 MainGame 的输入锁统一驱动。

`ObjectiveNavigation.resolve()` 与大地图共用同一份只读投影：只取 `TaskJournal.get_current_main_task()` 中已揭示的 `current_objective`，`RpgChapterMap.objective_points` 把 `task_id:objective_id` 映射到章节场景里的真实锚点（`get_objective_position`）；室外坐标不会被当成室内目标。没有目标时显示“自由探索”，不画箭头。

小地图以 48px 格读取玩家周围 ±7 格的可走格绘制局部平面图，随所在房间与走廊变化，附玩家圆点、目标菱形与“北”字；每 0.2 秒刷新一次。箭头画在可见屏幕坐标上，并按 `get_emote_offset()` 抬高退出角色头部范围，方向优先沿 `RpgChapterMap.get_navigation_path()` 的实际可通行格搜索（`can_cross_edge`，跳过角色占位格），找不到路线时退回直指目标，保证不会穿墙指路。该 HUD 只读章节状态，不写任何事实。

本次最低模块验证：`verify_map_ui.gd`、`verify_ui_manager.gd`、`verify_ui_theme.gd`、`verify_task_panel.gd`、`verify_main_game.gd` 及 `verify_settlement.gd`。窗口专项使用 `-- --capture` 在真实 `src/core/settlement.tscn` 且关闭开发工具的宿主执行键鼠、移动、暂停与知识/目标隔离夹具，截图输出到 `.godot/map_ui/`。不代表完整 S04 剧情或真实 Release 导出验收。

2026-10-19 图形专项由 `tests/verify_feedback_iteration.gd` 覆盖（76 项通过）：菜单拆分与入口、奶茶订单归档、一键接单后收银台结算不重复发钱、旧存档角色越界后回到店门口、小地图与箭头、长老宅双卫的警戒与听觉。截图输出到 `.godot/feedback_navigation/captures/`。完整回归 99 项中 64 项通过，28 个失败与 1 个挂起均为 HEAD 基线已有项（多次在全量回归和隔离基线复现），新增项无回归。

2026-10-18 验收结果（Godot 4.7.2，macOS / Apple M1）：地图专项 headless 初版 55 项通过，最终 Metal 窗口版 59 项通过（含重复解锁、按键无冲突与真实窗口尺寸断言）；UIManager 47、Theme 167、TaskPanel 92、MainGame 73、DebugBuild 97 项均通过。聚落检查通过 48,623 个物理采样点及 16 区域、锚点、桥、实际移动与碰撞。已人工检查 `.godot/map_ui/known_shop_640.png`、`settlement_640.png`、`settlement_1280.png`，全地点截图的知识和目标来自隔离夹具。headless 有 macOS 系统证书诊断，无脚本错误；导入阶段另有沙箱中编辑器设置写入和退出资源诊断，不计为玩法检查。未扩大到完整剧情回归或 Release 导出，因为没有修改剧情内容、任务业务或地图通行布局。
