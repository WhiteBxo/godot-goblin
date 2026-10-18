# 制作流程与共享库存

根据任务读[自由调配与图鉴](../../../docs/gameplay/free_tea_recipes.md)、[初级制作](../../../docs/gameplay/basic_tea_production.md)、[库存](../../../docs/gameplay/warehouse_inventory.md) 与 [统一经营会话](../../../docs/gameplay/business_session.md)；接口与配置以当前代码为准，历史教学步骤不覆盖新实现。

- TeaMaking 负责制作入口的协调，TeaProduction 负责制作规则与进度，WarehouseInventory 负责物品数量与发现信息；界面只提交请求并显示结果。
- 复用 GameState 提供的唯一跨场景库存和制作服务。钱包、制作、采集与交付使用同一库存，不在场景或弹窗重建时创建业务副本或重置队列。
- 菜单、食材、配方及相关 Resource 使用现有数据定义，不把目录与配方硬编码进 UI；修改资源读 [共享资源规范](../../resources/AGENTS.md)，核对稳定 ID、类别与实际消费者。
- 制作前校验完整原料、配方和请求；扣料、产生成品、记录进度保持整体提交与重复请求保护，失败不部分扣除，也不重复增加成品。
- 制作完成只将成品入库，指定 NPC 交付与任务完成由 [任务模块](../../core/tasks/AGENTS.md) 处理；不要恢复为制作后自动交付。
- 营业阶段与顾客组使用 BusinessScheduler / CustomerVisit，接口见 [营业与顾客调度](../../../docs/gameplay/business_scheduler.md)。生产接入优先 `configure_session()`，绑定 GameState 的原子营业提交；集成方提供明确的 plan 与 close_rule，规则缺失时关店保持 pending，不经普通变量 setter 写营业快照或根据交付数量推导关店。
- 顾客路线使用宿主注入的 ActorDirector、稳定 Actor ID 与实际拐点，遵守 [角色规范](../../core/actors/AGENTS.md)；不要与剧情控制器竞争同一角色的动作所有权。候选验证为 `verify_business_scheduler.gd`。
- 改弹窗操作同时读 [UI 规范](../../UI/AGENTS.md)；真实动作完成才发布业务事实，剧情 / Bridge 只消费结果，不在展示层伪造成功。

候选验证：`verify_tea_production.gd`、`verify_warehouse_inventory.gd`；会话共享或交付受影响时选择对应直接检查。按 [验证分级](../../../tests/AGENTS.md) 控制范围，给出相关制作 / 库存试玩步骤。
