# 启动、整局新游戏与返回标题

F5 进入 `src/UI/title/title_menu.tscn`。标题显示 Godot Goblin、新游戏、退出游戏，复用项目 Theme。默认聚焦新游戏，鼠标、Tab、Enter / 空格可操作。新游戏进入 `src/core/main.tscn` 奶茶店，启用 Day 1 正式经营配置并开始开场演出，详见 [Day 1 前两阶段](../gameplay/day_01_stages_01_02.md)。原三单无剧情教学使用 `src/debug/story/legacy_shop.tscn`。聚落仍可打开 `src/core/settlement.tscn` 后 F6 试玩。

## 导航与生命周期

`GameEntry`（`src/core/game_entry.gd`）是普通 RefCounted 工具类，不新增 Autoload：

| 接口 | 行为 |
| --- | --- |
| `start_new_game(tree: SceneTree) -> Error` | 先加载并校验奶茶店 PackedScene，再调用唯一 GameState 的 `start_new_game()`，成功后切换 |
| `return_to_title(tree: SceneTree) -> Error` | 切换到标题，不重置会话；成功切换后解除暂停 |
| `travel_to_scene(tree: SceneTree, destination: Node) -> Error` | 接收已预检的离树目标，复用导航锁；门口进出保留会话与暂停边界，详见[店铺与聚落进出](../systems/scene_travel.md) |

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

本功能不修改剧情原稿/JSON、地图、订单或任务配置，不产生 Day 1 阶段或完成事实。标题没有继续游戏、存档、设置、确认弹窗或结尾界面。

## 标题音乐

标题场景的 `TitleMusic` 使用 `assets/audio/music/start.ogg`，导入 `loop=false`（禁用循环），不设置节拍循环。Ogg 导入器使用 `loop` 布尔选项；WAV 才使用 `Loop Mode` 枚举。

进入标题后自动从头播放，2 秒线性音量淡入至 -8 dB，通过现有 Music 总线路由。自然播放结束后由单次 Timer 等待 15 秒，再从头播放并淡入；计时与淡入淡出不受游戏 time_scale 影响。播放器的 `target_volume_db`、`fade_in_seconds`、`fade_out_seconds` 和 ReplayTimer 的 `wait_time` 可在 Inspector 调整。

点击新游戏或退出时，禁用按钮并以 0.45 秒淡出后执行操作；静默间隔中离开则立即执行。新游戏失败恢复按钮、焦点和音乐淡入。播放器、计时器与 Tween 随标题释放，返回标题时重新开始，不遗留重播任务。音频来源见[许可证说明](../../assets/audio/LICENSE.md)。

局部自动验证：`godot --headless --path . --script res://tests/verify_title_music.gd`，使用真实 Ogg 的自然结束信号和完整 15 秒等待，覆盖淡入、重播、失败恢复及离树清理。听感试玩：F5 或 F6 运行标题场景，试听入场与重播淡入，点击新游戏或退出观察短淡出；在游戏暂停菜单返回标题应从曲首重新播放。

API 依据：[AudioStreamPlayer](https://docs.godotengine.org/en/4.7/classes/class_audiostreamplayer.html) 的自然结束 `finished` 信号与线性音量；[Ogg 导入器](https://docs.godotengine.org/en/4.7/classes/class_resourceimporteroggvorbis.html) 的 `loop=false`；[Timer](https://docs.godotengine.org/en/4.7/classes/class_timer.html) 单次计时；[Tween](https://docs.godotengine.org/en/4.7/classes/class_tween.html) 的节点生命周期绑定。

## 验证与试玩

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_game_entry.gd
/Applications/Godot.app/Contents/MacOS/Godot --path . --script res://tests/verify_game_entry.gd -- --capture
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_game_entry.gd -- --verify-quit
```

集成测试使用真实标题、奶茶店和聚落，覆盖键盘/鼠标按钮、重复请求、忙碌/错误目标拒绝、旧会话完整重置、默认出生与可操作性、Day 1 开场及其输入锁、暂停覆盖真实对白/演出后返回、场景服务释放、重复新游戏没有订阅累积及直接运行/重载保留数据。退出按钮单独运行，预期打印 `GAME_ENTRY_QUIT` 后正常退出。图形截图在 `.godot/game_entry/`，不提交缓存。

手动试玩：F5 → 默认新游戏焦点 → Enter 进入奶茶店 → 推进开场对白 → 按订单指引制作 → Esc / P 暂停 → 返回标题 → 新游戏。应恢复第一笔制作和初始库存；返回标题时原对白、声音与暂停均不残留。直接 F6 店铺及 F3 重启继续保留原场景生命周期。

2026-10-17 使用 Godot 4.7.2：入口 headless 65 项、Metal Forward+ 图形模式 69 项（包含四张截图保存检查）均为 0 失败；已查看两种窗口尺寸的标题和暂停截图。独立退出按钮命令正常退出。实际默认入口命令行启动无脚本错误。

相关 headless 回归全部通过：MainGame 73 项、UIManager 47 项、BusinessSession 48 项、DebugBuild 97 项、GameState 124 项。入口测试故意制造两次 Busy，日志警告为预期失败路径；沙箱 headless 的 macOS 系统证书读取诊断与玩法断言无关。当前没有安装导出模板，未执行真实 Release 导出，Debug 下关闭工具不等于 Release 验收。

## Godot 4.7 官方依据

- [SceneTree](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html)：场景切换替换 current_scene，`scene_changed` 在新场景初始化后发出；不在已离树的调用方等待后再访问节点。
- [Autoload](https://docs.godotengine.org/en/4.7/tutorials/scripting/singletons_autoload.html)：GameState 跨场景保留，因此仅显式新游戏重置整局。
- [Control](https://docs.godotengine.org/en/4.7/classes/class_control.html)：使用原生按钮焦点与 GUI 输入，容器排版适配视口。
- [Viewport.push_input](https://docs.godotengine.org/en/4.7/classes/class_viewport.html#class-viewport-method-push-input)：鼠标集成测试以视口局部坐标派发真实 GUI 事件，避免整数缩放造成坐标偏差。

合并验收：标题新游戏进入正式 Day 1；普通场景进出和重载保留原经营配置。Godot 4.7.2 headless 入口测试 66 项通过，旧教学验收通过独立 legacy_shop 宿主执行。
