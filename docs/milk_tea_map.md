# 奶茶店地图与自动门

## 素材与坐标

- 原图：用户提供的奶茶店参考图，保存在 `assets/map/milkTea/shop_interior_reference.png`（1376 × 768）。
- 游戏底图：`assets/map/milkTea/shop_interior_open.png`。使用内置 imagegen 编辑原图，清理卧室门扇、柜台门扇、入口门扇和左下卫生间门扇；保留墙体、门框及家具。没有采用删除中间浅色墙体的中间结果。
- 派生图由 Sprite2D 缩放回原图坐标空间，关卡统一放大 1.25 倍。碰撞、出生点和交互点均保存在场景中，不在运行时生成或覆盖。
- 这是整张背景图地图，并非 TileSet；可直接在关卡场景编辑家具碰撞、门实例和 Marker2D。
- 门扇由 `AutomaticDoor` 绘制，横门使用立面投影，卫生间侧门使用竖向投影。门宽、颜色、方向、开门角度、动画时长和关闭延迟均可在 Inspector 调整。

## 图像处理提示词

内置 imagegen，首轮以原图为编辑目标：

> Use case: precise-object-edit. Edit target: attached pixel art bubble tea shop floor plan, 1376 by 768. Create a clean background plate for a Godot game. Preserve EXACT framing, room layout, walls, furnishings, colors, pixel style and every coordinate. ONLY remove the brown swung open bedroom door leaf at x324..393 y340..469, reconstruct the wooden floor behind it leaving an open doorway between bedroom and corridor. ONLY remove the small wooden counter gate at x658..730 y422..487 leaving wooden floor behind it. ONLY remove the front entrance door leaf/glass at x1086..1162 y610..707 leaving floor and threshold visible; preserve door frame and mats. All three doors will be animated by game code. Do not alter any other part of image. Do not add text, do not move walls or objects. Output same aspect ratio.

最终一轮以首轮输出为编辑目标，只清理卫生间侧门：

> Precise localized edit to attached 1678x937 pixel game map. Preserve ALL walls, especially the TWO TALL CREAM WALL PANELS WITH BROWN BORDERS in the CENTER LEFT at x485..570,y428..554. Those are WALLS and MUST remain completely unchanged. Only change the narrow bathroom door leaf at x367..396,y640..738 (beside bathroom sink at far left lower room): replace that cream narrow rectangle with an open bathroom doorway showing matching floor. Keep both end jambs and every surrounding wall unchanged. No other edits anywhere. Keep image composition coordinates aspect ratio and furniture identical. Prior existing bedroom and counter openings must stay unchanged.

## 行为与验收

运行 `src/core/main.tscn`，使用 WASD 或方向键移动：

1. 靠近卧室门、卫生间侧门、柜台小门或店铺入口，门自动打开，无需 E。
2. 从门两侧经过均可通行；在门洞内停留，门不会关闭。
3. 离开感应区约 0.65 秒后关门；关闭途中折返会重新打开。
4. 中间浅色墙、外墙及家具保持阻挡；入口门外只允许走到门垫边缘，不切换关卡。
5. 订单、储藏和制作交互点仍使用 E，菜单打开期间暂停玩家移动。

相关自动验证：`tests/verify_shop_doors.gd`、`tests/verify_milk_tea_shop.gd`、`tests/verify_shop_camera.gd`。

## Godot 4.7 官方 API

- [Area2D](https://docs.godotengine.org/en/4.7/classes/class_area2d.html)：通过 body_entered / body_exited 和玩家碰撞层检测接近与离开，关闭前再次检查重叠对象。
- [CollisionShape2D](https://docs.godotengine.org/en/4.7/classes/class_collisionshape2d.html)：disabled 使用 set_deferred 修改，避免在物理查询刷新期间改变碰撞状态。
- [Tween](https://docs.godotengine.org/en/4.7/classes/class_tween.html)：由节点创建补间；反向操作先 kill 旧补间，从当前开合程度继续。
