# 旧洞穴地图

地图、编辑工具与宿主说明见 [洞穴 Demo](../../../docs/levels/cave_demo/README.md)。

- `cave_map.tscn` 保存的地板与河道格是布局来源；`cave_layout.json` 等保留为显式导入 / 比较数据，启动不读取它们覆盖 TileMap。
- CaveMap 管理 FloorLayer、RiverLayer、派生 BorderLayer 与 WallOutline；玩家通过宿主传入的 Callable 查询通行，不让 CaveMap 负责玩家输入或调试面板。
- 编辑地板后由编辑工具更新派生边缘 / 墙体；图集转换和共享 TileSet 沿用现有工具与资源，不在多个脚本复制 mask / atlas 或半格偏移规则。
- 布局选择、墙体切换和截图由 `src/debug/cave_demo/` 的专属组件负责，通用面板按 [Debug 规范](../../debug/AGENTS.md) 接入。调试组件场景需要依赖注入，不是独立游戏入口。

候选验证：`verify_cave_editor.gd`、`verify_editable_map.gd`、`verify_floor_atlas.gd`、`verify_walls.gd`，按本次风险只选相关项；修改导入工具另读 [工具规范](../../../tools/AGENTS.md)。
