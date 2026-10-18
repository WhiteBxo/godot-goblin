# 营业与顾客调度接口

核对日期：2026-10-18，Godot 4.7.2。已接通 GameState 的生产持久接口及可配置的原子关店／日程提交，尚未装配进正式宿主；Day 1 原有五单、剧情、任务实例、公共菜单及 MainGame 未修改。Day 2 的人数、配方、价格、客流和关店条件仍需正式配置。

## 组件与订单边界

- `BusinessScheduler` 位于 `src/gameplay/milk_tea/business_scheduler.gd`，只协调显式配置的营业阶段和顾客组。库存、制作、订单接受和原子交付收款继续使用共享的 TeaProduction / TaskDelivery / GameState。
- `CustomerVisit` 位于同目录，绑定每组实际 Actor ID、ActorDirector 和宿主提供的路线。入店到达后确认可接待，离店到达后隐藏 NPC 并退出实体碰撞层。动作失败发 `movement_failed`，不确认到达、不扣费、不处罚；修正路线后显式 `retry()`。
- TaskDelivery 新增可选 `set_order_availability(order_ids, predicate)`。只约束登记过的订单；未登记订单保持原有流程。顾客尚未到店、阶段未发布、持久接口缺失或已关店时，接单和交付入口拒绝请求。门控所属组件释放后拒绝业务，直到新组件接管，避免场景间隙绕过限制。
- OrderBoardModel 监听 `availability_changed`，未发布或不在接待状态的未完成订单不进入订单板和按单制作页；历史完成及其他终态仍可查看。既有章节激活、揭示、配方和任务期限条件继续生效，发布阶段不会替代它们。

## 配置与公开接口

`configure(plan, state, delivery, load_snapshot, commit_snapshot, close_session)` 接受已配置的共享服务。后面三个 Callable 可缺省；缺少读取／提交接口时可组装，营业操作返回 `ERR_UNAVAILABLE`。

生产接入使用 `configure_session(plan, state, delivery, close_rule = {})`，自动绑定 GameState 的读取、比较提交与关店入口；完整 TaskCatalog 须先由 TaskJournal 绑定。省略 close_rule 时可以发布阶段和接待顾客，关店仍返回 `ERR_UNAVAILABLE`。原 Callable 入口保留给已有调用方和隔离测试。

```gdscript
var plan := {
	"session_id": "configured_session",
	"stages": [{
		"id": "configured_stage",
		"ordinary_customers": [],
		"story_customers": [{
			"id": "configured_group",
			"actor_ids": ["registered_actor"],
			"order_ids": ["configured_order"]
		}]
	}]
}
```

以上 ID 仅说明字段，必须替换为真实目录与宿主注册 ID。订单必须存在，交付目标必须属于该组 Actor，每个订单和 Actor 只能归属一个组。组必须有明确的非空订单集合；原稿没有确认是否交付的顾客保持待配置，不用空订单制造“已完成”。session / group / order 实例 ID 在整局内保持稳定，不跨天复用已结算的订单实例。

| 调用 / 信号 | 契约 |
| --- | --- |
| `publish_stage(id)` | 持久发布一次。普通组同时请求 entering；固定剧情组保持 dormant，等待剧情协调器请求。没有随机生成、间隔和人数默认值 |
| `request_arrival(group_id)` | 已发布阶段中的固定组请求一次出场；已出现或离场返回 `ERR_ALREADY_EXISTS` |
| `confirm_arrival(group_id)` | 由表现适配器在实际到达后从 entering 转 waiting；等待状态才允许接单、制作订单和交付 |
| `is_group_served(group_id)` | 该组全部订单的 `delivery.<order_id>.completed` 回执均已提交才为 true；不以制作完成或任务展示状态替代 |
| `group_served(group_id)` | 真实交付后延迟到原子事务结束再通知。恢复不重发；等待方必须先查询，再订阅信号，不能只 await 一个可能已经发生的事件 |
| `request_departure(group_id)` | 全部交付后请求 leaving。普通组自动调用；固定组由剧情显式调用，可在交付后继续对白 |
| `confirm_departure(group_id)` | 实际离场隐藏后记 departed。重建不会再次出场 |
| `get_group(group_id)` | 返回配置、kind、stage_id、status、served 的独立副本 |
| `get_progress()` / `changed` | 返回订单已交付／总数、顾客组已服务／总数／已离场、已发布阶段／总数、closed 和持久／关店接口就绪状态。进度是配置内的范围，不代表正式一天的客流定额 |
| `customer_transition(group_id, status)` / `stage_published(id)` | 成功持久提交后发布的实时转换；不会在普通 refresh 或恢复时重播 |
| `request_close()` / `business_completed(session_id)` | 生产入口校验显式关店规则后同次提交 closed、完成 flag、日期／昼夜与到期结果。规则缺失时 pending；成功并回读确认 closed 后发一次，重复请求静默成功。交完所有单也不会自行发信号 |
| `projection_reset` | 恢复／新局时要求表现取消旧动作并重新投影，不是新的业务完成事实 |

Day 2 四组固定剧情顾客均使用上述接口，各自配置独立 group_id、实际 Actor 和订单。阶段发布、出场时机、交付后对白、离场次序仍由正式剧情协调器决定；组件不硬编码四组 Beat，也不自动激活任务。

`CustomerVisit.configure(scheduler, director, group_id, members)` 的 members 包含每个组员：`actor_id`、`entry`、`waiting`、`exit`；未注册角色可提供 `scene: PackedScene`。位置使用已注册 Marker ID 或宿主确认的 Vector2。可选 `arrival_route` / `departure_route` 是实际拐点，`speed` / `timeout` 沿用 ActorDirector 的 120 / 15 秒默认值。没有寻路，不增加 timeout 掩盖碰撞阻挡。已有稳定 Actor 优先复用；动态角色只在确需显示时生成，dormant/departed 不生成角色。

## GameState 持久与关店契约

持久数据只存于现有 GameState.variables；`business.session.` 是保留前缀，普通 `set_variable` 拒绝写入，调用方必须走专用事务。纯规则校验位于 `business_session_rules.gd`，与调度器共用，不持有第二份运行时状态。

```text
variables["business.session.<session_id>"] = {
    version: 1,
    published_stages: Array[String],
    groups: Dictionary[group_id -> "entering"|"waiting"|"leaving"|"departed"],
    closed: bool
}
```

未出场组不写入 groups。该结构随现有完整快照保存；不新增顶层 Schema，不复制接受、交付、库存、钱包或交易回执。

| GameState 生产接口 | 行为 |
| --- | --- |
| `bind_business_session(plan, close_rule = {}) -> Error` | 从已绑定的完整任务目录校验真实订单和目标。静态绑定不写事实、不通知；场景重建重复绑定相同规则。已有会话拒绝静默换规则 |
| `load_business_session(session_id) -> Dictionary` | 返回独立快照；缺失返回 `{}`，调度器按未开始处理 |
| `commit_business_session(session_id, expected, next) -> Error` | 比较当前归一化快照与 expected，过期预期返回 `ERR_BUSY`。只允许一次阶段发布或一次合法顾客转换，拒绝回退、删组和伪造交付后离场；普通提交不能关店 |
| `close_business_session(session_id, expected, next) -> Error` | 校验规则、来源日期／阶段及真实回执，再原子提交 closed、完成 flag、目标日期／昼夜和任务结果。无规则返回 `ERR_UNCONFIGURED`；重复已完成状态静默成功 |

`expected` 对尚未创建的会话是 `{version:1, published_stages:[], groups:{}, closed:false}`。生产提交共享钱包／交付的 guard；GameState 同步通知期间锁定库存，拒绝另一营业组件、钱包、制作、日程、新游戏及恢复的重入。暂停期间拒绝营业写入。失败不写任何事实；相同快照不重复通知。原 Callable 扩展仍须自行满足同样的提交契约。

close_rule 必须完整提供以下字段，不从交付数量推断默认条件：

| 字段 | 配置与校验 |
| --- | --- |
| `from` / `to` | `{day, phase}`，只允许 DayPhase 的相邻迁移，例如已确认某日白天到同日夜晚；day 接受整数值的 JSON number |
| `required_stages` | 必须已发布的阶段 ID 数组 |
| `served_groups` | 必须已有全部真实交付回执的顾客组 ID 数组 |
| `departed_groups` | 必须实际确认离场且有交付回执的顾客组 ID 数组 |
| `required_flags` | 关店当刻必须为真的剧情许可／业务事实数组 |
| `completed_flag` | 关店同次写入的持久完成事实，不能覆盖昼夜镜像或经营 profile |

所有数组均须显式给出且无重复引用；显式空数组允许已配置的手动关店，缺失字段不等于空数组。未知阶段／顾客、跳日、非法日期和冲突完成 flag 拒绝绑定。正式 Day 2 规则仍未确定，没有将测试里的订单数、日期或许可 flag 写入正式资源。

场景重建复用同一个持久读取入口及共享服务。entering 恢复到 waiting 位置，再确认到达；leaving 恢复到出口隐藏，再确认离场，不重放整条路线。等待中的普通顾客若已有全部回执（交付后尚未来得及提交离场便切场景），恢复为离场投影。固定组保留 waiting，`is_group_served()` 返回 true，剧情可继续放行。恢复时允许确认新实际完成的投影边界，但不重发旧 entering/leaving、group_served、stage_published 或 business_completed。

生产新游戏随 GameState 完整替换清空营业变量；静态规则保留供同一配置重建。营业数据沿用完整快照 v5，不增加顶层字段。完整恢复先校验保留前缀下的版本、结构、重复阶段及状态；已绑定时同时校验目录、离场回执、关店事实和最早可能日期。冷启动可先恢复、后绑定，绑定时再次核对实际目录。历史关店不会因之后撤销临时许可 flag 而重新开放，不重放付款或结束信号。

## 公共文件接线需求

1. 上述生产提交接口已完成。集成方提供明确的 plan 和 close_rule；未定前省略规则，不自行选择关店门槛。日程／期限继续使用 [DayPhase 与任务结果接口](../systems/schedule_and_task_results.md)；关店通过共享复合提交应用同一相邻迁移规则。
2. 集成宿主在共享目录、Journal、Delivery 和 ActorDirector 配置完成后创建 Scheduler，调用 configure_session；每组创建 CustomerVisit，注入 EntityRoot、真实角色资源、Marker 和分段路线。无需修改正式任务 Schema 或公共菜单。
3. 正式剧情协调器按时调用 publish/request_arrival，先查询 is_group_served 再订阅通知，交付对白结束后 request_departure。不要同时让 Day1ShopController/StoryDirector 与 CustomerVisit 控制同一 Actor。Day 1 现有五单继续沿用原控制器，迁入调度前须由集成方明确角色控制权和旧检查点迁移。
4. HUD 可订阅 changed 并读取 get_progress；既有订单板和制作消费者已随门控自动刷新。宿主销毁时一并销毁 Scheduler/Visit 和场景角色，新场景重新绑定门控；不要在 UI 重建时重置共享服务。

## 验证与试玩

生产存储验证：`Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/verify_business_persistence.gd`。2026-10-18 使用 Godot 4.7.2，94 项通过；另由测试启动两个独立引擎进程，分别读取等待接单和已关店快照。覆盖真实制作／指定交付／钱币奖励、过期预期拒绝、跨组件重入、暂停、非法恢复、场景重建、关店换夜与任务到期的完整通知、重复关店及新游戏。存档使用 PID 隔离目录和测试检查点，不写玩家正式存档。

本批相关回归共 43 个检查脚本，38 个通过。其余 gathering、dialogue 的旧接单断言，以及 cinematic_integration、story_authoring 的开场移动受阻，均在改动前复现；day1_stages_01_02 本轮两项倒茶计数失败，在 `7af642e` 隔离基线中复现一项同类失败。GameState 126、日程与任务结果 100、营业调度 188、文件存档 25、跨进程存档边界 18 项均通过。新增生产检查在 `7af642e` 仅叠加本批代码的隔离副本中也通过 94 项，没有脚本错误；工作区其余并发剧情／人物记录改动未计入本批提交。

日志和隔离副本保留于忽略目录 `.godot/verification/business_persistence/`；副本含素材、插件和导入缓存 junction，勿递归进入链接目标清理。初次隔离集成漏带 UID 缓存，产生插件 autoload 无法解析诊断；补齐同基线 UID 缓存后，新增检查重新通过且无上述诊断。工作区首次新增检查也遇到并发新增 CharacterJournal 尚未导入的解析错误；刷新类缓存后再验通过。部分既有测试退出仍报告资源未释放。未执行人工画面试玩、Release 导出或正式两天通关，本批没有新增正式顾客路线／关店入口。

下述为调度组件首次交付的历史记录。正式 F5 尚未装配新营业 plan；不能将生产接口及夹具验证视为正式 Day 2 通关。

命令：`Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/verify_business_scheduler.gd`。这是可独立运行的组件验收，使用测试专属内存适配器，不代表 A 的生产持久接口已经接入。测试四组固定顾客使用从现有订单克隆的夹具，其中一组有两单以验证部分交付；这些数量与奖励不是 Day 2 正式规则。

检查包括阶段门控、拒绝写入、接单／制作／原子交付、部分组交付、错误目标、重复收款、四组固定接口、缺失／虚假关店提交、通知期重入、快照与组件重建、入场／等待／离场恢复、实际 Actor 移动、受阻重试、显隐与 NPC 碰撞，以及原有五单的 10 钱包收入、4 古怪硬币和 group_settled 事实。

本次验证使用上述 Godot 4.7.2。`.godot/business_validation/integration` 是 `05429c3` 加本次 8 个代码／UID 文件的隔离副本，代码 SHA-256 与工作区逐一一致，未叠加并发存档／MainGame 改动；配套文档和任务开始前已有的未跟踪 milkTea 场景供既有测试读取。

| 实际检查 | 结果 |
| --- | --- |
| 新增 business_scheduler | 隔离 headless 188 项、D3D12 Forward+ 图形模式 188 项，均 0 失败 |
| 隔离 Day 1 正式五单与演出检查 | day1_stages_01_02：225 项、0 失败 |
| 隔离订单板／订单界面 | order_board：57 项；order_ui：33 项，均通过 |
| 工作区直接相关检查 | order_board 57、order_ui 33、task_delivery 69、task_system 196、wallet_transactions 108、business_session 48、game_state 126、schedule_results 100、main_game 74、game_entry 66、actor_director 165、characters 1923、gameplay_bridge 249 项，以及 tea_production，均通过；没有 SCRIPT ERROR |
| 工作区 day1_stages_01_02 | 225 项、1 项倒茶音效计数失败；`05429c3` 基线先通过 225 项，后一次出现同一音效断言 2 次失败，属于可复现的基线时序波动；未改音频或放宽断言 |
| 工作区／基线 gathering | 同为 81 项、4 失败：旧宿主断言仍要求订单板打开即接单，继而物资提交／结果／重复提交断言失败 |
| 工作区／基线 verify_story_authoring.py | 两侧通过前 4 个引用／动画用例后，同在 cinematic.opening 的顾客移动至 `(1470, 560)` 时阻挡，发生同样 2 个编排错误，后续用例未执行 |
| 格式与 Markdown 链接 | UTF-8、LF、末尾换行、局部链接和 git diff --check 通过 |

隔离副本初次漏复制旧测试读取的 docs 文件，导致该轮 Day 1 校验解析失败；补齐后重新执行，上表仅将补齐后的 225 项计为通过。若干既有测试退出时报告资源/ObjectDB 未释放，隔离通过项没有脚本错误。日志和副本留在忽略的 `.godot/business_validation/`，不提交。未运行无关素材、Shader 或 Release 导出，也未执行尚未接线的正式 Day 2 通关；未做人工店内路线／UI 视觉验收。

正式 Day 1 可 F5 或 F6 `src/core/main.tscn`：逐个接单、制作入库、对指定顾客交付；前三名组员可乱序交付，最后一单才完成批次。新调度组件的正式两天通关和店内路线试玩仍待上述宿主接线，不能将自动化夹具验收当成正式剧情通关。

## 官方 API 依据

- [Godot 4.7 Signal](https://docs.godotengine.org/en/4.7/classes/class_signal.html)：连接去重、解除订阅及同步通知；真实交付信号转为事务后的延迟调度。
- [Godot 4.7 Node](https://docs.godotengine.org/en/4.7/classes/class_node.html)：场景进出树的连接清理、异步动作取消与场景重建。
- [Godot 4.7 Dictionary.duplicate](https://docs.godotengine.org/en/4.7/classes/class_dictionary.html#class-dictionary-method-duplicate)：深拷贝配置、预期／下一份快照和公开投影，避免外部修改容器别名。
