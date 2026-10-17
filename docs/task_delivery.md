# 成品携带与指定 NPC 交付

本次改动将正式 TeaProduction 的制作与交付分开。两个正式入口均可直接验收：F6 `src/core/main.tscn`，或 F5 当前聚落 `src/core/settlement.tscn`。

## 数据与复用

任务继续使用 TaskCatalog / TaskJournal，状态仍来自 GameState 的激活与完成条件。交付任务只新增以下配置（每次交付固定一件）：

```json
"delivery": {
  "order_id": "order_001",
  "product_id": "pearl_milk_tea",
  "target_object_id": "fat_goblin"
}
```

`order_id` 在任务目录中唯一；成品必须是菜单中 `category = "product"` 的物品；NPC ID 直接复用 SettlementCharacter.actor_id。交付完成条件使用既有 `complete_when` 的 flag，不通过伪造剧情完成事件结算。

原奖励字段仅用于展示，没有实际结算器。按本次确认，在现有 `rewards` 中增加可选的 `items`，复用 WarehouseInventory 发放物品，不引入货币或新奖励框架：

```json
"rewards": {"text": "糖浆 × 1", "items": {"syrup": 1}}
```

首单配置沿用 `shop.first_order`，完成事实为 `shop.order_001_delivered`。一杯珍珠奶茶交给胖哥布林后返还糖浆一份，数值仅为可验证的教学配置。没有 `items` 的任务不产生库存奖励。TaskJournal 的奖励投影仍只显示原 text/reveal_when，不暴露结算数据。

## 执行流程

1. MainGame 装配 Systems/TaskDelivery，注入原目录、Journal、GameState 和共享库存。订单板打开成功后接取已发布的交付任务；已有 StoryDirector 路由继续优先。
2. TeaProduction 验证当前制作订单、配方和原料，原子扣料并增加成品。`get_completed_count()` 保持原 API，代表制作杯数；它不再代表交付次数，不再写任务完成事实。
3. MainGame 为现有 NPC 挂接通用 InteractionPoint，将 actor_id 交给原 ShopInteraction 分派。点位随 NPC 移动，NPC 场景没有交付规则。店铺入口增设一个胖哥布林，聚落复用已有角色。
4. TaskDelivery 检查订单、成品、NPC、任务 active 状态与交付回执，之后通过 `WarehouseInventory.try_exchange` 一次校验扣除与奖励的全部数量和容量。
5. 提交期间暂缓库存信号，扣成品、加奖励、`GameState.apply_flags` 一次写完成 flag 与 `delivery.<order_id>.completed` 回执。通知期间保留提交锁。任何库存或状态监听器第一次回调时都能读取完整的成品、奖励和任务结果。
6. MainGame 仅从成功交付回执更新原 `shop.orders_completed` 最高值。重复制作信号不推进任务。现有 GameplayBridge 继续等待 `shop.order_001_delivered`，遵守原来的暂停/弹窗/剧情取消规则。

回执存在 GameState 的原 flags 中，不是第二套任务状态。它防止重复交付、组件重建后发奖，以及外部单独撤销任务完成 flag 后再次领奖。重置整个 GameState 或同时恢复旧 GameState/库存快照仍是显式回档；本次不新增存档文件或跨场景库存生命周期。库存继续沿用原场景会话和快照接口。

`TaskJournal.get_task()` 按当前事实即时投影，避免它在 GameState 同步回调中的连接顺序影响交付校验。HUD 的常规 projection_changed 订阅保持原样。

## 关键拒绝条件

- 未配置或未知订单、成品 ID 不匹配、交付对象不匹配。
- 任务未激活、已完成，或已有交付回执。
- 成品不足、奖励物品不存在、奖励数量非法或容量溢出。
- 制作或交付的同步回调重入。

前述失败不扣物品、不写完成事实、不发奖励。目录完整校验后替换；配置阶段验证成品类别和奖励引用。奖励容量不足时整笔拒绝，可腾出库存后重试。若批量事实提交被拒绝，则在库存通知前恢复原快照。

## 试玩

1. 订单板按 E 接单：显示珍珠奶茶与胖哥布林，任务 HUD 显示交付目标。
2. 制作台选择红茶、奶精、珍珠，糖浆自动加入，点击“制作并入库”。原料各减一，成品库存加一，任务保持 active。
3. Esc 关闭后可以移动；仓库可查看成品。前往其他 NPC 按 E，成品不减少，任务不变。
4. 携带成品到胖哥布林按 E，显示交付成功：成品减一，糖浆奖励加一，任务 completed，HUD 隐藏。
5. 关闭弹窗后再次按 E：安全拒绝，库存和奖励保持不变。

#002、#003 的原配方选择、扣料、制作队列及结束保护保留，改为分别入库椰果茉莉奶茶和原味奶茶；当前示例只发布 #001 交付任务。TeaMaking 的剧情 Demo 会话不变，仍不等同于正式库存制作。

## 修改文件

| 范围 | 文件 |
| --- | --- |
| 交付系统 | `src/core/tasks/task_delivery.gd`、对应 `.uid` |
| 原任务/状态 | `src/core/tasks/task_catalog.gd`、`src/core/tasks/task_journal.gd`、`src/core/game_state.gd` |
| 制作/库存 | `src/gameplay/milk_tea/tea_production.gd`、`src/gameplay/milk_tea/warehouse_inventory.gd` |
| 数据 | `src/resources/tasks/tasks.json`、`src/resources/milk_tea/basic_menu.tres`、`src/resources/milk_tea/ingredient_definition.gd` |
| 装配/店铺 NPC | `src/core/main.gd`（仅本功能部分）、`src/core/main.tscn` |
| UI | `src/UI/milk_tea/shop_ui.gd`、`shop_popup.gd`、`production_panel.gd`、`warehouse_panel.gd` |
| 测试 | `tests/verify_task_delivery.gd`、对应 `.uid`；`verify_task_system.gd`、`verify_tea_production.gd`、`verify_warehouse_inventory.gd`、`verify_gameplay_bridge.gd`、`verify_milk_tea_shop.gd` |
| 试玩说明 | `src/debug/tasks/task_demo.gd`、本文、`docs/basic_tea_production.md`、`docs/milk_tea_mvp.md`、`docs/warehouse_inventory.md`、`docs/gameplay_bridge.md`、`docs/design/task_system.md` |

## 实测结果

Godot 4.7.2.stable.official.ed1daf0bf。本次实际执行：

| 验证 | 结果 |
| --- | --- |
| `verify_task_delivery.gd`（headless） | 69 项，0 失败 |
| 同一交付测试（Metal Forward+ 图形模式，`-- --capture`） | 69 项，0 失败；已检查两个入口的订单/交付截图 |
| `verify_task_system.gd` | 196 项，0 失败 |
| `verify_warehouse_inventory.gd` | 131 项，通过 |
| `verify_gameplay_bridge.gd` | 248 项，0 失败 |
| `verify_game_state.gd` | 120 项，0 失败 |
| `verify_interaction_feedback.gd` | 46 项，0 失败 |
| `verify_ui_manager.gd` | 47 项，0 失败 |
| `verify_main_game.gd` | 73 项，0 失败（含同期已提交的年鉴功能） |
| `verify_tea_production.gd` | PASS |
| `verify_milk_tea_shop.gd` | PASS，含实际物理空间从出生点到交付 NPC 的可达性 |
| `verify_settlement.gd` | PASS |
| `git diff --check` | 通过 |

交付测试包含非法配置、错误对象/成品、未激活、缺货、成品容量已满、奖励容量已满、同步重入、组件重建/快照恢复、同一 NPC 的多订单与多项奖励，以及两个正式场景中实际 E 键和制作按钮操作。截图在 `.godot/delivery_*_board.png` / `delivery_*_success.png`，不提交缓存。

命令格式：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/<测试名>.gd`。图形交付验收去掉 `--headless` 并增加 `-- --capture`。GameplayBridge 的临时 JSON 写入需要 Godot `user://` 目录可写；放行目录写入后已通过完整回归。沙箱下的 macOS 证书读取提示不影响上述业务断言；没有将失败的受限试跑计作通过。

## Godot 4.7 官方依据

- [Object.ConnectFlags](https://docs.godotengine.org/en/4.7/classes/class_object.html#enum-object-connectflags)：普通信号立即回调，因此提交前准备完整数据，并在通知期间防重入。
- [Object.set_block_signals](https://docs.godotengine.org/en/4.7/classes/class_object.html#class-object-method-set-block-signals)：库存通知暂缓至任务事实提交后，保留调用前的信号阻塞设置。
- [Dictionary.duplicate](https://docs.godotengine.org/en/4.7/classes/class_dictionary.html#class-dictionary-method-duplicate)：嵌套字典/数组需要深拷贝以隔离配置、快照与外部查询。
