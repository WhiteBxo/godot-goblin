# 成品携带与指定 NPC 交付

> 当前交付先检查 GameState.can_complete_task，成功同事务锁存 completed；失败、过期和取消均不可重新接取或交付。回执与持久终态一起快照恢复，见[日程与任务结果](../systems/schedule_and_task_results.md)。下文旧接口说明中的 flags 不再是唯一结果字段。

正式 TeaProduction 的制作与交付分开。F5 进入标题菜单并开始 Day 1；F6 `src/core/main.tscn` 或 `src/core/settlement.tscn` 可独立运行宿主。当前订单板、制作和 HUD 操作见[订单系统](order_system.md)。

`TaskDelivery.cancel_order(order_id)` 取消已接取且配置 `allow_cancel: true` 的订单，经 GameState 持久记录 `cancelled` 终态；不改库存、余额、交付回执或完成计数，拒绝重复取消、交付和重新接取。成功后发送 `order_cancelled`；BusinessScheduler 仅允许普通散客以取消替代交付完成离店，剧情客组仍遵守原来的交付条件。`is_order_cancelled(order_id)` 只读查询持久结果，读档后不重放取消信号。订单板开放第二天三张普通散客单及可选特调，独立教学的三张散客单也允许取消。

## 数据与复用

任务继续使用 TaskCatalog / TaskJournal，状态仍来自 GameState 的激活与完成条件。交付任务支持四种互斥需求，`product_id`、`items`、`uses` 与 `drink` 必须恰好出现一个。`uses` 明确按次扣料，仅接受共享会话库存，由 `get_use_requirement()` 查询；份数仍用 `items`。下面列静态成品与物资示例；自由饮品的要求、价格及原子结算见[第二期自由调配](free_tea_recipes.md#通用订单)：

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

整份材料与成品共用 `get_requirement()`，统一返回 `{item_id: 数量}`（JSON 数字在此转成 int，库存 API 只接受 int），`try_submit(order_id, target_object_id, drink_id = "")` 是规范入口，共享会话由 `GameState.commit_delivery()` 提交；`uses` 从 `get_use_requirement()` 单独查询并按次扣除，不能按整份解释。独立教学库存仍使用一次 `WarehouseInventory.try_exchange(需求, 奖励)`。旧的 `try_deliver(order_id, product_id, target_object_id)` 保留为兼容包装：成品订单校验 `product_id` 一致，材料订单要求传入空字符串。

`rewards.items` 通过共享库存结算物品，`rewards.money` 经已有钱包事务结算收入；自由饮品订单未显式配置金额时使用配方售价。物品示例：

```json
"rewards": {"text": "糖浆 × 1", "items": {"syrup": 1}}
```

tutorial 首单配置沿用 `shop.first_order`，完成事实为 `shop.order_001_delivered`。一杯珍珠奶茶交给胖哥布林后返还糖浆一份，数值仅为可验证的教学配置。没有 `items` 的任务不产生库存奖励。TaskJournal 的奖励投影仍只显示原 text/reveal_when，不暴露结算数据。

### 散客订单（营业玩法）

`src/resources/tasks/day1_daily_orders.json` 保留旧三款教学订单（10G／单），仅在显式 `debug.teaching_orders` 为真时开放。正式五单结束不会解锁该池。`tests/verify_daily_orders.gd` 覆盖这项隔离、接单、空库存拒绝、10G 教学结算、重复交付和订单板报酬。

正式散客在 `src/resources/tasks/day2_stages_01_05.json`：第二天三名普通客各可点一杯 H01，3G／杯，经 `BusinessScheduler` 和 `CustomerVisit` 入店、等待与离店。它们复用 `accept_order`、`try_submit` 和稳定交付回执；四组剧情客完成后可直接关店，已接普通单必须先交付。普通客也可雇一人执行专款代购，与饮品交付分别结算。`verify_two_day_flow.gd -- --ordinary-order` 覆盖接普通单后无法关店、交付后可以关店的真实分支。

两套数据都是一次性任务，当前未提供每日无限刷新。

### 第二天的特调订单

`day2_stages_01_05.json` 里另有五张可选特调单（`day2.orders.special_*`）。它们**不进营业计划**，因此不参与剧情客组的交单判定，也不会挡住关店；只有在对应顾客站在店里时才出现在订单板（`ChapterGameplay.OPTIONAL_ORDERS` 一处配置顾客、客组与到账反馈）。接单后该客组会等这杯特调，交付或从订单板「放弃此单」后才离店——和既有的辛辣试饮单同一套机制。金额按已确认配方售价结算，不写死 3G。

| 单据 | 顾客 | 需求 | 常见做法 | 售价 |
| --- | --- | --- | --- | --- |
| `day2_special_sour` | 围观者甲 | 发酵味 | 奶茶底 ＋ 苔痕青 | 4G |
| `day2_special_herbal` | 议论长老的顾客乙 | 草木气息 | 奶茶底 ＋ 醒神菇 | 16–19G |
| `day2_special_wine` | 格里芬使者 | 酒香 | 奶茶底 ＋ 老火烧 | 7–9G |
| `day2_special_smoky` | 打听酒馆的顾客乙 | 烟熏味 | 奶茶底 ＋ 炽舌椒 | 16–19G |
| `day2_special_spicy` | 歇脚的散客 | 辛辣 | 老火烧 ＋ 炽舌椒 | 23–28G |

五张单在一个白天里的典型收入是 66–79G（同杯多放哥布林原料还能更高），加上试饮单约 73–88G；普通散客仍是 3G／杯。`tests/verify_day2_special_orders.gd` 覆盖上板、接单、确认报价、制作、交付与到账金额。

原料来源（`uses_per_portion` 都是 5，采一次够五杯）：

| 原料 | 来源 | 份数 | 刷新 |
| --- | --- | --- | --- |
| 苔痕青 | 聚落 `night_gather_0`、`night_gather_6`（夜间） | 2 + 1 | 每日 |
| 炽舌椒 | 聚落 `night_gather_3`（昼夜均可） | 1 | 每日 |
| 醒神菇 | 聚落 `night_gather_5`（昼夜均可）／市场 50G 一整份 | 1 | 每日 |
| 老火烧 | 首日 S04 胖哥布林赠 2 次用量；不足时章节菜单可补领 1 份 | 2 | 一次性 |

因此这套单子不依赖随机掉落，也不需要额外的采集中间流程：首日夜路顺路就能带走苔痕青与炽舌椒，醒神菇同一个图层的野外点位随时可采。测试里先用 `publish_stage` + `request_arrival` 让顾客真的走进店里，再上板、接单、制作、交付，不需要手工摆 NPC。

## 第二天的醒神菇救治

第二天购买醒神菇后，完成配方对话会激活 `day2_recovery_drink`：醒神菇、荧绿薄荷糖浆、红斑咬木，且必须加冰。制作只入库；到胖哥布林身边交互或在菜单交付，才扣一杯、完成代购并写入救治事实。已购菇时旧原料交付不可用，避免跳过制作；未发现配方的第三天代购仍沿用原料交付。

两位售菇摊主各有一次配方对话，发现奖励全局只发一次。右侧摊主出售红斑咬木；若救治未完成且没有合格成品，店内菜单可将缺少的救治原料各补到一次用量。最终返店仍可自由制作、出门补货和存档，完成交付后才进入休息。未购菇的路线沿用原来的章末流程。

旅程回顾按债务任务的持久终态判断待续事项；赌场债务已免除或已偿还时不再显示欠款。

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
