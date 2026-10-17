# 洞窟聚落地图

场景、路线和锚点接口见 [聚落说明](../../../docs/levels/settlement/README.md)，美术要求见 [地图素材规范](../../../assets/map/AGENTS.md)。

- 聚落是一整片大洞窟中的连续平地，岩壁集中在整张地图外围；各区域以人造建筑或开放功能区组织，不围成独立小洞穴或悬空地台。整图建筑必须表现外墙厚度与外侧。
- `settlement_map.tscn` 保存地面、河道、街道、桥、外围岩壁及区域实例；运行时不从 `settlement_layout.json` 重建手工布局。
- `districts/` 和 `modules/` 保留关卡区域职责；装修服从各区域用途，不把酒馆、军营等都做成奶茶店。
- 剧情位置通过地图公开 anchor 接口取得，再由实际宿主注册；隐藏线索锚点不自动公开成普通地点提示。新增位置先读 [编排规范](../../../docs/design/AGENTS.md)。
- 采集点实例与静态坐标保存在关卡，规则在 [GatheringService](../../gameplay/gathering/AGENTS.md)；NPC 行为在 [角色模块](../../gameplay/characters/AGENTS.md)，地图不持有独立进度。
- 修改道路、桥、河流、建筑入口时检查直接受影响的连通和碰撞；全图相机、标签与路线观察留在 `src/debug/settlement/`，工具关闭或 Release 时地图仍能独立初始化。

候选验证：`tests/verify_settlement.gd`；出入口 / 采集契约变化再选择直接相关测试，F6 `src/core/settlement.tscn` 观察对应区域和路线。
