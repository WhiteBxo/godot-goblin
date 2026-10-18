# 成品携带与指定 NPC 交付

正式 TeaProduction 的制作与交付分开。F5 进入标题菜单并开始 Day 1；F6 `src/core/main.tscn` 或 `src/core/settlement.tscn` 可独立运行宿主。当前订单板、制作和 HUD 操作见[订单系统](order_system.md)。

## 数据与复用

任务继续使用 TaskCatalog / TaskJournal，状态仍来自 GameState 的激活与完成条件。交付任务支持三种互斥的需求，`product_id`、`items` 与 `drink` 必须恰好出现一个。下面列静态成品与物资示例；自由饮品的要求、价格及原子结算见[第二期自由调配](free_tea_recipes.md#通用订单)：

```json
"delivery": {
  "order_id": "order_001",
  "product_id": "pearl_milk_tea",
  "target_object_id": "fat_goblin"
}
```

```json
"delivery": {
  "order_id": "order_insomnia_01",
  "items": {"insomnia_mushroom": 3},
  "target_object_id": "tavern"
}
```

`order_id` 在任务目录中唯一；`product_id` 必须是菜单中 `category = "product"` 的物品；`items` 是 `{物品 ID: 正整数}`，物品只需存在于目录中，可一次提交多种材料多份；NPC ID 直接复用 SettlementCharacter.actor_id。交付完成条件使用既有 `complete_when` 的 flag，不通过伪造剧情完成事件结算。

材料需求与成品需求共用同一套结算：`get_requirement()` 把两种配置统一成 `{item_id: 数量}`（JSON 数字在此转成 int，库存 API 只接受 int），`try_submit(order_id, target_object_id, drink_id = "")` 是规范入口，扣减仍由一次 `WarehouseInventory.try_exchange(需求, 奖励)` 完成。旧的 `try_deliver(order_id, product_id, target_object_id)` 保留为兼容包装：成品订单校验 `product_id` 一致，材料订单要求传入空字符串。

`rewards.items` 通过共享库存结算物品，`rewards.money` 经已有钱包事务结算收入；自由饮品订单未显式配置金额时使用配方售价。物品示例：

```json
"rewards": {"text": "糖浆 × 1", "items": {"syrup": 1}}
```

tutorial 首单配置沿用 `shop.first_order`，完成事实为 `shop.order_001_delivered`。一杯珍珠奶茶交给胖哥布林后返还糖浆一份，数值仅为可验证的教学配置。没有 `items` 的任务不产生库存奖励。TaskJournal 的奖励投影仍只显示原 text/reveal_when，不暴露结算数据。

## 执行流程

1. MainGame 装配 Systems/TaskDelivery，注入原目录、Journal、GameState 和共享库存。打开订单板只查看；每单点击“接取订单”后调用 `accept_order()`，重复接取返回 `ERR_ALREADY_EXISTS`。已有 StoryDirector 路由继续优先。
2. TeaProduction 验证配方和原料，原子扣料并增加成品。正式 UI 使用 `craft()` 自由安排订单顺序。`get_completed_count()` 保持旧队列已制作前缀长度，不代表所有自由制作杯数、交付次数或完成事实。
3. MainGame 为现有 NPC 挂接通用 InteractionPoint，将 actor_id 交给原 ShopInteraction 分派。点位随 NPC 移动，NPC 场景没有交付规则。正式 S01–S02 使用各自的真实顾客，tutorial 首单使用胖哥布林；聚落复用已注册角色。
4. `deliver_to(target_id, preferred_order_id = "")` 优先选择已接取且可交付的追踪订单，否则按目录顺序选择。未接单不阻挡已接单。TaskDelivery 检查需求、NPC、接取状态、回执、库存与奖励容量。
5. 正式共享会话经 `GameState.commit_delivery()` 原子提交物品、钱包、完成 flag 和 `delivery.<order_id>.completed` 回执；独立测试库存保留交换与批量 flag 提交路径。通知期间保留提交锁，任何监听器第一次回调时都能读取完整结果。
6. TaskDelivery 在同一提交中从成功回执更新 `shop.orders_completed` 最高值，随后统一通知库存和事实变化。计数不依赖场景回调。重复制作信号不推进任务。现有 GameplayBridge 继续等待 `shop.order_001_delivered`，遵守原来的暂停/弹窗/剧情取消规则。

回执存在 GameState 的原 flags 中，不是第二套任务状态。它防止重复交付、组件重建后发奖，以及外部单独撤销任务完成 flag 后再次领奖。GameState 已统一持有跨场景库存和制作服务，整体快照同时恢复物品、订单和回执；仅显式新游戏或恢复完整旧快照改变整局进度，详见 [统一经营会话](business_session.md)。未新增存档文件。

`TaskJournal.get_task()` 按当前事实即时投影，避免它在 GameState 同步回调中的连接顺序影响交付校验。HUD 的常规 projection_changed 订阅保持原样。

## 关键拒绝条件

- 未配置或未知订单、成品 ID 不匹配、交付对象不匹配。
- 任务未激活、已完成，或已有交付回执。
- 成品或材料不足、奖励物品不存在、奖励数量非法或容量溢出。
- 制作或交付的同步回调重入。

前述失败不扣物品、不写完成事实、不发奖励。目录完整校验后替换；配置阶段验证成品类别、材料物品引用和奖励引用。奖励容量不足时整笔拒绝，可腾出库存后重试。若批量事实提交被拒绝，则在库存通知前恢复原快照。

材料与制作共用一份库存：两边都走 `try_exchange` 的整组校验，先扣先得，不会把数量扣成负数，详见 [采集与任务物资提交](gathering.md)。

## 试玩

1. 在 `src/debug/story/legacy_shop.tscn` 到订单板按 E 查看，选珍珠奶茶并点击“接取订单”，HUD 显示下一步。正式 Day 1 的顾客和奖励以当前剧情阶段为准。
2. 制作台默认按订单制作，自动带入配方，点击“制作 1 杯并入库”。原料各减一，成品库存加一，任务保持 active。
3. Esc 关闭后可以移动；仓库可查看成品。前往其他 NPC 按 E，成品不减少，任务不变。
4. 携带成品到胖哥布林按 E，显示短暂交付反馈：成品减一，糖浆奖励加一，任务 completed；HUD 切到其他有效订单或当前主线。
5. 再次按 E：安全拒绝，库存和奖励保持不变，无需关闭交付结果弹窗。

#002、#003 的旧制作队列 API 及快照保留兼容；正式订单界面不据此判断进度。上述 legacy 示例只发布 #001 交付任务，正式 Day 1 使用自己的剧情订单目录。TeaMaking 的剧情 Demo 会话不变，仍不等同于正式库存制作。

## 修改文件

| 范围 | 文件 |
| --- | --- |
| 交付系统 | `src/core/tasks/task_delivery.gd`、对应 `.uid` |
| 材料需求 | `task_catalog.gd` 的 `delivery.items` 校验；`task_delivery.gd` 的 `get_requirement` / `try_submit`（详见 [采集与任务物资提交](gathering.md)） |
| 原任务/状态 | `src/core/tasks/task_catalog.gd`、`src/core/tasks/task_journal.gd`、`src/core/game_state.gd` |
| 制作/库存 | `src/gameplay/milk_tea/tea_production.gd`、`src/gameplay/milk_tea/warehouse_inventory.gd` |
| 数据 | `src/resources/tasks/tasks.json`、`src/resources/milk_tea/basic_menu.tres`、`src/resources/milk_tea/ingredient_definition.gd` |
| 装配/店铺 NPC | `src/core/main.gd`（仅本功能部分）、`src/core/main.tscn` |
| UI | `src/UI/milk_tea/shop_ui.gd`、`shop_popup.gd`、`crafting_panel.gd`、`order_crafting_page.gd`、`free_crafting_panel.gd`、`warehouse_panel.gd` |
| 测试 | `tests/verify_task_delivery.gd`、对应 `.uid`；`verify_task_system.gd`、`verify_tea_production.gd`、`verify_warehouse_inventory.gd`、`verify_gameplay_bridge.gd`、`verify_milk_tea_shop.gd` |
| 试玩说明 | `src/debug/tasks/task_demo.gd`、本文、`docs/gameplay/basic_tea_production.md`、`docs/levels/milk_tea_mvp.md`、`docs/gameplay/warehouse_inventory.md`、`docs/systems/gameplay_bridge.md`、`docs/gameplay/task_system.md` |

## 早期实现实测记录

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
