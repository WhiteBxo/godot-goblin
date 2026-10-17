# 场景出入口与切换

配置、入口 ID 与切换边界见 [店铺与聚落进出](../../../docs/systems/scene_travel.md)。

- SceneExit 沿用现有交互点与 InputMap 路由，配置目标宿主场景及入口 ID；SceneEntrance 保存目标出生位置和朝向，位置属于关卡配置。
- 额外条件用 `SceneExit.required_flags`（GameState flag 全部为真才可通行，空数组不设门控）；`request_exit` 在进入切换前检查，失败只发 `travel_failed`，不占用 busy、不淡出。
- SceneTravel 负责一次切换的交接，不管理剧情内容。普通进出复用 GameState 经营会话，不调用新游戏、重置库存或补写探索完成事实。
- 保持演出、模态 UI 和活动 Bridge phase 期间拒绝切换的现有守卫；按住交互键不能落地后立即反向切换，失败或重载不遗留待消费入口。
- 黑场视觉通过 [ScreenTransition](../../UI/screen_transition/AGENTS.md) 实现；场景变更、输入协调与出生点应用仍由导航和宿主承担。
- 新增出口同时读 [交互规范](../../gameplay/interaction/AGENTS.md) 和目标 [关卡规范](../../levels/AGENTS.md)，检查真实目标场景、入口 ID 与可行走出生点。

候选验证：`tests/verify_scene_travel.gd`，加对应宿主进出和会话保持的最小观察；生命周期契约改变时按 [验证分级](../../../tests/AGENTS.md) 升级。
