# 营业与顾客调度接口

核对日期：2026-10-18，Godot 4.7.2。组件尚未装配进正式宿主；Day 1 原有五单、剧情、任务实例、公共菜单及 MainGame 未修改。Day 2 的人数、配方、价格、客流和关店条件不由本组件决定。

## 组件与订单边界

- `BusinessScheduler` 位于 `src/gameplay/milk_tea/business_scheduler.gd`，只协调显式配置的营业阶段和顾客组。库存、制作、订单接受和原子交付收款继续使用共享的 TeaProduction / TaskDelivery / GameState。
- `CustomerVisit` 位于同目录，绑定每组实际 Actor ID、ActorDirector 和宿主提供的路线。入店到达后确认可接待，离店到达后隐藏 NPC 并退出实体碰撞层。动作失败发 `movement_failed`，不确认到达、不扣费、不处罚；修正路线后显式 `retry()`。
- TaskDelivery 新增可选 `set_order_availability(order_ids, predicate)`。只约束登记过的订单；未登记订单保持原有流程。顾客尚未到店、阶段未发布、持久接口缺失或已关店时，接单和交付入口拒绝请求。门控所属组件释放后拒绝业务，直到新组件接管，避免场景间隙绕过限制。
- OrderBoardModel 监听 `availability_changed`，未发布或不在接待状态的未完成订单不进入订单板和按单制作页；历史完成及其他终态仍可查看。既有章节激活、揭示、配方和任务期限条件继续生效，发布阶段不会替代它们。

## 配置与公开接口

`configure(plan, state, delivery, load_snapshot, commit_snapshot, close_session)` 接受已配置的共享服务。后面三个 Callable 可缺省；缺少读取／提交接口时可组装，营业操作返回 `ERR_UNAVAILABLE`。

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
| `request_close()` / `business_completed(session_id)` | 只调用 A 注入的真实关店提交。缺失时 pending；成功并回读确认 closed 后发一次，重复请求静默成功。交完所有单也不会自行发信号 |
| `projection_reset` | 恢复／新局时要求表现取消旧动作并重新投影，不是新的业务完成事实 |

Day 2 四组固定剧情顾客均使用上述接口，各自配置独立 group_id、实际 Actor 和订单。阶段发布、出场时机、交付后对白、离场次序仍由正式剧情协调器决定；组件不硬编码四组 Beat，也不自动激活任务。

`CustomerVisit.configure(scheduler, director, group_id, members)` 的 members 包含每个组员：`actor_id`、`entry`、`waiting`、`exit`；未注册角色可提供 `scene: PackedScene`。位置使用已注册 Marker ID 或宿主确认的 Vector2。可选 `arrival_route` / `departure_route` 是实际拐点，`speed` / `timeout` 沿用 ActorDirector 的 120 / 15 秒默认值。没有寻路，不增加 timeout 掩盖碰撞阻挡。已有稳定 Actor 优先复用；动态角色只在确需显示时生成，dormant/departed 不生成角色。

## A 负责的持久与关店契约

已向 A 列明需求。A 确认可采用以下结构，但明确当前 `set_variable()` 不完全满足通知期拒绝重入，因此未批准直接作为最终提交接口；本组件没有直接写 GameState，也没有运行时第二份持久仓库。

```text
variables["business.session.<session_id>"] = {
    version: 1,
    published_stages: Array[String],
    groups: Dictionary[group_id -> "entering"|"waiting"|"leaving"|"departed"],
    closed: bool
}
```

未出场组不写入 groups。该结构随现有完整快照保存；不新增顶层 Schema，不复制接受、交付、库存、钱包或交易回执。

| 注入函数 | A 需要保证 |
| --- | --- |
| `load_snapshot(session_id) -> Dictionary` | 返回独立快照；缺失时返回 `{}`，组件按未开始处理。非法版本、重复／未知阶段、未知顾客状态等整包拒绝业务 |
| `commit_snapshot(session_id, expected, next) -> Error` | 比较当前归一化快照与 expected；整包替换 next 后再通知。失败不部分写。通知／交易／恢复期间拒绝写入，跨组件请求也遵守同一个 guard |
| `close_session(session_id, expected, next) -> Error` | 单独的可信关店入口，next.closed 为 true；验证正式关店规则后整体提交所需事实。如关店同时推进日程，应由共享入口一并处理；仅返回 OK 而未实际提交 closed，组件返回 `ERR_INVALID_DATA`，不发完成信号 |

`expected` 对尚未创建的会话是 `{version:1, published_stages:[], groups:{}, closed:false}`。Callable 返回原生 Error/int。提交不能 await；不得在营业状态写入后另行失败，组件无法回滚外部半提交。组件通知期也拒绝自身重入；该保护不能替代共享状态的 guard。

场景重建复用同一个持久读取入口及共享服务。entering 恢复到 waiting 位置，再确认到达；leaving 恢复到出口隐藏，再确认离场，不重放整条路线。等待中的普通顾客若已有全部回执（交付后尚未来得及提交离场便切场景），恢复为离场投影。固定组保留 waiting，`is_group_served()` 返回 true，剧情可继续放行。恢复时允许确认新实际完成的投影边界，但不重发旧 entering/leaving、group_served、stage_published 或 business_completed。新局需由 A 清空该会话快照，同时正常重置原有业务服务。

## 公共文件接线需求

1. A 补齐上述带 guard 的原子营业提交入口、快照恢复与清空；关店规则未定前保持 close Callable 缺省。日程／期限继续使用 [DayPhase 与任务结果接口](../systems/schedule_and_task_results.md)，组件不直接推进日程。
2. 集成宿主在共享目录、Journal、Delivery 和 ActorDirector 配置完成后创建 Scheduler，每组创建 CustomerVisit；注入 EntityRoot、真实角色资源、Marker 和分段路线。无需修改正式任务 Schema 或公共菜单。
3. 正式剧情协调器按时调用 publish/request_arrival，先查询 is_group_served 再订阅通知，交付对白结束后 request_departure。不要同时让 Day1ShopController/StoryDirector 与 CustomerVisit 控制同一 Actor。Day 1 现有五单继续沿用原控制器，迁入调度前须由集成方明确角色控制权和旧检查点迁移。
4. HUD 可订阅 changed 并读取 get_progress；既有订单板和制作消费者已随门控自动刷新。宿主销毁时一并销毁 Scheduler/Visit 和场景角色，新场景重新绑定门控；不要在 UI 重建时重置共享服务。

## 验证与试玩

命令：`Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/verify_business_scheduler.gd`。这是可独立运行的组件验收，使用测试专属内存适配器，不代表 A 的生产持久接口已经接入。测试四组固定顾客使用从现有订单克隆的夹具，其中一组有两单以验证部分交付；这些数量与奖励不是 Day 2 正式规则。

检查包括阶段门控、拒绝写入、接单／制作／原子交付、部分组交付、错误目标、重复收款、四组固定接口、缺失／虚假关店提交、通知期重入、快照与组件重建、入场／等待／离场恢复、实际 Actor 移动、受阻重试、显隐与 NPC 碰撞，以及原有五单的 10 钱包收入、4 古怪金币和 group_settled 事实。

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
