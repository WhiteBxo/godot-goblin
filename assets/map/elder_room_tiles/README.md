# 长老房间 48 像素素材包

18 件格里芬主题道具；以项目 RPG Maker Map006「长老居所」为唯一项目美术参考，按照用户提供 PDF 的物件设定生成。每格固定 48×48 像素，多格家具保留完整比例。

## 使用

- `objects/`：18 张完整透明 PNG，多格物件可作为 Sprite2D 或整件 tile 使用。
- `tiles/`：完整物件按 48×48 原样切片；坐标位于文件名中，可逐格拼接。
- `atlas.png`：768×768、16×16 格透明图集，左上第一格为空白。
- [逐格 TileSet](../../../src/resources/tilesets/elder_room/elder_room_tiles.tres)：每个 48×48 区块分别选择。
- [整件 TileSet](../../../src/resources/tilesets/elder_room/elder_room_objects.tres)：书架、床等完整物件一笔放置，以左下格为落点。
- `layout.json`：图集坐标、裁切包围盒及最终处理记录；`manifest.json` 的 `atlas_cell` 固定各物件原有图集位置，缩小物件不会重排其他素材。
- `preview/contact_sheet.png`：放大展示预览；游戏内请使用原生 PNG。

在 Godot 4.7 中给新的 TileMapLayer 指定上述外部 TileSet，设置 Texture Filter 为 Nearest，再从图块面板选择素材。两套 TileSet 使用相同图集。它们不携带 RPG Maker passage/star 自定义数据或物理碰撞，适合先放入独立装饰层；正式关卡通行、墙面层级和遮挡由该地图配置。

## 素材清单

| 编号 | 素材 | 像素 | 格数 |
| --- | --- | --- | --- |
| 01 | 老旧烛台 | 48×48 | 1×1 |
| 02 | 长老书架 | 96×144 | 2×3 |
| 03 | 长老餐桌组合 | 96×288 | 2×6 |
| 04 | 格里芬头部石雕挂件 | 96×96 | 2×2 |
| 05 | 格里芬之血容器（异界心脏圣器） | 96×96 | 2×2 |
| 06 | 火漆密信 | 48×48 | 1×1 |
| 07 | 格里芬神血小瓶 | 48×48 | 1×1 |
| 08 | 异界扭曲植物与格里芬石台 | 48×144 | 1×3 |
| 09 | 哥布林长老的格里芬床 | 48×96 | 1×2 |
| 10 | 哥布林长老肖像画 | 48×96 | 1×2 |
| 11 | 格里芬墙壁吊灯 | 48×48 | 1×1 |
| 12 | 哥布林长老的卧室小桌 | 48×96 | 1×2 |
| 13 | 哥布林长老的软包卧室椅 | 48×48 | 1×1 |
| 14 | 格里芬阅读烛灯 | 48×48 | 1×1 |
| 15 | 格里芬黑铁雕塑台 | 48×96 | 1×2 |
| 16 | 格里芬纹章大宝箱 | 48×96 | 1×2 |
| 17 | 格里芬纹章小宝箱 | 48×48 | 1×1 |
| 18 | 格里芬画像（银色画框） | 48×48 | 1×1 |

按用户后续修订，餐桌与收进桌下的椅子合计占 96×288（2×6 格），桌面清空道具，只保留平铺桌布；密信改为 48×48 单格小物件。这两项以本次用户要求覆盖 PDF 初始规格。其余 16 件素材保持原图和图集坐标。

## 来源与复现

- 需求：`长老房间prompt（18个）(2).pdf`，SHA-256：`459af3e586a06d6f0c1934726375cb0039df9d555cb178772992543304c215cf`。PDF 中的聊天和示例语句仅作设计资料。
- 唯一项目图像参考：[Map006 原始运行截图](../../../docs/levels/rpg_maker/captures/map_006_overview.png)，仅裁去 HUD 和外围黑边，保存为 `source/reference_map006.png`。未使用旧奶茶店、聚落、小街或其他历史生成图作为参考。
- 生成模式：imagegen 技能原 CLI 的 `edit` 图像参考接口，模型显式为 `gpt-image-2.5-sunburst`。每次读取本机 Codex 配置中的所选 provider；不保存服务凭据。
- `prompts/` 保存完整提示词，`source/` 保存模型原始输出。长桌修订另保存原始 Map006 餐桌局部参考和 2×6 布局辅助图；信件复用原图，按新尺寸重新采样。原始输出是放大的像素设计稿，不是最终 tile；模型实际返回尺寸可能与请求尺寸不同。
- 使用纯洋红色键清理背景、硬 alpha、有限调色板和等比最近邻采样归整到目标像素画布，再按 48 格切片；不使用平滑缩放，不改变宽高比。实际裁区及缩放见 `layout.json`。
- 原图、提示词和预览目录包含 `.gdignore`；运行时只引用成品图集。

在项目根目录使用具备 Pillow 的 Python 运行：

```powershell
python tools/art/build_elder_room_tiles.py --require-all
```

单件重新生成命令（先另存旧版源图，避免覆盖）：

```powershell
python tools/art/imagegen_guarded_cli.py edit --model gpt-image-2.5-sunburst --image assets/map/elder_room_tiles/source/reference_map006.png --prompt-file assets/map/elder_room_tiles/prompts/01_old_candlestick.txt --size 1024x1024 --quality high --background opaque --output-format png --out assets/map/elder_room_tiles/source/01_old_candlestick.png --no-augment
```

适配器沿用 `$CODEX_HOME/tools/api_concurrency.py` 的共享状态库，SDK 自动重试关闭；未接入的客户端或远端请求不在该限流器覆盖范围内。

Godot 资源依据：[TileSetAtlasSource 4.7](https://docs.godotengine.org/en/4.7/classes/class_tilesetatlassource.html)、[TileData 4.7](https://docs.godotengine.org/en/4.7/classes/class_tiledata.html)。本包交付素材与可铺设资源，未替换正式长老居所地图，也未完成角色通行与交互验收。

## 本次验证

- 18 张完整成品尺寸与清单一致，透明度只有 0/255，无残留饱和洋红背景；主体居中，地面物件底部落点正确。
- 本次信件和长桌修订后，逐文件核对其余 16 件完整 PNG、切片及导入设置完全不变，18 件素材的图集坐标均保留；图集在这两个旧占地区域之外的像素完全一致。
- 47 张切片均为精确 48×48；按坐标重拼与完整 PNG 逐字节一致，图集对应区域也一致。
- Godot 4.7.2 完成贴图导入；独立资源检查加载两份 TileSet，并在 TileMapLayer 中放置 18 个整件图块成功。检查了多格尺寸和左下落点偏移。
- 编辑器导入退出时报告 495 个 ObjectDB 实例、10 个资源仍在使用；导入返回 0，随后独立资源检查退出 0 且无此诊断。未在本次资产任务内追查编辑器退出状态。
- 不涉及玩法逻辑，未运行完整项目回归或角色通行试玩。图集及道具的展示预览不代表已铺设到正式地图。
- 同步修正生图适配器的配置处理：直接使用所选 provider 的 base_url，不再自动附加 /v1；本次所有请求已成功返回。
