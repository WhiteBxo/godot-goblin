# 系统优先级：剧情并行推进时的开发清单

整理日期：2026-10-17。前提：剧情编排在另一台机器上推进，本清单只列**不与剧情文本冲突**的系统工作，用于决定接下来写哪部分代码。

依据：[系统设计审查](system_design_review.md)、[Day 1 执行规格](../Day1开发.md)、各模块说明与当前源码。

## 结论

现在只推进 4 个系统，按以下顺序，逐个交付“触发 → 消耗 → 结果 → 失败 → 恢复”：

1. 日程与期限（Day / Phase 状态机）
2. 任务失败、超时与不可逆结果
3. 最小营业循环（顾客来店 → 接单 → 交付收款 → 离店）
4. 采集与任务物资提交

这四个系统都是剧情侧要调用的**下游接口**，不含任何对白、Beat 或场景演出；剧情分支合并后只需接数据，不需要返工系统实现。

## 已有能力：不要重做

| 能力 | 位置 | 备注 |
| --- | --- | --- |
| 统一经营会话、跨场景状态、快照 v2 | `src/core/game_state.gd` | 切场景、重载不丢库存/成品/事实 |
| 共享库存、发现与属性隐藏 | `src/gameplay/milk_tea/warehouse_inventory.gd` | 原子扣料、容量校验 |
| 固定订单制作 | `src/gameplay/milk_tea/tea_production.gd` | 制作与交付已分开 |
| 成品携带、指定对象交付、幂等发奖 | `src/core/tasks/task_delivery.gd` | 交付回执在 GameState flags |
| 钱包、购买、幂等领奖（含 money） | `src/core/economy/wallet_transactions.gd` | 目前正式配置无价格 |
| 任务目录、事实投影、HUD | `src/core/tasks/task_catalog.gd`、`task_journal.gd` | 正式目录只有 `shop.first_order` |
| 见闻录 | `src/core/chronicle/chronicle_journal.gd` | 已可被 StoryDirector 写入 |
| 演出基础 | `src/core/story/`、`src/core/actors/`、`src/core/camera/` | 对白、等待、镜头、角色、音频、转场 |
| 开发工具与测试 | `src/debug/developer_tools/`、`tests/` | F3 面板、各模块 headless 验证 |

## P0：现在做

| # | 系统 | 为什么现在做 | 最小交付 | 验收 | 依赖 |
| --- | --- | --- | --- | --- | --- |
| 1 | 日程与期限 | 夜间采集、第三天交货、不可逆失败都以它为截止点；纯状态机，不碰剧情文本 | `GameState` 增加 day/phase 状态与合法迁移表；统一推进入口（手动关店/入夜/次日）；`deadline` 查询接口，按「到达某天某 phase」判定过期；暂停时冻结推进入口 | 阶段只能按迁移表前进；重复推进不重复结算；跨场景保留；过期判定只落定一次 | 无 |
| 2 | 任务失败与超时 | 任务系统当前只有 inactive/active/completed，醒神菇这类“永久后果”无法表达 | `TaskCatalog` 增加 `fail_when`（条件式失败）与 `expires_at`（引用系统 1 的截止点）；`TaskJournal` 增加 `failed` 投影；失败回执写 flag，幂等 | 同一任务成功/失败只落定一次；成功后不再判失败；失败不重发奖励、不重复扣物；HUD 能显示失败态 | 系统 1 |
| 3 | 最小营业循环 | Day 1/Day 2 白天都要“有客人、能接单、能收钱”，现在只有三笔固定教学订单且无顾客实体 | 顾客生成与离店的通用组件（数据驱动，不含 AI 寻路）；订单实例（ID、菜品、口味、等待时长、金额）；接单/拒单/超时离开；结算走 `WalletTransactions.claim_reward` 的 money 分支，保证一单一次；剧情顾客以“插入点/占位接口”接入，不在系统里写剧情 | 一单只收一次钱；错单/拒单不扣料不收钱；顾客离店后订单不可再结算；跨场景营业数据不丢 | 系统 1、2；钱包 |
| 4 | 采集与任务物资提交 | Day 2 酒馆委托、醒神菇采购都要求“去点位拿材料并交给任务”，现在点位只是 Marker | 采集点组件（点位 ID → 食材/数量、昼夜可用、一次性/刷新、已采状态存 GameState）；采集入共享库存；任务材料提交复用 `TaskDelivery` 的物品校验与回执 | 采集点耗尽后不可再采；昼夜条件生效；任务材料与自由制作争抢同一库存时按先扣先得拒绝，不产生负数；重复提交被拒 | 系统 1；库存；交付 |

实施顺序建议：系统 1 与 2 一起做（同一份状态/判定链），再做 3，最后 4。3 与 4 都要改 `src/resources/tasks/tasks.json`，需等剧情分支合并后统一加条目，避免目录冲突。

## 实施记录：系统 4 已完成

2026-10-17 落地「采集与任务物资提交」，实现说明见 [采集与任务物资提交](../gathering.md)。

- 8 个 `night_gather_*` 锚点改为 `GatherPoints` 下的采集点实例，采集入共享库存，已采状态写 `GameState` 的 flags/variables。
- `delivery` 新增互斥的 `items` 材料清单，复用同一份扣减、完成 flag 与回执；成品订单与旧三参 API 保持兼容。
- 昼夜条件是事实 flag（`world.phase.night`），**不是**系统 1 的 phase 状态机：本轮没有新增 GameState 字段、没有推进入口，也没有升快照 schema。系统 1 接好后只需写这个 flag，采集侧不用改。
- `tasks.json` 的 `tavern.insomnia_order`、`basic_menu.tres` 的醒神菇、`settlement_map.tscn` 的 8 个点位都标注为占位，等剧情分支合并后按正式清单替换。
- 系统 1、2、3 与自由制作均未改动。

## P1：P0 完成后的下一个

| # | 系统 | 为什么排在这里 | 最小交付 |
| --- | --- | --- | --- |
| 5 | 统一文件存档与读取 | 多天 + 资金 + 不可逆分支一旦上线，崩溃或退出就无法解释进度；与剧情文件完全解耦 | `user://` 单槽位 + 版本号 + 校验；保存时机限制在安全阶段（阶段切换/交付后）；读取走现有 `restore_state`；拒绝损坏/旧版本而不猜测 |
| 6 | 临时代购 / 雇佣 | 原稿仍列为“待讨论”，且依赖系统 1/2/3 与专款规则 | 招募入口、接单与付款、回店交货、超预算/买不到/超时退款状态图；只做一人，不做队伍 |

## 与剧情分支的文件隔离

| 范围 | 约定 |
| --- | --- |
| 可安全改 | `src/core/game_state.gd`、`src/core/tasks/`、`src/core/economy/`、`src/gameplay/milk_tea/`、新增的 `src/gameplay/customers/` 与 `src/gameplay/gathering/`、`tests/` |
| 合并后再改 | `src/resources/tasks/tasks.json`（剧情会加任务）、`src/resources/milk_tea/*.tres`（配方/食材可能被剧情引用）、`src/core/main.tscn`、`src/levels/milkTea/milk_tea_shop.tscn`（顾客与 NPC 装配） |
| 完全让出 | `src/resources/dialogue/`、`src/resources/story/`、`docs/design/` 下的剧情稿、`docs/story_authoring/` |

`GameState` 的字段与快照 schema 是共享接口：新增 day/phase 与采集状态时必须同时升 `schema_version` 并补快照校验，剧情分支合并时只需在事件里读这些字段。

## 仍需策划定下的输入

以下不阻塞系统 1–4 的代码结构，但阻塞数值与验收：

1. 期限：接取日、雇佣截止、购买返回时间、治疗截止分别对应哪个 phase；“同刻完成”与“超时”谁优先。
2. 幻金菇前置：Excel 写的“完成醉酒守卫任务”是接取、材料子目标还是交付，避免与 Day 2 顺序成环。
3. 食材 ID：教学六项与 Excel C01–C10 的映射，以及“植脂末奶茶底”这类复合底料如何表示。
4. 稀有度枚举：普通/优良/稀有/精英/传奇 与 Excel 的 T2/T3 档位是否同一个概念。
5. 金额：初始余额、白天净收入、琥珀酒八折后单价、守卫报酬，以及委托专款是否与个人钱包隔离。

在这些确定前，系统内只留可配置字段与占位值，并在文档标注“未定”，不在代码里写死推导结果。

## 明确不做

自由配方与品质计算、AI 饮品生成、爆品判定、自由赌博模拟、长期雇佣与队伍、完整战斗/潜行感知、军队经营。这些要么依赖上面的规则闭环，要么属于 Day 2 之后的扩展，现在做只会扩大返工面。
