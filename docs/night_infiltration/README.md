# 夜间潜入：按原图坐标重建

本版以用户于 2026-10-17 重发的 1678 × 937 概念图为视觉依据。F6 入口为 `src/debug/night_infiltration/night_infiltration_demo.tscn`，地图为 `src/levels/night_infiltration/night_infiltration_map.tscn`。

## 选用的教程提示词

| 本地教程 | 采用的约束 | 本项目适配 |
| --- | --- | --- |
| `D:/taptapgamejam/教程资源/AI游戏美术/二维分层场景/提示词合集.txt` | 同一画布、同一原点、相同物体坐标；不重新居中或构图；补全被遮挡区域 | 保留原图 1678 × 937 坐标，裁切时记录偏移；所有可见像素优先来自原图 |
| `D:/taptapgamejam/教程资源/AI游戏美术/HD-2D游戏场景/批量生图提示词.txt` | 建筑与元素独立；地面单独提取；补全遮挡 | 38 个独立模块，地面单独成为 atlas；维持本图俯视角度，不套用示例的建筑正视图要求 |
| `D:/taptapgamejam/教程资源/AI游戏美术/HD-2D游戏场景/场景模版搭建提示词.md` | 贴图入口、底边锚点、独立碰撞 | 模块中保留 Visual / GroundAnchor，碰撞随建筑和道具移动；不引入本任务不需要的 3D 天空、粒子或九点缩放工具 |

本图是同一平面内的俯视场景，没有套用横向平台游戏的远山视差。

## 图像与场景构成

- 原图：`assets/map/night_infiltration/source/concept.png`，与最初第五阶段概念图逐像素一致。
- 全部建筑、道具、守卫与岩壁保持原图位置、轮廓、原始像素比例和冷暖光，不把单个元素放大重画，也不重新分配街巷宽度。
- `tools/art/extract_night_infiltration.py` 定义原图坐标遮罩和地面锚点，输出独立 PNG / PackedScene；`catalog.json` 记录裁区、位置、原尺寸和碰撞数据。没有对游戏素材进行 resample。
- 补绘用于隐藏地面、开门后露出的阈口，以及右下封口。可见地面沿用原图，保留每处光照和石块分布。
- 地面保存为 405 个 64 × 64 的 TileMapLayer 格子，每格读取 atlas 对应位置，避免小裁片反复平铺产生格纹。atlas 右、下仅做画布补边，实际世界范围仍为 1678 × 937。
- 长老房间作为背层，书桌、床、柜子、前墙和门楣另外裁出遮挡层，与玩家按脚底 Y 排序。四名守卫是独立静态站位模块。
- 宅邸正门按 E 打开，局部贴图与物理阻挡同步切换。门口是同图内部接口。
- 左下是唯一对外接口；右下缺口已用岩壁封闭，且有真实碰撞。连接约定见 `docs/design/scene_connections.md`，并已写入 `AGENTS.md`。

## imagegen 记录

已选用用户授权的 CLI/API 模式，显式模型为 `gpt-image-2.5-sunburst`，quality high。使用项目既有 `tools/art/imagegen_guarded_cli.py` 适配未修改的技能 CLI，逐次读取当前 Codex provider 配置，接入共享 `guarded_call`，关闭 SDK 自动重试，凭据不落入交付物。

完整提示词位于 `prompts/ground_plate.txt` 与 `prompts/door_and_exit_patch.txt`，接受的原始输出位于素材 `source/`，此目录使用 `.gdignore` 排除引擎导入。服务不接受该模型的自定义尺寸参数，因此实际使用 `--size auto`，返回 1673 × 940。处理只进行裁切、补边和局部平移（局部修改图 +4、-1），没有拉伸到参考尺寸。服务的其余修改均通过局部遮罩排除。

本轮两次同步请求正常结束。之前一轮的超时占用 `14aaaf51450343559172957f98856e9b` 仍保留，没有未经确认释放或吞掉不确定错误。

## 试玩

打开 F6 入口：

1. WASD 从左下入口进入，在守卫侧面穿过门框；人物不能穿过木柱、建筑、货物和外围岩壁。
2. 到右上宅邸正门前按 E。木门打开后可进入房间；书桌、床和柜子会阻挡脚部，角色前后遮挡随位置变化。
3. 在文书、圣物、醉酒守卫和火把附近按 E 查看，Esc 关闭说明后恢复移动。
4. M 切换全景与跟随，全景期间暂停角色移动。

这是场景、美术、通行与开门试玩。投币、贿赂、警报、火灾和完整 Day 1 剧情仍待玩法/剧情任务接入。左下接口已提供 `travel_requested(public_street, from_elder_district)`，本独立入口只展示去向，没有修改用户正在手工编辑的公共街道或 F5 入口。

## 重建与验证

日常编辑以关卡场景为准，runtime 不清空地板、不自动导入旧 JSON。

仅在明确需要覆盖手工调整、恢复本版原图坐标时运行：

```powershell
python tools/art/extract_night_infiltration.py
godot --headless --editor --import --path .
godot --headless --path . --script tools/map/bake_night_infiltration.gd -- --rebuild
```

已使用 Godot 4.7.2 执行：

```powershell
godot --headless --path . --script tests/night_infiltration/verify_night_infiltration.gd
```

结果 PASS：真实角色胶囊的出生与全点位可达、入口实际输入移动、墙体阻挡、E 开门/穿门、局部图像切换、文书 E/Esc 锁定恢复、保存地板格的读取、原尺寸模块和单一对外接口。修复了离线打包中重新设置继承子节点 owner 导致的孤立节点，试玩退出无资源泄漏报错。

Forward+ / D3D12 实际渲染截图：

- `captures/godot_overview.png`：实际 World2D 原尺寸全图，隐藏玩家与 HUD 便于对照；运行时仅加载地面 atlas 和独立模块，没有加载概念图整图。
- `captures/godot_playable_overview.png`：同一实际场景的全图，保留入口处的可操作主角。
- `captures/interior_playable.png`：玩家站在书桌前，正门已打开。
- `captures/desk_occlusion.png`：玩家站在书桌后，确认前后关系。
- `captures/offline_recomposition.png`：离线拆层合成审计，用于定位图层缺失，不作为游戏截图。

核对的 Godot 4.7 官方文档：

- [TileMapLayer](https://docs.godotengine.org/en/4.7/classes/class_tilemaplayer.html)：保存格子、atlas 坐标和 `local_to_map` / `get_cell_source_id`。
- [CanvasItem](https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html#class-canvasitem-property-y-sort-enabled)：同一 z_index 下按脚底 Y 排序。
- [Sprite2D](https://docs.godotengine.org/en/4.7/classes/class_sprite2d.html)：原尺寸纹理与偏移。
- [PackedScene](https://docs.godotengine.org/en/4.7/classes/class_packedscene.html)：保存新增子节点，同时保留模块继承子节点的 owner。
