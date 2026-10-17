# 通用 Developer Console（第一阶段）

Godot 4.7.2，默认收起。F3 打开/关闭，Esc 关闭；沿用共享像素字体与暖棕主题，面板位于屏幕右侧。仅 `DebugRuntime.is_enabled()` 为 true 时由 MainGame 装配。F3 的 `debug_toggle_console` action 只在 Debug 工具创建时注册到内存 InputMap，不修改项目输入配置。

## 功能与操作

| 分区 | 内容 |
| --- | --- |
| 状态 | 当前宿主场景路径、关卡、玩家世界坐标、FPS、GameState 当前天数和剧情阶段；打开时约每 0.2 秒刷新 |
| 角色 | 1×、2×、4×、8× 移速，返回当前关卡公开出生点，确认重启当前宿主；重启保留 GameState |
| 剧情 / 状态数据 | flags、variables、已完成事件的只读快照；StoryDirector 已加载事件数、当前事件和从 0 开始的步骤序号、最近错误 |
| 剧情 / 事件日志 | 真实 event_started、step_started、step_skipped、event_completed、event_finished 信号，含时间与失败/跳过原因；最多 200 条，支持清空 |

文本可滚动、选择和复制，日志不会强制跳回顶部。没有 GameState、StoryDirector、已加载事件或角色能力时明确显示不可用/未加载，并禁用对应角色操作。观察不会加载事件、发起剧情或补造事件数据；绑定前已经发出的信号也不会补造历史日志。被拒绝的 request 没有 event_finished 信号，其原因显示在最近错误，不伪造失败日志。

Console 在 UIManager 中注册为 DebugLayer 的 modal screen。打开后 MainGame 原有的模态/剧情/Actor 合并锁禁用玩家移动及交互；底层 UI 的焦点、鼠标和处理状态由 UIManager 保存/恢复。Console 自己不取得全局暂停：P 在面板内被消费，关闭后保留原有暂停、剧情和移动禁用状态。面板打开期间，E、M、Tab 对应的聚落动线、F2 等玩法或专用调试操作不会穿透；Tab/方向键供 GUI 导航。速度下拉菜单使用原生 popup，F3 也能从 popup 关闭 Console。

不提供 GameState 清空、剧情重置、库存或任务作弊、场景跳转、存档及命令解释器。重启按钮先显示确认与取消，不在首次点击时销毁场景。

## 装配与公开接口

- `MainGame._create_debug_components()` 在聚落、奶茶店或洞穴的玩家、出生点、镜头及剧情服务初始化完成后调用，正式初始化不依赖 Console。
- 洞穴布局覆盖仍由 `CaveDemoController` 在绑定移动查询前应用，其余洞穴工具在初始化后启动；`SettlementPreview` 仍独立管理聚落全图和动线。
- `DeveloperTools.configure(set_multiplier, get_multiplier, panel, context = {})` 保留原来的两个 Callable 接口。重绑断开旧面板与 StoryDirector 连接，保留目标已有倍率。倍率能力缺失返回 ERR_UNCONFIGURED，但观察仍可使用；工具关闭或面板无效时返回 ERR_UNCONFIGURED 并隐藏。
- context 注入 `status`、`respawn`、`restart`、`can_control`、`can_restart` Callables，以及 `state`、`story`、`ui_manager` 场景服务。角色与重启能力分别判定；当前宿主不是 SceneTree.current_scene 时禁用重启。
- `PlayerController` 统一公开 `set_speed_multiplier()`、`get_speed_multiplier()`、`get_movement_speed()` 与 `teleport_to()`，CavePlayer 和 ShopPlayer 继承；瞬移停止现有运动，各子类刷新自己的镜头。Console 不写玩家、GameState 或剧情私有变量。
- `StoryDirector.get_runtime_status()` 返回独立只读数据，不调用 Loader，不改变 dispatch。`bind_story_director()` 可重新绑定，先断开旧源；工具离树时解除订阅。
- UIManager 的可选 `uses_native_gui_input()` view 接口允许 Console 使用原生 OptionButton/TextEdit 导航；既有业务界面继续使用原来的输入路由。
- 通用 controller 挂 Systems，使用 Always；panel 挂 DebugLayer（50）。Release 不创建通用或场景专用调试节点，不注册 F3 action，不处理调试请求；MCPRuntimeProbe 的 Release 策略保持不变。

## 试玩与自动验收

1. F5 默认启动 `src/core/settlement.tscn`，或打开 `src/core/main.tscn` 按 F6 单独启动奶茶店宿主。
2. 开始时不应出现 Console。F3 打开，观察三个页签；调速后关闭，移动速度应改变，回出生点应停止残余运动且镜头重新对齐。
3. 展开面板时按住移动、E、P、M、F2；角色和底层 UI 不响应。Esc/F3 关闭后恢复控制。在店铺弹窗、剧情 busy 或暂停中打开/关闭，原状态应保留。
4. 在真实宿主正常触发剧情后查看事件日志；默认没有加载事件时应显示“未加载剧情事件”。展开角色页的重启确认，取消不重启，确认重启保留 GameState。
5. 洞穴宿主运行 `tests/verify_main_game.gd` 验证：F2 墙体、M 全图/跟随、移速及地图查询保持既有行为。`cave_demo.tscn` 本身是需要注入依赖的组件。裸 `src/levels/milkTea/milk_tea_shop.tscn` 同样只是地图资源；独立游戏宿主为 `src/core/main.tscn`。

```sh
godot --headless --path . --script tests/verify_developer_tools.gd
godot --headless --path . --script tests/verify_debug_build.gd
godot --headless --path . --script tests/verify_main_game.gd
godot --headless --path . --script tests/verify_ui_manager.gd
godot --headless --path . --script tests/verify_story_director.gd
godot --headless --path . --script tests/verify_player.gd
godot --headless --path . --script tests/verify_milk_tea_shop.gd
godot --headless --path . --script tests/verify_settlement.gd
godot --headless --path . --script tests/verify_gameplay_bridge.gd
```

`verify_debug_build.gd` 分别组装聚落、奶茶店和洞穴；Debug 还逐一关闭工具重测，并实际确认重载奶茶店宿主。Release 分支保留出生、移动、无调试节点、MCP 停止、按键无效及布局参数无效的断言。洞穴通行数以保存的 TileMap 地板为基准，替代旧测试已经过时的 6309 个 JSON 格子假设。

真实构建验收须在临时项目副本中纳入 tests 脚本和 fixtures，使用匹配版本模板分别导出 Debug/Release，再以 `--script res://tests/verify_debug_build.gd -- --original-layout` 运行。正式导出仍排除 tests。编辑器关闭工具或编辑器加载 Release PCK 都不等同于运行 Release executable。

2026-10-17 验证：工具 33 项、构建/输入 97 项、洞穴架构 72 项、UIManager 47 项、StoryDirector 163 项、Gameplay Bridge 246 项，以及玩家、奶茶店、聚落测试通过，三个 Console 页签已用有渲染的 Godot 窗口截图检查。额外 `verify_cinematic_integration.gd` 为 286 项、5 失败；未修改 HEAD 的临时副本复现相同五项：角色移动终点、顾客移动受阻及关联开场完成/时长/阶段断言。本次保留原断言，不调整地图与剧情来掩盖失败。机器缺少 export templates，真实 Debug/Release 导出运行尚未覆盖。

## 本次使用的官方文档

- [4.7 InputEvent 分发](https://docs.godotengine.org/en/4.7/tutorials/inputs/inputevent.html)：`_input` 先于 GUI 和 `_unhandled_input`；使用 InputMap actions，消费事件阻止专用调试工具接收。
- [4.7 Input](https://docs.godotengine.org/en/4.7/classes/class_input.html)：Input 单例轮询不受事件 handled 状态影响，因此玩家移动另外通过宿主合并锁禁止。
- [4.7 Window.window_input](https://docs.godotengine.org/en/4.7/classes/class_window.html#class-window-signal-window-input)：下拉 popup 独占输入时仍能接收 F3 并关闭 Console。
- [4.7 Control 焦点与 mouse_filter](https://docs.godotengine.org/en/4.7/classes/class_control.html)：modal 捕获鼠标，焦点管理沿用 UIManager，文本和选项保留原生交互。
- [4.7 暂停与 process mode](https://docs.godotengine.org/en/4.7/tutorials/scripting/pausing_games.html)：Console 使用 Always，在原有暂停中仍可查看；不擅自解除全局暂停。
