# 奶茶店宿主与试玩

核对日期：2026-10-18。F5 进入标题菜单并选择“新游戏”，或打开 src/core/main.tscn 后 F6，启动正式 Day 1 前两阶段。原三单教学使用 src/debug/story/legacy_shop.tscn。当前店内地图为 assets/map/milkTea/shop_interior_rooms.png，1376×768，MilkTeaShop 等比 1.25，世界范围 1720×960；旧 milkTea.png 保留为历史素材。

## 玩家流程

- WASD / 方向键移动，Shift 奔跑、Ctrl 潜行 / 蹲伏；靠近设施显示角框和底部 E 提示，不再常驻金色菱形与标签。
- 订单板逐笔接取；制作台默认按单制作，配方自动填入。切“自由调配 → 教学配方”可手动选料、配方重做与批量；内层“自由调配”提供三槽动态杯与独立加冰。
- 制作只入共享库存，关闭界面后到指定顾客按 E 交付；成功为非模态短反馈，钱 / 物品 / 回执同次提交。
- Esc 关闭顶层弹窗或在空闲时暂停，P 暂停；返回标题再新游戏重置整局，普通重载和店门进出保留经营配置与进度。
- 五单后停在金币调查边界并开放出店；正式 S03–S06 尚未发布。流程见[前两阶段](../gameplay/day_01_stages_01_02.md)，业务见[订单](../gameplay/order_system.md)、[制作](../gameplay/basic_tea_production.md)和[自由配方](../gameplay/free_tea_recipes.md)。

## 结构与坐标

| 组件 | 当前职责 |
| --- | --- |
| src/levels/milkTea/milk_tea_shop.tscn | 背景、Spawn、墙体 / 家具碰撞、开放房间与前景、三个设施点、StoryPositions 和命名出入口 |
| MilkTeaShop | 提供世界 / 相机边界、出生点、交互 / 剧情位置和导航接口；configure_depth_sort 统一角色与家具排序 |
| src/gameplay/player/shop_player.tscn | CharacterBody2D，Floating 模式；脚底横向胶囊 34×20；速度 240 世界像素 / 秒 |
| 玩家画面 | player_actions_pixel_frames.tres，24 组四向动作、274 帧；原始像素直接 2 倍生成，Visual 无额外缩放，可见站立约 118 世界像素 |
| BoundedFollowCamera | 唯一跟随相机，默认 zoom=0.5，位置平滑速度 8，top_level；按地图边界限制中心并处理尾差与宽高变化 |
| ShopInteraction / InteractionFeedback | 最近目标分发、实际高亮 / 提示；Story 路由、导航、调查、采集或交付按宿主协调 |
| ShopUI / UIManager | HUD、弹窗、焦点和覆盖；移动 / 交互锁最终由 MainGame 合并，不在关窗时无条件恢复 |
| MainGame / GameState | 宿主组装本地服务；唯一会话保存库存、制作、钱包与剧情，普通场景重建不重置 |

地图本地原点为背景左上角，1 本地单位为原始图片 1 像素，再经过关卡 1.25 等比变换。camera_insets 为本地左 / 上 / 右 / 下 (112, 54, 112, 10)，默认地图变换下相机范围为 Rect2(140, 67.5, 1440, 880)。出生点、门洞与屋顶详细配置见[开放房间与遮挡](milk_tea_map.md)。

世界 / 家具为物理层 1、玩家为层 2、NPC 为层 3；玩家 mask=5，NPC 只检测世界。隐藏 NPC 退出实体层；可见 NPC 脚底阻挡玩家。角色与家具按保存基线分配 Z 区间，同区间角色用 Y 排序；屋顶在其上。中文使用随包 Fusion Pixel 主题字体，不依赖系统 CJK 字体。

店门 shop_exit 连接聚落 shop_door，返店落 street_door；具体坐标、准入和状态交接见[店铺与聚落进出](../systems/scene_travel.md)。地图组件本身不承担订单、库存或剧情顺序。

## 检查与试玩

按改动范围选候选入口，本轮文档静态更新没有运行引擎：

```sh
godot --headless --path . --script res://tests/verify_milk_tea_shop.gd
godot --headless --path . --script res://tests/verify_shop_camera.gd
godot --headless --path . --script res://tests/verify_shop_equipment.gd
godot --headless --path . --script res://tests/verify_room_reveal.gd
godot --path . --script res://tests/verify_player_visuals.gd
```

手动检查用 F5 新游戏，推进开场后到订单板、制作台和仓库观察 E 提示、按单制作及 Esc 锁恢复。向四周墙体与家具持续移动应被阻挡并可沿边滑动；镜头到边缘停止，改变窗口比例仍不露出背景外。穿卧室 / 卫生间门洞观察屋顶 0.25 秒渐隐、退出恢复，以及角色与柜台、设备、门框的前后关系。F6 裸地图只能检查场景资源，完整玩家交互使用宿主。

玩家渲染检查需要图形环境，当前覆盖 274 帧；旧记录中的 68 帧属于前代素材。测试脚本存在不代表当前工作区通过，历史失败与适用限制见[现状记录](../development/development_status_2026_10_18.md#验证记录与限制)。

## 官方接口参考

- [CharacterBody2D](https://docs.godotengine.org/en/4.7/classes/class_characterbody2d.html)：俯视角 Floating 与物理移动。
- [Camera2D](https://docs.godotengine.org/en/4.7/classes/class_camera2d.html)：限制、平滑和缩放。
- [Area2D](https://docs.godotengine.org/en/4.7/classes/class_area2d.html)：交互与房间重叠检测。
- [CanvasItem](https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html)：Z / Y 排序与局部调制。

本轮仅修订说明，接口行为以项目实现为准，未新增 API 或引擎配置变更。
