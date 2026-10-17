# 交互选择、分发与反馈

职责与接入见 [2D 交互反馈](../../../docs/gameplay/interaction_feedback.md)。

- InteractionPoint 保存对象配置与 Area2D 范围状态；ShopInteraction 是目标选择和 dispatch 的统一入口，不再增加并行的检测 Area 或全局交互管理器。
- 交互沿用 InputMap actions，由宿主注入玩家、界面、交互点与 handler；焦点反馈不能通过查找玩家内部子节点取得朝向。
- 订单、仓库、制作台等先经过既有 StoryDirector 路由；未匹配时才回到原业务入口。调整 trigger 或对象 ID 时同时读 [剧情规范](../../core/story/AGENTS.md) 并检查实际注册。
- InteractionFeedback 是 EffectRoot 的场景内显示组件，通过公开接口接入现有交互与音频，不修改素材、碰撞或玩法结果。
- 反馈框使用对象本地美术范围；提示与成功反馈由真实目标和执行结果驱动，不能在失败或锁定时发出成功反馈。
- 新增采集点读 [采集规范](../gathering/AGENTS.md)，新增出口读 [导航规范](../../core/navigation/AGENTS.md)；空间和碰撞配置跟随所属关卡。

候选验证：`tests/verify_interaction_feedback.gd`，加直接相关宿主的目标切换、锁定、提示及成功 / 失败反馈观察。
