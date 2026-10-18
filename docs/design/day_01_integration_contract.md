# Day 1 正式剧情与业务配置约定

核对日期：2026-10-18，源码基线 `88684ac`。本文描述当前发布内容、稳定 ID、职责与剩余接入边界；待确认决策使用 [P 编号清单](../story_authoring/day_01_integration_pending.md)。正式可玩内容为 S01–S02，S03–S06 仅宿主与业务能力就绪、剧情数据为空，完整 Day 1 尚未发布。

## 1. 内容权威与发布边界

| 范围 | 正式来源 / 依据 | 使用约定 |
| --- | --- | --- |
| S01–S02 | [结构化工程](../story_authoring/day1_stages_01_02_project.json)与[生成清单](../story_authoring/day1_stages_01_02_bridge.json) | 工程是当前对白、演出及 Bridge 来源；[前两阶段 Markdown](day_01_stages_01_02_draft.md)保留初稿，不从它覆盖手调结果 |
| S03–S06 | [Day 1 修改版](day_01_story_flow_revised.md)及[Beat 化初稿](day_01_stages_03_06_draft.md) | 尚未迁移工程，冲突与空白先登记 P 编号，不自行决定角色、数值、顺序或对白 |
| 独立试编排 | [day1_scene01](day_01_scene_01.md)与[映射](../story_authoring/day1_scene01.json) | 只在独立 Demo 执行，不等于正式 S01；源稿散列差异仍需单独处理 |
| 历史精简范围 | [执行规格](day_01_development_spec.md) | 用于差异对照，不能覆盖新版投掷、双守卫、混乱撤离、地图或分支 |
| 生成规范 | [工作流](../guides/story_authoring_workflow.md)、[游戏内编排](../guides/story_editor.md)、[指令表](../guides/story_authoring_commands.md) | 修改实际正式来源，再生成运行时 JSON / Beat 清单；本次文档维护不改工程、运行时数据或散列 |

## 2. 当前六阶段接入

| 阶段 | 当前实际结果 | 剩余边界 |
| --- | --- | --- |
| S01 | 标题新游戏进入店铺，day1.opening 后等待人类订单；接单、制作入库、交付并收 10 普通货币 | 人类角色、配方、货款已在 day1 配置落地，不再使用旧胖哥布林教学代替 |
| S02 | 首位哥布林和甲乙丙三单，各交付发古怪硬币 strange_coin ×1；三个空白异闻录条目解锁；群单按独立回执聚合 | 前两阶段保持 current_day=1；最终到 day1.investigate_coins，尚未进入正式 S03 演出 |
| S03 | 店门双向导航、出店门控、章节接管和 declared derived_facts 能力存在 | 尚无正式观察点集合、探索结束条件、Story / Dialogue / Phase；P13 |
| S04 | 胖哥布林角色、地图 UI 的 unlock_map 接口与知识映射存在 | 店外 / 店内消费顺序、普通订单、地图教学、知识发布、接受 / 拒绝汇合尚未编排；P14/P16 |
| S05 | 昼夜、长老宅门洞、文书关闭回执、一次取血、真实返店与潜入组件存在 | 正式支付、四职责绑定、火把来源、可燃物、检查点、撤离及资源耗尽策略仍缺；P06/P08/P09/P13 |
| S06 | 血液特调资源、准入与指定胖哥布林交付业务存在；标题卡及 Day 2 占位能力存在 | 用量选择、异常 / 帮助 / 休息表现、章末事件未发布；P07/P10。不会自然推进 Day 2 |

主链仍为 S01→S02→S03→S04→S05→S06。S04 两条选项按原稿最终汇合；S05 双卫支付与必然醉酒事件的关系、文书 / 血液 / 混乱顺序保持待定。不能要求完成次日特调才放行当夜。

## 3. 已发布 ID 与预留名称

### 3.1 S01–S02 的实际 ID

前期规划的 `day1.s01.*` / `day1.s02.*` 名称不覆盖以下已经发布的稳定 ID；不要按旧命名模板重命名运行数据。

| 类型 | 已发布值 |
| --- | --- |
| 演出事件 | day1.opening、day1.first_goblin、day1.group_arrival、day1.ending |
| 操作阶段 | day1.wait_human、day1.wait_goblin、day1.wait_group；完成到 day1.investigate_coins |
| Actor | player、human_customer、goblin_customer、goblin_a、goblin_b、goblin_c；fat_goblin 保留后续用途 |
| 位置 | 奶茶店 StoryPositions 下的 day1_player、day1_door、day1_aisle、day1_counter、day1_group_a/b/c 等，由 Day1ShopController 实际注册 |
| 任务 | day1.order_human、day1.order_goblin、day1.order_group_a/b/c |
| 订单 | day1_human、day1_goblin、day1_group_a/b/c |
| 完成事实 | day1.human_settled、day1.goblin_settled、day1.group_a_settled / group_b_settled / group_c_settled；聚合 day1.group_settled |
| 接单事实 | task.day1.human.active、task.day1.goblin.active、task.day1.group_a/b/c.active；各单独立 |
| Bridge | day1.first_drink_tutorial、day1.goblin_first_order、day1.goblin_group_orders；输出 day1.human_done / goblin_done / group_done |
| 章节与见闻录 | day1.stages_01_02_completed、day1.chronicle_unlocked；条目 chronicle.casino / griffin_blood / elder，仅空白解锁 |
| 库存 | strange_coin（古怪硬币）为任务道具、非货币；pearl_milk_tea、coconut_milk_tea、plain_milk_tea 为教学固定成品 |

每单回执为 `delivery.<order_id>.completed`。打开 orders 只写 `shop.orders_viewed`；玩家明确接取才写 accepted_flag。制作 UI 以真实任务与库存安排顺序，不依赖旧三单队列下标。

### 3.2 后四阶段实际业务与预留

| 引用 | 当前状态与写入责任 |
| --- | --- |
| day1.s03 / s04 / s05 / s06 及子阶段 | Day1Access 和章节宿主支持；当前后章事件没有填充，不会由前段自动走完 |
| day1.s03.exploration_completed | 预留；只有确认观察集合并填 derived_facts 或真实探索业务后才可产生 |
| day1.s04.map_available | MainGame.unlock_map 在聚落地图及玩家可用、screen 注册成功后写；正式 S04 尚未调用 |
| day1.s04.commission_accepted | 保留给正式选项汇合；Debug 世界流程入口仅准备验收事实 |
| day1.s05.guard_payment_completed | pay_items / commit_item_payment 已能原子扣真实库存物品、写回执及配置的放行 flags；正式金额、币种、次数与事件未填 |
| day1_elder_document / day1_blood_storage | 聚落真实 StoryInteractionPoint 的 interaction_id；实际关闭文书 / 取物成功后提交 |
| day1.s05.document_read / blood_acquired | GameState.commit_story_interaction 在一次事务中写事实、物品及 story.<entry_id>.resolved；读文书不自动成为持有文书 |
| day1_griffin_blood | 已有真实材料；点位入库 ×1，隐藏信息与正式用量仍有 P07；不允许普通自由配方 |
| day1.s05.escape_completed | 潜入服务仅在配置有效且满足真实物品 / 区域 / 必然事件等条件时写；正式配置为空，当前流程不能产生 |
| day1.s05.returned_shop | 已取得血液，处于 S05/S06，实际通过 street_door 抵达奶茶店才写；不等于安全撤离 |
| day1_blood_milk_tea | 已有固定特调：血液、红茶、奶精、糖浆；要求取血事实、真实返店和 S06 阶段，并实际扣库存 |
| day1.s06.blood_drink / day1_s06_blood_drink | 已有任务 / 订单，仍放在前章任务文件；通过 available flag 揭示，接单后交给 fat_goblin |
| day1.s06.blood_drink_delivered | TaskDelivery 真实消耗特调后写；不代表饮用异常演出已执行 |
| day1.s06.blood_amount / completed | 用量值仍待定；章末 completed 尚无正式事件写入，不为调通流程伪造 |
| day2.placeholder | 章节能力及 UI / 出店门禁支持；当前不自动进入，没有正式 Day 2 内容 |

任务 / 事件 / 事实使用点号命名空间；物品、订单、对象 ID 仍须 `is_valid_identifier()`，不可含点号。预留后四阶段事件名见稿件与 pending，不因本表登记就变成可调用事件。

### 3.3 宿主与资源

- `main.tscn` 与 `settlement.tscn` 复用 MainGame。正式 shop 选择 day1；有进度的 tutorial 往返保留原配置。新进程 F6 聚落默认 tutorial，不启动五单。
- Day1ShopController 负责前两阶段 setup / 剧情 / Bridge 与检查点；Day1ChapterController 在聚落接管，在店铺从 investigate_coins / S03 起或 day2.* 接管。章节摆位使用 setup 的真实 Marker，不能复制 Demo 坐标。
- 聚落角色为 fat_goblin、common_goblin、guard、guard_captain、elder、chef、tavern、casino，昼夜显隐由世界协调层处理。guard 不是 drunken_guard Marker，也不自动代表四个潜入职责。
- 店门出口为 shop_exit / shop_enter，入口为 street_door / shop_door。出入口与落点见[导航](../systems/scene_travel.md)，不再使用旧预留 day1_exit_shop 作为实际 ID。
- 聚落 StoryAnchors 由宿主注册；night_gather_0..7 对应独立 GatherPoint。位置存在不等于该处正式事件、支付或撤离已接通。
- MainGame 初始化交互声音时注册正式 SoundLibrary；Day 1 控制器也注册自身所需资源。标题音乐由标题场景单独持有，日常 BGM 由前段剧情启动；详见[音效库](../assets/sound_library.md)。Demo 的 cinematic.* / demo.* 仍只在对应宿主注册。

## 4. 业务、事务与恢复

制作只扣料并增加成品；交付通过 GameState.commit_delivery 合并扣成品 / 材料 / 动态杯、物品奖励、钱包收入、任务完成、稳定回执、批次进度和交付计数，通知时已经整体提交。不要在 delivered 回调追加独立 add_money 形成第二笔结算。错误对象、缺货、未接取、溢出和重复请求均不能留下部分结果。

`shop.orders_completed` 是跨任务交付总量，不代替正式群单集合。TeaProduction 的兼容 completed_order_ids 是旧制作前缀，不代表已交付。自由 craft_formula 只产生动态杯及图鉴，不推进教学订单；任务支持 product_id / items / drink 三种互斥需求，正式自由订单尚未发布。

Bridge v2 只等待真实业务 flag；每个 stage 唯一，输入 completion.flag 与输出 completion_flag 不同。已发布三段采用 allow_existing=true，取消后不要求重做已消耗订单。Director busy 时不开放玩家操作；关窗、演出失败与取消不回滚已提交业务。前段由“继续剧情”重建边界；后段自动事件失败 / 取消后不自行重播。

GameState 完整快照 v4 包含经营配置、库存 v3、制作、钱包与剧情。完整 v2/v3 可迁移，剧情 v1 拒绝；普通导航 / 重载保留会话，新游戏显式重置。没有文件存档或继续菜单，不能从局部剧情快照覆盖经营数据。

## 5. 后续发布检查

1. 用批准内容填后章 setup、Story、Dialogue、phases、任务与真实关卡绑定；按原稿决定空间、价格、顺序、信息揭示和失败恢复。
2. 核对每个实际 Actor / Marker / 音频及 trigger；宽泛 NPC 路由不能遮蔽交付，隐藏角色不能成为隐形墙。
3. 验证支付、拾取、交付的唯一回执，群单聚合、取消恢复、资源不足策略及跨场景状态；阶段变更不冒充抵达或业务完成。
4. 分别验证正式成功 / 失败 / 重试、画面与听感、章末和 Day 2 占位；独立夹具通过不等于六阶段发布验收。

本轮只核对文档与源码，没有生成剧情或运行上述检查。历史能力测试见[世界流程](../gameplay/day_01_world_flow.md#工作区收尾核验2026-10-18)；当前缺口与历史失败见[项目现状](../development/development_status_2026_10_18.md)。
