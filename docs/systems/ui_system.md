# 项目 UI 系统

UI 使用 Godot 4.7 原生 Control、Container 和 Theme，不增加 autoload 或第三方 UI 插件。`MainGame.get_ui_manager()` 返回当前场景的 UIManager。MainGame 负责玩法锁；DialogueManager 和 StoryDirector 继续负责对白与剧情内容。

## 层与生命周期

| 层 | 内容 | process mode |
| --- | --- | --- |
| HudLayer / 10 | ShopUI：标题和交互提示 | Always |
| PopupLayer / 20 | 独立 ShopPopup、DialogueUI | Always；被覆盖时 Disabled |
| PauseLayer / 30 | PauseMenu | WhenPaused |
| TransitionLayer / 40 | 预留转场层，原 ScreenTransition 模块独立使用 | Always |
| DebugLayer / 50 | 调试显示和 UI demo 按钮 | Always |

UIManager 在 Systems 下使用 Always；World 和其他普通 Systems 保持 Pausable。界面节点由其 CanvasLayer 持有，管理器保存注册和模态栈。店铺 HUD 和弹窗通过独立场景实例化，不再从 HUD 内部 reparent 弹窗。

手册使用 `handbook_hud`（HudLayer 的右上角图标及未读圆点）与 `handbook`（PopupLayer 的统一模态窗口）。委托与异闻录通过页签切换，未解锁页签隐藏；全部未解锁时入口隐藏。`MainGame.open_handbook()` 选择上次页签，首次优先委托；`open_tasks()` / J 键和 `open_chronicle()` 选择对应页。`tasks`、`chronicle` 保留为手册别名，复用弹窗互斥、操作锁、Esc 关闭和 P 暂停；ItemList 使用原生方向键、Enter 和鼠标输入，Tab 继续由原生 Control 导航及管理器焦点约束处理。详见 [见闻录模块](../gameplay/chronicle.md)。

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

别名的 `open_screen` 先检查目标生命周期、暂停和 popup 冲突，再调用 prepare；prepare 失败不打开窗口。窗口已打开时，别名只切换内容，不重入模态栈或触发 modal_changed。`is_open` 和 `close_screen` 对别名均查询/关闭同一个正式窗口；两个业务别名可同时报告 true。`screen_closed` 仅发送正式 screen ID。

信号为 `modal_changed()`、`pause_changed(paused)`、`screen_closed(id)`。非模态显示改变也可能触发 modal_changed，订阅者应重新查询状态。

新增界面将内容放在独立 Control 场景，根节点引用共享 Theme；模态根覆盖全屏，遮罩接收鼠标。业务请求以 signal 交给宿主处理，宿主将关闭请求接到 `close_screen`。可选实现：

- `get_default_focus() -> Control`：打开和恢复时的默认焦点；没有可选项可返回 null。
- `bind_ui(manager, id)`：切换为管理器输入路由；未绑定时保留独立场景输入。
- `uses_native_gui_input() -> bool`：返回 true 时由原生 Control 处理确认、方向和 Tab；用于 Developer Console 的 OptionButton 和只读 TextEdit，其他界面的输入分发不变。
- `handle_ui_input(event)`：处理栈顶的确认和方向输入，当前用于对白。Tab 导航由管理器处理。
- `on_ui_closed()`：同步结束业务生命周期；对白在此请求 DialogueManager 取消。此回调发生在界面已出栈、隐藏之后，应可重复安全调用。

当前 `popup` 层模态互斥，`pause` 可覆盖 popup；通用 HUD 使用非模态注册。`pause` 是管理器保留 ID；通过 open_screen("pause") 或 set_paused(true) 均会取得暂停。不要在 pause 层注册其他业务界面。

## 输入、焦点与操作锁

- Esc 关闭店铺弹窗或取消对白；无弹窗时暂停；暂停时返回。P 使用独立 `pause_game` action 切换暂停。
- Enter、空格、E 确认；方向键和 Tab/Shift+Tab 在顶部界面导航，过滤按键 echo。确认与返回的 release 同样消费，避免关闭后穿透到世界交互。鼠标使用 Godot GUI 控件原生事件。
- 覆盖下层时保存其 Control 的 mouse_filter、focus_mode 和根 process_mode，禁用处理、鼠标与焦点；恢复后还原。打开时保存原焦点的弱引用；关闭时恢复仍有效可见的焦点。
- MainGame 将模态、对白、剧情 busy 和 Actor 控制合并为一个操作锁。在第一个锁进入时保存玩家移动与交互原状态，最后一个锁解除时恢复；ShopInteraction 不修改玩家移动状态。
- 暂停冻结 World、剧情执行和被覆盖对白的打字机；恢复保留对白内容、选项和滚动位置。继续按钮只恢复游戏，不取消对白。
- 节点离树自动注销，移除模态和失效焦点引用；UIManager 销毁会关闭界面、结束活动对白并释放其取得的暂停。外部已有暂停不会被取得或解除。
- 独立 interaction demo 由宿主监听 ShopUI opened/closed 管理操作锁；独立 DialogueUI demo 保留本地输入，不依赖 MainGame。

## 主题与 F6 验收

共享主题是 `src/resources/ui/game_theme.tres`，各正式 UI 根显式引用，独立预览也能使用。正文使用现有 12px 像素字体；Title 使用 24px，Speaker 和 Hint 是主题 variation。面板沿用暖棕底色与金棕边框，按钮具备 normal、hover、pressed、focus、disabled 样式。使用 Container、anchors 和滚动容器约束长文本。

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
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --log-file /private/tmp/goblin-ui-test.log --script res://tests/verify_<name>.gd
```

相关测试为 `ui_manager`、`main_game`、`milk_tea_shop`、`dialogue`、`story_director`、`cinematic_integration`、`interaction_feedback`、`screen_transition`。主场景架构测试显式构建洞穴 fixture 保留开发工具覆盖，默认店铺的实际交互由 milk_tea_shop 与 ui_manager 验证。

窗口版 UI 验证同时输出三种尺寸的店铺、对白和暂停截图至 `/private/tmp/goblin-ui-{shop,dialogue,pause}-<width>x<height>.png`：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --log-file /private/tmp/goblin-ui-visual.log --script res://tests/verify_ui_manager.gd -- --capture
```

窗口截图来自游戏 viewport，不包含宽窗口的比例留白。验收同时断言实际 Window 尺寸，避免只修改截图文件名。

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
