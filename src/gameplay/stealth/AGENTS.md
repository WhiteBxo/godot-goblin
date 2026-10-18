# Day 1 最小潜入

本模块只实现 Day 1 投掷、守卫感知、短暂混乱与局部重试，不扩展战斗或通用 AI。

- Day1StealthService 持有场景内临时状态；库存由宿主注入 GameState 的唯一 WarehouseInventory，不维护余额、奖励或存档副本。
- Day1StealthSetup 保存关卡绑定与确认依据。缺少角色、火把、可燃目标、检查点或撤离规则时拒绝启动；不从 Marker、装饰素材或角色名称猜测绑定。
- 四个守卫职责必须绑定不同的实际 SettlementCharacter；guard_captain 不得充当宅邸第二卫，drunken_guard Marker 不是 Actor。
- 支付业务仍由既有交易接口负责。本模块不写 guard_payment_completed，只消费已确认的放行事实；剧情事件由宿主请求。
- 玩家锁由 MainGame 合并协调。失败、重试、取消、reset/restore 与退出必须清理投掷物、燃烧和感知计时；不回滚已消耗资源或调查回执。

接口、待定项及试玩见 [玩法说明](../../../docs/gameplay/day_01_stealth.md)。模块验证为 tests/verify_day1_stealth.gd，加正式宿主接线检查；按 [测试规范](../../../tests/AGENTS.md) 选择范围。
