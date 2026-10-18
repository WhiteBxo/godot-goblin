# 玩法模块通用边界

适用于 `src/gameplay/`。每个功能的场景和脚本就近放置，内部实现不承包宿主组装、剧情顺序或通用 UI。

| 修改内容 | 继续阅读 |
| --- | --- |
| 玩家输入、移动、朝向与演出接管 | [player/AGENTS.md](player/AGENTS.md) |
| NPC 身份、场景、动画与显隐碰撞 | [characters/AGENTS.md](characters/AGENTS.md) |
| 交互点、目标选择、dispatch 与反馈 | [interaction/AGENTS.md](interaction/AGENTS.md) |
| 采集点与采集规则 | [gathering/AGENTS.md](gathering/AGENTS.md) |
| 剧情调查与拾取点位（文书、圣物） | [story_interaction/AGENTS.md](story_interaction/AGENTS.md) |
| Day 1 投掷、守卫反应与局部重试 | [stealth/AGENTS.md](stealth/AGENTS.md) |
| 奶茶制作、制作入口与共享库存 | [milk_tea/AGENTS.md](milk_tea/AGENTS.md) |
| 哥布林动作 SpriteFrames | [goblin_actions/AGENTS.md](goblin_actions/AGENTS.md) |
| 房间遮挡与门框前景 | [rooms/AGENTS.md](rooms/AGENTS.md) |

## 输入、物理层与依赖

- 玩家操作统一使用 InputMap actions，避免在多个脚本中直接硬编码按键。新增 action 时核对 `project.godot` 与现有输入流程。
- 2D 物理层固定为 1 世界与家具、2 玩家实体、3 可碰撞 NPC；常量见 `PlayerController`。玩家 `collision_mask` 覆盖 1 和 3，NPC 自身 mask 只保留 1。
- NPC 只在场上提供实体占据；隐藏必须退出层 3，避免未出场角色成为隐形墙。关卡碰撞和 Actor 表现代码也必须遵守本约定。
- 玩家移动权限由宿主统一协调。玩法组件只报告状态或经公开接口工作，不能在完成后无条件恢复移动，绕过演出、模态或切场景的锁。
- 场景组件通过公开接口获取地图通行查询、共享服务和状态；不会因 F6、重载或重建 UI 自行重置整局。
- 跨模块共享库存与制作会话读 [核心状态规范](../core/AGENTS.md)；涉及真实交付读 [任务规范](../core/tasks/AGENTS.md)，涉及剧情控制读 [剧情规范](../core/story/AGENTS.md)。

验证选择见 [tests/AGENTS.md](../../tests/AGENTS.md)，各子模块仅列本模块候选项。
