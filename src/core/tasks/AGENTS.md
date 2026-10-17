# 任务目录、投影与交付

先按任务读 [任务系统](../../../docs/gameplay/task_system.md)、[成品与材料交付](../../../docs/gameplay/task_delivery.md)；前者的历史范围不能覆盖后者和当前代码。

- TaskCatalog 负责定义与校验；TaskJournal 是可丢弃的只读投影，GameState 是接单、完成事实与回执的唯一来源，不在 UI 或 Journal 缓存一份可写进度。
- 制作与交付分开：制作成功只产生库存成品，不自动完成指定 NPC 的交付任务。
- `delivery.product_id` 与 `delivery.items` 恰好选择一个；order ID 唯一，目标使用真实 `target_object_id`，物品存在于共享目录。Schema 以实际 TaskCatalog 为准。
- 交付从 TaskDelivery 公开入口校验目标、持有量和当前状态，经既有 GameState / 交易协调整体提交扣除、奖励和回执；错误目标、重复请求或失败不能部分扣物或重复领奖。
- 业务依赖见 [制作与库存](../../gameplay/milk_tea/AGENTS.md)、[钱包交易](../economy/AGENTS.md)；任务列表与提示遵守 [UI 规范](../../UI/AGENTS.md)，剧情只消费真实完成事实，不伪造任务业务。
- 修改任务 JSON 另读 [资源规范](../../resources/AGENTS.md)，保持稳定任务 ID、引用和直接消费者契约。

候选验证：`verify_task_system.gd`、`verify_task_delivery.gd`；展示变动选 `verify_task_panel.gd`，按 [验证分级](../../../tests/AGENTS.md) 只执行相关项。
