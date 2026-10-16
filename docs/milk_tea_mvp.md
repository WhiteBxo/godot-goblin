# 奶茶店 MVP

Godot 4.7.2，运行 `src/core/main.tscn`（打开主场景后 F6，或直接 F5）。背景 `assets/map/milkTea/milkTea.png` 已替换为用户于 2026-10-16 提供的 1672 × 941 PNG；角色使用用户提供的四向精灵图，均直接保存原始附件，未重新生成图片。

- WASD / 方向键：八方向移动，斜向不加速。
- 左上仓库、上方制作台、下方订单板：靠近金色标记显示「按 E 交互」，E 打开对应信息界面。
- Esc / 返回按钮：关闭界面并恢复移动。弹窗期间角色停止移动。
- 当前 UI 展示订单、库存及配方，不实现库存扣减、制作结算、剧情或 NPC 系统。

## 结构与坐标

- `src/levels/milkTea/milk_tea_shop.tscn`：背景、出生点、15 个实体碰撞形状、三个交互组件实例，可直接在编辑器中修改。`get_world_bounds()` 提供背景世界范围；四面外墙在初始化时按图片尺寸与 `boundary_insets`（左、上、右、下）同步，并封闭底部侧墙缺口。
- `src/gameplay/player/shop_player.*`：独立角色，`CharacterBody2D` 的 Floating 模式和 `move_and_slide()`。脚部横向胶囊碰撞体为 34 × 20 世界像素；显示缩放为 0.4，角色约 110 像素高，与门、柜台比例相符。四向动画说明见 [玩家素材说明](../assets/characters/player/README.md)。
- `src/gameplay/player/bounded_follow_camera.gd`：角色子节点上的跟随相机，位置平滑速度为 8，默认缩放 0.75。由主场景注入背景世界范围；限制屏幕四边，窗口变宽或变高时自动提高最小缩放，避免视野超过背景。
- `src/gameplay/interaction/interaction_point.*`：复用 `Area2D`，导出地点 ID、名称、说明；通过 `availability_changed` 和 `interacted` 信号通知协调组件。
- `src/gameplay/interaction/shop_interaction.gd`：选择最近可交互地点，处理 E，并协调角色与 UI。新增地点可实例化组件，通过 `MilkTeaShop.get_interaction_points()` 自动接入。
- `src/UI/milk_tea/shop_ui.*`：显示提示与信息弹窗，通过 `closed` 信号恢复角色。提示挂到 HudLayer，弹窗挂到 PopupLayer。
- `MainGame` 装配依赖；保留原洞穴初始化分支，正式关卡不依赖调试组件。

场景坐标以背景左上角为原点，1 世界单位 = 1 背景像素，图片 1672 × 941。640 × 360 逻辑视口默认显示约 853 × 480 的世界范围，镜头随玩家移动并在背景边缘停止。碰撞覆盖墙体、柜台、货架、箱子和设备可见区域；顶部边界留出角色头部余量，角色完整图像保持在背景内。背景仍为单张图片，不涉及 TileMap 格子或布局导入。物理层 1 = 环境、2 = 玩家，交互 Area 仅检测玩家层。

中文使用 SystemFont，优先 Microsoft YaHei / Noto Sans CJK SC；移植到没有中文系统字体的平台时需要随包提供中文字体。

## 验证

```powershell
godot --headless --path . --script res://tests/verify_milk_tea_shop.gd
godot --headless --path . --script res://tests/verify_player.gd
godot --headless --path . --script res://tests/verify_shop_camera.gd
```

验证实际输入移动、斜向速度、15 处物理碰撞、持续顶住柜台、基于实际物理空间的三个地点可达性、E 打开三个 UI、标题匹配、Esc 关闭、弹窗锁定移动和离开范围。渲染环境可追加 `-- --capture`，将场景和订单弹窗截图保存到 `.godot/milk_tea_verification/`。

相机测试覆盖跟随、平滑过程中四角限制、角色全图不越界、底部绕墙缺口、宽屏/竖屏尺寸变化，以及关卡平移后的世界坐标。渲染环境追加 `-- --capture` 可保存 `follow_camera.png`。

手动验收：F5 从地毯走向三个金色标记，检查提示、E 打开内容、Esc / 按钮关闭；持续朝货架、制作设备、柜台和四侧外墙移动，应被阻挡且可沿边滑动。走动时镜头平滑跟随，接近四边后停止，不出现图片外的空白；改变窗口比例也应保持视野在背景内。

## 关键官方文档（4.7）

- [CharacterBody2D](https://docs.godotengine.org/en/4.7/classes/class_characterbody2d.html)：俯视角使用 `MOTION_MODE_FLOATING`；在物理帧设置 velocity，再调用 `move_and_slide()`，无需再次乘 delta。
- [Camera2D](https://docs.godotengine.org/en/4.7/classes/class_camera2d.html)：通过 `limit_*` 限制屏幕边缘；使用节点位置调整构图，保持 `offset` 为零以免越过限制；设置限制与出生点后重置平滑。
- [Sprite2D.get_rect](https://docs.godotengine.org/en/4.7/classes/class_sprite2d.html#class-sprite2d-method-get-rect)：读取背景局部矩形并转换至世界坐标，供相机与边界初始化使用。
- [Input.get_vector](https://docs.godotengine.org/en/4.7/classes/class_input.html#class-input-method-get-vector)：四个 InputMap action 产生长度不超过 1 的移动向量。
- [Area2D](https://docs.godotengine.org/en/4.7/classes/class_area2d.html)：使用 body_entered / body_exited 信号，检测遵循 collision_mask；更新发生在物理步。
- [Signals](https://docs.godotengine.org/en/4.7/getting_started/step_by_step/signals.html)：组件发出信号，由共同父场景装配的协调器连接，避免交互点引用 UI 内部层级。
