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

TeaProduction 无剧情依赖、无新剧情 API。MainGame 监听原 changed，读取 get_completed_count。
只有配方/库存校验成功并提交进度后才增长。组装层先消费本场景已观察的序号，再写：

- `shop.order_001_delivered`（后续同为 002、003）：固定订单序号交付事实，重复通知幂等。
- `shop.orders_completed`：固定队列已完成的最高进度，取 max，避免重进场景降低快照中进度。

失败配方、缺库存、关闭 UI、TeaMaking 完成不改变上述事实。
UI 中固定配方 Demo session 与真实订单控件互斥显示，防止误认它们是一套业务。
当前固定队列没有跨天唯一订单标识；TeaProduction 库存/中间进度也没有实现持久化。
本次只保存既有 GameState 结果，不冒充完整经营存档。新的一天/动态订单需先有对应实际业务。

## 正式入口与示例

正式 `src/core/settlement.tscn` 组装无 TeaMaking/TeaProduction 的 flag Bridge，
可等待已有聚落业务事实；不会自动加载任何 Demo，也不凭空添加制作能力。
真实奶茶教学示例在店铺场景运行；正式聚落进店、转场和 Day 1 发布尚未接入，不在本次编造。

F6：`src/debug/gameplay_bridge/order_bridge_demo.tscn`。
开场 → WASD 到订单板 E 调查 → 推进教学 → 奶茶制作台 E →
选择红茶/奶精/珍珠，糖浆自动加入 → 制作并交付 → Esc 关闭 → 自动续播。
完成后再次调查订单板出现一次特殊对白，再次则回原订单 UI。
旧 `gameplay_bridge_demo.tscn` 继续验证固定顺序配方，不代表真实订单。

源稿、映射与验证规范见 [编排工作流](story_authoring_workflow.md#自动演出与玩家操作gameplay-bridge)。
运行 `tests/verify_gameplay_bridge.gd`、`verify_story_director.gd`、`verify_tea_production.gd`、
`verify_game_state.gd`、`verify_ui_manager.gd` 与 `verify_settlement.gd`。

实现核对 Godot 4.7 [Signal](https://docs.godotengine.org/en/4.7/classes/class_signal.html) 的同步通知、
[Node](https://docs.godotengine.org/en/4.7/classes/class_node.html) 的暂停/退出与自动断连；
依据原 GameState restore 的实际信号顺序（state_changed 在 state_restored 前），
避免在状态替换过程中写入新的剧情结果。


## 本次验证记录（2026-10-17，Godot 4.7.2）

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
