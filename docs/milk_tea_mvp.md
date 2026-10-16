# 奶茶店 MVP

Godot 4.7.2，运行 `src/core/main.tscn`（F6 或 F5）。沿用现有背景 `assets/map/milkTea/milkTea.png` 和 goblin 角色；未重新生成图片。

- WASD / 方向键：八方向移动，斜向不加速。
- 左上仓库、上方制作台、下方订单板：靠近金色标记显示「按 E 交互」，E 打开对应信息界面。
- Esc / 返回按钮：关闭界面并恢复移动。弹窗期间角色停止移动。
- 当前 UI 展示订单、库存及配方，不实现库存扣减、制作结算、剧情或 NPC 系统。

## 结构与坐标

- `src/levels/milkTea/milk_tea_shop.tscn`：背景、出生点、固定全景镜头、15 个实体碰撞形状、三个交互组件实例。由 Godot MCP 创建并保存，可直接在编辑器中修改。
- `src/gameplay/player/shop_player.*`：独立角色，`CharacterBody2D` 的 Floating 模式和 `move_and_slide()`。脚部圆形碰撞体；身体在脚部上方绘制。
- `src/gameplay/interaction/interaction_point.*`：复用 `Area2D`，导出地点 ID、名称、说明；通过 `availability_changed` 和 `interacted` 信号通知协调组件。
- `src/gameplay/interaction/shop_interaction.gd`：选择最近可交互地点，处理 E，并协调角色与 UI。新增地点可实例化组件，通过 `MilkTeaShop.get_interaction_points()` 自动接入。
- `src/UI/milk_tea/shop_ui.*`：显示提示与信息弹窗，通过 `closed` 信号恢复角色。提示挂到 HudLayer，弹窗挂到 PopupLayer。
- `MainGame` 装配依赖；保留原洞穴初始化分支，正式关卡不依赖调试组件。

场景坐标以背景左上角为原点，1 世界单位 = 1 背景像素，图片 1672 × 941。镜头居中缩放到 640 × 360 的逻辑视口。碰撞覆盖墙体、柜台、货架、箱子和设备可见区域；背景仍为单张图片，不涉及 TileMap 格子或布局导入。物理层 1 = 环境、2 = 玩家，交互 Area 仅检测玩家层。

中文使用 SystemFont，优先 Microsoft YaHei / Noto Sans CJK SC；移植到没有中文系统字体的平台时需要随包提供中文字体。

## 验证

```powershell
godot --headless --path . --script res://tests/verify_milk_tea_shop.gd
```

验证实际输入移动、斜向速度、15 处物理碰撞、持续顶住柜台、基于实际物理空间的三个地点可达性、E 打开三个 UI、标题匹配、Esc 关闭、弹窗锁定移动和离开范围。渲染环境可追加 `-- --capture`，将场景和订单弹窗截图保存到 `.godot/milk_tea_verification/`。

手动验收：从地毯走向三个金色标记，检查提示、E 打开内容、Esc / 按钮关闭；持续朝货架、制作设备、柜台和外墙移动，应被阻挡且可沿边滑动。

## 关键官方文档（4.7）

- [CharacterBody2D](https://docs.godotengine.org/en/4.7/classes/class_characterbody2d.html)：俯视角使用 `MOTION_MODE_FLOATING`；在物理帧设置 velocity，再调用 `move_and_slide()`，无需再次乘 delta。
- [Input.get_vector](https://docs.godotengine.org/en/4.7/classes/class_input.html#class-input-method-get-vector)：四个 InputMap action 产生长度不超过 1 的移动向量。
- [Area2D](https://docs.godotengine.org/en/4.7/classes/class_area2d.html)：使用 body_entered / body_exited 信号，检测遵循 collision_mask；更新发生在物理步。
- [Signals](https://docs.godotengine.org/en/4.7/getting_started/step_by_step/signals.html)：组件发出信号，由共同父场景装配的协调器连接，避免交互点引用 UI 内部层级。
