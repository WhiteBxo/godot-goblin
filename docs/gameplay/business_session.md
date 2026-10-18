# 统一经营会话

## 状态归属

沿用唯一的 GameState Autoload；磁盘持久化由独立[存档系统](../systems/save_system.md)负责。GameState 持有 WalletTransactions，后者持有唯一 WarehouseInventory；TeaProduction 使用这份库存。奶茶店与聚落通过公开 getter 绑定相同服务，场景销毁不影响会话数据。

| 数据 | 唯一归属 | 生命周期 |
| --- | --- | --- |
| 钱包余额、商人余量、交易与领奖回执 | GameState 持有的 WalletTransactions | 整局会话 |
| 原料份数与已用次数、固定成品、配方杯、图鉴、剧情物品及发现属性 | WalletTransactions 持有的 WarehouseInventory | 整局会话 |
| 经营配置及订单队列已制作 ID 前缀 | GameState 的 profile_id 与 TeaProduction | 整局会话；制作与交付分开 |
| 接单、交付回执、批次完成、剧情阶段、单次事件、见闻录 | GameState 的 flags / variables / completed_events | 整局会话 |
| 任务展示、交付协调器、弹窗、焦点、角色与演出动作 | 场景本地节点 | 重建后由会话投影 |
| 食材目录、默认库存、订单配置 | basic_menu.tres / day1_menu.tres | 静态资源 |

F5 进入标题菜单，“新游戏”进入 src/core/main.tscn 并启用 Day 1 五单经营配置；F6 可直接运行该店铺，原三单教学使用 src/debug/story/legacy_shop.tscn。完整流程见 [Day 1 前两阶段](day_01_stages_01_02.md)。钱包沿用已有事务接口；正式五单均为 H01，每杯收入 3G，实体投币按 10G 面额直接扣钱包。自由饮品交付也支持按售价结算，但正式自由订单和购买 UI 尚未发布。

## 生命周期与接口

| 操作 | 调用 | 结果 |
| --- | --- | --- |
| 首次启动进程 / F5 / F6 | Autoload 初始化，宿主选择配置 | 默认库存、空成品与剧情事实；正式店铺选择 day1 |
| 配置选择 | select_business_profile(profile) | 相同配置幂等；存在经营或剧情进度时禁止隐式切换 |
| 新游戏 | start_new_game() -> Error | 重置当前所选配置的整局数据；保留服务对象与 UI 订阅，发 state_reset |
| 场景切换 / 重载 / 开发面板重启 | SceneTree 原接口 | 保留当前配置与全部经营事实，只重新绑定显示 |
| 关闭应用再启动 | 标题选择“继续游戏” | 从最近安全自动检查点恢复完整会话；不恢复逐帧位置 |
| 显式完整恢复 | restore_state(snapshot) -> Error | 整体校验替换，包括配置；发 state_restored，不重播已完成事件或发奖 |
| 兼容清理调用 | reset_state() -> bool | 重置整个会话；已经默认则静默返回 false，禁止用于普通场景切换 |

钱包交易、制作、交付及整体恢复的同步通知期间，new game / restore 返回 ERR_BUSY，reset 返回 false。整体替换期间同时禁止库存、制作与剧情 setter 写入，防止监听器覆盖刚提交的数据。显式新游戏即使已经默认也会发 reset，以取消尚未产生持久结果的本地演出。

make_drink 原子扣料并入库成品，不写交付事实。TaskDelivery 保留原公开接口，通过 GameState.commit_delivery 一次提交扣成品、货款或物品奖励、任务完成、稳定回执、批次进度及 shop.orders_completed，全部完成后通知观察者。弹窗按实际已提交的资金与物品变化显示所得，失败整体不变。订单板订阅 TaskJournal，恢复后不会缓存旧目标。

## 快照边界

GameState 原生 Variant 完整快照为 schema_version = 8，包含剧情字段、business.profile_id、business.inventory、business.production.completed_order_ids / formula_requests 及 economy。库存子快照为 v6，含原料开封次数、配方杯数 drinks 和首次发现 encyclopedia；规则见[自由调配](free_tea_recipes.md#快照与迁移)。economy v3 包含余额、库存、商人余量、交易/领奖回执、配方固定报价和首次爆品奖励。business.inventory 和 economy.inventory 是同一库存的独立副本，恢复时必须完全一致；制作 ID 必须为所选配置的连续前缀。

完整快照包含 `task_results` 持久终态。旧完整 v2–v7 按版本和字段迁移，兼容两个分支的旧布局；历史实体币折算一次，已有报价与领奖回执保留。旧未定价自由杯作为历史资料保留，读档不抽价、不补发奖。只有剧情的 v1、缺失必要字段、非法金额、未知物品及损坏快照整体拒绝，原会话不变。具体迁移边界见 [GameState](../systems/game_state.md) 与[自由配方](free_tea_recipes.md#快照与迁移)。正式入口在声明的安全检查点自动保存，通过标题继续游戏恢复；已验证 20 个两天及交接边界的独立进程恢复。

子服务快照只用于组件验证与内部事务，完整经营恢复必须调用 GameState。原生 var_to_bytes / bytes_to_var 保留数值类型，普通 JSON 不能直接保证 GameState 的原生类型约定。

Day 1 从最近已完成的演出边界重建人物、订单与交互；未完成段从段首重试。已完成事件不重播，交付有独立回执保护。演出取消后提供「继续剧情」。不保存逐帧动画位置。

## 验证与试玩

- tests/verify_business_session.gd：真实 change_scene_to_file / reload_current_scene、共用库存、制作与交付、完整快照、重入与新游戏。
- tests/verify_day1_stages_01_02.gd：正式五单 UI 流程、全部源稿对白、五个边界的快照及实际场景重载、经济原子失败、取消续播、见闻录与音频。
- F5 或 main.tscn 的 F6：试玩正式 Day 1。旧三单组件试玩使用 legacy_shop.tscn 的 F6。
- 测试命令：Godot --headless --path . --script tests/verify_business_session.gd；图形集成去掉 --headless 并加 -- --capture。

## Godot 4.7 依据

- [Node 生命周期与处理模式](https://github.com/godotengine/godot/blob/4.7/doc/classes/Node.xml)：场景重建与暂停处理边界。
- [SceneTree](https://github.com/godotengine/godot/blob/4.7/doc/classes/SceneTree.xml)：切换或重载 current_scene 后等待 scene_changed。
- [Object 信号](https://github.com/godotengine/godot/blob/4.7/doc/classes/Object.xml)：同步通知前提交完整数据，恢复时保留服务身份与已有订阅。
