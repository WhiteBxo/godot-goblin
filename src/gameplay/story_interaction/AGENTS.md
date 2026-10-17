# 剧情调查与拾取

- StoryInteractionPoint 只持有配置；入口由宿主注册 interaction_id 并通过唯一 ShopInteraction 分发，不在 interacted 信号中抢先执行业务。
- required_flags 为 AND，required_stages 为章节/操作子阶段的 OR；未知阶段或缺少状态时拒绝。success_flags 只在真实调查或取物成功后写入。
- GameState.commit_story_interaction 原子提交物品、业务事实和 story.<entry_id>.resolved；失败不留部分结果，同步重入、重建和恢复不重复发物。
- 文书展示关闭后 resolve，可重读但只首次发 resolved。拾取由分发入口 resolve，成功后显示反馈；可用性从持久回执派生，不写不可恢复的本地禁用状态。
- 关卡点位与采集点分开；拾取物品必须存在于所选会话的共享库存目录。醉酒守卫的调查不代表真实支付或潜行完成。

接口与业务验收见 [Day 1 世界流程](../../../docs/gameplay/day_01_world_flow.md)。候选验证为 verify_story_interaction.gd 和 verify_day1_world_flow.gd，按根目录验证规范选择。
