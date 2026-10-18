# 关卡与地图规范

适用于关卡场景、控制脚本和关卡专属布局数据。游戏宿主的组装见 [核心规范](../core/AGENTS.md)，地图美术另见 [地图素材规范](../../assets/map/AGENTS.md)。

| 关卡 | 模块规范 |
| --- | --- |
| 奶茶店（保留现有 milkTea 路径大小写） | [milkTea/AGENTS.md](milkTea/AGENTS.md) |
| 洞窟聚落 | [settlement/AGENTS.md](settlement/AGENTS.md) |
| 旧洞穴 Demo 地图 | [cave/AGENTS.md](cave/AGENTS.md) |
| RPG Maker MZ 移植地图 | [rpg_maker/AGENTS.md](rpg_maker/AGENTS.md) |

- 地图负责显示、边界、出生点与通行规则，通过公开方法向宿主提供查询；不承担玩家输入、剧情顺序或通用 UI。
- 第一天与第二天的地图接口遵循 [场景连接约定](../../docs/design/scene_connections.md)：公共街道分别连接长老居所与商业街；通行按已保存的地图地形配置。
- 布局、出生点和可调参数放对应场景数据或 Resource，明确单位、地图原点及变换；格子 / 世界坐标转换集中处理，不在调用方重复写死格子尺寸。
- 地图显示与可行走规则分别表达。修改贴图、遮挡、家具或建筑时核对碰撞和通行，不能无意改变玩法；物理层遵守 [玩法规范](../gameplay/AGENTS.md)。
- 供成员编辑的静态地图必须把格子保存在场景的 TileMapLayer。运行时由保存的地板格建立通行规则，不清空手工布局，不用旧 JSON 覆盖。
- 边缘、墙体等派生显示由编辑工具同步；JSON 导入必须显式执行，核对目标输出，不能在启动时悄悄重建地图。
- 关卡专属数据随关卡；共享 TileSet 使用 `src/resources/` 下的外部 Resource。动态 JSON 及其他资源的导出见 [资源规范](../resources/AGENTS.md)。
- 以约 110 世界像素高的主角校准门口、家具和步行距离。保持素材原始比例；尺寸或布局不合适时按地图素材规范重新生成，不拉伸整张素材修正。
- 关卡初始化不能依赖调试组件。全图预览、截图、布局对比及墙体调试放 [debug](../debug/AGENTS.md)，正式地图通过公开接口提供所需数据。
- 剧情位置使用场景内明确配置的 Marker / anchor 并由宿主实际注册；剧情绑定另读 [编排规范](../../docs/design/AGENTS.md)，不能为缺失位置编造坐标。

按 [验证分级](../../tests/AGENTS.md) 检查当前关卡与直接调用方；视觉或通行改动给出目标宿主、行走路线与可观察结果，不把裸地图组件当作完整游戏入口。
