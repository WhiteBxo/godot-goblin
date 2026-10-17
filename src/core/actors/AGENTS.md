# ActorDirector 与角色动作

本模块是场景内角色表现服务，不负责剧情条件、flag 或调度顺序。接口与动作契约见 [ActorDirector](../../../docs/systems/actor_director.md)。

- Director 放 Systems，生成角色放宿主注入的 EntityRoot；已有角色和动态角色都使用实际注册的稳定 Actor ID，不按对话说话人或显示名称猜身份。
- 角色控制通过 PlayerController 的公开演出接口；一个角色共用动作互斥槽，取消、替换、解除注册和释放时保持控制权与动作结束状态一致。
- 移动由物理 tick 驱动，使用角色自身碰撞规则；`actor_move` 是有碰撞的直线移动，不提供自动寻路。到达目标需转弯时使用确认过的分段 Marker，不能仅增大 timeout 掩盖受阻。
- 修改角色碰撞、显隐或输入接管前，阅读 [玩法物理层约定](../../gameplay/AGENTS.md)、[玩家规范](../../gameplay/player/AGENTS.md) 与相关 [NPC 规范](../../gameplay/characters/AGENTS.md)。隐藏 NPC 必须退出实体占据层。
- Director 不读剧情 JSON、不持有任务进度；剧情适配读 [story/AGENTS.md](../story/AGENTS.md)。

候选验证：`tests/verify_actor_director.gd`；角色控制或显隐有改动时补直接相关角色检查与 F6 观察，按 [验证分级](../../../tests/AGENTS.md) 选范围。
