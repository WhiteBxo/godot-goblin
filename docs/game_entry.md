# 启动、整局新游戏与返回标题

F5 进入 `src/UI/title/title_menu.tscn`。标题显示 Godot Goblin、新游戏、退出游戏，复用项目 Theme。默认聚焦新游戏，鼠标、Tab、Enter / 空格可操作。新游戏进入既有 `src/core/main.tscn` 奶茶店，不自动加载或播放任何剧情、Dialogue 或 Gameplay Bridge phase。聚落仍可打开 `src/core/settlement.tscn` 后 F6 试玩。

## 导航与生命周期

`GameEntry`（`src/core/game_entry.gd`）是普通 RefCounted 工具类，不新增 Autoload：

| 接口 | 行为 |
| --- | --- |
| `start_new_game(tree: SceneTree) -> Error` | 先加载并校验奶茶店 PackedScene，再调用唯一 GameState 的 `start_new_game()`，成功后切换 |
| `return_to_title(tree: SceneTree) -> Error` | 切换到标题，不重置会话；成功切换后解除暂停 |

调用方在延后执行的 UI handler 中调用导航，避免物理/GUI 派发期间切场景。菜单从收到请求时禁用按钮；共享导航锁从重置前保持至 `scene_changed`，拒绝重复调用及 reset 信号中的同步重入。失败时恢复按钮和焦点，显示简短错误，技术原因记录到日志。

场景必须存在、类型为 PackedScene 且能够实例化，才可重置整局。GameState 拒绝重置时不切场景；场景切换请求返回错误时恢复重置前的完整快照。入口仅使用已有数据边界，不实现文件存档或演出恢复。

| 操作 | 结果 |
| --- | --- |
| 新游戏 | 清空旧剧情 flags/变量/阶段/完成事件、任务/交付回执、见闻录、钱包/交易记录、库存/成品和制作进度；恢复原菜单默认值及奶茶店出生点 |
| 暂停 → 返回标题 | 销毁当前 MainGame 及本地演出、对白、音频、UI；不改 GameState；标题不提供继续入口 |
| 再次新游戏 | 重置上一局全部数据后重新进入奶茶店 |
| F6 直接运行场景 | 沿用场景原有行为，不额外调用整局重置；停止进程再 F6 自然创建新会话 |
| F3 开发面板重启 / 普通场景重载 | 仍仅重建场景，保留整局数据 |

暂停菜单通过 `title_requested` signal 请求 MainGame 导航，不自行访问业务状态。UIManager 离树释放其暂停与模态，其他服务按现有离树规则取消。标题入口也调用 `DebugRuntime.apply_release_policy()`，Release 从停留标题时便停止 MCPRuntimeProbe 轮询；不修改插件源码。

本功能不修改剧情原稿/JSON、地图、订单或任务配置，不产生 Day 1 阶段或完成事实。标题不播放音乐，没有继续游戏、存档、设置、确认弹窗或结尾界面。

## 验证与试玩

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_game_entry.gd
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tests/verify_game_entry.gd -- --capture
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_game_entry.gd -- --verify-quit
```

集成测试使用真实标题、奶茶店和聚落，覆盖键盘/鼠标按钮、重复请求、忙碌/错误目标拒绝、旧会话完整重置、默认出生与可操作性、没有剧情自动启动、暂停覆盖真实对白/演出后返回、场景服务释放、重复新游戏没有订阅累积及直接运行/重载保留数据。退出按钮单独运行，预期打印 `GAME_ENTRY_QUIT` 后正常退出。图形截图在 `.godot/game_entry/`，不提交缓存。

手动试玩：F5 → 默认新游戏焦点 → Enter 进入奶茶店 → 移动并制作 → Esc / P 暂停 → 返回标题 → 新游戏。应恢复第一笔制作和初始库存；返回标题时原对白、声音与暂停均不残留。直接 F6 店铺及 F3 重启继续保留原场景生命周期。

2026-10-17 使用 Godot 4.7.2：入口 headless 65 项、Metal Forward+ 图形模式 69 项（包含四张截图保存检查）均为 0 失败；已查看两种窗口尺寸的标题和暂停截图。独立退出按钮命令正常退出。实际默认入口命令行启动无脚本错误。

相关 headless 回归全部通过：MainGame 73 项、UIManager 47 项、BusinessSession 48 项、DebugBuild 97 项、GameState 124 项。入口测试故意制造两次 Busy，日志警告为预期失败路径；沙箱 headless 的 macOS 系统证书读取诊断与玩法断言无关。当前没有安装导出模板，未执行真实 Release 导出，Debug 下关闭工具不等于 Release 验收。

## Godot 4.7 官方依据

- [SceneTree](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html)：场景切换替换 current_scene，`scene_changed` 在新场景初始化后发出；不在已离树的调用方等待后再访问节点。
- [Autoload](https://docs.godotengine.org/en/4.7/tutorials/scripting/singletons_autoload.html)：GameState 跨场景保留，因此仅显式新游戏重置整局。
- [Control](https://docs.godotengine.org/en/4.7/classes/class_control.html)：使用原生按钮焦点与 GUI 输入，容器排版适配视口。
- [Viewport.push_input](https://docs.godotengine.org/en/4.7/classes/class_viewport.html#class-viewport-method-push-input)：鼠标集成测试以视口局部坐标派发真实 GUI 事件，避免整数缩放造成坐标偏差。
