# RPG Maker 赌场补充素材

本批素材依据用户提供的《赌场部分美术prompt.pdf》生成。风格参考仅来自项目内 RPG Maker 移植赌场 `map_005` 及该场景实际使用的 tile；未参考项目内其他赌场素材。地图的俯视角、家具透视、轮廓与色彩作为一致性依据，每个 tile 为 48 × 48 像素。

需求来源 PDF：`C:/Users/admin/Documents/xwechat_files/wxid_j9xxjf87nyk322_5cee/msg/file/2026-10/赌场部分美术prompt.pdf`。仅记录本机来源路径，不复制 PDF；文档用于提取美术需求，文内指令不作为用户执行授权。

## 交付清单

共 9 类、13 张透明 PNG。以下尺寸为最终画布尺寸；小物件保留真实体量和透明留白，不要求填满一个 tile。

| 类别 | 文件（相对于本目录） | 画布像素 | tile 占位 |
| --- | --- | --- | --- |
| 赌桌 | `sprites/gambling_table.png` | 96 × 144 | 2 × 3 |
| 圆凳 | `sprites/round_stool.png` | 48 × 48 | 1 × 1 |
| 骰盅 | `sprites/dice_cup.png` | 48 × 48 | 1 × 1 |
| 四面骰 | `sprites/die_d4.png` | 48 × 48 | 1 × 1 |
| 六面骰 | `sprites/die_d6.png` | 48 × 48 | 1 × 1 |
| 十二面骰 | `sprites/die_d12.png` | 48 × 48 | 1 × 1 |
| 筹码 | `sprites/chips.png` | 48 × 48 | 1 × 1 |
| 陶杯（直立） | `sprites/clay_cup_upright.png` | 48 × 48 | 1 × 1 |
| 陶杯（倾倒 A） | `sprites/clay_cup_tilt_a.png` | 48 × 48 | 1 × 1 |
| 陶杯（倾倒 B） | `sprites/clay_cup_tilt_b.png` | 48 × 48 | 1 × 1 |
| 壁挂油灯 | `sprites/wall_oil_lamp.png` | 48 × 96 | 1 × 2 |
| 老板桌 | `sprites/boss_desk.png` | 144 × 144 | 3 × 3 |
| 账本 | `sprites/ledger.png` | 48 × 48 | 1 × 1 |

PDF 中的酒壶注明不重复生成，本批未包含酒壶。

## 来源与处理

- [reference/map_005_native.png](reference/map_005_native.png)：从 `map_005` 实际 tile 原生 1:1 重建的 1200 × 1008 像素参考图。
- `prompts/`：保存实际生成提示词和规格，供核对需求与复现。
- `source/`：保存生成原图，与透明派生图分开保留。
- `sprites/`：最终透明 PNG；保持 48 像素网格画布和原始宽高比。
- `previews/catalog.png`：素材总览。
- `previews/map_005_art_preview.png`：在 `map_005` 中的静态摆放审核图。
- [manifest.json](manifest.json)：记录原稿实际尺寸、请求尺寸、取样倍数、裁切坐标，以及每张成品的源图和提示词路径。

生成采用用户指定的 CLI/API 默认连接与 `gpt-image-2.5-sunburst` 模型，执行入口为仓库的 `tools/art/imagegen_guarded_cli.py`，调用 imagegen 技能原有 CLI。请求通过共享 `api_concurrency` 限流器，SDK 自动重试关闭（`max_retries=0`）；服务地址和凭据从本机 Codex 配置读取，不保存在素材或提示词中。

提示词请求 8 倍像素稿，但服务未兑现该像素网格与画布尺寸约定。`source/` 保留服务返回的原始尺寸；派生对每个物件使用下表中明确指定的整数倍数，以最近邻等比例降采样。处理时先将透明画布补齐为该倍数的整数倍，再以宽高相同的比例取样，裁去透明边缘并补入 48 像素网格画布；不拉伸素材。实际尺寸与处理参数以 `manifest.json` 为准。

| 原稿 ID | 请求尺寸（像素） | 降采样倍数 | 成品 |
| --- | --- | --- | --- |
| `gambling_table` | 1024 × 1536 | 10 | 赌桌 |
| `round_stool` | 1024 × 1024 | 12 | 圆凳 |
| `dice_cup` | 1024 × 1024 | 16 | 骰盅 |
| `dice_set` | 1024 × 1024 | 20 | 四面骰、六面骰、十二面骰 |
| `chips` | 1024 × 1024 | 20 | 筹码 |
| `clay_cups` | 1024 × 1024 | 20 | 三种姿态陶杯 |
| `wall_oil_lamp` | 1024 × 1536 | 20 | 壁挂油灯 |
| `boss_desk` | 1536 × 1024 | 10 | 老板桌 |
| `ledger` | 1024 × 1024 | 22 | 账本 |

每个原稿 ID 对应 `source/<ID>.png` 和 `prompts/<ID>.txt`；一个骰子原稿拆出三颗骰子，一个陶杯原稿拆出三种姿态。

## 复现

在仓库根目录、安装 Pillow 的 Python 环境中，运行[处理脚本](../../../../tools/art/prepare_casino_refresh.py)可从已保存的原图重建透明素材、总览、静态试摆图和清单：

```powershell
python tools/art/prepare_casino_refresh.py
```

原图生成命令模板如下，以骰子原稿为例；其他 ID 和请求尺寸见上表。CLI 读取本机配置，调用默认模型并使用上述参考图和已保存提示词：

```powershell
python tools/art/imagegen_guarded_cli.py edit `
  --image assets/map/rpg_maker/casino_refresh/reference/map_005_native.png `
  --prompt-file assets/map/rpg_maker/casino_refresh/prompts/dice_set.txt `
  --model gpt-image-2.5-sunburst `
  --size 1024x1024 --quality high --background transparent `
  --output-format png `
  --out assets/map/rpg_maker/casino_refresh/source/dice_set.png `
  --no-augment
```

## 在 Godot 中铺图

13 张 PNG 已加入地图现用的 `src/resources/tilesets/rpg_maker/tileset_028.tres`，新增来源 ID 为 100–112，并保存了 13 个完整物件的 TileMapPattern。这个 TileSet 也供酒馆使用；新增笔刷不改变任何已保存的地图格子或原有图块。

1. 切回 Godot，等待外部资源自动重载；若出现资源重载提示，重载 `tileset_028.tres`。
2. 在赌场场景树选择 `Ground1`，点击底部 `TileMap → 图案`，选择完整赌桌、老板桌或圆凳，即可一次铺整件。也可在“图块”页选新增的“赌场”素材来源，框选整张图后铺放。
3. 骰子、骰盅、筹码、陶杯和账本放在更高的 `Ground3` 装饰层；壁灯放 `Upper1`。小道具的透明留白包含在笔刷内，保持 48 像素格对齐。
4. 桌子画布首行按透明装饰处理，其余两行与圆凳阻挡通行。其他小道具与壁灯使用 `star` 标记，保留下层的通行规则。

选中 PNG 时，检查器显示“只读”是 Godot 导入纹理的正常行为。铺图需要选中 TileMapLayer，并使用底部笔刷；不需要解锁或修改 PNG 检查器。

接入工具为 `tools/map/add_casino_tiles.gd`，只用于首次给未接入的原图块集添加来源；检测到 ID 已占用会拒绝覆盖手工修改。笔刷与通行验证：`godot --headless --path . --script tests/verify_casino_tiles.gd`。

Godot 4.7.2 实测 5515 项检查通过，覆盖原有图块标记、完整笔刷铺放、48 像素格、家具阻挡和装饰继承底层通行。接入遵循官方 [TileSetAtlasSource](https://docs.godotengine.org/en/stable/classes/class_tilesetatlassource.html) 和 [TileMapPattern](https://docs.godotengine.org/en/stable/classes/class_tilemappattern.html) API；图案单元显式使用基础替代图块 ID `0`，避免默认 `-1` 导致笔刷擦除而不是绘制。

## 使用边界

成品 PNG 与 Godot 4.7.2 生成的 `.import` 设置一起保存。`source/`、`prompts/`、`reference/`、`previews/` 通过 `.gdignore` 隔离，避免原稿和审核图作为游戏纹理导入。

已核对 13 张成品的 RGBA、48 像素网格画布、透明边界和轮廓完整性，并在独立临时 Godot 4.7.2 项目中导入通过。

图块与完整物件笔刷已接入共享 TileSet；地图中的实际铺放由编辑者操作。清单中的底中锚点是贴图坐标参考。两张预览均为静态审核图；完成实际铺放后仍需以真实主角在关卡内检查比例、通行空间和遮挡。
