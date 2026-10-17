# 巢穴地图 Tile Demo

本文保留成员 demo 的来源说明。下文命令和路径属于原工程，当前项目的入口与验收命令见 [接入说明](README.md)。

这是一个独立的 Godot 4 项目，用俯视角把编辑版地图的房间与通道完整铺成石砖地面。蓝色区域统一显示为地下河；玩家可以直接穿过浅水到达两岸。镜头始终跟随玩家并保持在画面中央。

## 试玩

双击 `开始试玩.cmd`，使用 **WASD** 或 **方向键** 移动。当前角色只有基础移动与地图边界碰撞。

## 地图与素材

- `map_layout.json` 从 `cave-map-editor/巢穴地图_编辑版.json` 提取房间和通道坐标，保留左上包含、右下不含的格子约定。
- `assets/cave_floor_atlas.png` 是用户提供的 4×4 地板与虚空图集。源 PNG 不会被修改。运行时从每个 mask 的缺失角开始做受颜色阈值限制的四邻接 flood fill，只把连通的蓝色虚空变成纯黑，石砖像素保留原样；mask 0 为空 tile，显示为黑色。地图占用格作为四角采样点，位值 NW=1、NE=2、SW=4、SE=8；图集各行从左到右对应 mask `4,10,13,12`、`9,14,15,7`、`2,3,11,5`、`0,8,6,1`。地板层偏移 `(16,16)`，让组合边界落在原地图格界，窄通道仍沿用原格子范围。
- `assets/river.png` 是 32×32 地下河 tile。源纹样由 Codex 内置 imagegen 生成，Godot 通过 `Image.resize(32, 32, Image.INTERPOLATE_NEAREST)` 缩为像素 tile，源文件保存在 `assets/river_source.png`。完整提示词：

  > Use case: stylized-concept. Asset type: one seamless underground river water tile for a Godot top-down pixel art game. Create a single 32x32 logical-pixel water texture, displayed enlarged with nearest-neighbor solid square pixels. Full square filled edge to edge with dark muted teal-blue water, palette #244958 #306373 #417f8b #70a3a6, very sparse short horizontal pixel ripple strokes. Low contrast, simple readable 1990s pixel art matching dark slate cave stone tiles. Flat top-down view. Seamlessly repeatable on all four edges, no shoreline, no banks, no objects, no perspective, no lighting gradient, no text, no borders, no grid, no transparency. Minimal detail; every pixel is on a strict 32 by 32 logical grid.
- 河道按地图蓝带铺在 x=5..8、y=4..61，包含种植区、水源和中间通道。

## 验收截图

- 整图概览：原工程的 `captures/map_overview.png`
- 玩家出生点：原工程的 `captures/player_spawn.png`
- 地下河通道：原工程的 `captures/river_crossing.png`
- 房间与窄通道连接处：原工程的 `captures/map_junction.png`
- 原图与虚空黑化效果对比：原工程的 `captures/atlas_processing_comparison.png`

使用 Godot 运行 `godot --headless --path . --script res://tools/verify_floor_atlas.gd` 可核对完整 mask 表、实际铺图、单格窄道与镜头居中。

## 无纹理墙体轮廓原型

直接运行原来的开始游戏.cmd。F2 依次切换「墙体 + 石砖地面」「纯色轮廓」「关闭墙体」；M 切换全图与跟随视角，WASD / 方向键移动。

- wall_outline.gd 从可走格子生成北侧 48px 墙面、4px 顶沿、6px 侧沿和5px前沿，墙面位于不可走侧。墙体为纯色色块，无纹理。
- 默认使用 map_layout_walls.json。原 map_layout.json 保留，房间和其他通道坐标均未改变。顶部绕道上移两格至 y=-2，两端连接延长；Godot 支持负格坐标。编辑器仍使用原布局，当前修改只作用于此 demo。
- 原布局在 I/J 北墙有26段墙面与顶绕道重叠，调整后为0；6309个可走格子全部连通，14个房间可达，河道保留232格。
- --original-layout 可读取原布局复现冲突；该选项用于对比。
- 验证：godot --headless --path . --script res://tools/verify_walls.gd；地板回归：godot --headless --path . --script res://tools/verify_floor_atlas.gd。加 -- --original-layout 可以回归旧布局。
- captures/walls_overview.png、walls_junction.png、walls_top_bypass.png、walls_river.png 为实际运行截图；wall_validation.json 记录几何、全图连通、角色通道穿行和墙脚碰撞检查。
