# 钱包与原子交易

接口、幂等与快照契约见 [钱包与原子交易](../../../docs/gameplay/wallet_transactions.md)，生命周期见 [统一经营会话](../../../docs/gameplay/business_session.md)。

- WalletTransactions 由 GameState 持有，并持有唯一 WarehouseInventory；调用方使用已有 getter，不创建独立余额或库存副本。
- 余额、库存、回执等操作保持整体提交与失败无部分修改。提交段在主线程同步完成，不插入 `await`、外部调用或 signal；发布通知时订阅者只能看到完整状态。
- 沿用请求 ID、回执和会话 guard 的重入 / 重复请求规则，禁止为重试重复扣款或发奖。准备交付的草稿由 GameState 在统一状态提交中完成，见 [任务规范](../tasks/AGENTS.md)。
- 展示用奖励文字不代表已定义可执行奖励；未经任务要求不为订单添加价格、收入或新存档框架。
- 改库存协议另读 [制作与库存规范](../../gameplay/milk_tea/AGENTS.md)；改重置 / 恢复通知同时读 [核心状态规范](../AGENTS.md)。

候选验证：`tests/verify_wallet_transactions.gd` 及本次受影响的交付 / 会话检查；状态契约变化按 [验证分级](../../../tests/AGENTS.md) 升级。
