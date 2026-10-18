# Day 1 后四阶段与 Day 2 五阶段编排交接

核对日期：2026-10-18。交付范围为剧情来源、工程、派生映射与接线需求；未修改玩法、地图、MainGame、公共菜单或正式任务目录。

本轮新增正式可播放区间为 **0**。Day 1 S03–S06 的事件、对白、Phase 和 Setup 原为空；Day 2 仍是宿主占位。九个阶段均有来源或实际接线阻塞，不能把下游组件的独立测试通过解释为剧情已通关。既有 S01–S02 工程和运行产物完整保留。

## 工程、来源与发布边界

| 范围 | 工程正式编辑入口 | 待发布内容 | 派生映射 |
| --- | --- | --- | --- |
| Day 1 S03–S06 | [day1_stages_03_06_project.json](day1_stages_03_06_project.json) | 24 Beat | [清单](day1_stages_03_06_bridge.json)、[逐 Beat 表](day1_stages_03_06_beat_map.md) |
| Day 2 S01–S05 | [day2_stages_01_05_project.json](day2_stages_01_05_project.json) | 29 Beat | [清单](day2_stages_01_05_bridge.json)、[逐 Beat 表](day2_stages_01_05_beat_map.md) |

两份工程沿用 `goblin_story_project`。顶层 `events/beats/dialogues` 是已批准的编译集合，本轮均为空；`pending` 是保存在完整工程 JSON 中的开发元数据，现有 StoryProject 不编译它，F3 表单不显示它。未增加 runtime 指令、Loader 字段或编辑器功能。工程保存仍能保留此对象；保存不会使待发布对白、业务草案或选项进入正式运行目录。

`pending.beats` 保留原 Beat ID、逐字 Markdown、来源行、模式、宿主、阻塞号、对白引用及稳定步骤 ID；`ordered_lines` 保留文本在原段中的顺序。`pending.dialogues` 是可由 DialogueLibrary 校验的 v1 文本，包括文书的段间空行、内心与出声、重复句和原文疑点。`pending.event_drafts` 仅用于检查分段对白指令和选择条件，使用 `review.*` 命名空间，不是正式事件；它们不承担动作、资金、任务、地图或阶段推进。`chronicles` 保存原文对应的见闻录命令草案，插入时点仍由来源行定位。

混合 Beat 已将点单／交付前、真实业务后的文本分组；不得把各组串起来跳过玩家操作。S04 选项使用 `accept/refuse`，无新增问题文案；酒馆采集分支使用 flag 正反条件，分支汇合位置仍 pending。没有补 NPC 动作、音效、坐标、配方、金额或招募台词。

源稿为 [Day 1 初稿](../design/day_01_stages_03_06_draft.md)（内容来自修改版）及 [Day 2 初稿](../design/day_02_stages_01_05_draft.md)（来自 PDF）。此次导入后，以工程中保存的内容及稳定 ID 合并后续编辑，MD 留作导入初稿；不要用旧 MD 覆盖工程修改。清单 `source_sha256` 固定导入来源，`authoring_sha256` 跟随保存后的工程。S04 正文版独有内容保存在 `pending.source_alternatives`，未擅自选择或合并。

## 九个阶段的发布条件

| 阶段 | 自动演出／玩家操作边界 | 当前阻塞 |
| --- | --- | --- |
| D1 S03 | 检查金币 → 实际出店 → 街道变化 → 有限探索 → 回到店门 | P13：首事件立即续播还是门交互、出店事实、观察点集合与结束判定；现有锚点注册不等于空间与触发已批准 |
| D1 S04 | 胖哥布林点单 → 普通消费（模式未定）→ 介绍信仰 → 真正解锁地图 → 两条委托分支汇合 | P04/P05/P14：场所、普通订单、收费、两版见闻录；P16：文字疑点。地图提示必须晚于 `unlock_map()` 成功 |
| D1 S05 | 潜入各步与调查／拾取／支付 → 相应短演出 → 实际撤离返店 | P06/P08/P09：支付、四种守卫职责、文书／血液／混乱的顺序与区域；P17：正式文书正文未接线；P16：返店系统提示无正文 |
| D1 S06 | 思考 → 玩家选用量／制作 → 到店 → 真实交付 → 饮用异常 → 帮助休息 | P07/P10/D13：用量、剩余量、到店与抽搐表现、帮助操作和换天；已有固定配方不能取代玩家决定用量 |
| D2 S01 | 清晨对话 → 两次真实资金转交 → 委托 → 准备营业 | D01/D02/D03/D11/D13：换天、守卫约定冲突、钱袋、店内椅子与动作、剩余血液 |
| D2 S02 | 普通营业与四组剧情顾客；各组点单闲聊 → 真实服务 → 后续对白／离场；另有代购招募 | D03/D04/D05/D14：人数、订单、时机、收款、持久接线、关店与招募；不把四组固定 NPC 作为跑腿者，不把招募完成设为未批准的关店前置 |
| D2 S03 | 酒馆对白 → 原子购买 → 已购提示 → 采集委托条件分支 → 令牌 → 自行去赌场 | D05/D06/D07/D15：老板身份、价格／折扣／限量、分支归属、清单报酬与任务接线；不把目录标价 60 或推导 48 变成已批准的价格 |
| D2 S04 | 入场／抵押对白 → 第一局结算 → 债务 → 第二局结算／奖励 → 免除 → 离场 | D08/D15：赌具模式、私兵、奖励 bundle／选择方式、债务期限；自由赌博未实现，不能发布“赌场已开放”提示 |
| D2 S05 | 真返店 → 制作前对白 → 制成 → 守卫前三句 → 交付 → 试饮 → 报酬 → 后续对白 → 再返店 | D02/D09/D10/D11：配方、血液排除、守卫身份与交付入口、报酬、人物记录；制作不等于交付，交付不等于已支付；人物记录不能用见闻录冒充 |

## A/B/C/D 的实际接口与交接

| 负责人／组件 | 已核对的真实接口 | 集成所需输入与消费方式 |
| --- | --- | --- |
| A 日程／任务终态 | [DayPhase](../../src/core/schedule/day_phase.gd).advance_to；[GameState](../../src/core/game_state.gd).bind_task_catalog/get_task_result/settle_task_result；[接口说明](../systems/schedule_and_task_results.md) | 传完整合并目录；换天与关店规则未定时不调用推进。截止须明确 day/phase/at 或 after；缺失规则保持未配置。恢复查询持久终态，不重放结算信号。并行工作区另新增 bind_business_session/load_business_session/commit_business_session/close_business_session，供 B 生产适配 |
| B 营业／顾客调度 | [BusinessScheduler](../../src/gameplay/milk_tea/business_scheduler.gd).publish_stage/request_arrival/is_group_served/request_departure/request_close；CustomerVisit；[接口说明](../gameplay/business_scheduler.md) | 每组明确实际 Actor、非空订单集合、entry/waiting/exit 和通行路线。真实到达后才能接单；先查询全部回执，再订阅 group_served。并行工作区已新增 `configure_session(plan,state,delivery,close_rule)` 接 A 真实持久接口；仍缺正式 plan、close_rule 和宿主调用，不能用 `set_variable` 或内存夹具冒充 |
| C 酒馆／赌场 | [TavernPurchase](../../src/core/economy/tavern_purchase.gd).compile_products/configure/purchase；[FixedStoryCasino](../../src/core/economy/fixed_story_casino.gd).settle_first_loss/settle_second_win/waive_debt/get_status；[接口说明](../gameplay/day_02_trade.md) | 静态同源报价、限量、完整奖励 bundle、债务任务与不同 loss/win 回执；运行中折扣仍缺钱包原子报价／资格接口。loss、win+奖励、waive 为三个可恢复边界；债务取消结果不等于交十杯完成 |
| D／人物记录（本轮期间的并行源码） | `src/core/characters/character_journal.gd`：CharacterJournal.configure/unlock_character/append_record/get_character/get_characters/mark_read；MainGame.get_character_journal/open_characters；Story 新增 character_unlock/character_append | 人物记录与见闻录分开。D2 S05 的记录正文已逐字保存，正式角色身份和触发未定，尚未发布。新增组件仍在并行编辑，本轮不替代其功能／UI 验收，也不纳入提交；待集成确认 D 对应交付归属与版本 |
| 已有采集／材料提交；临时代购未见交付 | [GatheringService](../../src/gameplay/gathering/gathering_service.gd).harvest 与 [TaskDelivery](../../src/core/tasks/task_delivery.gd).try_submit；[采集说明](../gameplay/gathering.md) | 可复用夜间采集和真实材料提交。仓库中未发现临时代购／雇佣组件交付，不能宣称已有招募、专款、回货、超价、失败退款接口；D03 保持 pending |

集成适配器只在业务提交成功后投影事实，再由 Bridge 消费。GameState 同步通知期间不能再开启另一个交易；B 的 group_served 已延迟，其他服务应在安全边界查询回执后投影。恢复先查持久结果再订阅实时信号。业务源 flag 与 Bridge 输出 flag 必须不同；唯一订单可接受持久结果，招募／探索历史策略未确认时不填默认值。

本轮期间出现的 A/B 并行代码改动不纳入本 commit，也不以本轮内容验证代替其模块验收。当前源码已可通过 `configure_session` 绑定生产持久接口；因此 D14 剩余阻塞是正式数据、规则与宿主装配。`close_rule` 必须显式给出 from/to、required_stages、served_groups、departed_groups、required_flags、completed_flag；未定前传空规则保持关店 pending，不擅自填空门槛来结束营业。

初次核对时人物记录组件尚不存在，后续并行源码已增加独立 CharacterJournal 和两条 Story 指令；D10 现收窄为正式身份／内容触发与雇佣队伍规则。该组文件编辑期间曾使当前工作区加载报 `CharacterJournal` 类型未注册；内容检查的最终隔离方式和结果见 Beat 表，不将带脚本错误的进程计为通过。

`pending.phases` 共 13 条；`config` 非空只表示六字段可组成 Bridge v2 草案，**不表示可发布**。缺少 stage、来源或历史策略时为 null，并逐项记录缺口。赌场单个奖励 phase 不能覆盖第一局和免除；守卫 paid phase 必须保留“谢了”后的原文，不能直接跳到街道独白。这两处在正式拓扑确定后需增加短事件边界。续播事件须同时要求 `after_event`、精确 stage、Bridge 输出 true，并无交互 trigger。

## 交给集成负责人的任务、订单清单

这些是配置需求，不是可加载 TaskCatalog；不向正式目录写带 null／默认金额的任务。所有新订单／物品／交付对象使用合法标识符，不能含点号；任务与事实沿用命名空间。

| 任务 ID（沿用／预留） | 订单／对象 | 激活、真实结果与缺口 |
| --- | --- | --- |
| `day1.s04.blood_commission`（预留） | 潜入委托，无已定 delivery | 委托选择汇合后可激活；完成定义涉及取血、撤离、返店还是特调尚需 P08；不能依赖 Day 2 守卫交付 |
| S04 普通消费任务（ID 未定） | `day1_s04_fat_goblin_order` → `fat_goblin` | P14 模式先确认；配方、数量、币种、价格、整笔回执待定；不复用 S01–S02 订单 |
| `day1.s06.blood_drink`（已存在） | `day1_s06_blood_drink`／`day1_blood_milk_tea` → `fat_goblin` | 实际定义在 [前两阶段任务目录](../../src/resources/tasks/day1_stages_01_02.json)，已由合并目录加载。保留 ID、不再添加同 ID 到空的后四阶段目录；真实完成 `day1.s06.blood_drink_delivered`；P07 用量与原料剩余仍未定 |
| `day2.task.wake_mushroom`（预留） | 代购目标 `insomnia_mushroom`，交给谁未定 | 原文标题“帮胖哥布林购买醒神菇”；上限 30、跑腿费 5；资金金额／归属、招募／采购／交货／治疗各边界与两天期限未定。不复用 `tavern.insomnia_order` |
| 四组剧情服务任务（ID 未定） | `day2_s02_festival_order`、`day2_s02_elder_order`、`day2_s02_emissary_order`、`day2_s02_rumor_order_a/b`（均预留） | 分别对应 festival/elder/emissary/rumor 组；人数与订单数待 D04，`_a/b` 不能视作已确认数量。各组用实际全部订单回执；未出场不可接／交；不复用 Day 1 回执 |
| `day2.task.guard_materials`（预留） | `griffin_amber_wine`、`phantom_gold_mushroom` | Day 1 接取还是 Day 2 清晨激活、与成品订单是否同任务待 D02；获得材料需真实交易／奖励，不设剧情成功 flag |
| `day2.task.festival_prep`（预留） | 清单物品、数量、交付订单 ID 待定 → 酒馆老板身份待定 | 原文“七日祭的准备”；第三天交食材，确切截止、报酬、秘密内容均未定。用 `delivery.items` 的真实扣料业务，不套用占位醒神菇 ×3／糖浆奖励 |
| `day2.task.casino_wager`（预留） | 固定两局，无虚构扣款 | 第一局失败是赌局状态；不把整条第二局可成功的任务直接锁存 failed。完成须第二局回执、奖励入库、债务免除都真实成立 |
| `day2.task.casino_debt`（预留） | 十杯奶茶要求；配方、对象、订单与期限待定 | C 第一局同事务激活；确认采用真实取消策略后显式 `allow_cancel:true`，由 C.waive_debt 接 A 写 cancelled；不发十杯成品，不用 complete flag 冒充免除 |
| `day2.task.guard_special_order`（预留） | `day2_guard_special_order`／`day2_guard_special_milk_tea` → 守卫 Actor 待定 | 配方比例与可选材料未定，明确排除血液；完成需指定成品交付与约定报酬真实提交。原文先试饮再支付，与现有原子交付结算边界需 D09 决定 |

## 角色、空间与 Setup 需求

| 内容 | 实际绑定／候选 | 所需接线 |
| --- | --- | --- |
| 主角 | 两宿主已注册 `player` | 沿用宿主出生／实际抵达；不为草案添加坐标 |
| 胖哥布林 | 已注册 `fat_goblin` | S04 场所与首次立绘未定；S06 到店、倒下与帮助，D2 椅子及瘫坐／站起／跌坐未定。聚落 `shop_rest_chair` 不是店内同名 Marker 授权 |
| 守卫 | 已注册 `guard`；`drunken_guard` 是 Marker／调查点 | 入口卫、宅邸双卫、最后巡逻、醉酒守卫不得默认合并。D1/D2 同一醉酒角色的身份、位置与交付目标需统一 |
| Day 2 四组顾客 | 无正式独立 Actor 绑定 | 甲／乙是说话人，不是跨组共享 Actor；每组配独立实例，普通跑腿人另配。B.CustomerVisit 与 StoryDirector 不同时控制同一 Actor |
| 酒馆／赌场老板 | `tavern`／`casino` 只是“人物”候选 | 确认身份再绑定；赌场卫队无正式资源／数量；不可拿普通哥布林冒充私兵 |
| 聚落位置 | MainGame 已注册 `get_story_positions()` 返回的 StoryAnchors | `00_shop_entrance`、`elder_document`、`elder_blood_storage`、`tavern_bartender`、`casino_boss` 等存在；只有已批准且可通行的路线才用于正式动作 |
| 出店／回店 | SceneTravel；D1 `record_shop_arrival()` | D1 真实返店事实已实现；S03 出店专用事实与 D2 两次返店没有对应正式投影。不能复用 D1 returned_shop 跳过第二次移动 |
| 地图／文书 | 聚落 `unlock_map()`；`day1_elder_document` | 地图成功后再显示解锁提示；文书现有正文与来源冲突见 P17，需要集成方配置正文与关闭完成回执，不能让 Story trigger 遮蔽后不再记读完 |

Day 1 Setup 的 `auto_events/derived_facts/scene_setups` 保持原空数组；没有把 pending Actor 或假完成条件装进去。Day 2 新空目录仅供工程生成一致性检查，**没有加入宿主 SETUP、TASK_FILES 或占位准入**。正式发布时由集成方按确定后的 host/stage 配置角色、入口和恢复；不在 MainGame 硬编码 Beat 顺序。

## 验证 case 与发布操作

每 Beat 有 source 静态 case 与 route pending case，保存在工程 `pending.cases`；运行时映射 `beats` 为空，不伪造 `[start,count)` 区间或执行成功的 case。实际受阻 case 尚未执行，不会以 fixture 写成功 flag 来通过验收。

| case | 必须观察的结果 | 当前范围 |
| --- | --- | --- |
| 来源、稳定 ID、分段、原文疑点 | 文书五段、重复句、`都是都是`、两个选项和全部内心／出声逐字保留 | 静态核对、原 Loader 校验 |
| 已发布隔离 | 编译／保存工程不泄漏 pending 内容，现有 Day 1 空目录逐字保留 | 工程 CLI、局部自动测试 |
| 真实路由未遮蔽 | 主店／聚落中的后续空目录对 orders/storage/tea_station/NPC/文书返回无剧情匹配；D2 仍占位 | 真实宿主、真实 request_interaction；不代表业务通关 |
| 选择／条件 | accept/refuse 两路汇合一次；has_gathered 正反互斥，分支范围确认后各执行一次 | 草案 Schema 检查；正式执行 pending |
| 业务反例 | 错对象、缺料、未付款、满库存、关窗、第一笔／部分组完成都不续播 | 待真实配置和宿主接入；不复跑未变更的下游组件全部测试 |
| 恢复／取消／优先级 | once 已消耗不重播，取消不重发钱物；已完成业务关模态后续播；恢复先查真实事实 | 待正式事件、Phase、Setup；现有章节宿主模块测试只证明框架 |

批准一个独立区间后：先合并工程正式来源，解决该区间全部 pending；把完整自动演出（含真实动作）、对白和玩家 phase 迁入标准集合；生成、核对 after/stage/output 条件与真实路由，再由集成方接任务、订单、公共菜单和 Setup。不可仅把 review 文本片段迁入正式集合后宣称完成。

本轮实际验证结果见两份 Beat 表的验证记录。人工 F6、完整两天通关与正式 Release 导出未执行：本轮没有可发布事件。既有观察入口为 `src/core/main.tscn` 和 `src/core/settlement.tscn`；可观察后四阶段仍无正式自动演出、Day 2 仍提示未开放，这只是隔离边界，不能验收草案的镜头、动作、声音与阅读节奏。

Godot 4.7 官方依据：[JSON](https://docs.godotengine.org/en/4.7/classes/class_json.html) 的解析错误与整数数字处理、[Signal](https://docs.godotengine.org/en/4.7/classes/class_signal.html) 的连接与通知语义；编排工具沿用实际 Loader，不用 JSON 文本外形代替业务成功。
