# Gameplay Bridge

StoryDirector 仍是唯一演出执行器。GameplayBridge 只衔接既有短事件与玩法结果，
复用 GameState、Signal、UIManager；MainGame 仍是唯一输入锁管理者。
ActorDirector、CameraDirector、DialogueManager、ShopInteraction 路由没有改职责。

## Phase 数据与接口

`configure(director, ui, tea = null)`：TeaMaking 可选。
`load_phases(path)` 校验后替换有效配置；旧 v1 JSON 不变。

v1 保留 `id/after_event/stage/recipe/completion_flag/next_event`，只在有 TeaMaking 的宿主使用。
v2 仅把 recipe 替换为：

```json
"completion": {"flag": "shop.order_001_delivered", "allow_existing": true}
```

其余五字段保持不变。flag 是业务输入，completion_flag 是 Bridge 输出，不可同名。
source 策略必须显式填写；不支持表达式、变量比较或未实现的业务 command。

- `allow_existing: true`：已存在的业务结果可完成目标，但仍须等待前置成功、阶段、UI 与暂停。
- false：阶段激活时若源为 false 则 armed，后续变 true 才通过；提前 true 需先观察到 false。
- 当前活跃等待的 flag/armed 保存在 GameState.variables 的 `<phase_id>.bridge_wait`，
  输出结果保存在 completion_flag。普通取消/切阶段清除等待凭据；reset/restore 不回写快照。
- restore 后仍须宿主显式 load_phases；已记录的完成或已保存的 armed 等待可恢复，不重播已完成事件。
- state_changed 只重查活跃等待并缓存结果；process 边界持久化并请求续播，避免在同步回调栈重入或污染 restore。
- modal/暂停/Director busy 在请求前等待。真正请求后若仍被拒绝（含 ERR_BUSY），
  只发一次 continuation_failed 并保留 last_error；取消后不自动重试。宿主可明确重建等待。

TeaMaking 增加 `has_recipe`、`has_session`、`is_completed_session` 查询。
既有 recipe_completed 还必须对应实际完成的当前 session，外部 begin 重开后需重建等待。
不允许仅用匹配 token 的伪造 Signal 完成目标。

## 真实订单接线

TeaProduction 只负责制作，成功后成品入共享库存；其 get_completed_count 是兼容制作进度，不代表已交付。TaskDelivery 在指定 NPC 的真实交付中经 GameState.commit_delivery 提交业务事实：

- `shop.order_001_delivered`：任务配置的首单交付事实；后续订单需配置自己的交付任务。重复通知幂等。
- `shop.orders_completed`：已成功交付订单的最高计数（制作不计数），取 max，避免重进场景降低快照中进度。

失败配方、缺库存、关闭 UI、TeaMaking 完成不改变上述事实。
UI 中固定配方 Demo session 与真实订单控件互斥显示，防止误认它们是一套业务。
固定队列仅作兼容。当前共享库存、制作、钱包、订单回执、动态杯和图鉴都进入 GameState 完整 v4 内存快照，普通切场景保留；尚无文件存档。阶段订单由真实目录 / 接单事实提供，Bridge 不创建订单实例或编造完成。

## 正式入口与示例

F5 从标题新游戏进入奶茶店，Day1ShopController 加载正式 S01–S02 的三个 flag phase，依次等待 day1.human_settled、day1.goblin_settled、day1.group_settled。聚落也绑定 GameState 的共享 TeaProduction / 库存和 flag Bridge，店门通过 SceneTravel 双向连接。Day1ChapterController 负责后章交接，但其 Story / Dialogue / phases 当前为空；不自动加载 Demo 或完成后四阶段。

F6：`src/debug/gameplay_bridge/order_bridge_demo.tscn`。
开场 → WASD 到订单板 E 调查 → 推进教学 → 再开订单板接取首单 → 奶茶制作台 E →
按单带入配方并制作入库 → Esc 关闭 → 胖哥布林按 E 交付 → 无模态 / 暂停阻挡时自动续播。详见 [成品交付](../gameplay/task_delivery.md)。
完成后再次调查订单板出现一次特殊对白，再次则回原订单 UI。
旧 `gameplay_bridge_demo.tscn` 继续验证固定顺序配方，不代表真实订单。

源稿、映射与验证规范见 [编排工作流](../guides/story_authoring_workflow.md#自动演出与玩家操作gameplay-bridge)。
运行 `tests/verify_gameplay_bridge.gd`、`verify_story_director.gd`、`verify_tea_production.gd`、
`verify_game_state.gd`、`verify_ui_manager.gd` 与 `verify_settlement.gd`。

实现核对 Godot 4.7 [Signal](https://docs.godotengine.org/en/4.7/classes/class_signal.html) 的同步通知、
[Node](https://docs.godotengine.org/en/4.7/classes/class_node.html) 的暂停/退出与自动断连；
依据原 GameState restore 的实际信号顺序（state_changed 在 state_restored 前），
避免在状态替换过程中写入新的剧情结果。


## 历史验证记录（2026-10-17，Godot 4.7.2）

以下数量与文件范围保留该批次历史；本轮文档同步未重新运行。当前候选检查按[验证分级](../../tests/AGENTS.md)选择。

通过：Gameplay Bridge 246 项（含 v1/v2 原加载器、源稿散列/映射与实际按钮交付、
提前/失败/重复/过期 session、UI/暂停、重入/拒绝/取消、快照、连续两阶段和聚落接线）、
StoryDirector 163 项、GameState 120 项、UIManager 47 项、AudioManager 64 项、
TeaProduction、MilkTeaShop、Settlement。图形窗口跑完整 Bridge 测试，并检查制作弹窗截图。

未通过的既有检查：cinematic 集成 286 项中 5 项失败；当前改动前 HEAD `c19e7c4` 的临时导出副本
复跑得到相同 5 项失败，涉及原玩家移动断言、顾客移向 `(1470, 560)` 时受阻及连带时长/后续步骤/到达断言。
`verify_story_authoring.py` 在原 cinematic 开场首例被同一顾客路线阻断。
因此旧编排全套检查未完整通过；本次新旧 Bridge 与新增订单源稿映射验证通过，未改地图或原失败断言。

本次修改的 runtime 文件仅 `src/core/story/gameplay_bridge.gd`、`src/core/main.gd`、
`src/gameplay/milk_tea/tea_making.gd`、`src/UI/milk_tea/shop_popup.gd`。
扩展既有 `verify_gameplay_bridge.gd`、`verify_story_director.gd`、`verify_tea_production.gd`；
新增 order_bridge_demo 的 Markdown、Story/Dialogue/Phase JSON、Beat 清单及独立 Debug 宿主。
更新本说明、story_authoring_workflow、story_authoring_commands、story_director、basic_tea_production 文档。
没有修改 StoryDirector、ShopInteraction、TeaProduction 或 GameState 的 runtime 实现。
