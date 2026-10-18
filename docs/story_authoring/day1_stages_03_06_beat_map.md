# Day 1 S03–S06 Beat 映射与验证

核对日期：2026-10-18。正式编辑入口为 [day1_stages_03_06_project.json](day1_stages_03_06_project.json)，派生清单为 [day1_stages_03_06_bridge.json](day1_stages_03_06_bridge.json)。本表覆盖 24 Beat、19 个 Dialogue、127 个文本节点、3 条 Phase 草案、56 条静态／待执行 case。

**本轮新增发布区间为 0；以下所有 Beat、事件及 Phase 均 pending。** 标准编译集合为空，没有运行时步骤区间，不填虚假的 `[start, start + count)`。`event_id` 是保留的正式事件候选；`review.*` 是仅供原 Loader 检查的文本片段，未装入正式宿主。动作、业务调用、真实触发及恢复拓扑尚未具备，不能将文本片段直接发布。

最初来源：[导入初稿](../design/day_01_stages_03_06_draft.md)。导入后以工程为正式来源，MD 不覆盖手动编辑。工程中逐 Beat 的 `source_markdown`、来源行、稳定步骤 ID 和 `ordered_lines` 保留原文顺序，`chronicles` 保存见闻录原文及来源行。

- 导入来源 SHA-256：`2f5365b226e1cce76e166058b0dcb3eb4855e79d20297b0045432e1f309c9b96`
- 已保存工程 SHA-256：`f0b2b574d6d6336cd9442f3c5de93314790e2377a1e463ae365cc7b7622b4df2`
- 具体任务、订单、Actor／Marker、A/B/C/D 接口与发布条件见[两日交接](day_01_02_authoring_handoff.md)。

## 逐 Beat 追踪

来源行为初稿的 1 起始闭区间，用来定位首次导入文本；不是 Story 步骤索引。宿主 `shop` 为奶茶店、`settlement` 为聚落；场所未确认的混合标注继续 pending。

| Beat／来源行 | 模式／宿主 | 正式事件候选 | review 文本片段 | Dialogue／分段 | 阻塞 |
| --- | --- | --- | --- | --- | --- |
| `s03_coin_inspect`<br>38–50 | 自动演出<br>shop | `day1.s03.coin_inspect` | `review.day1.s03_coin_inspect_before` | `day1.s03.coin_inspect` (before) | [P13](day_01_integration_pending.md#p13) |
| `s03_street_gone`<br>51–61 | 自动演出<br>settlement | `day1.s03.street_gone` | `review.day1.s03_street_gone_before` | `day1.s03.street_gone` (before) | [P13](day_01_integration_pending.md#p13) |
| `s03_limited_exploration`<br>62–77 | 玩家操作<br>settlement | `null` | `review.day1.s03_limited_exploration_before` | `day1.s03.limited_exploration` (before) | [P13](day_01_integration_pending.md#p13) |
| `s03_back_to_door`<br>78–87 | 自动演出<br>settlement | `day1.s03.back_to_door` | `review.day1.s03_back_to_door_before` | `day1.s03.back_to_door` (before) | [P13](day_01_integration_pending.md#p13)、[P14](day_01_integration_pending.md#p14) |
| `s04_fat_goblin_arrives`<br>92–134 | 自动演出<br>pending | `day1.s04.commission` | `review.day1.s04_fat_goblin_arrives_before` | `day1.s04.fat_goblin_arrives` (before) | [P04](day_01_integration_pending.md#p04)、[P05](day_01_integration_pending.md#p05)、[P13](day_01_integration_pending.md#p13)、[P14](day_01_integration_pending.md#p14) |
| `s04_fat_goblin_order`<br>135–143 | 待确认（[P14](../story_authoring/day_01_integration_pending.md#p14)：原稿只写「主角开始制作奶茶」「没过多久，奶茶做好了」）。<br>pending | `null` | 无对白片段 | 无对白；保留原叙述 | [P04](day_01_integration_pending.md#p04)、[P05](day_01_integration_pending.md#p05)、[P11](day_01_integration_pending.md#p11)、[P14](day_01_integration_pending.md#p14) |
| `s04_first_taste`<br>144–159 | 自动演出<br>pending | `day1.s04.after_order` | `review.day1.s04_first_taste_before` | `day1.s04.first_taste` (before) | [P04](day_01_integration_pending.md#p04)、[P14](day_01_integration_pending.md#p14) |
| `s04_griffin_faith`<br>160–211 | 自动演出<br>pending | `day1.s04.after_order` | `review.day1.s04_griffin_faith_before` | `day1.s04.griffin_faith` (before) | [P14](day_01_integration_pending.md#p14) |
| `s04_griffin_blood`<br>212–243 | 自动演出<br>pending | `day1.s04.after_order` | `review.day1.s04_griffin_blood_before` | `day1.s04.griffin_blood` (before) | [P14](day_01_integration_pending.md#p14) |
| `s04_map_handover`<br>244–263 | 自动演出（地图解锁需宿主能力）<br>pending | `day1.s04.map_handover` | `review.day1.s04_map_handover_before` | `day1.s04.map_handover` (before) | [P14](day_01_integration_pending.md#p14)、[P16](day_01_integration_pending.md#p16) |
| `s04_commission_choice`<br>264–291 | 自动演出（含选项；伪选择，两条路径汇合）<br>pending | `day1.s04.commission_choice` | `review.day1.s04_commission_choice_choice` | `day1.s04.commission_choice` (choice)<br>`day1.s04.commission_choice_accept` (accept)<br>`day1.s04.commission_choice_refuse` (refuse) | [P01](day_01_integration_pending.md#p01)、[P14](day_01_integration_pending.md#p14) |
| `s05_step1_outside`<br>313–321 | 玩家操作（教学）<br>settlement | `null` | 无对白片段 | 无对白；保留原叙述 | [P09](day_01_integration_pending.md#p09)、[P13](day_01_integration_pending.md#p13) |
| `s05_step2_throw`<br>322–329 | 玩家操作（教学）<br>settlement | `null` | 无对白片段 | 无对白；保留原叙述 | [P05](day_01_integration_pending.md#p05)、[P09](day_01_integration_pending.md#p09) |
| `s05_step3_bribe`<br>330–337 | 玩家操作（教学）<br>settlement | `null` | 无对白片段 | 无对白；保留原叙述 | [P06](day_01_integration_pending.md#p06)、[P09](day_01_integration_pending.md#p09) |
| `s05_drunken_guard`<br>338–364 | 自动演出（含支付，支付须为真实业务）<br>settlement | `day1.s05.drunken_guard` | `review.day1.s05_drunken_guard_before`<br>`review.day1.s05_drunken_guard_after_payment` | `day1.s05.drunken_guard` (before)<br>`day1.s05.drunken_guard_after_payment` (after_payment) | [P06](day_01_integration_pending.md#p06)、[P09](day_01_integration_pending.md#p09)、[D02](day_02_integration_pending.md#d02) |
| `s05_final_patrol`<br>365–370 | 玩家操作<br>settlement | `null` | 无对白片段 | 无对白；保留原叙述 | [P09](day_01_integration_pending.md#p09) |
| `s05_document`<br>371–395 | 玩家操作（调查）+ 自动演出<br>settlement | `day1.s05.document` | `review.day1.s05_document_before`<br>`review.day1.s05_document_document`<br>`review.day1.s05_document_after_document` | `day1.s05.document` (before)<br>`day1.s05.document_document` (document)<br>`day1.s05.document_after_document` (after_document) | [P08](day_01_integration_pending.md#p08)、[P17](day_01_integration_pending.md#p17) |
| `s05_blood_acquired`<br>396–403 | 玩家操作（拾取）<br>settlement | `null` | 无对白片段 | 无对白；保留原叙述 | [P07](day_01_integration_pending.md#p07)、[P08](day_01_integration_pending.md#p08)、[D13](day_02_integration_pending.md#d13) |
| `s05_escape`<br>404–413 | 玩家操作<br>settlement | `null` | 无对白片段 | 无对白；保留原叙述 | [P08](day_01_integration_pending.md#p08)、[P09](day_01_integration_pending.md#p09) |
| `s05_shop_system_update`<br>414–423 | 自动演出 + 玩家操作（打开奶茶店系统）<br>shop | `day1.s05.return_shop` | 无对白片段 | 无对白；保留原叙述 | [P07](day_01_integration_pending.md#p07)、[P16](day_01_integration_pending.md#p16) |
| `s06_pondering`<br>429–436 | 自动演出<br>shop | `day1.s06.pondering` | 无对白片段 | 无对白；保留原叙述 | [P07](day_01_integration_pending.md#p07) |
| `s06_blood_drink`<br>437–445 | 玩家操作<br>shop | `null` | 无对白片段 | 无对白；保留原叙述 | [P07](day_01_integration_pending.md#p07)、[P10](day_01_integration_pending.md#p10)、[D13](day_02_integration_pending.md#d13) |
| `s06_reaction`<br>446–467 | 自动演出<br>shop | `day1.s06.reaction` | `review.day1.s06_reaction_before` | `day1.s06.reaction` (before) | [P07](day_01_integration_pending.md#p07)、[P10](day_01_integration_pending.md#p10) |
| `s06_help_and_rest`<br>468–480 | 待确认（原稿列为玩家操作「帮助胖哥布林，并安排他暂时留在店里休息」，但没有操作方式，[P10](../story_authoring/day_01_integration_pending.md#p10)）<br>shop | `day1.s06.help_and_rest` | `review.day1.s06_help_and_rest_before` | `day1.s06.help_and_rest` (before) | [P01](day_01_integration_pending.md#p01)、[P10](day_01_integration_pending.md#p10)、[D13](day_02_integration_pending.md#d13) |

## 玩家操作 Phase 草案

自动演出自然结束后由玩家实际操作；只能消费业务成功提交的持久事实，Bridge 独占输出 flag。`allow_existing` 未定时为 null；不擅自选历史策略。下表 `config` 可组成六字段也仍不等于已接线／可发布。赌场第一局、第二局奖励、债务免除与守卫制作、交付、支付分别保留真实边界，最终拓扑见交接清单。

| Phase／Beat | 前置事件／等待 stage | 来源事实／历史策略 | Bridge 输出／续播事件 | 真实业务 owner | 缺口／配置状态 |
| --- | --- | --- | --- | --- | --- |
| `day1.bridge.s03_exploration`<br>`s03_limited_exploration` | `day1.s03.street_gone`<br>`day1.s03` | `day1.s03.exploration_completed`<br>allow_existing=`null` | `day1.bridge.s03_exploration.completed`<br>`day1.s03.back_to_door` | 探索业务（无正式写入者） | 观察点集合、历史策略与结束判定 P13；config=null |
| `day1.bridge.fat_goblin_order`<br>`s04_fat_goblin_order` | `day1.s04.commission`<br>`day1.s04.wait_fat_goblin_order` | `null`<br>allow_existing=`true` | `day1.bridge.fat_goblin_order.completed`<br>`day1.s04.after_order` | TaskDelivery（订单未配置） | P14 模式与场所；P04/P05 配方、金额、币种；真实整笔回执；config=null |
| `day1.bridge.blood_drink`<br>`s06_blood_drink` | `day1.s06.pondering`<br>`day1.s06.wait_blood_drink` | `day1.s06.blood_drink_delivered`<br>allow_existing=`true` | `day1.bridge.blood_drink.completed`<br>`day1.s06.reaction` | TaskDelivery / GameState.commit_delivery | 已存在真实交付事实，但 P07 用量、P10 到店与表现、D13 剩余量未解决；不发布简化版；v2 草案，未发布 |

## Case 与实际验证记录

工程 `pending.cases` 保存本范围 56 个稳定 case ID。每 Beat 的 `.source` 核对原文、归属与分段；`.route` 仍为 pending，fixture=null。选择两路／采集条件正反以及每个 Phase 的业务事实正反另列 case；未真实执行的 case 不写通过。真实交互检查证明空发布集合不遮蔽 fallback，不证明待发布剧情已经能运行。

2026-10-18 最终验证使用 Godot 4.7.2，固定基线 `7af642e43c6766694b2b9208ca86486715bd5205` + 本轮编排文件组成独立快照，路径为 `.godot/later_story_validation/`。快照还原样复制了任务开始前已有的未跟踪 `src/levels/milkTea/milkTea.tscn`，以实例化原有真实宿主；该场景未修改、未纳入本 commit。已对复制的本轮文件逐字／SHA-256 比对。未复制并行开发的 A/B 持久化与 CharacterJournal 等修改，因此这些接口的模块验收不包含在下列结果内。

| 实际检查 | 结果与边界 |
| --- | --- |
| 编辑器 headless 导入快照 | 完成；无脚本／导入错误。退出有原有 ObjectDB／资源泄漏诊断，不作为无告警运行 |
| 两份工程 `tools/story/edit_story_project.gd -- <project>` | 均 `STORY_PROJECT: OK`；已发布 Beat=0，运行产物／散列一致 |
| `tests/verify_later_story_authoring.gd` | PASS，1,187 checks，0 failures；原 StoryProject／DialogueLibrary／StoryLibrary、工程元数据保留、pending 隔离、真实两宿主 request_interaction 与聚落 Marker 注册 |
| `tests/verify_day1_chapter_systems.gd` | PASS，95 checks，0 failures；只证明已有章节框架与 fallback |
| `python -X utf8 tests/verify_later_story_sources.py --check-import` | PASS；Day 1 为 24 Beat／125 句，Day 2 为 29 Beat／399 句；逐字、顺序、文书段落、选择、见闻录及初始来源散列 |
| 人工 F6、完整两天通关、正式 Release 导出 | 未执行；本轮无正式可播放事件，不以 Loader 检查替代动作／镜头／声音／节奏验收 |

实际命令在独立快照上使用 `--headless --path .godot/later_story_validation --script res://...`；工程一致性检查附 `-- res://docs/story_authoring/<project>.json`。日志位于 `.godot/later_story_snapshot_{import,day1_cli,day2_cli,validation,chapter}.log`，仅为本地诊断，不是源依赖。早先并行编辑期间当前工作区发生过 `CharacterJournal` 类型未注册的 CLI 进程；虽打印 OK，不计入上述通过结果。

后续人工入口为 `src/core/main.tscn`／`src/core/settlement.tscn`。在正式数据与接线完成前，只能观察原有后四阶段无新自动演出、Day 2 未开放的隔离状态；业务成功、恢复／取消、分支、路由优先级与原文演出均须按工程 case 另行验收。
