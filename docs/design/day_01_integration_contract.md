# Day 1 正式剧情与业务配置约定

核对日期：2026-10-17。源码基线：`ab18ce6`。本文件与[待定清单](../story_authoring/day_01_integration_pending.md)共同交付开发顺序 1；只定义对接，不是可加载配置，也不代表 Day 1 已接通。

2026-10-18 增量核对：当前源码已发布 S01–S02，strange_coin 为真实库存币；[S05 投掷与守卫组件](../gameplay/day_01_stealth.md)已加入正式聚落宿主，但火把、角色、支付与撤离配置仍缺失，正式 S05 尚未接通。下文历史“规划/未接线”矩阵不能覆盖这些源码现状；此次不冻结 P06/P08/P09 的剧情顺序和数值。

并行工作提示：核对期间工作区出现未提交的 `GameEntry`、标题菜单、暂停返回标题接线，以及将默认入口改为标题菜单的修改。本文件不纳入或验收这些改动；下述正式入口/新游戏缺口以已提交基线为准。合并后集成端应重新确认启动路径，不能据本文重复实现已有的并行工作。

## 1. 内容权威与发布边界

| 范围 | 内容依据 | 使用约定 |
| --- | --- | --- |
| S01–S02 | [前两个阶段初稿](day_01_stages_01_02_draft.md) | 保留 Beat、对白、表情意图、玩家操作及原有待确认项；不反向采用旧 Demo 内容 |
| S03–S06 | [Day 1 修改版](day_01_story_flow_revised.md)的对应阶段 | 保留角色动机、选择及剧情顺序；正文与补充对白有冲突时进入 pending，不自行择一 |
| 已执行试编排 | [day1_scene01](day_01_scene_01.md)及[映射清单](../story_authoring/day1_scene01.json) | 仅独立开场至顾客点单；不能当成正式 S01 或制作教程完成 |
| 历史范围差异 | [Day 1 精简执行稿](day_01_development_spec.md) | 仅用于识别差异。不得据此删除新版投掷、双守卫、混乱撤离、地图或接受/拒绝选项 |
| 后续生成 | [编排工作流](../guides/story_authoring_workflow.md)、[指令表](../guides/story_authoring_commands.md) | Markdown 继续是剧情唯一内容来源；本文只补接线约定，不补对白、数值、坐标或节奏 |

本次只新增两份 Markdown。不更改原稿、Story/Dialogue/Phase、正式任务/菜单、场景、脚本、输入或默认入口；不自动启动剧情，不自动迁移存档。所有新增 ID 都是规划预留，须由后续实现与编排共同发布。

引用状态统一如下，后文不能省略宿主差别：

- **已有且宿主已注册**：源码可追到实际创建/注册/注入；仅证明静态接线，不代表本次运行通过。
- **资源存在但未接线**：文件、数据或位置存在，但目标正式剧情尚未加载、注册或绑定；锚点不等于交互能力。
- **规划预留**：本文件为协作保留的名字，当前不应写入发布 JSON 并期待其执行。
- **待确认**：来源矛盾、身份/空间/数值不明确或能力不足，见编号 pending。存在候选文件也不能擅自升级为已确认。

## 2. 六阶段对接与依赖

下表中的“成功”是后续实现必须验证的业务或剧情结果，不是要求现在用 `set_flag` 模拟成功。模式未由原稿明确的部分保留待确认。

| 阶段与原稿定位 | 模式与进入条件 | 成功结果与后续 | 重复、取消及当前缺口 |
| --- | --- | --- | --- |
| S01 `shop_opening` → `first_human_customer` | 自动演出；正式新游戏启动，进入奶茶店 | 顾客真实点单后结束短事件，进入教学操作等待 | 仅完整成功才消耗 once；失败可能已生成顾客，重试须处理现场。人类顾客与正式宿主未定：[P02](../story_authoring/day_01_integration_pending.md#p02) |
| S01 `first_drink_tutorial` → `stage_one_end` | 玩家操作后自动演出；点单成功、订单已发布 | 查看订单→正确制作入库→交人类顾客→货款到账；全部成立后进入 S02 | 关窗/错误配方不完成；制作成功不等于交付或收款。不能拿现有胖哥布林示例代替：[P04](../story_authoring/day_01_integration_pending.md#p04)、[P11](../story_authoring/day_01_integration_pending.md#p11) |
| S02 `shop_quiet_again` → `goblin_first_customer` | 自动演出；S01 教学及收款成功 | 首位哥布林点单后进入玩家操作 | 日期与身份绑定不猜测：[P01](../story_authoring/day_01_integration_pending.md#p01)、[P03](../story_authoring/day_01_integration_pending.md#p03) |
| S02 `goblin_first_order` → `goblin_coin_reaction` | 玩家操作后自动演出；首位哥布林订单可用 | 真正交付→按原稿获得古怪金币→反应对白；之后进入群客段 | 交付回执不能代替金币取得；重复演出不再发币，取消不回滚已提交交付：[P05](../story_authoring/day_01_integration_pending.md#p05)、P11 |
| S02 `goblin_group_customers` → `chronicle_unlocked` | 自动演出；首枚金币取得与反应段完成 | 群客点单；解锁赌场、格里芬之血、长老的空白条目，再开放群客订单操作 | 空正文不补写背景真相；见闻录服务能建空条目，但功能入口目前从启动即存在：[P12](../story_authoring/day_01_integration_pending.md#p12) |
| S02 `goblin_group_orders` → `coins_raise_suspicion` | 玩家操作后自动演出；这批订单已明确 | 全批真实交付并按原稿收币→顾客离场→主角决定调查金币，进入 S03 | 数量未定，不能用总制作数或三笔教学队列冒充全批交付；按订单集合去重：[P03](../story_authoring/day_01_integration_pending.md#p03)、P04、P05 |
| S03 修改版「第三阶段：消失的街道」 | 出店、有限探索与自动反应混合；S02 成功 | 玩家实际出店，探索结束退回店门，形成异世界发现认知→S04 | 原稿列的是观察示例，不是已批准的必查点。衣柜与变量秘密不得展示；出入口、范围及结束判定：[P13](../story_authoring/day_01_integration_pending.md#p13) |
| S04 修改版「第四阶段」及「补充：第四阶段的整体对白」 | 对话/选项与地图查看；S03 发现完成 | 保留信仰、血液传闻、地图与委托；接受/拒绝两条原有路径最终汇合到接受，进入夜间准备 | 正文在店外，补充对白却先在店内消费；该普通订单是否玩家操作未明确。地图能力、时间过渡和准确顺序：[P08](../story_authoring/day_01_integration_pending.md#p08)、[P14](../story_authoring/day_01_integration_pending.md#p14) |
| S05 修改版「第一部分、关卡教学」step1–step3 | 玩家操作与演出混合；委托已接受、夜间条件已由正式业务建立 | 按原稿查看目标/小地图、投币引开入口守卫、投掷与贿赂突破宅邸双卫 | 不能改写为只有一名醉酒守卫，也不能以移动 NPC 冒充完整潜行。投掷、发现后处理、支付/放行：[P06](../story_authoring/day_01_integration_pending.md#p06)、[P09](../story_authoring/day_01_integration_pending.md#p09) |
| S05 修改版「第二部分、剧情事件：醉酒的守卫」 | 必然发生的短事件；相对 step1–step6 的确切位置未定 | 支付成功、放行并记录次日特殊订单伏笔；不要求当日在酒馆/赌场取得材料 | 与双卫贿赂是否同一次支付未定；不能重复扣钱或拿日后交付作本次放行前置：P06、P09 |
| S05 step4 与「第三部分、取得格里芬之血的细节」 | 调查/拾取与自动演出混合；已进入可搜索区域 | 取得文书相关信息及血液，目标转向撤离；详细段落先翻文书后拿血 | 不采用旧稿“文书必为拾血硬门槛”的默认值；阅读/持有及顺序需定。入库与一次性回执必须真实：[P07](../story_authoring/day_01_integration_pending.md#p07)、[P08](../story_authoring/day_01_integration_pending.md#p08) |
| S05 step5–step6 与详细段落的返店 | 玩家操作与演出混合；已取得所需物品/信息 | 教学版要求取火把、投向可燃物、制造混乱撤离；详细段落写沿原路返回。统一后安全返店→S06 | 保留两种来源的差异，不删除混乱桥段也不强行插入详细段落；火把、阻碍、撤离判定及重试待定：P08、P09、P13 |
| S06 修改版「第六阶段：第一杯格里芬之血特调」 | 玩家制作/用量选择、交付及自动异常演出，后续帮助/休息的交互模式待定 | 血液成为可用材料→特调成品入库→交给胖哥布林→饮用异常→帮助并暂留休息，完成本章叙事 | 不把制成当喝下；材料未明、配方未定时不发布假可玩段。没有“三档统一中毒”等已定数值：[P07](../story_authoring/day_01_integration_pending.md#p07)、[P10](../story_authoring/day_01_integration_pending.md#p10) |

依赖主链为 S01→S02→S03→S04→S05→S06。S04 两个选择只改变对白路径，最后汇合；不能设成一条永久拒绝分支。S05 的具体子节点拓扑由 P08/P09 阻塞，当前不宣称内部顺序已全部冻结。

不存在“先完成守卫次日特调才能放行 Day 1”的依赖；Day 1 只建立伏笔。S06 必须依赖实际持有可用血液与返店结果，不能仅凭剧情阶段强行开放制作。内容中衣柜机制、长老真实目的、血液长期危害属于开发者信息，不作为玩家可见见闻录正文。

## 3. 统一 ID 表

### 3.1 命名与兼容

事件、对白、任务、见闻录及事实使用点号命名空间；新规划统一以 `day1.` 开头。六个章节阶段为 `day1.s01`、`day1.s02`、`day1.s03`、`day1.s04`、`day1.s05`、`day1.s06`，均为规划预留，当前运行未采用。

**订单、成品/原料、交付对象 ID 的当前 TaskCatalog 校验要求 `is_valid_identifier()`，不能含点号。** 因此这些新对象采用同一逻辑命名空间的 `day1_` 前缀；不能为了点号统一而生成现有 Loader 拒绝的配置。不改 Schema、不重命名已有 ID。

Bridge 的每条 phase 要求 `stage` 唯一，因此章节名不能同时用作 S02 多个等待阶段。预留操作子阶段 `day1.s01.wait_human_order`、`day1.s02.wait_first_goblin_order`、`day1.s02.wait_group_orders`、`day1.s06.wait_blood_drink`；完整子阶段与 phase 发布时一一对应，章节名仅作为归类，不将其误写为额外的 GameState 字段。

### 3.2 现有执行内容与规划名字

| 类型 | ID / 规划规则 | 状态与约束 |
| --- | --- | --- |
| 已有试编排事件 | `day1.scene01` | 已有且宿主已注册：仅 [Day1Scene01Demo](../../src/debug/story/day1_scene01_demo.gd) 加载/请求；正式 MainGame 不加载 |
| 已有试编排对白 | `day1.scene01_background`、`day1.scene01_order` | 已有且宿主已注册：同一 Demo 加载 [对白文件](../../src/resources/dialogue/day1_scene01.json)；六句对白，含五句独白和一句点单 |
| 规划演出事件 | `day1.s01.opening`、`day1.s01.after_human_order`；`day1.s02.first_customer`、`day1.s02.coin_reaction`、`day1.s02.group_arrival`、`day1.s02.after_group_orders` | 规划预留；以源稿操作边界拆短事件，不能把玩家操作塞进 busy 事件；不自动替换 `day1.scene01` |
| 规划后四阶段事件 | `day1.s03.discovery`、`day1.s04.commission`、`day1.s05.drunken_guard`、`day1.s05.document`、`day1.s05.return_shop`、`day1.s06.reaction` | 规划预留；是事件名预留，不决定原稿未明确的触发点或 S05 子顺序；其他短事件按源稿细化后登记 |
| 规划对白 | `day1.s01.shop_opening`、`day1.s01.first_human_customer`；S02 使用 `day1.s02.<原 Beat ID>`；后续使用 `day1.s03.discovery`、`day1.s04.commission`、`day1.s05.drunken_guard`、`day1.s05.document`、`day1.s06.reaction` | 规划预留；同一字符串可用于不同类型，但跨事件对白须显式引用。对白拆分后保留 Beat 对应关系，不生成本文未提供的台词 |
| 规划任务 | `day1.s01.human_order`、`day1.s02.first_goblin_order`、`day1.s02.group_orders`、`day1.s04.blood_commission`、`day1.s06.blood_drink` | 规划预留；不将旧任务完成直接等同为新任务完成 |
| 现有制作订单 | `order_001`、`order_002`、`order_003` | 资源存在但未接线到正式剧情：[basic_menu.tres](../../src/resources/milk_tea/basic_menu.tres) 固定顺序队列，只能制作一次连续前缀，不能重开 UI 重置 |
| 规划制作/交付订单 | `day1_s01_human_order`、`day1_s02_first_goblin_order`、`day1_s02_group_order_<序号>`、`day1_s04_fat_goblin_order`、`day1_s06_blood_drink` | 规划预留；群客序号与 S04 是否需要玩家订单分别由 P03/P14 决定，当前固定队列不能按这些名字动态发单 |
| 现有原料 | `black_tea`、`green_tea`、`creamer`、`pearl`、`coconut`、`syrup` | 已有且宿主已注册：两个正式入口共用 GameState 库存；实际配方仍为示例。`insomnia_mushroom` 也在目录，但不是 Day 1 血液 |
| 现有成品 | `pearl_milk_tea`、`coconut_milk_tea`、`plain_milk_tea` | 已有且宿主已注册：固定制作产物；是否成为正式订单配方由 P04 决定，禁止仅凭“普通奶茶”自动选配方 |
| 规划物品 | `day1_griffin_blood`、`day1_blood_milk_tea` | 规划预留：需新增真实定义、取得和制作接线；不将 `has_blood` 一类 flag 当库存 |
| 古怪金币/文书/地图/火把 | 不分配最终物品 ID | 待确认：金币可能是物品或货币；文书可能仅阅读；地图可能是功能；火把数量/用法未定。确认数据类型后才建立 `day1_` 物品名：P05/P08/P09/P14 |
| 规划见闻录条目 | `day1.chronicle.casino`、`day1.chronicle.griffin_blood`、`day1.chronicle.elder`、`day1.chronicle.griffin`、`day1.chronicle.emissary` | 规划预留；前三项按 S02 原稿解锁空白，其他按 S04 信息；同一对象跨章节继续补记，不重新建条目 |
| 规划见闻录记录 | `day1.chronicle.<条目短名>.s04_first`、`day1.chronicle.<条目短名>.s04_follow_up` | 规划预留的命名模板，不是字面 ID；后续只对确有 Markdown 正文的记录分配。只解锁空白时不调用 append |

### 3.3 宿主绑定：角色、交互、位置和音频

| 引用 | 实际核对与状态 | 正式剧情边界 |
| --- | --- | --- |
| `player` | 已有且宿主已注册：[MainGame](../../src/core/main.gd) 在店铺/聚落创建 ActorDirector 并注册玩家 | 可复用，但不能据此推断出生点、朝向和每段走位已确认 |
| `fat_goblin` | 已有且宿主已注册：独立店铺与聚落都有该 SettlementCharacter，MainGame 同时创建同 ID 的 NPC 交互点 | 可作为真实交付目标；正式 S04/S06 的出现时机、位置、普通/特殊订单仍未配置 |
| `common_goblin`、`guard` | 已有且宿主已注册：聚落实例并注册；角色文件为 `src/gameplay/characters/common_goblin.tscn`、`guard.tscn` | `guard` 是角色，不是 `drunken_guard`；普通哥布林模板不能代表多名独立顾客实例或宅邸双卫 |
| `guard_captain`、`elder`、`chef`、`tavern`、`casino` | 已有且宿主已注册：聚落人物及其同名交互点 | 场景当前有长老不等于 Day 1 长老应在场，需按原稿外出条件管理；不得将守卫长默认当第二名宅邸卫兵 |
| `customer` | 已有且宿主已注册：试编排由 actor_spawn 动态生成 `src/debug/cinematic/customer.tscn` | 是经试编排注明的占位角色，不是已确认正式人类顾客；正式预留 `day1_human_customer`，P02 |
| `orders`、`storage`、`tea_station` | 已有且宿主已注册：两种关卡返回交互点，MainGame 交给 ShopInteraction | 分别为订单板、仓库、制作台；剧情 trigger 路由优先，失败类型不能都当 UI 回退 |
| `door`、`aisle`、`counter` | 已有且宿主已注册：仅试编排场景保存 Marker，宿主同步变换后调用 register_position | 正式场景未按同名注册；不要复制 Demo 坐标到聚落 |
| `00_shop_entrance`、`shop_rest_chair`、`shop_workbench`、`drunken_guard`、`elder_document`、`elder_blood_storage` | 资源存在但未接线：聚落 [SettlementMap](../../src/levels/settlement/settlement_map.gd) 提供 get_story_anchor，Marker 保存在地图场景 | MainGame 未将这些锚点自动 register_position；它们不是出入口、调查/拾取 trigger 或成功事实。`drunken_guard` 也不是已注册 Actor ID |
| `night_gather_0` 至 `night_gather_7` | 已有且宿主已注册：聚落 GatheringService 注册实际 GatherPoint；同名 Marker 另存于 StoryAnchors | 当前采集的是醒神菇示例，不是取得圣血的实现；夜间 flag 不等于正式日程服务 |
| 正式出店、文书、血液容器交互 | 规划预留 `day1_exit_shop`、`day1_elder_document`、`day1_blood_storage` | 尚无这些可用点位；原有 `00_shop` / `10_elder` 为地点说明，不能冒充剧情出入口/搜索成功 |
| `shop.door_bell` | 已有且宿主已注册：试编排宿主明确 register_sound；声音也在 [SoundLibrary](../../src/resources/audio/sound_library.tres) | 正式 MainGame 未自动导入 SoundLibrary，不能声称正式宿主已注册 |
| `music.daily_milk_tea`、`shop.order_open`、`shop.tea_pour`、`shop.sealer` | 资源存在但未接线：SoundLibrary 有 ID；基础 AudioManager 场景未配置 sounds 字典，MainGame 未注册目录 | 当前试编排脚本也只注册门铃，Story JSON 没有 BGM 步骤，与其 Markdown 音乐要求不一致，见 [P15](../story_authoring/day_01_integration_pending.md#p15)；不在本次修复 |

正式 Actor 预留 `day1_first_goblin_customer`、`day1_group_goblin_<序号>`，具体实例数、模板与立绘由 P03 决定。Actor ID、说话人名称和立绘映射各自独立，不能按名字相似自动绑定。

## 4. 事实归属、事务与 Bridge

### 4.1 现有接口与事实

| 能力/事实 | 已有接口与实际语义 | 不能据此推断 |
| --- | --- | --- |
| 制作入库 | [TeaProduction](../../src/gameplay/milk_tea/tea_production.gd).make_drink(recipe, order_id)，`changed()` 后可查询制作数/队列及库存 | changed 不携带成功订单 ID，也没有正式 Day 1 made flag；固定队列制作完成不等于顾客已收货 |
| 实际交付 | [TaskDelivery](../../src/core/tasks/task_delivery.gd).try_submit(order_id, target_object_id)、deliver_to(target_object_id)，成功发 `delivered(order_id)` | 同步事务包含扣物品、物品奖励、完成 flag 和回执，不包含钱包收款 |
| 当前交付事实 | `shop.order_001_delivered`；`delivery.order_001.completed`、`delivery.order_insomnia_01.completed`；`tavern.insomnia.delivered` | 只有对应交付成功才写；不是点击次数，不是正式人类顾客完成，也不是特调喝下 |
| 订单板查看 | `shop.orders_viewed` 由 MainGame 在 UI 真正打开后写入 | 不区分阶段/订单；不能拿它证明某笔正式订单已被看过 |
| 当前总量 | `shop.orders_completed` 由交付器按成功回执更新；TeaProduction.get_completed_count 是制作数 | 交付计数可能包括材料委托，不适合作为正式群客订单集合完成条件 |
| 钱包 | [WalletTransactions](../../src/core/economy/wallet_transactions.gd).add_money/spend_money/purchase/claim_reward；结果 ok/code/request_id，`transaction_finished(result)` | 普通余额不是已确认古怪金币物品；TaskDelivery 不自动调用钱包；初始余额 0，商品和货币奖励默认未配置 |
| 任务进度 | TaskJournal 只读投影 GameState；任务目录 Schema 支持 flag/event_completed/variable_at_least | 任务完成没有普遍的发金币动作；当前交付 rewards 只接受 text/reveal_when/items，不支持直接添 money 字段 |
| 见闻录 | ChronicleJournal.unlock_entry/append_record；Story 支持 chronicle_unlock/chronicle_append | 不自动从对白关键词提取内容；全局记录 ID 去重；没有正式 Day 1 条目库 |
| 会话与恢复 | GameState 持有库存/制作/钱包；start_new_game、to_dict、restore_state，完整快照 schema_version=2 | 不含磁盘保存/正式标题流程；不能在换场景时 reset 或恢复局部剧情快照清空经营数据 |

### 4.2 规划业务事实与写入责任

以下全部为**规划预留**，当前没有对应写入者。业务端实现成功后再发布；正文中的事实名是准确约定，不能当现有 API 使用。

| 事实/变量 | 写入责任及成功证据 | 剧情消费点 |
| --- | --- | --- |
| `day1.s01.order_made`、`day1.s01.order_delivered`、`day1.s01.order_paid` | 制作/交付/结算协调层分别确认指定订单成功；paid 需要钱包真实回执 | S01 教学目标与结束段；不能由 Story 直接设置假成功 |
| `day1.s01.business_completed` | 同一协调层确认上述三者属于同一订单，且所需收款已完成；P11 未解前无写入者 | S01 Bridge 的单一输入，不把 Bridge 扩为 AND 表达式执行器 |
| `day1.s02.first_order_delivered`、`day1.s02.first_coin_received` | 对应交付与金币取得业务；币的表示按 P05 | 交付后进入收币/反应，不能提前将剧情事件完成当金币入账 |
| `day1.s02.group_orders_completed` | 群客协调层核对发布的订单集合及每笔交付/原稿收币结果；数量待 P03 | 群客操作后的续播；不用 shop.orders_completed 总量替代 |
| `day1.s03.exploration_completed` | 正式探索协调层确认原稿最终采用的观察/返回条件 | S03 收束；条件待 P13，不编造若干必查点 |
| `day1.s04.map_available` | 实际地图功能在已确认形式下可用；若仅是提示不得写 | 原稿地图查看能力；P14 |
| `day1.s04.commission_accepted` | 两条原稿选项路径成功汇合后的 Story 确认；只表示承诺，不自动发物品或钱 | 任务激活、夜间准备准入 |
| `day1.s05.guard_payment_completed` | 支付业务以稳定事务 ID 确认真实扣款；具体哪次贿赂由 P06/P09 | 支付后的放行演出，不用 spend 请求已发出作为成功 |
| `day1.s05.document_read` | 文书内容实际展示完成后的调查协调层 | 任务目标/认知；是否要求与拾血先后绑定待 P08 |
| `day1.s05.blood_acquired` | 真实入库及一次性取得回执提交后由拾取协调层写入 | 历史取得事实；后续能否制作仍须查实际库存，不将历史取得等同当前持有 |
| `day1.s05.escape_completed`、`day1.s05.returned_shop` | 确认后的撤离与场景/区域过渡业务 | 分别表示安全撤离、实际返店，不能只改 story_stage 冒充抵达 |
| `day1.s06.blood_drink_made`、`day1.s06.blood_drink_delivered` | 正式特调订单制作/交付业务 | 交付后播放饮用与异常；不能将原有 pearl_milk_tea 成品认作特调 |
| `day1.s06.blood_amount` | 用量操作成功后保存玩家选择，类型/单位/范围待 P07 | 如原稿需要则用于反馈；本文不规定 1/2/3 或药效计算 |
| `day1.s06.completed` | 整段异常、帮助及休息安排按最终稿完成后由 Story 写入 | 章节完成；结束 UI 与回标题另按 P10 实现 |

任务激活统一预留 `day1.task.<任务短名>.active`，例如 `day1.task.human_order.active`、`day1.task.blood_commission.active`；任务完成直接引用已验证的业务事实或成功事件，不复制独立任务计数。S04 接受事实可直接作为取血委托激活条件，不强制再写第二个等价 flag。

### 4.3 续播与中断约定

- 演出短事件在玩家操作前结束；宿主不能在 StoryDirector busy 中解锁玩家。phase 继续使用现有 v2 六字段，业务输入 completion.flag 与 Bridge 输出 completion_flag 不同。
- 预留 phase ID `day1.bridge.<操作短名>`，输出 `day1.bridge.<操作短名>.completed`；例如 `day1.bridge.human_order` 与 `day1.bridge.human_order.completed`。这些名字尚未生成配置；before/after 事件和 stage 必须真实存在且相互匹配。
- 对已明确绑定的唯一订单持久回执，采用 `allow_existing: true`，避免取消重入后要求重做已消耗订单；原稿若要求本阶段新操作则先作为能力/语义冲突登记，不能擅自清旧回执。未完成的投掷、潜行等不预设历史策略。
- 自动续播段同时检查前置事件成功、操作子阶段及 Bridge 输出；StoryLibrary 的条件不会自动启动事件，需要 phase 或正式宿主请求。未知能力不添加虚构 command。
- 失败配方、缺料、错误对象、关窗不写成功。已提交制作/交付/入账不因取消对白回滚；重试使用原订单与稳定回执，场景重建继续同一经营会话。
- **交付与钱的原子边界尚未实现**：先扣成品再单独 add_money 不能当作“整笔订单完成”。P11 决定原子扩展或可恢复的分步结算后，才能发 business_completed；本次不替业务选择方案、不设 fake paid flag。

## 5. 现有示例与两机协作

| 示例/接线 | 当前行为 | 正式接入时的必要处理（本次不执行） |
| --- | --- | --- |
| `shop.first_order` → `order_001` → `pearl_milk_tea` → `fat_goblin` | 真实制作和交付、糖浆奖励 1 份 | 不能充当 S01 人类顾客；由集成端决定隔离示例或发布独立 Day 1 配置，避免改名导致已有快照/测试失配 |
| `tavern.insomnia_order` → `order_insomnia_01` | 醒神菇 3 份交 tavern，糖浆 2 份占位奖励 | 不是 Day 1 主线，也不是已批准的后续醒神菇代购规则；不能误加入 Day 1 正式任务链 |
| 打开 `orders` | MainGame 遍历交付目录并 accept_order；交付器检查 reveal_when 后激活 | 正式阶段任务不能靠查看一次订单板全部提前接取；需先定义发布/阶段门控，不能只添加任务 JSON |
| 固定制作队列 | 永远从 order_001 连续制作到 order_003，不按 story_stage 选单 | 新增多阶段订单前需明确队列/发布能力；不能把现有三笔反复映射到多人收款 |
| NPC 路由 | Story 交互优先；无匹配才尝试采集/交付 | 宽泛 NPC 对白可能遮蔽交付，once 结束后的 fallback 也需验证；同一 fat_goblin 对应普通/特殊订单时用阶段与明确订单区分 |

剧情端维护原稿、演出/对白/phase 和追踪映射；业务端维护独立玩法服务、成功事实、失败与恢复契约；**集成端集中修改 MainGame、正式菜单、任务目录与场景注册**。跨机器共享本文件的 ID 和 pending 编号，不直接修改另一端生成物，也不把测试 fixture 当正式发布内容。

新资源或新决定先更新对应源稿的编排约定，再更新本文与 pending，然后生成并验证关联 Beat。只有 pending 的受影响区间不能发布，其他已明确段落可继续独立编排。本文不代替原 Beat 清单，不伪造 source_sha256 或可执行验证 cases。

## 6. 检查结果与后续验收

本次静态核对：上述引用对应任务/菜单、MainGame 注册、Demo 注册和业务接口；已提交基线的正式入口为 `src/core/settlement.tscn`，没有完整 Day 1 加载启动。工作区并行修改已将入口指向标题菜单，其导航不能等同为六阶段剧情已加载。已确认主阶段链没有要求后续结果作为前置的循环；S05 内部顺序、支付以及 S04 场所冲突明确挂起，不宣称完整拓扑已通过。

后续发布前逐项验证：同一订单不重复制作/交付/收款；不同订单的回执不会互相完成；交付后取消仍能正确收束；群客完成只核对本批订单；phase 的 stage 唯一且来源/输出不同；Story trigger 不遮蔽业务；物品实际入库后才可制作；取得文书、血液和撤离的最终顺序均有明确原稿依据。

本次只检查 Markdown、文件/ID/接口引用、命名约束、Git diff 和修改范围，不运行引擎、编排 cases 或整套玩法回归。没有新增试玩入口；已有 F6 `src/debug/story/day1_scene01_demo.tscn` 仅用于原开场，不能验收上述规划。用户及并行流程的 `project.godot`、MainGame、标题/暂停界面与测试改动均不修改、不暂存。
