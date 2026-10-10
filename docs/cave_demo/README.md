# 洞穴墙体 demo 接入说明

此模块从成员提交的 cave-tile-wall-demo 移植。沿用调整后的顶部绕道、原始地板和河流素材，以及纯色墙体轮廓。

## 运行与场景

- 使用 Godot 4.7 系列打开根目录的 project.godot，F5 启动洞穴试玩入口。
- WASD / 方向键移动；F2 切换石砖墙体、纯色轮廓和关闭墙体；M 切换全图与跟随镜头。
- 正式组装入口是 src/core/main.tscn；默认启动的 src/debug/cave_demo/cave_demo.tscn 继承它并提供调试操作和截图。
- CaveMap 负责布局、FloorLayer、RiverLayer 和 WallOutline；Player 通过入口传入的 Callable 查询可行走位置；HUD 通过公开方法更新提示。
- 保留原来的轴向移动和身体四角格子检测。此次没有引入新的物理碰撞规则，门、箱子等动态碰撞另作功能开发。
- 主项目沿用 Forward Plus 和 Windows D3D12。地图和角色场景使用 nearest 过滤；视口为 960×540。

## 数据与资源

- src/levels/cave/cave_layout.json 是默认布局：6309 个可走格、7013 个铺图格、14 个房间、232 个河道格，墙体冲突为 0。
- cave_layout_original.json 保存原布局，供 --original-layout 对比；它有 6305 个可走格、7005 个铺图格和 26 段墙体重叠。
- 两份数据均声明格子尺寸、出生格、河道矩形及墙高等参数；矩形左上包含、右下不含，负格坐标合法。
- 源地板图集保留在 assets/map/cave/cave_floor_atlas.png，SHA256 为 4eda50dfaee516cf3a3bdd99b3b675fd78573e44a1dfc8e5150c7de2e5824b52。
- 图集每格 32×32，边距和间距为 9；NW、NE、SW、SE 分别为 1、2、4、8。MASK_TO_ATLAS 在 CaveAtlas 中定义，地板层偏移半格。
- 原图的虚空黑化处理提前生成 cave_floor_processed.png，外部 TileSet 位于 src/resources/tilesets/，游戏启动时直接读取这些资源。
- river_source.png 为成员 demo 中保留的生成源图，river.png 是 nearest 缩小到 32×32 的派生图；玩家外观由原 demo 的绘制代码生成 goblin.png。
- 素材来源和生成提示词见 source_demo.md，说明沿用成员文档。
- export_presets.cfg 保留 JSON 导出过滤，并排除文档、离线工具与测试；运行时不依赖 .godot 缓存中的自定义文件。

## 处理与验收命令

下列命令在项目根目录执行，godot 指向本机的 Godot 4.7 可执行文件。

```text
godot --headless --path . --script res://tools/map/prepare_cave_assets.gd
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/verify_floor_atlas.gd
godot --headless --path . --script res://tests/verify_floor_atlas.gd -- --original-layout
godot --headless --path . --script res://tests/verify_walls.gd```

离线资源处理后重新导入资源，再运行回归。墙体检查结果写入被忽略的 .godot/verification/wall_validation.json。

```text
godot --path . -- --capture-walls-junction
godot --path . -- --capture-walls-map
godot --path . -- --capture-walls-top
godot --path . -- --capture-walls-river
godot --path . -- --capture-atlas-compare
```

截图默认写入 user://captures；可添加 --capture-dir=res://.godot/verification 指定本地验收输出。

手动验收：穿过河道和顶部单格绕道，靠近墙脚确认没有越界；连续按 M 返回跟随后继续移动，镜头应重新跟随；F2 切换不应改变通行规则。

## 接入验证记录

- Godot 4.7.2：新旧布局的 16 种 mask、图集原图校验、铺图数量、河道、窄通道和镜头居中回归通过。
- 墙体与行走回归：18274 项检查、0 失败；包含全图连通、全部房间、绕道实际移动、墙脚限制、地图平移、键位绑定和反复切换镜头。
- 从无 .godot 缓存的副本导入后，墙体回归仍通过；Windows Desktop PCK 在空工作目录启动，正常读取 JSON 布局。
- D3D12 / Forward Plus 实际渲染验证通过；通道截图在 HUD 区域外与成员 demo 截图逐像素一致。
- headless 编辑器退出时的 ObjectDB / resource 清理提示在移植前的 Git 基线中也存在；运行时回归和 PCK 启动未出现这些提示。

[全图预览](captures/walls_overview.png) · [通道预览](captures/walls_junction.png)
