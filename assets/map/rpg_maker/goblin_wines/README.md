# 哥布林酒品地图图块

来源：用户提供的 `D:/taptapgamejam/策划/哥布林酒品` 五张 PNG；沿用项目内使用范围，未新增第三方授权声明。

图集从左到右：劣质酸苔麦酒、纯正哥布林老火烧、暴徒熔岩老火烧、格里芬琥珀酒、格里芬圣血祭酒。
原图为 32×32，逐像素保留，居中放入 48×48 透明格，无缩放。

在 RPG 地图的 `Upper0..3` 图层选择名为“哥布林酒品（五种）”的图集（source 200），即可单格绘制。三套现有 TileSet 均已接入。图块为 star 装饰，不改变底层通行，也不自动提供拾取交互。

重新生成（需要 Pillow）：

```powershell
python tools/map/build_goblin_wine_tiles.py 'D:/taptapgamejam/策划/哥布林酒品' assets/map/rpg_maker/goblin_wines/wine_tiles.png
```

独立图块库：`src/resources/tilesets/goblin_wines.tres`，可供新的 48px TileMapLayer 使用。
