# 奶茶店 MVP

Godot 4.7.2，运行 `src/core/main.tscn`（打开主场景后 F6，或直接 F5）。背景 `assets/map/milkTea/milkTea.png` 为用户于 2026-10-16 提供的 1672 × 941 PNG；角色以用户原图为参考，使用内置 imagegen 修整四向八帧步态并补充独立中立站姿。

- WASD / 方向键：八方向移动，斜向不加速。
- 左上仓库、上方制作台、下方订单板：靠近金色标记显示「按 E 交互」，E 打开对应信息界面。
- Esc / 返回按钮：关闭界面并恢复移动。弹窗期间角色停止移动。
- 制作台已接入初级制作：选择茶底、奶精、小料，按订单制作并自动交付，成功后扣减库存并展示下一笔订单。仓库、订单板与制作台共享本次营业数据。详见 [基础制作说明](basic_tea_production.md)。

## 结构与坐标

- `src/levels/milkTea/milk_tea_shop.tscn`：背景、出生点、15 个实体碰撞形状、三个交互组件实例，可直接在编辑器中修改。`get_world_bounds()` 提供背景世界范围；四面外墙在初始化时按图片尺寸与 `boundary_insets`（左、上、右、下）同步，并封闭底部侧墙缺口。
- `src/gameplay/player/shop_player.*`：独立角色，`CharacterBody2D` 的 Floating 模式和 `move_and_slide()`。脚部横向胶囊碰撞体为 34 × 20 世界像素；新素材显示缩放为 0.52，角色约 110 像素高。动画按速度调整节奏并保留转向时的步态进度；nearest 与 alpha cutout 保持轮廓清晰。四向动画说明见 [玩家素材说明](../assets/characters/player/README.md)。
- `src/gameplay/player/bounded_follow_camera.gd`：角色子节点上的跟随相机，位置平滑速度为 8，默认缩放 0.5。相机保留为玩家子节点，但启用 top_level 隔离父节点碰撞位移；在玩家移动后的物理帧先将目标限制到合法取景中心范围，再交给 Camera2D 平滑，并在误差小于 0.01 世界像素时结束平滑尾差，避免底边持续按 S 时出现像素抖动。主场景注入 `get_camera_bounds()`；`camera_insets` 按左、上、右、下排除图片外圈装饰黑框，不修改背景像素和家具坐标。窗口变宽或变高时自动提高最小缩放，避免视野越界。
- `src/gameplay/interaction/interaction_point.*`：复用 `Area2D`，导出地点 ID、名称、说明；通过 `availability_changed` 和 `interacted` 信号通知协调组件。
- `src/gameplay/interaction/shop_interaction.gd`：选择最近可交互地点，处理 E，并协调角色与 UI。新增地点可实例化组件，通过 `MilkTeaShop.get_interaction_points()` 自动接入。
- `src/UI/milk_tea/shop_ui.*`：显示提示与信息弹窗，通过 `closed` 信号恢复角色。提示挂到 HudLayer，弹窗挂到 PopupLayer。
- `MainGame` 装配依赖；保留原洞穴初始化分支，正式关卡不依赖调试组件。

场景坐标以背景左上角为原点，1 世界单位 = 1 背景像素，图片 1672 × 941。640 × 360 逻辑视口默认显示 1280 × 720 的世界范围，比旧缩放多显示 50% 的宽度；安全取景区域为 Rect2(100, 80, 1480, 861)，保留少量跟随空间且不会显示外圈黑框。碰撞覆盖墙体、柜台、货架、箱子和设备可见区域；外墙余量同步调整，避免角色在安全取景边缘被裁切。背景仍为单张图片，不涉及 TileMap 格子或布局导入。物理层 1 = 环境、2 = 玩家，交互 Area 仅检测玩家层。

中文使用 SystemFont，优先 Microsoft YaHei / Noto Sans CJK SC；移植到没有中文系统字体的平台时需要随包提供中文字体。

## 验证

```powershell
godot --headless --path . --script res://tests/verify_milk_tea_shop.gd
godot --headless --path . --script res://tests/verify_player.gd
godot --headless --path . --script res://tests/verify_shop_camera.gd
godot --path . --script res://tests/verify_player_visuals.gd
```

验证实际输入移动、斜向速度、15 处物理碰撞、持续顶住柜台、基于实际物理空间的三个地点可达性、E 打开三个 UI、标题匹配、Esc 关闭、弹窗锁定移动和离开范围。渲染环境可追加 `-- --capture`，将场景和订单弹窗截图保存到 `.godot/milk_tea_verification/`。

相机测试覆盖较宽取景、外圈黑框隔离、平滑过程中四角限制、角色全图不越界、底部绕墙缺口、宽屏/竖屏尺寸变化，以及关卡平移后的世界坐标。底边回归覆盖中部和两角持续按 S，逐渲染帧确认相机中心与画布变换完全固定，并验证离开底边后恢复跟随。渲染环境追加 `-- --capture` 可保存 `follow_camera.png`。玩家测试还验证加速时的动画节奏、转向进度；渲染测试逐帧检查 68 个新素材姿势的硬透明度、跑步起伏和切帧隔离。

手动验收：F5 从地毯走向三个金色标记，检查提示、E 打开内容、Esc / 按钮关闭；持续朝货架、制作设备、柜台和四侧外墙移动，应被阻挡且可沿边滑动。走动时镜头平滑跟随，接近四边后停止，不出现图片外的空白；改变窗口比例也应保持视野在背景内。

## 关键官方文档（4.7）

- [CharacterBody2D](https://docs.godotengine.org/en/4.7/classes/class_characterbody2d.html)：俯视角使用 `MOTION_MODE_FLOATING`；在物理帧设置 velocity，再调用 `move_and_slide()`，无需再次乘 delta。
- [Camera2D](https://docs.godotengine.org/en/4.7/classes/class_camera2d.html)：通过 `limit_*` 限制屏幕边缘；使用节点位置调整构图，保持 `offset` 为零以免越过限制；设置限制与出生点后重置平滑。
- [AtlasTexture](https://docs.godotengine.org/en/4.7/classes/class_atlastexture.html)：用 region 与 margin 把不同裁切区域放在同一逻辑画布，固定躯干和脚底锚点。
- [2D sprite animation](https://docs.godotengine.org/en/4.7/tutorials/2d/2d_sprite_animation.html)：SpriteFrames 顺序组织不同姿势；[CanvasItem shader](https://docs.godotengine.org/en/4.7/tutorials/shaders/shader_reference/canvas_item_shader.html) 提供 fragment 的 COLOR alpha，供轮廓阈值处理。
- [Sprite2D.get_rect](https://docs.godotengine.org/en/4.7/classes/class_sprite2d.html#class-sprite2d-method-get-rect)：读取背景局部矩形并转换至世界坐标，供相机与边界初始化使用。
- [Input.get_vector](https://docs.godotengine.org/en/4.7/classes/class_input.html#class-input-method-get-vector)：四个 InputMap action 产生长度不超过 1 的移动向量。
- [Area2D](https://docs.godotengine.org/en/4.7/classes/class_area2d.html)：使用 body_entered / body_exited 信号，检测遵循 collision_mask；更新发生在物理步。
- [Signals](https://docs.godotengine.org/en/4.7/getting_started/step_by_step/signals.html)：组件发出信号，由共同父场景装配的协调器连接，避免交互点引用 UI 内部层级。
