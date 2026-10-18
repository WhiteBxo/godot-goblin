# RPG Maker 原生尺寸图块图集

由 [离线转换工具](../../../tools/map/prepare_rpg_maker_maps.py) 从 [完整源素材快照](../../rpg_maker/source/README.md) 生成。每格为原生 48×48；自动图块由原始 24×24 四分块拼合，没有缩放或重新绘画。

- `tileset_028_*`：酒馆与赌场。
- `tileset_030_*`：哥布林洞窟。
- `tileset_031_*`：长老居所。
- `shadow_tiles.png`：MZ 的 16 种四分格半透明阴影。
- `catalog.json`：离线转换中间数据，包含完整可用调色板、原始四层格子、阴影、桌沿、区域与出生点。运行时不读取，导出排除。

三个图块组的有效原生图块都纳入调色板，包括当前地图未使用的图块。动画帧横向排列，由外部 Godot TileSet 以每秒 2 帧播放；水面保留 0/1/2/1 周期，瀑布保留三帧周期。桌沿派生图块 ID 为原 ID + 10000。

继续编辑使用 [Godot 场景与外部 TileSet](../../../docs/levels/rpg_maker/README.md)。完整图片、音频、字体、特效和原包文档在源快照中，未经 Godot 支持的 Effekseer 等格式保留原件，不宣称已实现对应播放系统。
