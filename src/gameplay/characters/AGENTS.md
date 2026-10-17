# NPC 场景与身份

本目录保存角色场景、身份配置、SpriteFrames 与 character catalog；角色素材接入见 [人物说明](../../../docs/assets/characters.md)。

- SettlementCharacter 复用 PlayerController，身份保存在场景中，剧情对白与顺序保存在 Story / Dialogue 数据，不在角色脚本里写 Beat 顺序。
- `actor_id`、显示名称、剧情身份与资源绑定各有用途；使用目标宿主实际注册的 Actor，不以同名节点、人类占位角色或说话人 ID 冒充角色。
- NPC 禁用玩家输入，按 [玩法物理层约定](../AGENTS.md) 配置碰撞：自身 mask 只含世界层，实体占据随实际可见性加入 / 退出 NPC 层。
- 注册、动态生成、演出控制与退出清理遵守 [ActorDirector 规范](../../core/actors/AGENTS.md)，宿主通过公开接口注入依赖。
- 动画来源、原图和派生素材分开保存；切帧、朝向、脚底锚点与资源映射一起核对，不为一张角色图改动其他角色素材。动作资源另见 [goblin_actions/AGENTS.md](../goblin_actions/AGENTS.md)。

候选验证：`tests/verify_characters.gd`，以及本次涉及的 Actor 显隐 / 碰撞观察；不要因调整一张立绘运行全项目回归。
