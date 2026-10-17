# 消失的街道：拆图与 Godot 试玩

本次将已生成的小街概念图拆成独立 PNG / PackedScene，再用现有主角在 Godot 4.7.2 中运行校准。入口为 `src/debug/disappeared_street/disappeared_street_demo.tscn`，正式地图为 `src/levels/disappeared_street/disappeared_street_map.tscn`。未更改 F5 的正式入口。

## 试玩与验收

在 Godot 打开试玩场景，按 F6：

1. WASD 从店门出发，在建筑和摊位之间行走；人物不能穿过墙体、柜台和岩壁。
2. 靠近店门按 E，黑场后进入现有奶茶店。再到门口按 E 返回，落在店外安全位置；一直按住 E 不会往返连跳。
3. 在摊位、金币、空街和暗巷处按 E 查看。弹窗期间不能移动，Esc 关闭后恢复。
4. M 切换全景和跟随；全景期间停止移动。P 暂停，Esc 返回。
5. 暗巷可以靠近，但本阶段不会进入深处，保留原稿中的止步反应。

目前是美术和通行试玩，不是完整剧情编排。没有接入 Day 1 的自动演出、阶段推进或一次性事件账本；石屋和摊位不开放内部玩法。店内沿用项目既有场景和比例，连接示例仅在此试玩入口组装。

## 生成来源

模型为 `gpt-image-2.5-sunburst`，CLI/API 使用项目已有的 `tools/art/imagegen_guarded_cli.py`。该适配器读取当前 CODEX_HOME 配置，将每次同步调用接入同一共享限流状态库，并关闭 SDK 自动重试；没有修改技能自带 CLI。

唯一视觉来源是 `assets/map/disappeared_street/source/concept.png`。提示词保存在本目录 `prompts/`，接受的生成结果保存在素材目录的 `source/`。该目录只供处理和追踪，用 `.gdignore` 排除引擎导入。

| 来源图 | 提示词 | 最终用途 |
| --- | --- | --- |
| shop.png | shop.txt | 现代奶茶店外立面 |
| dwelling.png | dwelling_compact.txt | 石屋；初稿尺寸偏大后重新生成 |
| stalls.png | stalls.txt | 两个完整摊位，分别裁切 |
| props.png | props_compact.txt | 长凳、盆栽、木箱、木桶、陶罐、灯柱和店招；初稿重新校准 |
| cave_rim.png | cave_rim.txt | 12 个原尺寸岩壁裁片，在关卡内独立摆放 |
| ground.png | ground.txt | 无建筑和道具的地面贴图 |

`dwelling_compact.txt` 的第二张输入是同目录下保留的 `dwelling_guide.png`，用于限定重绘范围。`props_compact.txt` 的输入为保留的 `props_initial.png`。初稿仅作重绘参考，不被运行场景加载。

AI 拆图包含补绘，外形并非原图像素的无损复原。模型输出中的柔光、半透明噪点和背景残色经过处理，保留硬 alpha。所有游戏 Sprite2D 均保持 scale=(1,1)；没有缩放整张素材来迁就布局。只有素材一览缩略图和相机视口采用显示缩放。

实际运行后将偏大的地面金币替换为摊位图中已有的较小金币，按原尺寸颜色选择提取，保留三枚金币轮廓；具体裁区和处理写入 `catalog.json`。

## 编辑与重建

`assets/map/disappeared_street/catalog.json` 记录 24 个素材的来源、裁切区域、原尺寸、场景和碰撞。地面是外部 `street_ground.tres` 配合关卡内保存的 120 个 TileMapLayer 格子；场景运行不会清空或重建地图。角色的脚部查询跟随保存的地板格，实体碰撞另外管理。

直接在关卡场景中移动模块、调整碰撞或涂地板即可。模块根节点的 GroundAnchor 是地面基准点；与玩家一起沿同一 Y-sort 层级排序。岩壁从透明轮廓生成静态碰撞，底部和侧面的重复裁片维持连续平地。

只有明确需要恢复初始布局时才执行下面的离线命令；它会覆盖该关卡的手工调整：

```powershell
python tools/art/extract_disappeared_street.py
godot --headless --editor --import --path .
godot --headless --path . --script tools/map/bake_disappeared_street.gd -- --rebuild
```

首次生成的 JSON 布局来源是 `src/levels/disappeared_street/street_layout.json`，不在 runtime 自动导入。拆图脚本只做原尺寸裁切、去底和透明处理；完整 API 请求仍由技能 CLI 执行。

## 已执行验证

使用项目 Godot 4.7.2、Forward+ / D3D12 实际打开窗口运行，截图均来自引擎，见 `captures/`：

- `street_overview.png`：真实 World2D 的全图，保留同一个玩家。
- `shop_scale.png`、`market_scale.png`：跟随镜头下校准门和柜台的比例。
- `dark_exit.png`：暗巷的通行与视觉范围。
- `shop_connection.png`：进入现有奶茶店后的实际落点。
- `extracted_assets.png`：透明素材一览，仅用于审查。

真实移动验证命令：

```powershell
godot --path . --script tests/verify_disappeared_street.gd -- --captures
```

结果 PASS：出生点清空、所有交互点可达、实际输入移动、墙体/柜台阻挡、删除地板格后角色止步、E 查看时锁定移动、长按 E 安全进店、再次 E 返回同门及保持玩家实例。运行中发现店内根节点的 1.25 变换，已将入口落点改为通过该场景的 `to_global()` 转换。

核对的 Godot 4.7 官方说明：

- [CanvasItem.y_sort_enabled](https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html#class-canvasitem-property-y-sort-enabled)：同一 z_index 下按地面锚点排序，原子模块的子节点整体排序。
- [TileMapLayer](https://docs.godotengine.org/en/4.7/classes/class_tilemaplayer.html)：地板数据保存在场景，runtime 读取 `get_cell_source_id()`。
- [BitMap.opaque_to_polygons](https://docs.godotengine.org/en/4.7/classes/class_bitmap.html#class-bitmap-method-opaque-to-polygons)：从透明轮廓生成可简化的碰撞多边形。
- [StaticBody2D](https://docs.godotengine.org/en/4.7/classes/class_staticbody2d.html)：静态建筑、道具和岩壁的物理阻挡。
