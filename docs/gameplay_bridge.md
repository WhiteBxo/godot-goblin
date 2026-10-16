# Gameplay Bridge

`MainGame` 为奶茶店组装 `TeaMaking` 与 `GameplayBridge`，默认不加载剧情或目标。
宿主加载原 v1 Story/Dialogue JSON 后调用 `get_gameplay_bridge().load_phases(path)`。
示例数据见 `src/resources/story/gameplay_bridge_demo_phases.json`，编排规则见
[自然语言剧情编排工作流](story_authoring_workflow.md#自动演出与玩家操作gameplay-bridge)。

流程：前段短事件成功结束 → GameState stage + completed_events 准入 → 开放配方 session →
TeaMaking recipe_completed → 写完成 flag → 等所有 modal 关闭/暂停解除 → 原 StoryDirector 请求后段事件。
Bridge 每帧只检查衔接条件，不执行 steps。MainGame 保留唯一输入锁管理，未改 Actor/Camera 职责。

当前目标只支持一杯 `pearl_milk_tea`，依次加入 `tea`、`milk`、`pearls`。
顺序错误清空杯进度，关窗保留当前 session；制作不涉及库存、收益、订单队列或计时。
制作按钮仅当前目标有效且制作台弹窗可处理输入时生效。完成后按钮禁用，弹窗由玩家关闭。
目标 ID/session/完成标记隔离前后两次制作，前一杯不能满足后一阶段。

GameState 沿用已有 stage、命名空间 flag 和 once 事件账本，不新增存档 Schema。
reset/restore、外部阶段变化和依赖移除会取消旧 session/待续播。
restore 后由宿主显式 load_phases 恢复：已完成目标不必重做；未完成杯不保存中间进度。
后段取消或非 BUSY 拒绝不会自动重试；后者发 `continuation_failed`，并保存 `last_error`。
BUSY 属暂时阻挡，保留目标等后续帧。加载无效 phase 保留此前有效配置。

成功事件只清理所属 SFX，BGM 留在 AudioManager 继续播放；取消仍清理该事件未交接的音乐。
后续音乐步骤、显式 stop_bgm、AudioManager 场景退出仍控制音乐生命周期。

## 试玩

F6 打开 `src/debug/gameplay_bridge/gameplay_bridge_demo.tscn`：

1. 推进开场对白，确认演出中不能移动。
2. WASD 到奶茶制作台，E 打开；依次加入红茶、牛奶、珍珠。
3. 可先试错顺序，或中途 Esc 退出再 E 继续。错误不会提前续播。
4. 完成后弹窗仍开着，音乐持续；Esc 关闭后自动出现后段对白。
5. 对白结束，恢复移动且不会重复触发。P 暂停时也不会提前续播。

音乐为既有 AudioDemoTones 的原创合成测试音。Demo 不改正式第一天剧情。

## 验证记录（Godot 4.7.2）

- `tests/verify_gameplay_bridge.gd`：真实 MainGame、原 Loader/StoryDirector、真实交互点及按钮回调；
  验证源稿 SHA-256、映射、多个玩法阶段、提前/乱序/重复/过期完成、弹窗、暂停、
  reset/restore、取消（含同步 event_started 取消）、资源拒绝、依赖退出和 BGM。
- Gameplay Bridge 最终 156 项通过；图形窗口亦执行完整流程并截图检查制作弹窗。
- StoryDirector 147、GameState 120、UIManager 47、AudioManager 64 项通过。
- 旧 `verify_cinematic_integration.gd` 为 286 项中 5 项失败；改动前 HEAD 导出副本使用同样配置
  重跑得到相同失败：原玩家移动断言与顾客移向 `(1470, 560)` 时受阻，以及连带时长/阶段/到达断言。
  `verify_story_authoring.py` 首个旧开场 case 也被同一顾客路线阻断。未修改该地图或放宽原测试。

实现核对 Godot 4.7 官方 API：[Signal](https://docs.godotengine.org/en/4.7/classes/class_signal.html)、
[Node 暂停与生命周期](https://docs.godotengine.org/en/4.7/classes/class_node.html)、
[AudioStreamPlayer](https://docs.godotengine.org/en/4.7/classes/class_audiostreamplayer.html)。
