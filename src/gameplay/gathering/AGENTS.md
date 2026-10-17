# 采集点与采集服务

数据约定、刷新方式和任务接入见 [采集与任务物资提交](../../../docs/gameplay/gathering.md)。

- GatherPoint 只保存静态配置与接近判定，不读 GameState 或缓存已采状态；GatheringService 负责点位注册、可用性求值和提交规则。
- GameState 保存采集事实，WarehouseInventory 保存物品；通过依赖注入使用现有服务，没有有效 gate 时采集点不可用。
- 保持 `once` / `daily`、当前天数和 required flag 的现有语义，可用性从真实状态求值；已采点下一次目标查询就应退出可交互候选。
- 物品 ID 必须存在于共享目录且符合采集类别；扣刷新资格、增加库存与通知保持现有整体成功 / 失败契约，不让容量或校验失败消耗采集机会。
- 点位及 Marker 配置在所属关卡；新增位置先读 [关卡规范](../../levels/AGENTS.md)，任务提交另读 [任务规范](../../core/tasks/AGENTS.md)。

候选验证：`tests/verify_gathering.gd`；只在交付协议实际受影响时补交付测试，F6 观察目标点的可用性、库存与刷新状态。
