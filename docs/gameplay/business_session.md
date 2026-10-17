# 统一经营会话

## 状态归属

沿用唯一的 `GameState` Autoload，不新增管理器或文件存档。GameState 按需创建并持有 `WarehouseInventory` 和 `TeaProduction` 子节点；两个正式入口 `src/core/main.tscn`、`src/core/settlement.tscn` 绑定同一份服务，场景销毁不影响经营数据。

| 数据 | 唯一归属 | 生命周期 |
| --- | --- | --- |
| 原料、成品数量、发现及已知属性 | GameState 持有的 WarehouseInventory | 整局会话 |
| 固定教学订单队列的已制作 ID 前缀 | GameState 持有的 TeaProduction | 整局会话；制作与交付分开 |
| 接单、交付回执、完成计数、剧情阶段、单次事件、手札 | GameState 的原有 flags / variables / completed_events | 整局会话 |
| 任务展示、交付协调器、弹窗、焦点、角色位置、演出动作、TeaMaking 顺序投料 | 场景本地节点 | 场景重建时重新创建；剧情结果从 GameState 投影 |
| 食材目录、默认库存、三笔教学订单 | basic_menu.tres | 静态配置，不写入运行时数据 |

当前没有钱包、购买结算或磁盘存档实现，设计文档 `docs/development/system_design_review.md` 也将其列为待设计能力。本次不伪造余额、收款或购买接口；已有物品奖励仍通过原库存交易接口结算。

## 生命周期与接口

| 操作 | 调用 | 结果 |
| --- | --- | --- |
| 首次启动进程 / F5 / F6 | Autoload 首次创建，首次查询初始化服务 | 默认库存、空成品、第一笔制作订单、空剧情事实 |
| 新游戏 | `GameState.start_new_game() -> Error` | 原子恢复整局默认值；保留服务对象和 UI 订阅，发 state_reset 取消本地演出/教学；调用方另行选择场景和出生位置 |
| 场景切换 / 退出再进店铺 | 原 `SceneTree.change_scene_to_*` | 全部经营数据和剧情事实保留，只重新绑定显示 |
| 场景重载 / 开发面板重启 | 原 `reload_current_scene()` | 与场景切换相同，不调用新游戏接口 |
| 关闭应用再启动 | 当前没有自动读档 | 新进程使用默认状态，不承诺跨进程保存 |
| 显式恢复完整快照 | `GameState.restore_state(snapshot) -> Error` | 整体校验、整体替换，发 state_restored；不重播已完成事件或再次发奖 |
| 兼容旧清理调用 | `GameState.reset_state() -> bool` | 重置整个会话；已经默认则静默返回 false。禁止用于普通场景切换 |

钱包交易、制作或交付提交及整体恢复的同步通知期间，new game / restore 返回 `ERR_BUSY`，reset 返回 false。整体替换通知期间还禁止库存、制作及剧情 setter 写入，防止监听器把刚恢复的快照覆盖。显式 start_new_game 即使已经默认也发 reset，确保取消尚无持久结果的本地演出。

```gdscript
var inventory := GameState.get_warehouse_inventory()
var production := GameState.get_tea_production()
# 实际制作使用 UI 展示的订单 ID，旧请求不会重复制作。
var result := production.make_drink(recipe, displayed_order_id)
# 场景协调器通过原 TaskDelivery 接单和交付。
game.get_task_delivery().accept_order("order_001")
game.get_task_delivery().deliver_to("fat_goblin")
```

原 `add_ingredient` / `try_consume` / `try_exchange` 管理物品，`make_drink` 原子扣料并入库成品；TaskDelivery 原子提交扣成品、奖励、完成事实、回执及 `shop.orders_completed`。计数不再依赖 MainGame 的通知回调，离开场景不会漏结算。制作 changed 不写交付事实。订单板订阅 TaskJournal 投影变化，restore / new game 后不缓存旧交付要求。

## 快照边界

GameState 的原生 Variant 快照升级至 `schema_version = 2`，包含原剧情字段及 `business.inventory`、`business.production.completed_order_ids`、`economy`（余额、库存、商人余量及交易/领奖回执）。`business.inventory` 和 `economy.inventory` 指向同一库存的独立副本，恢复时必须完全一致；缺少任一整体字段的旧/局部快照拒绝恢复，避免重置钱包或经营进度。库存沿用自己的 v1 子格式；制作 ID 必须为静态队列的连续前缀，拒绝重复、乱序、未知 ID 和缺少经营数据的局部快照。所有数据先校验，失败不改变任何状态或发通知。相同快照静默恢复。

v1 GameState 只有剧情数据，不能判断其对应的库存、成品或订单状态，因此拒绝恢复，不猜测或清空经营进度。旧快照迁移及应用重启后自动恢复时机仍待产品确认；仓库目前没有正式存档文件需要迁移。子服务快照只供组件验证和事务使用，完整营业恢复必须调用 GameState 的整体接口。原生 `var_to_bytes` / `bytes_to_var` 保留数值类型；普通 JSON 不能直接保证 GameState 的原生类型约定。

## 验证与试玩

`tests/verify_business_session.gd` 使用真实 `change_scene_to_file` / `reload_current_scene`，覆盖离开店铺、重进、聚落共用、携带成品交付及重建后重复交付拒绝；覆盖 UI 刷新、完整快照往返、非法/旧版本原子拒绝、新游戏和通知重入。

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/verify_business_session.gd
```

F6 入口：`src/core/main.tscn`。订单板 E 接单，制作台制作首杯，仓库确认成品 1 杯；F3 开发面板确认“重启”后，制作台仍显示 #002，仓库仍有首杯。到胖哥布林 E 交付，成品减一、糖浆奖励加一；再次重启后不能重复领奖。停止运行再 F6 是新进程，显示默认库存和 #001。显式新游戏及跨场景往返由上述脚本覆盖。

2026-10-17，Godot 4.7.2 headless 验证：会话 45 checks、GameState 122、仓库 131、交付 69、StoryDirector 163、Gameplay Bridge 248、手札 65、开发工具 33、MainGame 73 全部通过；原制作与店铺移动/交互验证也 PASS。剧情测试使用已有 user:// 临时文件权限完成，不新增存档流程。未执行人工画面试玩；本次没有改动布局或素材。

## Godot 4.7 依据

- [Autoload](https://docs.godotengine.org/en/4.7/tutorials/scripting/singletons_autoload.html)：在场景之前加载，跨场景持有数据。
- [SceneTree](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html)：切换/重载替换 current_scene；测试等待 scene_changed 后访问重建的场景。
- [Object 信号](https://docs.godotengine.org/en/4.7/classes/class_object.html#class-object-method-set-block-signals)：同步通知前提交完整数据，暂缓组件信号并保留原阻塞状态；恢复时保持服务身份，已有 UI 订阅继续有效。

2026-10-17 合并钱包事务后，Godot 4.7.2 headless 回归：GameState 124、仓库 131、钱包 108、经营会话 48、交付 69、MainGame 73、任务 196、手札 65、StoryDirector 163、Gameplay Bridge 248 项均通过，TeaProduction 也 PASS。新增覆盖同一库存身份、制作/恢复通知期间钱包重入拒绝及不一致库存快照原子拒绝；手札测试临时文件改为跨平台 user:// 路径。未执行人工画面试玩。
