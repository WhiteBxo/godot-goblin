# 采集点与任务物资提交

本轮把聚落里预留给夜间采集的 8 个纯 Marker 变成可用的采集点，并让任务可以提交材料清单，而不是只能交一件成品。

## 数据与职责

| 部分 | 位置 | 职责 |
| --- | --- | --- |
| `GatherPoint` | `src/gameplay/gathering/gather_point.gd`、`gather_point.tscn` | 只保存静态配置与接近判定；不缓存已采状态、不读 GameState |
| `GatheringService` | `src/gameplay/gathering/gathering_service.gd` | 注册表、可用性求值、原子提交、信号 |
| 采集点实例 | `src/levels/settlement/settlement_map.tscn` 的 `GatherPoints` | 8 个 `NightGather0..7`，坐标取自 `StoryAnchors/night_gather_0..7` |
| 物品 | `src/resources/milk_tea/basic_menu.tres` | 醒神菇 `insomnia_mushroom`，`origin=otherworld`、`category=material`、默认 0 份且未发现 |
| 任务 | `src/resources/tasks/tasks.json` | `tavern.insomnia_order`（占位数值）通过 `delivery.items` 提交材料 |

`GatherPoint` 继承既有 `InteractionPoint`，因此沿用 `ShopInteraction` 的唯一选择/派发契约：距离与朝向打分、E 键、`availability_changed`、`interacted`。它不覆盖 `interact()`，也不覆盖 body 进出回调。

```gdscript
@export var item_id: String = ""          # 必须是目录中的非 product 物品
@export_range(1, 2147483647, 1) var amount: int = 1
@export_enum("once", "daily") var refresh_mode: String = "daily"
@export var required_flag: String = ""    # 空 = 无条件；夜间填 world.phase.night
```

`is_available()` 每次调用都向注入的 gate（`GatheringService.is_harvestable`）查询，不做缓存；没有注入时 fail-closed。`GatherPoint` 与 `GatheringService` 之间只有单向依赖：服务持有并绑定点位。

## 状态键

采集状态落在 `GameState` 的 flags / variables；采集本身没有新增顶层字段。当前完整快照已由后续经营与自由配方升级为 v4，库存为 v3，见[经营会话](business_session.md#快照边界)。

| 模式 | 键 | 类型 | 语义 |
| --- | --- | --- | --- |
| `once` | `gather.<interaction_id>.harvested` | flag | 该点永久采尽 |
| `daily` | `gather.<interaction_id>.day` | int variable | 上次采集的 `current_day` |
| 两种 | `gather.total.<item_id>` | int variable | 该物品累计采集量，供任务目标显示进度 |

`interaction_id` 是存档面向的稳定 ID：改 ID 等于重置该点。键名都满足 `GameState._is_namespaced_key()`（至少两段、每段合法标识符），因此随 `to_dict()` / `restore_state()` 一起往返，`start_new_game()` 后自然复位。

`gather.total.*` 只记录累计采集量，不因交付或制作消耗而回退；库存数量不能代替它当任务进度。

## 可用性规则

```text
未就绪 / 正在提交        → 不可用
点位未注册或已释放        → 不可用
required_flag 非空且为 false → 不可用（昼夜条件）
once 且 harvested flag 为 true → 不可用
daily 且 day >= current_day   → 不可用（当天已采）
```

- 夜间点声明 `required_flag = "world.phase.night"`；正式写入经 DayPhase 同时更新 world.phase 与夜晚镜像，夜转昼推进一天。没有自动流逝时间，见[日程](../systems/day_phase.md)。
- `daily` 的可采性只依赖 `current_day`，已有 DayPhase 换天可使日刷新点重新可采；任务期限仍未实现。
- 采集后点位在下一次查询立即不可选中，`ShopInteraction` 不再显示提示。

## 原子提交

`harvest(id)` 与 `TaskDelivery.try_submit()` 使用同一套提交协议：

1. 预检就绪、重入、注册表、可用性；失败不触碰状态。
2. 预检库存容量（目录与数量已在 `configure()` 校验，这是库存唯一还可能拒绝的原因）。
3. `GameState.begin_business_transaction()` 取得会话锁；期间交付、制作、重置都会被拒绝。
4. 阻塞库存与状态信号 → `try_exchange({}, {item_id: amount})` 入共享库存（同时置 discovered）→ 写 `day` / `total` → 最后写 `once` flag。
5. 任一步失败：恢复库存快照、回滚已写变量、恢复信号阻塞状态、结束事务。
6. 成功：恢复信号状态后手动各发一次 `state_changed`、`inventory.changed`，再 `harvested.emit(...)`，最后释放事务锁。

一次入库只发一次通知；观察者回调时库存、天数、累计量和 flag 都已是完整结果，且不能重入。

## 失败条件

| 场景 | 结果 |
| --- | --- |
| 库存已满 | 拒绝，不写任何事实 |
| 点位未注册 / 已释放 | 拒绝，`has_point` 为 false |
| `required_flag` 未设置 | 点不可选；直接调用 `harvest()` 也拒绝 |
| 当天已采 / 已永久采尽 | 拒绝，库存不变 |
| 观察者在 `harvested` 中重入 | `_committing` + 事务锁双重拒绝 |
| 快照恢复 | flags/variables/库存一起恢复；耗尽点仍不可采 |
| 配置非法 | `configure()` 返回 `ERR_INVALID_DATA`，旧注册表保持不变 |

## 任务材料提交

以下为固定成品与材料两种需求示例；当前还支持互斥的 drink 自由饮品需求，详见[自由订单](free_tea_recipes.md#通用订单)：

```json
"delivery": {"order_id": "order_001", "product_id": "pearl_milk_tea", "target_object_id": "fat_goblin"}
"delivery": {"order_id": "order_insomnia_01", "items": {"insomnia_mushroom": 3}, "target_object_id": "tavern"}
```

- 材料订单复用同一份扣减、奖励、完成 flag 与 `delivery.<order_id>.completed` 回执，重复提交仍被拒绝。
- `TaskDelivery.get_requirement()` 把 JSON 数字统一转成 int（库存 API 只接受 int）。
- 新入口 `try_submit(order_id, target_object_id)`；旧 `try_deliver(order_id, product_id, target_object_id)` 保留为兼容包装（材料订单传空字符串）。
- 材料与制作共用一份库存，所有扣减都经过 `WarehouseInventory.try_exchange` 的整组校验，先扣先得、不产生负数。

占位任务 `tavern.insomnia_order` 要求 3 份醒神菇交给 `tavern`，奖励糖浆 × 2；`reveal_when` 使用夜晚 flag，白天订单板不显示。该条只在 tutorial 目录中加载，正式 day1 目录不包含它；数值不能作为 Day 2 代购委托的已批准规则。

## 试玩

打开 `src/core/settlement.tscn` 后 F6（新进程默认 tutorial；Debug 下 F4 切换昼夜）。F5 是标题与正式 Day 1，不加载本示例委托：

1. F4 切到夜晚，左上状态栏显示「夜晚」。
2. 前往任意夜光菌丛按 E：提示「采集成功：醒神菇 × 1（现有 1）」。
3. 在原地点再按 E：不再弹出采集结果；换一处点位可继续采。
4. 打开订单板：出现「酒馆的醒神菇委托：醒神菇 × 3 → 酒馆人物」，选择该单并点击“接取订单”。
5. 集满 3 份后到酒馆人物按 E：醒神菇 −3、糖浆 +2、任务完成；再次按 E 只显示拒绝，库存不变。
6. `night_gather_6`、`night_gather_7` 是一次性点位，采尽后换天也不会恢复。

Release 不创建 `SettlementPreview`，F4 无效；正式昼夜由 DayPhase 及调用它的剧情 / 世界协调层提供。

## 验证

以下是 2026-10-17 采集实现批次的历史记录，本轮文档更新未复跑。

项目引擎 Godot 4.7.2。实际执行（Windows，headless）：

| 验证 | 结果 |
| --- | --- |
| `tests/verify_gathering.gd` | PASS，81 项 |
| `tests/verify_task_delivery.gd` | PASS，69 项 |
| `tests/verify_task_system.gd` | PASS，196 项 |
| `tests/verify_settlement.gd` | PASS（48,623 个碰撞采样点） |
| `tests/verify_warehouse_inventory.gd` | PASS，133 项 |
| `tests/verify_business_session.gd` | PASS，48 项 |
| `tests/verify_game_state.gd` | PASS，124 项 |
| `tests/verify_tea_production.gd` | PASS |
| `tests/verify_milk_tea_shop.gd` | PASS |
| `tests/verify_gameplay_bridge.gd` | PASS，248 项 |
| `tests/verify_main_game.gd` | PASS，73 项 |
| `tests/verify_debug_build.gd` | PASS，97 项 |
| `tests/verify_interaction_feedback.gd` | PASS，46 项 |

```sh
Godot --headless --path . --script tests/verify_gathering.gd
```

`verify_gathering.gd` 覆盖：配置校验与注册表不变、昼夜门控、daily/once 刷新、通知次数、库存满与重复采集、观察者重入、快照往返与新游戏、材料订单的 schema 与提交回执、材料与制作争抢库存、任务进度投影，以及真实聚落场景里 E 键采集与酒馆交付。

`tests/verify_task_delivery.gd` 的重复订单用例改为按目录长度取最后一条：正式目录已从 1 条任务增加到 2 条。

## 修改文件

| 范围 | 文件 |
| --- | --- |
| 采集 | `src/gameplay/gathering/gather_point.gd`、`gather_point.tscn`、`gathering_service.gd`（含 `.uid`） |
| 装配 | `src/core/main.gd`、`src/levels/settlement/settlement_map.gd`、`settlement_map.tscn` |
| 交付 | `src/core/tasks/task_catalog.gd`、`task_delivery.gd` |
| 数据 | `src/resources/tasks/tasks.json`、`src/resources/milk_tea/basic_menu.tres`、`ingredient_definition.gd`、`assets/ui/milk_tea/ingredients/insomnia_mushroom.svg`（含 `.import`） |
| 调试 | `src/debug/settlement/settlement_preview.gd`、`project.godot`（`debug_toggle_night`，F4） |
| 测试 | `tests/verify_gathering.gd`、`tests/verify_task_delivery.gd` |

## Godot 4.7 官方依据

- [Area2D](https://docs.godotengine.org/en/4.7/classes/class_area2d.html)：采集点沿用 Area2D + 圆形 reach，靠 `body_entered` / `body_exited` 判断玩家是否在范围内。
- [Object.set_block_signals](https://docs.godotengine.org/en/4.7/classes/class_object.html#class-object-method-set_block_signals)：提交期间暂缓库存与状态通知，成功后只发一次。
- [Callable](https://docs.godotengine.org/en/4.7/classes/class_callable.html)：点位通过注入的 Callable 查询可用性，避免 `GatherPoint` 反向依赖服务。
- [String.is_valid_identifier](https://docs.godotengine.org/en/4.7/classes/class_string.html#class-string-method-is-valid-identifier)：点位 ID、物品 ID 与状态键段都用它校验。
- [Dictionary.duplicate](https://docs.godotengine.org/en/4.7/classes/class_dictionary.html#class-dictionary-method-duplicate)：配置与快照查询返回副本，调用者不能改写共享数据。
