# 洞穴墙体 demo 接入说明

此模块从成员提交的 cave-tile-wall-demo 移植。沿用调整后的顶部绕道、原始地板和河流素材，以及纯色墙体轮廓。

## 运行与场景

- 使用 Godot 4.7 系列打开根目录的 project.godot，F5 启动洞穴试玩入口。
- WASD / 方向键移动；F2 切换石砖墙体、纯色轮廓和关闭墙体；M 切换全图与跟随镜头。
- 默认启动 src/core/main.tscn，根节点为 MainGame；World/LevelRoot 挂载 CaveMap，World/EntityRoot 挂载 Player，World/EffectRoot 预留世界特效。
- Systems/CaveDemoController 是独立调试组件，通过 configure 接收地图、玩家和 DebugOverlay；src/debug/cave_demo/cave_demo.tscn 现在是该组件的场景，不是游戏入口。
- 当前试玩提示属于 DebugLayer/DebugOverlay；HudLayer 预留正式游戏 HUD，PopupLayer 预留弹窗，PauseLayer 与 TransitionLayer 为空且默认隐藏。
- 主场景通过 get_active_level()、get_player()、get_debug_tools() 提供引用；初始化顺序为选择布局、绑定移动查询、设置出生点与跟随镜头、启动调试控制。
- CaveMap 负责 FloorLayer、RiverLayer、派生的 BorderLayer 和 WallOutline；Player 通过入口传入的 Callable 查询可行走位置；调试提示由 DebugOverlay 的公开方法更新。
- 保留原来的轴向移动和身体四角格子检测。此次没有引入新的物理碰撞规则，门、箱子等动态碰撞另作功能开发。
- 主项目沿用 Forward Plus 和 Windows D3D12。地图和角色场景使用 nearest 过滤；视口为 960×540。

## 在编辑器中画地图

1. 双击 src/levels/cave/cave_map.tscn，在 2D 编辑器中编辑关卡本身。
2. 选中 FloorLayer，在底部 TileMap 面板选择 Terrains → StoneFloor 画地板，也可以在 Tiles 中选任意石砖格绘制。右键擦除，Ctrl+Z / Ctrl+Shift+Z 撤销或重做。
3. FloorLayer 的格子就是可走区域。CaveMap 的 @tool 会在编辑时匹配周围格子、更新 BorderLayer 和墙体；BorderLayer 属于自动生成的装饰，不要手工编辑。
4. 选中 RiverLayer 单独绘制或擦除河流；河流不改变地板的通行规则。出生点由 CaveMap 的 spawn_cell 设置，墙高等参数在 WallOutline 的 Inspector 中设置。
5. Ctrl+S 保存关卡，再 F5 试玩。正常启动保留手工画的地板和河流。若把出生点擦掉，应先将 spawn_cell 移到有效地板上。

运行中由代码改格子后，显式调用 refresh_from_tiles() 更新通行规则和边界；编辑器绘制通过 changed 和格子批量更新 hook 自动刷新。不要通过 load_layout() 刷新手工地图，它是替换格子的导入操作。

需要重新从成员 JSON 导入时，明确指定输出路径；以下命令会替换输出场景中的手工格子，通常先导入新场景再检查：

```text
godot --headless --path . --script res://tools/map/import_cave_layout.gd -- --layout=res://src/levels/cave/cave_layout.json --output=res://src/levels/cave/imported_cave.tscn
```

相关实现依据：[TileMapLayer 数据与 changed signal](https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html)、[Terrain 编辑](https://docs.godotengine.org/en/stable/tutorials/2d/using_tilesets.html#creating-terrain-sets-autotiling)、[在编辑器中运行 @tool](https://docs.godotengine.org/en/stable/tutorials/plugins/running_code_in_the_editor.html)。

## 数据与资源

- src/levels/cave/cave_map.tscn 保存当前地图格子，是正式布局来源：6309 个地板格、232 个河道格，墙体冲突为 0。启动直接使用这些格子，不再读取 JSON 重建地板或河流。
- cave_layout.json 保留成员 demo 的导入基线：6309 个可走格、7013 个旧版半格铺图候选、14 个房间。
- cave_layout_original.json 保存原布局，供 --original-layout 对比；它有 6305 个可走格、7005 个铺图格和 26 段墙体重叠。
- 两份数据均声明格子尺寸、出生格、河道矩形及墙高等参数；矩形左上包含、右下不含，负格坐标合法。
- 源地板图集保留在 assets/map/cave/cave_floor_atlas.png，SHA256 为 4eda50dfaee516cf3a3bdd99b3b675fd78573e44a1dfc8e5150c7de2e5824b52。
- 原图集每格 32×32，边距和间距为 9；NW、NE、SW、SE 分别为 1、2、4、8。MASK_TO_ATLAS 在 CaveAtlas 中定义，原 demo 的显示格偏移半格。
- prepare_cave_grid.gd 将原图集四个 16×16 象限重新拼成标准 32×32 格，生成 cave_ground.png、cave_border.png 及对应的外部 TileSet。布局坐标与 FloorLayer 现在完全对齐，原地图像素不变。
- 原图的虚空黑化处理提前生成 cave_floor_processed.png，外部 TileSet 位于 src/resources/tilesets/，游戏启动时直接读取这些资源。
- river_source.png 为成员 demo 中保留的生成源图，river.png 是 nearest 缩小到 32×32 的派生图；玩家外观由原 demo 的绘制代码生成 goblin.png。
- 素材来源和生成提示词见 source_demo.md，说明沿用成员文档。
- export_presets.cfg 保留 JSON 导出过滤，并排除文档、离线工具与测试；运行时不依赖 .godot 缓存中的自定义文件。

## 处理与验收命令

下列命令在项目根目录执行，godot 指向本机的 Godot 4.7 可执行文件。

```text
godot --headless --path . --script res://tools/map/prepare_cave_assets.gd
godot --headless --path . --script res://tools/map/prepare_cave_grid.gd
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/verify_floor_atlas.gd
godot --headless --path . --script res://tests/verify_floor_atlas.gd -- --original-layout
godot --headless --path . --script res://tests/verify_walls.gd
godot --headless --path . --script res://tests/verify_main_game.gd
godot --headless --path . --script res://tests/verify_editable_map.gd
```

离线资源处理后重新导入资源，再运行回归。墙体检查结果写入被忽略的 .godot/verification/wall_validation.json。

编辑器回归：在 Godot Script 面板打开 tests/verify_cave_editor.gd，使用 File → Run 执行，或通过 MCP 调用该 EditorScript 的 _run()。它使用临时场景验证自动刷新、Undo/Redo、Terrain 画笔、参数预览与保存重开，不修改正式地图，结果写入 .godot/editable_map_verification/editor_validation.json。

```text
godot --path . -- --capture-walls-junction
godot --path . -- --capture-walls-map
godot --path . -- --capture-walls-top
godot --path . -- --capture-walls-river
godot --path . -- --capture-atlas-compare
```

截图默认写入 user://captures；可添加 --capture-dir=res://.godot/verification 指定本地验收输出。

屏幕层的 layer 分别为 10、20、30、40、50，关闭 follow_viewport_enabled。MainGame 和调试组件使用 Always，Systems 与 World 使用 Pausable，PauseLayer 使用 WhenPaused；此次没有新增暂停操作入口或转场功能。

手动验收：穿过河道和顶部单格绕道，靠近墙脚确认没有越界；连续按 M 返回跟随后继续移动，镜头应重新跟随；F2 切换不应改变通行规则。

## 接入验证记录

- 可编辑地图：28 项运行时检查、18 项真实编辑器检查通过，覆盖格子序列化、手工增删、Undo/Redo、Terrain 画笔、通行与墙体同步、参数预览及保存重开。
- 新旧布局的整张地板像素与原半格拼接结果一致，实际 D3D12 通道和全图截图也与原基线完全一致。
- 可编辑地图的无缓存副本与 PCK 启动通过，PCK 的通道截图与改动前基线完全一致。
- MainGame 架构回归：50 项检查、0 失败，覆盖节点归属、公开 getter、屏幕层顺序、World 平移、暂停/恢复处理、调试输入和屏幕提示固定位置。
- MainGame 重构后的通道与全图截图和接入基线逐像素一致；无缓存副本的架构检查及 PCK 启动通过。
- Godot 4.7.2：新旧布局的 16 种 mask、图集原图校验、铺图数量、河道、窄通道和镜头居中回归通过。
- 墙体与行走回归：18274 项检查、0 失败；包含全图连通、全部房间、绕道实际移动、墙脚限制、地图平移、键位绑定和反复切换镜头。
- 从无 .godot 缓存的副本导入后，墙体回归仍通过；Windows Desktop PCK 在空工作目录启动，正常读取 JSON 布局。
- D3D12 / Forward Plus 实际渲染验证通过；通道截图在 HUD 区域外与成员 demo 截图逐像素一致。
- headless 编辑器退出时的 ObjectDB / resource 清理提示、导出阶段的 Callable 序列化提示在此前基线中也存在；运行时回归和 PCK 启动未出现这些提示。

[全图预览](captures/walls_overview.png) · [通道预览](captures/walls_junction.png)
