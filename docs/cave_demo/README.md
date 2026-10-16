# 洞穴墙体 demo 接入说明

此模块从成员提交的 cave-tile-wall-demo 移植。沿用调整后的顶部绕道、原始地板和河流素材，以及纯色墙体轮廓。

## 当前区域间距调整

- 墙高从 48px 提高到 56px；顶沿、侧沿与前沿仍为原来的 4px、6px、5px。
- 仓库南侧与下方横廊、聚餐区与住宿区、住宿区与入口前厅的间距均调整为 6 格。住宿区东侧纵廊向右移动，卸货庭院向右移动 4 格，使右下阶梯两侧也留出更宽的黑色实体区域。
- 移除右侧纵廊向左的冗余短枝，使住宿区东侧黑带保持完整。
- 保留 14 个房间的尺寸；住宿区下移 4 格，入口前厅与洞外撤离下移 7 格，连接通道按新坐标衔接。出生格仍为 `(63, 76)`，河道仍为 232 格。
- 当前场景和 cave_layout.json 已同步保存新的布局；cave_layout_original.json 与 source_demo.md 保留历史版本。
- 试玩时按 M 查看全图，重点观察横向房间夹缝和右下竖向黑带；F2 可切换纯色轮廓与石砖地面。

## 运行与场景

- 使用 Godot 4.7 系列打开根目录的 project.godot，F5 启动洞穴试玩入口。
- WASD / 方向键移动；F2 切换石砖墙体、纯色轮廓和关闭墙体；M 切换全图与跟随镜头。
- 右下角“开发者工具”可在运行中选择玩家移速 1×、2×、4×、8×，每次启动默认 1×。倍率基于 Player 的 speed（默认 122 px/s），不累乘、不写回场景；恢复 1× 即恢复基础速度。移动查询按小步执行，避免高倍率跳过不可走区域。
- 默认启动 src/core/main.tscn，根节点为 MainGame；World/LevelRoot 挂载 CaveMap，World/EntityRoot 挂载 Player，World/EffectRoot 预留世界特效。
- Debug 运行时，MainGame 在 Systems 中创建通用 DeveloperTools 和洞穴专属 CaveDemoController，在 DebugLayer 中创建 DeveloperPanel 和 DebugOverlay。Release 不创建这些节点。src/debug/cave_demo/cave_demo.tscn 是调试组件的场景，不是游戏入口。
- 当前试玩提示属于 DebugLayer/DebugOverlay；HudLayer 预留正式游戏 HUD，PopupLayer 预留弹窗，PauseLayer 与 TransitionLayer 为空且默认隐藏。
- 主场景通过 get_active_level()、get_player()、get_debug_tools() 和 get_demo_tools() 提供引用；后两个 getter 分别返回通用和洞穴专属调试组件，工具关闭或 Release 时返回 null。初始化顺序为选择布局、绑定移动查询、设置出生点与跟随镜头、启动可选调试组件，正常启动不依赖调试组件。
- CaveMap 负责 FloorLayer、RiverLayer、派生的 BorderLayer 和 WallOutline；Player 通过入口传入的 Callable 查询可行走位置；调试提示由 DebugOverlay 的公开方法更新。
- 保留原来的轴向移动和身体四角格子检测。此次没有引入新的物理碰撞规则，门、箱子等动态碰撞另作功能开发。
- 主项目沿用 Forward Plus 和 Windows D3D12。地图和角色场景使用 nearest 过滤；设计视口为 640×360，默认窗口为 1280×720，canvas_items + keep + integer 使用 2 倍整数缩放。保留 transform pixel snap，关闭 vertex pixel snap；相机平滑沿用当前玩家场景配置。

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

移速工具使用 [OptionButton 的 item_selected signal](https://docs.godotengine.org/en/stable/classes/class_optionbutton.html#class-optionbutton-signal-item-selected) 将选择交给调试控制器，再通过玩家公开接口设置倍率。屏幕空白和提示使用 [Control.MOUSE_FILTER_IGNORE](https://docs.godotengine.org/en/stable/classes/class_control.html#enum-control-mousefilter)，只有工具区域接收鼠标。

## 数据与资源

- src/levels/cave/cave_map.tscn 保存当前地图格子，是正式布局来源：6330 个地板格、232 个河道格，墙体冲突为 0。启动直接使用这些格子，不再读取 JSON 重建地板或河流。
- cave_layout.json 保存当前区域间距调整后的导入布局：6330 个可走格、14 个房间；与正式场景一致。
- cave_layout_original.json 保存原布局，供 --original-layout 对比；它有 6305 个可走格、7005 个铺图格和 26 段墙体重叠。
- 两份数据均声明格子尺寸、出生格、河道矩形及墙高等参数；矩形左上包含、右下不含，负格坐标合法。
- 源地板图集保留在 assets/map/cave/cave_floor_atlas.png，SHA256 为 4eda50dfaee516cf3a3bdd99b3b675fd78573e44a1dfc8e5150c7de2e5824b52。
- 原图集每格 32×32，边距和间距为 9；NW、NE、SW、SE 分别为 1、2、4、8。MASK_TO_ATLAS 在 CaveAtlas 中定义，原 demo 的显示格偏移半格。
- prepare_cave_grid.gd 将原图集四个 16×16 象限重新拼成标准 32×32 格，生成 cave_ground.png、cave_border.png 及对应的外部 TileSet。布局坐标与 FloorLayer 现在完全对齐，原地图像素不变。
- 原图的虚空黑化处理提前生成 cave_floor_processed.png，外部 TileSet 位于 src/resources/tilesets/，游戏启动时直接读取这些资源。
- river_source.png 为成员 demo 中保留的生成源图，river.png 是 nearest 缩小到 32×32 的派生图；玩家现使用用户提供的四向精灵图，切帧说明见 [玩家素材说明](../../assets/characters/player/README.md)。
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

截图入口会隐藏通用开发者面板；图集对比使用 MarginContainer、HBoxContainer 和 VBoxContainer，根据视口自动安排两个完整预览。截图和 --original-layout 参数仅在 Debug 构建生效。

出生和切换视角时调用 Camera2D.reset_smoothing() 并更新滚动位置，立即对准目标；普通移动继续使用玩家场景中的平滑设置。[相机 API](https://docs.godotengine.org/en/4.7/classes/class_camera2d.html#class-camera2d-method-reset-smoothing)

## 通用开发者工具

DeveloperTools 通过 configure(set_multiplier, get_multiplier, panel) 接收两个 Callable 和 DeveloperPanel，不依赖 CavePlayer 或 CaveMap 类型。新角色只需提供倍率设置和读取接口；setter 应接受 1、2、4、8，getter 返回实际生效的倍率。配置成功返回 OK，依赖缺失或工具关闭返回 ERR_UNCONFIGURED 并隐藏面板。重新 configure 会断开旧面板的 signal 并切换目标，初始倍率恢复 1×。

面板的 speed_multiplier_selected signal 交给 DeveloperTools.set_player_speed_multiplier()，组件校验允许倍率后调用 setter，再通过 getter 同步显示。MainGame 注入玩家公开接口；CaveDemoController 只管理洞穴专属调试行为。组件场景挂 Systems 并使用 Always，面板挂 DebugLayer；全屏根 Control 忽略鼠标，只有面板区域接收输入。

DebugRuntime.is_enabled() 同时检查 debug feature 和开发开关；Release 无法通过开发开关启用工具。DebugRuntime.apply_release_policy() 在 MainGame 启动时停止第三方 MCPRuntimeProbe 的处理，不改写 autoload 配置或插件源码。

```text
godot --headless --path . --script res://tests/verify_developer_tools.gd
godot --headless --path . --script res://tests/verify_debug_build.gd
```

构建边界测试需分别在 Debug 和 Release export template 执行；只用编辑器运行 PCK 仍带 debug feature，不能作为 Release 验收。依据：[Feature tags](https://docs.godotengine.org/en/4.7/tutorials/export/feature_tags.html)、[Containers](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_containers.html)、[pixel snap 限制](https://docs.godotengine.org/en/4.7/classes/class_projectsettings.html#class-projectsettings-property-rendering-2d-snap-snap-2d-transforms-to-pixel)。

本轮真实构建验收在临时项目副本中将 verify_debug_build.gd 的检查改为等价 Node 入口场景，然后分别导出 Debug 和 Release EXE；正式主场景和导出配置未替换为测试入口。两种构建均验证出生与移动；Debug 验证倍率和旧布局，Release 验证调试节点缺席、调试按键无效、旧布局参数无效及 MCP 轮询停止。

屏幕层的 layer 分别为 10、20、30、40、50，关闭 follow_viewport_enabled。MainGame 和调试组件使用 Always，Systems 与 World 使用 Pausable，PauseLayer 使用 WhenPaused；此次没有新增暂停操作入口或转场功能。

手动验收：穿过河道和顶部单格绕道，靠近墙脚确认没有越界；连续按 M 返回跟随后继续移动，镜头应重新跟随；F2 切换不应改变通行规则。

## 本次区域间距验证

- Godot 4.7.2 墙体与行走检查：18,360 项、0 失败；6330 个地板格全部可达，14 个房间连通，河道保留 232 格，墙体冲突为 0。
- 可编辑地图检查：29 项、0 失败，覆盖手工增删格、显式刷新、保存与重开。
- 当前与原始布局的图集检查均通过；主场景检查 50 项、0 失败。
- 实际 D3D12 / Forward Plus 全图与 H-D 连接处截图已更新，横向黑色夹缝和右下竖向黑带加宽。

## 历史接入验证记录

- 通用开发工具与近期设置修正：MainGame 71 项、独立工具 11 项检查通过；640×360 和默认 1280×720 的运行界面、鼠标打开下拉框与原生选项选择通过，真实 Debug / Release EXE 构建边界检查通过。原有编辑器退出的资源清理警告和导出 Callable 警告仍存在，运行时验收没有这些警告。
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
