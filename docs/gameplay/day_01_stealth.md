# Day 1 投掷与守卫反应

> 2026-10-19：正式两天路线已接通，当前玩法与整次重试以[整合记录](../development/two_day_integration_2026_10_19.md)为准。后续体验打磨加入墙体裁切的观察区域、警戒百分比、分心倒计时、发现者名称及重试说明，见[体验打磨记录](../development/experience_polish_2026_10_19.md)。以下 10-18 的缺口与局部重试规则保留为历史记录，不覆盖现行正式关卡。

2026-10-18：玩法组件已实现，**Day 1 第五阶段正式流程尚未接通**。来源为[修改稿第五阶段](../design/day_01_story_flow_revised.md#第五阶段夜间潜入)、[对接契约](../design/day_01_integration_contract.md)及 [P05/P06/P08/P09](../story_authoring/day_01_integration_pending.md)。没有发布新的 Story/Dialogue/Bridge 数据，也没有决定文书与血液的顺序。

## 2026-10-18 正式关卡核对

本轮以 `e8aaa44` 的源码和实际正式宿主为基线。本轮只修复潜入组件的有效绑定与必然事件边界，并补相关验证；没有为缺少依据的配置生成角色、坐标、物品或支付金额。

| 核对项 | 当前有来源的实现 | 正式接通仍需补齐 |
| --- | --- | --- |
| 1. 角色与职责 | [正式宿主](../../src/core/settlement.tscn)各实例化一名 `guard`、`guard_captain`；[守卫资源](../../src/gameplay/characters/guard.tscn)身份是“长老居所守卫；可供醉酒守卫剧情使用”。[地图](../../src/levels/settlement/settlement_map.tscn)另有 `StoryAnchors/drunken_guard` Marker 和 `InteractionPoints/drunken_guard` 调查点，两者均非 Actor。`Day1StealthSetup.guards` 为空。 | ENTRANCE、MANSION_LURE、MANSION_GATE、DRUNKEN 四个槽均缺实际绑定，以及有依据的身份、站位与朝向。资源中“可供醉酒剧情使用”不是角色复用方案的确认。若策划决定 `guard` 同时承担宅邸卫兵和醉酒事件，现有独立职责约束会拒绝，必须先确认交接方案；不能用守卫长补位或将 Marker 当角色。 |
| 2. 投币、支付与醉酒事件 | [正式订单](../../src/resources/tasks/day1_stages_01_02.json)真实交付奖励 `strange_coin`，服务释放投掷时扣一枚库存币；只有入口与诱饵职责响应投币。放行还要求支付事实与角色放行事实，醉酒职责另要求事件完成。 | [后四阶段事件文件](../../src/resources/story/day1_stages_03_06.json)的 `events` 仍为空；没有已发布醉酒事件或正式支付写入者。P06/P09 的支付币种、金额、次数、对象关系、稳定交易 ID、余额不足处理和必然拦截节点均未确认。调查回执、对白结束不能代替支付。 |
| 3. 火把与可燃目标 | Setup 的 `torch_item_id` 为空，`flammable_targets` 为空。组件只接受已确认目标的真实射线命中。 | 没有正式火把库存定义、取得点、取得数量和去重回执；也没有确认过的可燃对象、命中形状、唯一 ID 与来源引用。壁挂火把、柴堆等装饰不能作为配置依据。 |
| 4. 文书、取血、混乱与撤离 | 地图已有 `day1_elder_document` 与 `day1_blood_storage`，均要求 S05、夜间与接受委托。文书关闭才写阅读事实；血液真实入库 `day1_griffin_blood` × 1 并写取得事实。Setup 缺省要求血液物品与取得事实，未额外要求先读文书。 | 文书是否必读／必拿、文书与取血先后、混乱是否必需仍受 P08 来源冲突阻塞。`escape_rules_reference`、`escape_zone` 和 `checkpoint` 仍未配置；`confusion_required = false` 只是缺省值，不能当成已经确认的撤离规则。现有返店区域和实际返店事实不能冒充潜入成功。 |
| 5. 发现、重试与耗尽 | 普通守卫发现后失败，醉酒守卫发现后请求拦截事件；局部重试清理感知、火焰和在途物并回检查点，保留已消耗物品及已提交调查／支付结果。不向普通钱包回退，不自动补币／补火把。 | 检查点缺确认位置；古怪金币／火把耗尽后的补给、替代路线或退出任务策略仍需 P05/P06/P09 决定。当前组件允许空库存重试，但这不保证任务仍可完成；本轮没有增加免费补给或退款。 |

本轮修复：撤离区必须有启用且实际含 Shape2D 的碰撞 owner；检查点、守卫、目标必须位于场景树中。运行中检查点或撤离形状失效会取消本次尝试并回到 PENDING，避免继续使用脱离场景的绑定。醉酒职责即使已有支付及放行事实，事件完成前仍会拦截，不能提前停止感知。

本轮验证使用 Godot `4.7.2.stable.official.ed1daf0bf`，在 Windows 仓库根执行 `Godot_v4.7.2-stable_win64_console.exe --headless --path . --script res://tests/<脚本>`：

- 修改前 `verify_day1_stealth.gd`：84 项通过。
- 修改后 `verify_day1_stealth.gd`：103 项通过，含正式 `settlement.tscn` 宿主、唯一库存注入、全部职责缺口、真实 InputMap 和暂停锁。新增覆盖无效撤离形状、检查点／撤离区退出场景、支付不能跳过醉酒事件，以及火把／古怪金币耗尽后的重试。
- `verify_drink_throw.gd`：96 项通过；`verify_day1_world_flow.gd`：通过真实文书展示关闭、取血、返店与后续业务检查。

上述日志无脚本错误。没有修改场景、角色资源、正式对白、剧情顺序、GameState、共享交易或 MainGame；没有运行全项目回归、Release 导出或人工整段通关。本轮未新增关卡配置：现有来源没有提供可合法落地的缺失绑定。组件夹具通过、世界流程返店通过均不代表正式潜入通关。

试玩仍使用下方 F6 入口：观察夜间聚落及“夜间潜入暂不可用”，按 F 不扣物品、不产生支付／撤离事实；文书与血液可通过原有 E 调查验证，其结果不解锁缺失的潜入配置。守卫分心、点火与完整撤离只能在独立测试夹具中验证，不能作为正式关卡验收。

引擎核对：[Godot 4.7 CollisionObject2D](https://docs.godotengine.org/en/4.7/classes/class_collisionobject2d.html) 的 shape owner 与实际形状数量分别查询，并排除 disabled owner；保留[物理 tick 内执行射线查询](https://docs.godotengine.org/en/4.7/tutorials/physics/ray-casting.html)的既有实现。

## 已实现的组件

- Day1StealthService 是 Systems 下的场景内服务，使用宿主提供的共享库存、玩家、EffectRoot、Actor 查询和控制权限。无新 Autoload、钱包、业务副本或存档。
- 复用 player_throw（默认 F）及玩家动作信号。鼠标世界位置在动作开始时固定，动画实际释放时通过 WarehouseInventory.try_consume 扣除一件；提前取消不扣，释放后取消不退款。无物品时没有投掷物，更不会改扣普通钱包。同步重入不会第二次消费同一释放。
- 古怪金币复用源码已有 strange_coin，来源为 S02 的真实订单交付；每次投出消耗一枚。它不与普通钱包兑换。火把 ID 保持空白，装饰 wall_torch 不能作为库存火把。
- 投掷物逐物理帧扫射世界层，墙体会截停飞行。硬币落点在听觉范围内才能令可引开的守卫转向并分心；计时结束恢复观察。没有自动寻路、追击或伤害。
- 守卫使用视距、视锥、世界碰撞遮挡与累积警戒，离开视线会衰减警戒。持续看见玩家才发现；普通守卫使尝试失败，醉酒守卫报告拦截事件。分心/混乱期间暂停发现，其他守卫继续独立观察。
- 火把只在真实射线命中已绑定、具有效碰撞和确认依据的 Day1FlammableTarget 时产生短暂火焰提示与附近守卫混乱。落空、墙体截停、未确认或未绑定目标均不算成功；不模拟火势扩散。醉酒守卫不能被火焰绕过其必然事件。

缺省距离及秒数只是可调组件参数，不代表正式地图的确认数值。

第三期新增[饮品投掷与区域效果](drink_throw_effects.md)：HUD 可选择持有的配方杯，释放时原子扣杯，并执行六种区域效果及修饰。正式配置仍保持待确认。下方硬币与火把说明保留；饮品相关接口、可腐蚀物绑定和独立 F6 入口见第三期说明。

## 关卡配置与宿主

SettlementMap.get_stealth_setup() 提供保存于地图的 Day1StealthSetup；当前只有空配置节点，没有移动地图物件或生成地图美术。MainGame 装配服务及复用主题的 Day1StealthHUD，通过统一锁协调失败/拦截、UIManager 模态、演出、暂停与切场景。服务只报告结果，不直接恢复移动权限。

正式启用前配置必须包含：

| 绑定 | 要求 |
| --- | --- |
| 四个职责槽 | ENTRANCE、MANSION_LURE、MANSION_GATE、DRUNKEN；当前组件以独立已注册的 SettlementCharacter 隔离职责，拒绝默认重用同一 Actor 或将 guard_captain 当卫兵 |
| 双卫组合 | MANSION_LURE 可被投币引开，MANSION_GATE 保持观察；第二卫的放行必须来自确认后的支付业务 |
| 醉酒事件 | 独立 Actor、事件 ID 和明确的放行事实；drunken_guard Marker 不能替代该 Actor |
| 投掷物 | 已确认的古怪金币/火把库存定义与真实来源；无配置时拒绝启动，不注入道具 |
| 可燃目标 | 场景实际对象的命中 Area2D、唯一 target_id、有效 Shape2D 和 design_reference；不自动把木桶/柴堆标成可燃 |
| 检查点 | 明确的 Marker2D；不会根据地图 Spawn 或醉酒 Marker 猜测 |
| 撤离区 | 正式 Area2D 的实际碰撞形状、escape_rules_reference、所需事实与当前库存；必须包含真实血液及取得事实 |
| 混乱要求 | 由 P08 明确 confusion_required；若要求混乱，必须由本次有效命中产生且计时仍有效 |

进入已接受委托的夜间 S05 且配置完整时才能启动；也可显式调用 begin_attempt。取消保持取消，重新开始需要显式请求；离开 S05 或整局 reset/restore 清理临时状态。相同快照的 no-op restore 沿用 GameState 既有“不发恢复通知”语义，不等同局部重试。

职责槽及测试中的四个独立实例不代表正式角色数量已冻结。醉酒事件是否复用其他守卫、何时交接职责仍属 P09；若最终确认复用，需先补明确的角色/事件交接，再启用正式配置。本次没有生成或注册任何正式占位守卫。

宿主收到 guard_intercepted(event_id) 后请求原 StoryDirector 短事件。未发布事件时明确报错并保留拦截，玩家可重试。放行同时要求真实支付完成事实与配置指定的角色放行事实；醉酒拦截结束还要确认事件完成。**组件不执行贿赂、不分配金额，也不写 day1.s05.guard_payment_completed**；P06 的支付次数、币种和对象关系继续待定。

escaped 只在所需物品仍实际持有、业务事实/必然醉酒事件成立、玩家脚底确实进入正式撤离形状且未在同一物理帧被发现时发出，同时写 day1.s05.escape_completed。该事实不代表返店、发奖或自动进入 S06；这些仍由既有业务和后续 Story/Bridge 消费。

## 失败与重试

retry_attempt 只接受失败或拦截状态，并再次核对外部控制权与配置。恢复玩家检查点及守卫初始位置/朝向，清除警戒、分心、混乱、燃烧、待释放动作与所有在途投掷物。已实际消耗的物品、已提交的调查/支付回执保留；重试本身不扣物、不退款、不发奖，也不清整局状态。

已经成功的尝试不能重试领奖。已用完古怪金币/火把时不会自动补给；耗尽后的正式继续策略仍需 P09 明确。当前没有为本关编造任何贿赂或奖励数据。

## 验证与 F6

模块测试：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --log-file /tmp/day1_stealth.log --script res://tests/verify_day1_stealth.gd`。

测试在内存的独立夹具中定义 fixture_torch、角色位置、可燃命中区、撤离区及外部业务结果，仅供规则验证，不进入正式目录或地图，不证明这些设计已确认。正式宿主另以自身唯一 GameState 库存检查拒绝启用、真实 InputMap 输入及暂停锁。

F6 运行现有 `src/debug/story/day1_world_flow_demo.tscn`，它继承正式 `src/core/settlement.tscn` 并只准备已接受委托的夜间 S05。预期：聚落夜景和“夜间潜入暂不可用”提示，古怪金币/火把操作禁用；具体缺口由服务 get_configuration_issues 返回，并记录在 pending。WASD、原有 E 调查与暂停流程保留。按 F 不会扣资源或写支付/撤离事实。这个入口不是完整潜入通关 Demo。

组件首次交付的历史结果（非本轮）：Day1Stealth 84 项、玩家动作 177 项、MainGame 73 项、GameplayBridge 248 项、UI 主题 156 项及 Day1WorldFlow、Settlement 均通过。新增检查覆盖飞行中被发现的投掷物清理、已释放资源不退款，以及目标/守卫释放后的安全取消；发现并修复了已释放对象进入强类型循环时的脚本错误，最终日志无脚本错误。Bridge 首次沙箱运行因 user:// 临时 JSON 不可写产生 20 项连带失败，正常权限下复跑 248 项全部通过。编辑器导入无脚本解析错误；沙箱存在系统证书、编辑器设置保存和退出资源诊断。没有执行全项目回归或 Release 导出，因为未更改共享状态协议、Loader 或数据格式。

组件首次交付的历史图形验证：独立 Metal 图形进程执行组件及真实宿主交互检查；最终 HUD 缩窄后，只以 `-- --host-only --capture` 复查正式宿主，8 项通过，截图保存于 `/tmp/day1_stealth_pending.png`，确认提示及按钮未越出视口。输入和暂停由脚本驱动，不计为人工整段通关。已有编辑器本次 F6 运行窗口黑屏并出现 UID 诊断，因此未将编辑器 F6 观察计为通过；独立图形宿主已正常渲染。正式通关仍受上述配置与剧情待定项阻塞。

引擎依据：[Godot 4.7 射线查询的物理帧和世界坐标约定](https://docs.godotengine.org/en/4.7/tutorials/physics/ray-casting.html)、[PhysicsDirectSpaceState2D](https://docs.godotengine.org/en/4.7/classes/class_physicsdirectspacestate2d.html)、[InputEvent](https://docs.godotengine.org/en/4.7/classes/class_inputevent.html)。投掷与视线查询都只在物理 tick 执行，输入继续走 InputMap。

## 2026-10-19 操作反馈

本轮只补表现层，不改视距、视锥、警戒时间、投掷消耗、失败与重试规则。

- 投掷准星：持可投物且 `can_accept_input()` 时，`ThrowAimIndicator` 在鼠标世界位置绘制整像素十字、1 像素中心点和 230 世界像素虚线射程圈；有效为暖金色、无效为红色。判定直接复用 `_valid_target`，表现不会承诺服务端会拒绝的落点。弹窗、暂停、外部控制或演出接管时隐藏。
- 命中反馈：`_resolve_impact` 在同一物理帧生成 0.24 秒 `ThrowImpactEffect`（1 帧亮点、外扩圆环与四向尘点，按金币／火把／饮品取色）。宿主收到 `throw_resolved` 后加 2 像素、0.12 秒震屏并播放已登记的 `story.impact`；投掷物只在结算时消失，服务不等待表现。
- 警戒：`Day1GuardResponse` 的视锥颜色随 `exposure / discovery_seconds` 由黄转橙，填充从 0.20 增至 0.32；初次进入视线时头顶警戒框上跳 4 像素并在 0.18 秒内恢复。`get_alert_ratio()` 返回所有处于 ALERT 守卫中的最大比例，供 UI 只读轮询。
- 被发现：服务发 `attempt_failed` 时先在同一帧生成 0.8 秒 `StealthAlertMarker`（守卫头顶感叹号），宿主再触发全屏暖白闪（0.45 峰值，0.05 秒进、0.22 秒出）、4 像素 0.22 秒震屏、`ui.failure` 和 0.18 秒镜头聚焦发现者；0.55 秒后 0.35 秒回到跟随。镜头请求仍由宿主转交 CameraDirector，未让潜入组件直接抓相机。
- 屏幕张力：`ThreatOverlay` 以 `get_alert_ratio()` 驱动径向暗角（最高 0.42 alpha，`GradientTexture2D` 生成、无外部素材），只显示在世界之上、HUD 之下；离开视线后按 1.6/秒回落。
- 像素边界：准星、投射物与震屏偏移都在整像素上取整，沿用相机既有的限制内钳制；命中闪白与暗角只在潜行任务曝光时出现，不持续闪烁。

验证：`verify_day1_stealth.gd` 105 项（含准星显示／锁定时隐藏、命中效果数量、警戒比例、发现标记），正式宿主 `--host-only` 9 项，`verify_feel_layer.gd` 10 项，`verify_two_day_flow.gd` 282 项。没有新增音频 ID；如需独立的投掷起手声，仍需走音效包生成链与 manifest 校验。持续推近镜头未采用，避免 640×360 像素网格在非整数缩放下抖动；张力改由暗角与视锥承担。

## 2026-10-19 试玩后的巡逻与视锥

试玩反馈“发现范围像半屏”“守卫站着不动、分心太久”后，正式章节场景改为：

- 视锥半角 45°（90° 扇形），不再是 170° 半圆。入口卫 84、宅邸左卫 48、右卫 60、醉卫 48 世界像素；发现时间 0.9–1.2 秒，分心 2.0–3.0 秒，听觉 120–156。
- 四名守卫各有一段短巡逻：入口卫在 (1128,456)–(1224,456)，醉卫在 (1392,456)–(1440,456)，左卫在 (1608,456)–(1704,456)，右卫在 (1800,456)–(1896,456)。巡逻、暂停与受阻换向都由 `Day1GuardResponse.advance()` 推进，不增加寻路或追击。
- 投币命中后守卫走向声源，停在约 28 像素处，计时结束后面向原方向并回到路线；站桩夹具（`patrol_offsets` 为空）保持原有“原地转向”语义，测试与独立 Demo 不受影响。
- 检查点重试会清空巡逻索引、停留计时、受阻计时和声源点，并回传送原站位与朝向。
- 关卡路标拆分并抬到角色头顶上方：北侧守卫、酒馆/赌场、奶茶店、观察位、撤离点、投币落点、长老居所门牌。付费后新增“长老居所 → 东侧”路标；双卫付款事件追加“宅邸双卫放行”标题卡，说明进门方向。
- 新增主线任务 `day1.s05.infiltration`，目标顺序为醉卫交涉、双卫付款、书房文书、右室血液、回观察位撤离，补齐潜入阶段的 HUD 与地图目标。

验证：`verify_rpg_chapter_maps.gd` 192 项（含视锥边界、巡逻位移、重置回位），`verify_day1_stealth.gd` 105 项，`verify_two_day_flow.gd` 282 项，`verify_day1_world_flow.gd` 48 项。没有发现 TileMap 通行数据中真实存在的不可见碰撞；石墙与宅门附近用路标说明绕行和入口。
