# Day 2 S01–S05 Beat 映射与验证

> 2026-10-20：下表为早期导入草案。现行发布状态、步骤区间与工程散列以 [day2_stages_01_05_bridge.json](day2_stages_01_05_bridge.json) 为准；新增内容及验证见[实施记录](../development/story_supplement_2026_10_20.md)。本历史表不作为当前 pending 清单。

核对日期：2026-10-18。正式编辑入口为 [day2_stages_01_05_project.json](day2_stages_01_05_project.json)，派生清单为 [day2_stages_01_05_bridge.json](day2_stages_01_05_bridge.json)。本表覆盖 29 Beat、43 个 Dialogue、399 个文本节点、10 条 Phase 草案、80 条静态／待执行 case。

**本轮新增发布区间为 0；以下所有 Beat、事件及 Phase 均 pending。** 标准编译集合为空，没有运行时步骤区间，不填虚假的 `[start, start + count)`。`event_id` 是保留的正式事件候选；`review.*` 是仅供原 Loader 检查的文本片段，未装入正式宿主。动作、业务调用、真实触发及恢复拓扑尚未具备，不能将文本片段直接发布。

最初来源：[导入初稿](../design/day_02_stages_01_05_draft.md)。导入后以工程为正式来源，MD 不覆盖手动编辑。工程中逐 Beat 的 `source_markdown`、来源行、稳定步骤 ID 和 `ordered_lines` 保留原文顺序，`chronicles` 保存见闻录原文及来源行。

- 导入来源 SHA-256：`d717aa8e77a6ff9b1132e291ad32dcae7990dac736f0a5023970d0363dc91742`
- 已保存工程 SHA-256：`c371d51e6ca10d3d94b80fdbc460db9670418963c99de30ae31ff2ecfd7a4856`
- 具体任务、订单、Actor／Marker、A/B/C/D 接口与发布条件见[两日交接](day_01_02_authoring_handoff.md)。

## 逐 Beat 追踪

来源行为初稿的 1 起始闭区间，用来定位首次导入文本；不是 Story 步骤索引。宿主 `shop` 为奶茶店、`settlement` 为聚落；场所未确认的混合标注继续 pending。

| Beat／来源行 | 模式／宿主 | 正式事件候选 | review 文本片段 | Dialogue／分段 | 阻塞 |
| --- | --- | --- | --- | --- | --- |
| `s01_fat_goblin_wakes`<br>42–66 | 自动演出<br>shop | `day2.s01.morning` | `review.day2.s01_fat_goblin_wakes_before` | `day2.s01.fat_goblin_wakes` (before) | [D01](day_02_integration_pending.md#d01)、[D11](day_02_integration_pending.md#d11) |
| `s01_wants_more`<br>67–96 | 自动演出（与上一 Beat 同一短事件）<br>shop | `day2.s01.morning` | `review.day2.s01_wants_more_before` | `day2.s01.wants_more` (before) | [D11](day_02_integration_pending.md#d11) |
| `s01_stop_selling_blood`<br>97–106 | 自动演出<br>shop | `day2.s01.morning` | `review.day2.s01_stop_selling_blood_before` | `day2.s01.stop_selling_blood` (before) | [D13](day_02_integration_pending.md#d13) |
| `s01_remember_guard`<br>107–169 | 自动演出<br>shop | `day2.s01.morning` | `review.day2.s01_remember_guard_before` | `day2.s01.remember_guard` (before) | [D02](day_02_integration_pending.md#d02)、[D05](day_02_integration_pending.md#d05)、[D11](day_02_integration_pending.md#d11) |
| `s01_mushroom_commission`<br>170–242 | 自动演出（含资金转交，须为真实业务）<br>shop | `day2.s01.mushroom_commission` | `review.day2.s01_mushroom_commission_before`<br>`review.day2.s01_mushroom_commission_after_funds` | `day2.s01.mushroom_commission` (before)<br>`day2.s01.mushroom_commission_after_funds` (after_funds) | [D03](day_02_integration_pending.md#d03) |
| `s01_stage_end`<br>243–250 | 自动演出<br>shop | `day2.s01.stage_end` | 无对白片段 | 无对白；保留原叙述 | [D03](day_02_integration_pending.md#d03) |
| `s02_business_open`<br>257–266 | 自动演出 → 玩家操作（自由营业）<br>shop | `day2.s02.business_open` | `review.day2.s02_business_open_before` | `day2.s02.business_open` (before) | [D04](day_02_integration_pending.md#d04)、[D14](day_02_integration_pending.md#d14) |
| `s02_festival_talk`<br>267–302 | 自动演出 + 玩家操作 + 自动演出<br>shop | `day2.s02.festival_order` | `review.day2.s02_festival_talk_before`<br>`review.day2.s02_festival_talk_after` | `day2.s02.festival_talk` (before)<br>`day2.s02.festival_talk_after` (after) | [D04](day_02_integration_pending.md#d04)、[D06](day_02_integration_pending.md#d06)、[D13](day_02_integration_pending.md#d13)、[D14](day_02_integration_pending.md#d14) |
| `s02_elder_authority`<br>303–322 | 自动演出 + 玩家操作 + 自动演出<br>shop | `day2.s02.elder_order` | `review.day2.s02_elder_authority_before`<br>`review.day2.s02_elder_authority_after` | `day2.s02.elder_authority` (before)<br>`day2.s02.elder_authority_after` (after) | [D04](day_02_integration_pending.md#d04)、[D05](day_02_integration_pending.md#d05)、[D14](day_02_integration_pending.md#d14) |
| `s02_emissary_rumor`<br>323–347 | 自动演出 + 玩家操作 + 自动演出<br>shop | `day2.s02.emissary_order` | `review.day2.s02_emissary_rumor_before`<br>`review.day2.s02_emissary_rumor_after` | `day2.s02.emissary_rumor` (before)<br>`day2.s02.emissary_rumor_after` (after) | [D04](day_02_integration_pending.md#d04)、[D05](day_02_integration_pending.md#d05)、[D14](day_02_integration_pending.md#d14) |
| `s02_tavern_casino_talk`<br>348–379 | 自动演出 + 玩家操作 + 自动演出<br>shop | `day2.s02.rumor_order` | `review.day2.s02_tavern_casino_talk_before`<br>`review.day2.s02_tavern_casino_talk_after` | `day2.s02.tavern_casino_talk` (before)<br>`day2.s02.tavern_casino_talk_after` (after) | [D04](day_02_integration_pending.md#d04)、[D05](day_02_integration_pending.md#d05)、[D14](day_02_integration_pending.md#d14) |
| `s02_find_errand_runner`<br>380–398 | 自动演出 → 玩家操作（招募，未设计）<br>shop | `day2.s02.errand` | `review.day2.s02_find_errand_runner_before` | `day2.s02.find_errand_runner` (before) | [D03](day_02_integration_pending.md#d03)、[D04](day_02_integration_pending.md#d04) |
| `s02_stage_end`<br>399–405 | 自动演出（换昼夜入口未实现）<br>shop | `day2.s02.stage_end` | 无对白片段 | 无对白；保留原叙述 | [D01](day_02_integration_pending.md#d01)、[D04](day_02_integration_pending.md#d04)、[D14](day_02_integration_pending.md#d14) |
| `s03_amber_wine`<br>412–441 | 自动演出 → 玩家操作（购买）<br>settlement | `day2.s03.amber_wine` | `review.day2.s03_amber_wine_before`<br>`review.day2.s03_amber_wine_after_purchase` | `day2.s03.amber_wine` (before)<br>`day2.s03.amber_wine_after_purchase` (after_purchase) | [D07](day_02_integration_pending.md#d07)、[D15](day_02_integration_pending.md#d15) |
| `s03_tavern_commission`<br>442–489 | 自动演出（条件分支）<br>settlement | `day2.s03.commission_token` | `review.day2.s03_tavern_commission_before`<br>`review.day2.s03_tavern_commission_gathered`<br>`review.day2.s03_tavern_commission_not_gathered`<br>`review.day2.s03_tavern_commission_common` | `day2.s03.tavern_commission` (before)<br>`day2.s03.tavern_commission_gathered` (gathered)<br>`day2.s03.tavern_commission_not_gathered` (not_gathered)<br>`day2.s03.tavern_commission_common` (common) | [D05](day_02_integration_pending.md#d05)、[D07](day_02_integration_pending.md#d07) |
| `s03_griffin_token`<br>490–531 | 自动演出<br>settlement | `day2.s03.commission_token` | `review.day2.s03_griffin_token_before` | `day2.s03.griffin_token` (before) | [D05](day_02_integration_pending.md#d05)、[D06](day_02_integration_pending.md#d06)、[D07](day_02_integration_pending.md#d07) |
| `s03_to_casino`<br>532–551 | 玩家操作（移动 + 可选采集）→ 自动演出<br>settlement | `day2.s03.to_casino` | `review.day2.s03_to_casino_before` | `day2.s03.to_casino` (before) | [D07](day_02_integration_pending.md#d07)、[D08](day_02_integration_pending.md#d08) |
| `s04_afraid_to_enter`<br>558–578 | 自动演出<br>settlement | `day2.s04.casino` | `review.day2.s04_afraid_to_enter_before` | `day2.s04.afraid_to_enter` (before) | [D08](day_02_integration_pending.md#d08) |
| `s04_casino_boss`<br>579–614 | 自动演出<br>settlement | `day2.s04.casino` | `review.day2.s04_casino_boss_before` | `day2.s04.casino_boss` (before) | [D08](day_02_integration_pending.md#d08) |
| `s04_stake`<br>615–682 | 自动演出<br>settlement | `day2.s04.casino` | `review.day2.s04_stake_before` | `day2.s04.stake` (before) | [D08](day_02_integration_pending.md#d08) |
| `s04_first_round`<br>683–714 | 待确认（固定失败；以演出呈现或让玩家操作一局必输的赌具，[D08](../story_authoring/day_02_integration_pending.md#d08)）<br>settlement | `day2.s04.rounds` | `review.day2.s04_first_round_before`<br>`review.day2.s04_first_round_after_loss` | `day2.s04.first_round` (before)<br>`day2.s04.first_round_after_loss` (after_loss) | [D08](day_02_integration_pending.md#d08) |
| `s04_second_round`<br>715–790 | 待确认（固定获胜，同上）<br>settlement | `day2.s04.rounds` | `review.day2.s04_second_round_before`<br>`review.day2.s04_second_round_after_win`<br>`review.day2.s04_second_round_after_reward`<br>`review.day2.s04_second_round_waiver` | `day2.s04.second_round` (before)<br>`day2.s04.second_round_after_win` (after_win)<br>`day2.s04.second_round_after_reward` (after_reward)<br>`day2.s04.second_round_waiver` (waiver) | [D08](day_02_integration_pending.md#d08)、[D15](day_02_integration_pending.md#d15) |
| `s04_leave_casino`<br>791–807 | 自动演出<br>settlement | `day2.s04.leave` | `review.day2.s04_leave_casino_before` | `day2.s04.leave_casino` (before) | [D08](day_02_integration_pending.md#d08)、[D15](day_02_integration_pending.md#d15) |
| `s05_street_check`<br>812–828 | 自动演出<br>settlement | `day2.s05.street` | `review.day2.s05_street_check_before` | `day2.s05.street_check` (before) | [D08](day_02_integration_pending.md#d08)、[D09](day_02_integration_pending.md#d09) |
| `s05_back_in_shop`<br>829–859 | 自动演出<br>shop | `day2.s05.back_in_shop` | `review.day2.s05_back_in_shop_before` | `day2.s05.back_in_shop` (before) | [D09](day_02_integration_pending.md#d09)、[D11](day_02_integration_pending.md#d11) |
| `s05_make_special`<br>860–887 | 自动演出 → 玩家操作 → 自动演出<br>shop | `day2.s05.special_before` | `review.day2.s05_make_special_before`<br>`review.day2.s05_make_special_after` | `day2.s05.make_special` (before)<br>`day2.s05.make_special_after` (after) | [D09](day_02_integration_pending.md#d09) |
| `s05_deliver_guard`<br>888–926 | 自动演出 + 玩家操作（交付）+ 自动演出<br>settlement | `day2.s05.guard_greet` | `review.day2.s05_deliver_guard_before`<br>`review.day2.s05_deliver_guard_after_delivery`<br>`review.day2.s05_deliver_guard_after_reward` | `day2.s05.deliver_guard` (before)<br>`day2.s05.deliver_guard_after_delivery` (after_delivery)<br>`day2.s05.deliver_guard_after_reward` (after_reward) | [D02](day_02_integration_pending.md#d02)、[D09](day_02_integration_pending.md#d09) |
| `s05_useful_guard`<br>927–953 | 自动演出<br>settlement | `day2.s05.useful_guard` | `review.day2.s05_useful_guard_before` | `day2.s05.useful_guard` (before) | [D09](day_02_integration_pending.md#d09)、[D10](day_02_integration_pending.md#d10) |
| `s05_unsolved`<br>954–979 | 自动演出<br>shop | `day2.s05.unsolved` | `review.day2.s05_unsolved_before` | `day2.s05.unsolved` (before) | [D01](day_02_integration_pending.md#d01)、[D09](day_02_integration_pending.md#d09)、[D13](day_02_integration_pending.md#d13) |

## 玩家操作 Phase 草案

自动演出自然结束后由玩家实际操作；只能消费业务成功提交的持久事实，Bridge 独占输出 flag。`allow_existing` 未定时为 null；不擅自选历史策略。下表 `config` 可组成六字段也仍不等于已接线／可发布。赌场第一局、第二局奖励、债务免除与守卫制作、交付、支付分别保留真实边界，最终拓扑见交接清单。

| Phase／Beat | 前置事件／等待 stage | 来源事实／历史策略 | Bridge 输出／续播事件 | 真实业务 owner | 缺口／配置状态 |
| --- | --- | --- | --- | --- | --- |
| `day2.bridge.festival_order`<br>`s02_festival_talk` | `day2.s02.festival_order`<br>`null` | `delivery.day2_s02_festival_order.completed`<br>allow_existing=`true` | `day2.bridge.festival_order.completed`<br>`day2.s02.festival_after` | B.is_group_served（订单与持久接线未配置） | D04/D14：独立阶段、组员、订单、实际到达；rumor 不能用一单冒充全组；config=null |
| `day2.bridge.elder_order`<br>`s02_elder_authority` | `day2.s02.elder_order`<br>`null` | `delivery.day2_s02_elder_order.completed`<br>allow_existing=`true` | `day2.bridge.elder_order.completed`<br>`day2.s02.elder_after` | B.is_group_served（订单与持久接线未配置） | D04/D14：独立阶段、组员、订单、实际到达；rumor 不能用一单冒充全组；config=null |
| `day2.bridge.emissary_order`<br>`s02_emissary_rumor` | `day2.s02.emissary_order`<br>`null` | `delivery.day2_s02_emissary_order.completed`<br>allow_existing=`true` | `day2.bridge.emissary_order.completed`<br>`day2.s02.emissary_after` | B.is_group_served（订单与持久接线未配置） | D04/D14：独立阶段、组员、订单、实际到达；rumor 不能用一单冒充全组；config=null |
| `day2.bridge.rumor_order`<br>`s02_tavern_casino_talk` | `day2.s02.rumor_order`<br>`null` | `null`<br>allow_existing=`true` | `day2.bridge.rumor_order.completed`<br>`day2.s02.rumor_after` | B.is_group_served（订单与持久接线未配置） | D04/D14：独立阶段、组员、订单、实际到达；rumor 不能用一单冒充全组；config=null |
| `day2.bridge.errand_runner`<br>`s02_find_errand_runner` | `day2.s02.errand`<br>`null` | `day2.s02.errand_runner_hired`<br>allow_existing=`null` | `day2.bridge.errand_runner.completed`<br>`null` | D 临时代购（未发现交付） | D03：招募不是购买或治疗完成；无招募对白、资金与期限规则；可能 Day3 仍未招募，不设营业硬前置；config=null |
| `day2.bridge.amber_wine`<br>`s03_amber_wine` | `day2.s03.amber_wine`<br>`null` | `day2.s03.amber_wine_bought`<br>allow_existing=`true` | `day2.bridge.amber_wine.completed`<br>`day2.s03.commission_token` | C.TavernPurchase.purchase 成功回执→集成投影 | D07/D15：价格、同源商品、折扣资格、限量与余额不足；当前没有该业务 flag 写入者；config=null |
| `day2.bridge.casino_reward`<br>`s04_second_round` | `day2.s04.casino`<br>`null` | `day2.s04.casino_reward_received`<br>allow_existing=`true` | `day2.bridge.casino_reward.completed`<br>`day2.s04.leave` | C.FixedStoryCasino.get_status + A.get_task_result | 必须另拆 loss/win/reward/waiver 边界；D08 奖励、身份、赌具模式未定；不能只凭一枚 flag 完成赌场；config=null |
| `day2.bridge.special_drink`<br>`s05_make_special` | `day2.s05.back_in_shop`<br>`day2.s05.wait_special_drink` | `day2.s05.special_drink_made`<br>allow_existing=`true` | `day2.bridge.special_drink.completed`<br>`day2.s05.special_after` | TeaProduction 真实指定成品入库→集成投影 | D09：配方、数量、血液排除、制作前对白事件边界未冻结；after_event 需包含制作前对白，不能丢句；v2 草案，未发布 |
| `day2.bridge.guard_delivery`<br>`s05_deliver_guard` | `day2.s05.guard_greet`<br>`null` | `day2.s05.special_drink_delivered`<br>allow_existing=`true` | `day2.bridge.guard_delivery.completed`<br>`day2.s05.guard_after` | TaskDelivery / GameState.commit_delivery | D02/D09：Actor、交付入口、阶段、配方与价格；前三句必须先于真实交付；config=null |
| `day2.bridge.guard_reward`<br>`s05_deliver_guard` | `day2.s05.guard_after`<br>`null` | `day2.s05.guard_reward_paid`<br>allow_existing=`true` | `day2.bridge.guard_reward.completed`<br>`day2.s05.useful_guard` | 实际钱包结算回执→集成投影 | D09：原文先喝再付费，与原子交付收款的边界需确认；谢了及其后数句必须在支付后，不能直接跳到 useful_guard；config=null |

## Case 与实际验证记录

工程 `pending.cases` 保存本范围 80 个稳定 case ID。每 Beat 的 `.source` 核对原文、归属与分段；`.route` 仍为 pending，fixture=null。选择两路／采集条件正反以及每个 Phase 的业务事实正反另列 case；未真实执行的 case 不写通过。真实交互检查证明空发布集合不遮蔽 fallback，不证明待发布剧情已经能运行。

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
