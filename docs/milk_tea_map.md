# 奶茶店开放房间与遮挡渐隐

## 素材和场景

当前主场景仍是 `src/core/main.tscn`。关卡使用用户本次提供的原始地图 `assets/map/milkTea/shop_interior_rooms.png`，1376 × 768，逐字节复制，未重绘、修改家具、处理像素或调整整张背景透明度。背景 Sprite2D 不居中，位置为 (0, 0)，缩放为 (1, 1)；MilkTeaShop 保留 (1.25, 1.25) 缩放，因此世界范围是 1720 × 960。

地图内卧室和卫生间的门扇节点与门碰撞已移除，直接走开放门洞；柜台小门和店铺正门沿用原有自动门。原自动门处理过的旧底图不再被当前关卡引用。

当前项目没有 CameraDirector 类。实际镜头是 ShopPlayer 下原有的 BoundedFollowCamera；房间组件不引用、创建、切换或修改 Camera2D，也不向 StoryDirector、MainGame 或玩家发送移动锁定请求。

## Godot 节点配置

在 `src/levels/milkTea/milk_tea_shop.tscn` 中：

```text
MilkTeaShop (Node2D, scale 1.25)
├─ Background (Sprite2D, 原始地图, centered=false)
├─ Spawn (Marker2D, 1048, 553)
├─ WallsAndFurniture (StaticBody2D, layer 1 / mask 2)
│  └─ 各墙体及家具的 CollisionShape2D
├─ Doors (保留柜台和正门)
├─ Rooms (Node2D)
│  ├─ Bedroom (RoomReveal / Area2D 实例)
│  │  ├─ Interior (CollisionPolygon2D)
│  │  └─ Occlusion (Node2D, z_index=20)
│  │     └─ PlaceholderRoof (Polygon2D)
│  └─ Bathroom (相同的 RoomReveal 场景实例)
└─ InteractionPoints (原有订单、仓储、制作交互)
```

| 节点 | 配置与职责 |
| --- | --- |
| Bedroom / Bathroom | 实例化 `src/gameplay/rooms/room_reveal.tscn`；脚本为 `room_reveal.gd`，类型 Area2D。Collision Layer 全关（0），Mask 仅第 2 层（数值 2），Monitoring 开启，Monitorable 关闭。`observer_group = player`，`fade_duration = 0.25`。 |
| Interior | CollisionPolygon2D，Build Mode 为 Solids；绘制室内与门槛感应范围，不产生实体阻挡。实例启用 Editable Children 后编辑 polygon。 |
| Occlusion | Node2D，仅该节点的 `modulate.a` 被 Tween 控制。`z_index = 20`，高于玩家的 10，沿用世界坐标，不放入 CanvasLayer。 |
| PlaceholderRoof | 独立 Polygon2D，深灰褐色、不透明；仅覆盖各自室内。当前为验证机制的占位美术。 |
| Background | 始终保持 `modulate.a = 1`，不被房间组件引用或改动。 |
| WallsAndFurniture | 实体阻挡沿用玩家的 layer 2 / mask 1。卧室下墙、中间浅色墙、卫生间上墙和浅色侧墙保持碰撞；门洞没有阻挡体。 |
| Player / Camera2D | 原有 ShopPlayer、脚部 CapsuleShape2D 和 BoundedFollowCamera，房间系统不调整输入、位置、速度、镜头限制或缩放。 |

所有下述坐标都是地图原始像素坐标，已经保存在关卡场景内，不在运行时覆盖。

| 房间 | Interior 多边形顶点 | PlaceholderRoof 顶点 |
| --- | --- | --- |
| 卧室 | (150,103), (394,103), (394,480), (334,480), (334,411), (150,411) | (151,104), (394,104), (394,411), (151,411) |
| 卫生间 | (150,448), (299,448), (299,612), (334,612), (334,664), (150,664) | (151,450), (298,450), (298,664), (151,664) |

卧室入口在下侧偏右，通行测试沿 x=362 从 y=510 走至 y=385。卫生间按本次图中浅色侧墙的下方留洞，沿 y=634 从 x=370 走至 x=272；不从浅色墙板中穿过。卫生间侧墙碰撞为 Rect2(299,499,35,113)，门洞为 x=299…334、y=612…664。营业区与走廊经 y=500…560 的现有缺口连通，制作区左侧浅色墙体有实体碰撞。

## 机制与边界

- 正常进出由 Area2D 的 body_entered / body_exited 驱动。延后至当前物理信号批次完成后读取全部重叠对象，仅接受 player 分组。
- Tween 仅改变当前房间 Occlusion 的 modulate.a，进入为 0，离开为 1；使用 0.25 秒 Sine / EaseInOut 补间。
- 快速折返先 kill 上一个 Tween，然后从实际当前 alpha 继续；不会重置到 0 或 1，也不会积累旧补间。
- 初始遮挡从透明开始，等 MainGame 设置出生点及物理同步后直接解析最终状态。新实例的凹多边形重叠缓存可能稍晚发布，因此仅初始化时用同一 Interior 多边形及玩家脚点做几何补充判断，避免室内出生闪出屋顶。后续仍完全由 Area2D 处理。
- 多名 player 观察者中任意一人仍在室内时保持显露；非 player 物体无效，最后一个观察者被释放后恢复遮挡。
- 节点退出场景树时取消 Tween。组件随 World 使用 Pausable 生命周期，沿用 Godot 节点绑定 Tween 的暂停和释放行为。
- `occupancy_changed(occupied)` 提供公开通知；`is_occupied()`、`get_occlusion_alpha()` 便于调试，不依赖具体玩家节点层级。

## 复用与正式美术

新增房间时，把 room_reveal.tscn 实例放在当前关卡 Rooms 下，保持 Interior / Occlusion 名称；打开 Editable Children，分别绘制 Interior 的感应多边形与 PlaceholderRoof 的覆盖范围。配置观察分组和淡出时间即可，不需要注册管理器或增加相机。

本图只有完整室内背景，没有独立屋顶贴图，无法从原图直接得到正式屋顶。因此本次交付的是可运行的占位遮挡机制。正式美术需补充卧室、卫生间各一张带透明背景的屋顶/顶部遮挡 PNG，室内家具和地板不能烘焙进遮挡图，门洞与保留墙边应留透明。推荐两图都采用 1376 × 768 画布，位置与原始地图对齐。

接入时隐藏 PlaceholderRoof，在同一个 Occlusion 下添加 Sprite2D，centered=false、position=(0,0)、scale=(1,1)，赋予对应 PNG。也可使用裁剪尺寸图片，但须设置正确地图坐标偏移。不要把 Background 移入 Occlusion，也不要添加独立 Camera2D。

## 验证与试玩

开发顺序：先只配置卧室，运行 `verify_room_reveal.gd -- --bedroom-only` 并检查卧室进出截图；确认后再配置同组件的卫生间。

在项目根目录执行（将 Godot 替换为本地 Godot 4.7.2 console 可执行文件）：

```powershell
Godot --headless --path . --script tests/verify_room_reveal.gd
Godot --headless --path . --script tests/verify_milk_tea_shop.gd
Godot --headless --path . --script tests/verify_shop_camera.gd
Godot --headless --path . --script tests/verify_shop_doors.gd
Godot --headless --path . --script tests/verify_story_director.gd
```

房间测试通过真实 InputMap 移动检查两个门洞、持续跟随镜头、场景身份与移动权限，另外覆盖墙体阻挡、0.25 秒时长、渐变中间值、室内出生、快速往返、补间中断、两房独立、多观察者、非玩家和释放中的生命周期。测试中的瞬时位置设置只用于边界条件准备，正式房间组件从不移动玩家。

F6 独立运行关卡仅查看地图和占位遮挡；正式试玩请 F5 运行 main.tscn。先由营业区向左穿过中间墙下方缺口进入走廊，再向上走进卧室，观察深色占位屋顶在 0.25 秒内消失；退出后恢复。再从走廊下方绕过卫生间浅色侧墙底端，向左走进卫生间，观察相同渐隐效果。全程无需 E、没有黑屏或场景切换。最后尝试沿墙推动，确认只能从门洞通行。

## Godot 4.7 官方文档

- [Area2D](https://docs.godotengine.org/en/4.7/classes/class_area2d.html)：重叠列表随物理步更新，初始化不能仅依赖 ready 时的列表。
- [Tween](https://docs.godotengine.org/en/4.7/classes/class_tween.html)：Node.create_tween 绑定生命周期，kill 后从当前属性值创建新补间。
- [CanvasItem](https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html)：modulate 影响子节点，使用单独 Occlusion 限定影响范围。
- [CollisionPolygon2D](https://docs.godotengine.org/en/4.7/classes/class_collisionpolygon2d.html)：使用保存的多边形定义每个 Area 的覆盖形状。
- [Geometry2D](https://docs.godotengine.org/en/4.7/classes/class_geometry2d.html#class-geometry2d-method-is-point-in-polygon)：初始化时按相同室内多边形判定脚点。
