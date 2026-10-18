# 日程推进与任务结果接口

核对日期：2026-10-18，Godot 4.7.2。供营业、代购、赌场和剧情协调器接入；正式剧情、任务实例 JSON、菜单、地图与 MainGame 组装未改。

## 状态归属与公开入口

| 所有者 / 字段 | 约定 |
| --- | --- |
| GameState.current_day | 从 1 开始；正式推进经 DayPhase，原 set_current_day 保留兼容，不用于营业推进 |
| variables["world.phase"] | `day` / `night`；缺失时按旧 night flag 推断，显式空值、错误类型或未知值拒绝迁移 |
| flags["world.phase.night"] | phase 镜像，与日期和 phase 同次提交 |
| GameState.task_results | 快照 v5 的持久终态表；任务 ID → `{status, day, phase, reason}` |
| GameState 的目录绑定 | 静态规则副本，随场景销毁继续工作；不写入快照，也不由 Journal.refresh 修改 |
| TaskJournal / OrderBoardModel / TaskPanel | 可丢弃投影；库存、钱包、事实与结果只属于共享会话 |

| 接口 | 行为 |
| --- | --- |
| `DayPhase.advance_to(state, day, phase) -> Error` | 当前目标返回 OK 且静默；只允许下一相邻阶段。白天→同日夜晚，夜晚→次日白天；拒绝跳阶段、倒退、未知阶段与日期溢出 |
| `DayPhase.enter_night / enter_day(state) -> bool` | 保留既有接口；仅实际迁移返回 true。新业务重试使用带绝对日期的 advance_to |
| `DayPhase.is_deadline_reached(state, deadline) -> bool` | 按天数、昼夜顺序比较；缺失状态、非法配置或未知当前阶段返回 false |
| `DayPhase.is_deadline_reached_at(day, phase, deadline) -> bool` | 无状态依赖的同一比较，用于配置预览和完整快照归一化 |
| `GameState.bind_task_catalog(catalog) -> Error` | 原子替换静态目录绑定。现有 TaskJournal.configure 自动调用；无界面的业务可直接调用，不需更改宿主组装。传入完整合并目录（可用 TaskCatalog.load_files），不以单个业务的子目录覆盖其他未结任务规则 |
| `GameState.get_task_result(task_id) -> Dictionary` | 返回独立副本；尚无终态返回空字典 |
| `GameState.can_complete_task(task_id) -> bool` | 已开始、未结算、无失败条件且未截止；TaskDelivery 在扣物/入账前检查 |
| `GameState.has_conflicting_task_result(task_id) -> bool` | 多种终态条件同时满足时返回 true，供协调器诊断 pending |
| `GameState.settle_task_result(task_id, status, reason = "") -> Error` | 可信协调器请求终态；已有结果返回 ERR_ALREADY_EXISTS。成功/失败/过期须满足对应配置；取消须显式 allow_cancel 且没有其他终态候选 |
| `TaskJournal.get_visible_tasks() -> Array[Dictionary]` | 目录顺序的活动与终态历史，继续遮蔽未揭示内容；get_active_tasks 仍只返回 active |

营业组件确认自己的关店规则后，传入配置所指的绝对目标，例如 `DayPhase.advance_to(GameState, 1, "night")`。剧情、代购和赌场不得自行改 phase 两个键；该入口不判断营业额、时间、委托数、赌局输赢，也不自动开始剧情或切场景。重复请求当前目标不通知；已经过时的目标拒绝并保持状态。

## TaskCatalog JSON v1 的可选扩展

原有必填字段保持；新增可选字段如下，仍拒绝未知字段并整体校验目录。

| 字段 | Schema / 缺失约定 |
| --- | --- |
| `fail_when` | 与 complete_when 相同的显式 `flag` 或已注册 `event_completed` 条件；缺失表示失败规则 pending，不自动失败 |
| `deadline` | 精确 `{ "day": 正整数, "phase": "day"或"night", "boundary": "at"或"after" }`；缺失表示期限 pending，不自动过期 |
| `allow_cancel` | bool；只有显式 true 才允许请求取消。缺失表示取消规则 pending |

示例只说明 Schema，不属于正式任务实例：

```json
"deadline": {"day": 2, "phase": "night", "boundary": "at"},
"fail_when": {"type": "flag", "key": "commission.example_failed"},
"allow_cancel": true
```

`at` 在进入指定阶段时即截止；`after` 在经过指定阶段后截止，例如第 1 天夜晚的 after 截止点在第 2 天白天被跨越。期限 day 接受 JSON 中整数值的 number，须小于 int64 最大值；快照结果 day 必须为原生 int。

只有 activate_when 满足的任务才结算；配置了 delivery.accepted_flag 时还必须已经接单。未接取订单不因日期变化过期；接取已经到期的订单会在接取事实提交时立即过期，因此调用方可在接单前用期限查询决定是否展示。没有 accepted_flag 的原有任务沿用 activate_when 作为开始边界。

每次正常事实提交，在 state_changed 之前检查目录；只有恰好一个终态候选才锁存。终态是 `completed`、`failed`、`expired`、`cancelled`，撤销条件、重复通知、重新绑定或后续到期都不能替换它。若同次提交同时满足成功/失败/截止多个条件，任务保持 active 且结果 pending，交付拒绝；没有擅自规定策划优先级。修正冲突事实后可再结算。

持久结果中的 day/phase 是结算点；reason 是可选展示原因，自动条件结算为空字符串。结果不表示已经发钱：交付仍由 TaskDelivery / GameState.commit_delivery 原子处理库存、钱包、完成事实、交付回执、计数和终态；错误目标、满仓、缺货或交易失败均不写成功结果。任务交付调用 commit_delivery 的末尾 task_id 参数，在 GameState 边界再次校验任务状态和成功事实；省略 task_id 仅兼容不绑定任务的原始业务事务。失败、过期和取消只记结果，不能据此自行执行退款、押金释放或违约扣款。

## 通知与恢复

- 正常结算：提交全部事实、日期、镜像、经济和结果，再发一次 state_changed；随后每个新结果发 `task_settled(task_id, result)`。结果参数为副本，通知期间拒绝同步写状态、推进、交易、新游戏与恢复。信号只用于反馈；恢复后的业务依据持久结果查询。
- 没有终态的普通事实更新沿用既有 state_changed 契约。TaskJournal 只订阅一次；refresh/get_task 不写状态，不重发结算。
- 完整快照 v5 新增必填 task_results，非法 ID、终态、类型或结果结构整包拒绝。容器输入、输出及信号副本隔离；此接口只提供会话快照，文件读写由独立[存档系统](save_system.md)负责。
- 完整 v2/v3/v4 按既有经营迁移补空 task_results。已绑定目录时，恢复在比较/替换前静默推导已有明确结束事实；旧结果时间只能使用快照中的日程点，不猜历史时刻。未绑定目录先恢复已有结果，之后绑定时再静默补齐可推导结果。冲突条件仍 pending。
- restore 先替换完整会话，再发 state_changed / state_restored；不发 task_settled、event_completed、delivered，不重放奖励。相同归一化快照（含重复旧版恢复）静默。绑定目录补齐旧结果只通知状态，不发结算事件。
- 场景重建重新 configure Journal；已保存结果优先于实时条件，离树时仍由 GameState 的规则副本处理推进。reset/start_new_game 清空终态，静态目录绑定保留到下一次显式绑定；普通进出场景不 reset。任务 ID 是整局唯一实例；重复委托须由业务提供新的稳定实例 ID。

## UI 与试玩入口

任务手册保留目录顺序的活动任务和终态历史；完成时保持选择和滚动。历史详情显示结果、结算天数/昼夜及非空原因；不显示“等待后续剧情”或引导继续交付。订单投影将失败、过期和取消标记为不可制作、不可交付；HUD 继续只追踪 active。

运行 `Godot --path . --script res://tests/verify_schedule_results.gd -- --capture` 可查看隔离结果界面，依次验证完成、失败、过期、取消。测试自动检查六条记录和四类详情，并生成 `.godot/schedule_results_640.png` / `schedule_results_320.png`。正式入口仍可接取既有订单、交付后打开手册，观察“已完成”历史；正式失败/期限/取消尚无规则，不声称能够正式通关这些分支。

## 接入待定规则

| 模块 | 保持 pending 的输入 |
| --- | --- |
| 营业 | 何时关店、能否提前结束、是否允许跨阶段、是否要等待未完成业务 |
| 代购 / 委托 | 每个稳定实例 ID、接取与完成/失败事实、具体截止日/阶段、at/after 边界、允许取消与否 |
| 资金结算 | 取消/失败/过期后的专款、预付款、押金、退款、欠款与违约规则；若需结果与资金同事务，需业务提供明确规则后扩展原子入口 |
| 赌场 | 输赢事实、退出条件、赌资结算与日程推进目标；输一局不自动等于委托失败 |
| 同时命中 | 成功与失败、成功与期限同时满足时的业务优先级，当前保留 pending |

## 验证与官方依据

本次使用 `Godot_v4.7.2-stable_win64_console.exe --headless --path <验证副本> --script res://tests/verify_<name>.gd`；验证副本位于 `.godot/schedule_validation/integration`，基于 `af443b0` 加本次 20 个文件，另保留任务开始前的未跟踪 milkTea 场景。验证副本与本次代码文件逐一做 SHA-256 对照。原工作区出现并发存档 UI/MainGame 未完成改动导致编译失败，因此该轮试跑不计通过，不回滚外部文件。

| 检查 | 实际结果 |
| --- | --- |
| 新增 schedule_results | headless 100 项、D3D12 Forward+ 图形 100 项，均 0 失败；已查看 640×360 / 320×360 截图，结果标记、换行和滚动正常 |
| game_state / day_phase / task_system / task_delivery / task_panel | 126 项 / PASS / 196 项 / 69 项 / 92 项，均通过 |
| order_board / order_ui / handbook / business_session / wallet_transactions / free_recipes / save_store | 57 / 33 / 44 / 48 / 108 / 189 / 23 项，均通过 |
| tea_production / warehouse_inventory / main_game / game_entry / day1_world_flow / day1_chapter_systems | 全部通过（库存 199 项，MainGame 74 项，入口 66 项，章节 95 项） |
| story_director / gameplay_bridge / chronicle / story_interaction / day1_stealth / ui_manager / milk_tea_shop / settlement / scene_travel / day1_scene01 | 全部通过；32 份相关 GDScript 中合计 29 份通过，另 3 份为下表基线失败 |
| 本地 Markdown 链接、UTF-8/LF/末尾换行与 git diff --check | 通过 |

以下失败在未叠加本次改动的 `5620740` 独立副本中复现，未修改无关断言、碰撞、音频或正式任务配置：

| 基线检查 | 本次 / 基线 |
| --- | --- |
| day1_stages_01_02 | 同为 225 项、1 失败：成功制作的倒茶音效次数 |
| gathering | 同为 81 项、4 失败：宿主仍假设打开订单板自动接单，继而酒馆交付、结果与重复交付断言失败 |
| cinematic_integration | 同为 286 项、6 失败：移动/旧回调断言及顾客到 `(1470, 560)` 的路线阻断，继而时长、后续阶段和到达断言失败 |
| `python -X utf8 tests/verify_story_authoring.py --godot <exe>` | 两侧先通过 4 个非法引用/动画用例，随后 cinematic.opening 的实际移动校验均有 2 项错误，后续用例未执行 |

若干旧测试及编辑器导入在退出时报告资源/ObjectDB 未释放；通过项没有 SCRIPT ERROR。没有运行与本次契约无关的素材、Shader、玩家外观等测试，也未执行 Release 导出、正式两天通关或并发存档 UI 的整体验收。日志、基线/验证副本与截图保存在 `.godot/schedule_validation/`，不提交。

新增 `verify_schedule_results.gd` 覆盖绝对推进去重、昼夜截止、四种持久终态、冲突 pending、原子交付、快照迁移/拒绝、场景组件重建和宽窄屏结果显示。

- [Godot 4.7 Autoload](https://docs.godotengine.org/en/4.7/tutorials/scripting/singletons_autoload.html)：沿用跨场景唯一会话。
- [Dictionary.duplicate](https://docs.godotengine.org/en/4.7/classes/class_dictionary.html#class-dictionary-method-duplicate)：深复制原生嵌套状态，不向投影或订阅者交出结果表引用。
- [Signal](https://docs.godotengine.org/en/4.7/classes/class_signal.html)：连接去重与同步通知，完整提交后发布，恢复不重发结算。
