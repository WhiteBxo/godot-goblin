# Day 1 投掷与守卫反应

2026-10-18：玩法组件已实现，**Day 1 第五阶段正式流程尚未接通**。来源为[修改稿第五阶段](../design/day_01_story_flow_revised.md#第五阶段夜间潜入)、[对接契约](../design/day_01_integration_contract.md)及 [P05/P06/P08/P09](../story_authoring/day_01_integration_pending.md)。没有发布新的 Story/Dialogue/Bridge 数据，也没有决定文书与血液的顺序。

## 已实现的组件

- Day1StealthService 是 Systems 下的场景内服务，使用宿主提供的共享库存、玩家、EffectRoot、Actor 查询和控制权限。无新 Autoload、钱包、业务副本或存档。
- 复用 player_throw（默认 F）及玩家动作信号。鼠标世界位置在动作开始时固定，动画实际释放时通过 WarehouseInventory.try_consume 扣除一件；提前取消不扣，释放后取消不退款。无物品时没有投掷物，更不会改扣普通钱包。同步重入不会第二次消费同一释放。
- 金币复用源码已有 strange_coin，来源为 S02 的真实订单交付；每次投出消耗一枚。它不与普通钱包兑换。火把 ID 保持空白，装饰 wall_torch 不能作为库存火把。
- 投掷物逐物理帧扫射世界层，墙体会截停飞行。金币落点在听觉范围内才能令可引开的守卫转向并分心；计时结束恢复观察。没有自动寻路、追击或伤害。
- 守卫使用视距、视锥、世界碰撞遮挡与累积警戒，离开视线会衰减警戒。持续看见玩家才发现；普通守卫使尝试失败，醉酒守卫报告拦截事件。分心/混乱期间暂停发现，其他守卫继续独立观察。
- 火把只在真实射线命中已绑定、具有效碰撞和确认依据的 Day1FlammableTarget 时产生短暂火焰提示与附近守卫混乱。落空、墙体截停、未确认或未绑定目标均不算成功；不模拟火势扩散。醉酒守卫不能被火焰绕过其必然事件。

缺省距离及秒数只是可调组件参数，不代表正式地图的确认数值。

第三期新增[饮品投掷与区域效果](drink_throw_effects.md)：HUD 可选择持有的配方杯，释放时原子扣杯，并执行六种区域效果及修饰。正式配置仍保持待确认。下方金币与火把说明保留；饮品相关接口、可腐蚀物绑定和独立 F6 入口见第三期说明。

## 关卡配置与宿主

SettlementMap.get_stealth_setup() 提供保存于地图的 Day1StealthSetup；当前只有空配置节点，没有移动地图物件或生成地图美术。MainGame 装配服务及复用主题的 Day1StealthHUD，通过统一锁协调失败/拦截、UIManager 模态、演出、暂停与切场景。服务只报告结果，不直接恢复移动权限。

正式启用前配置必须包含：

| 绑定 | 要求 |
| --- | --- |
| 四个职责槽 | ENTRANCE、MANSION_LURE、MANSION_GATE、DRUNKEN；当前组件以独立已注册的 SettlementCharacter 隔离职责，拒绝默认重用同一 Actor 或将 guard_captain 当卫兵 |
| 双卫组合 | MANSION_LURE 可被投币引开，MANSION_GATE 保持观察；第二卫的放行必须来自确认后的支付业务 |
| 醉酒事件 | 独立 Actor、事件 ID 和明确的放行事实；drunken_guard Marker 不能替代该 Actor |
| 投掷物 | 已确认的金币/火把库存定义与真实来源；无配置时拒绝启动，不注入道具 |
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

已经成功的尝试不能重试领奖。已用完金币/火把时不会自动补给；耗尽后的正式继续策略仍需 P09 明确。当前没有为本关编造任何贿赂或奖励数据。

## 验证与 F6

模块测试：`/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --log-file /tmp/day1_stealth.log --script res://tests/verify_day1_stealth.gd`。

测试在内存的独立夹具中定义 fixture_torch、角色位置、可燃命中区、撤离区及外部业务结果，仅供规则验证，不进入正式目录或地图，不证明这些设计已确认。正式宿主另以自身唯一 GameState 库存检查拒绝启用、真实 InputMap 输入及暂停锁。

F6 运行现有 `src/debug/story/day1_world_flow_demo.tscn`，它继承正式 `src/core/settlement.tscn` 并只准备已接受委托的夜间 S05。预期：聚落夜景和“夜间潜入暂不可用”提示，金币/火把操作禁用；具体缺口由服务 get_configuration_issues 返回，并记录在 pending。WASD、原有 E 调查与暂停流程保留。按 F 不会扣资源或写支付/撤离事实。这个入口不是完整潜入通关 Demo。

本次自动化结果：Day1Stealth 84 项、玩家动作 177 项、MainGame 73 项、GameplayBridge 248 项、UI 主题 156 项及 Day1WorldFlow、Settlement 均通过。新增检查覆盖飞行中被发现的投掷物清理、已释放资源不退款，以及目标/守卫释放后的安全取消；发现并修复了已释放对象进入强类型循环时的脚本错误，最终日志无脚本错误。Bridge 首次沙箱运行因 user:// 临时 JSON 不可写产生 20 项连带失败，正常权限下复跑 248 项全部通过。编辑器导入无脚本解析错误；沙箱存在系统证书、编辑器设置保存和退出资源诊断。没有执行全项目回归或 Release 导出，因为未更改共享状态协议、Loader 或数据格式。

独立 Metal 图形进程执行组件及真实宿主交互检查；最终 HUD 缩窄后，只以 `-- --host-only --capture` 复查正式宿主，8 项通过，截图保存于 `/tmp/day1_stealth_pending.png`，确认提示及按钮未越出视口。输入和暂停由脚本驱动，不计为人工整段通关。已有编辑器本次 F6 运行窗口黑屏并出现 UID 诊断，因此未将编辑器 F6 观察计为通过；独立图形宿主已正常渲染。正式通关仍受上述配置与剧情待定项阻塞。

引擎依据：[Godot 4.7 射线查询的物理帧和世界坐标约定](https://docs.godotengine.org/en/4.7/tutorials/physics/ray-casting.html)、[PhysicsDirectSpaceState2D](https://docs.godotengine.org/en/4.7/classes/class_physicsdirectspacestate2d.html)、[InputEvent](https://docs.godotengine.org/en/4.7/classes/class_inputevent.html)。投掷与视线查询都只在物理 tick 执行，输入继续走 InputMap。
