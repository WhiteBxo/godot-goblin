# 格里芬鹰徽 RPG Maker 图块

来源：用户在 2026 年 10 月 20 日提供的鹰徽地图素材拼版图 `source/reference.png`。原图保留为派生依据，未覆盖或修改用户原图。

本目录输出按 RPG Maker 风格整理的 48×48 像素地图素材：

| 文件 | 画布尺寸 | 用途 |
| --- | ---: | --- |
| `sprites/stone_floor_atlas.png` | 384 × 48 | 8 种可重复铺设的石砖地面变体 |
| `sprites/eagle_crest_floor.png` | 48 × 48 | 鹰徽石砖单格 |
| `sprites/lantern.png` | 48 × 144 | 1 × 3 格壁灯 |
| `sprites/round_medallion.png` | 96 × 96 | 2 × 2 格圆形鹰徽 |
| `sprites/shield_sign.png` | 96 × 96 | 2 × 2 格鹰盾牌 |
| `sprites/eagle_pillar.png` | 48 × 144 | 1 × 3 格鹰柱 |
| `sprites/grand_eagle_monument.png` | 144 × 144 | 3 × 3 格中央鹰像 |

所有装饰 PNG 使用真实 alpha 透明背景；地面图块为不透明 RGBA 图块。多格装饰已居中放入整数 48px 网格画布，可直接作为 RPG Maker 物件图块或 Godot TileMap 图案的输入。

## 处理与复现

处理脚本为 [`tools/map/build_eagle_crest_tiles.py`](../../../../tools/map/build_eagle_crest_tiles.py)，使用 Pillow 从保存的源图裁切、去除黑色底版、等比例缩放到网格画布，并输出 `manifest.json` 与 `previews/catalog.png`：

```powershell
python tools/map/build_eagle_crest_tiles.py `
  assets/map/rpg_maker/eagle_crest/source/reference.png `
  assets/map/rpg_maker/eagle_crest
```

`manifest.json` 记录源图尺寸、裁切坐标、最终网格占位和输出尺寸。`source/` 与 `previews/` 通过 `.gdignore` 隔离，不会作为运行时纹理被 Godot 自动导入。

本次只生成素材，没有接入现有共享 TileSet，也没有改变任何地图场景的通行或遮挡规则。实际铺放时，地面放在底层，鹰徽和装饰物放在上层装饰层，并在游戏内用主角比例复核遮挡与通行。
