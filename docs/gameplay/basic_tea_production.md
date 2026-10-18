# 初级奶茶制作

F5 进入标题菜单，选择“新游戏”进入 [Day 1 正式流程](day_01_stages_01_02.md)；F6 可单独运行店铺 `src/core/main.tscn` 或聚落 `src/core/settlement.tscn`。原三单教学验收使用 `src/debug/story/legacy_shop.tscn`。走到奶茶制作台按 E 打开制作界面；操作弹窗时停止移动，Esc 或返回按钮关闭后恢复移动。新游戏重置整局，普通场景重载不重置，详见 [启动与新游戏](../guides/game_entry.md)。

## 制作界面

制作台默认“按订单制作”：左侧选择已接饮品订单，右侧显示需求、缺口和“制作 1 杯并入库”。配方自动带入，已有足够成品则提示直接交付，材料委托不进入列表。详见[订单系统](order_system.md)。

切到外层“自由调配”后，有两个内层页签：

| 内层页签 | 操作与产物 |
| --- | --- |
| 教学配方 | 固定配方手动选料、配方填料、成品重做、整数杯数与“最大”；按整份扣料并产出既有 product_id |
| 自由调配 | 基底 + 最多两槽辅料，辅料可重复；独立加冰；UI 每次制作一杯，按使用次数扣料并生成配方杯与图鉴 |

新自由配方候选仅限已发现且允许普通配方的原料；初始六种教学食材不因此变成自由配方基底。新表原料默认 0 份、未发现，不会为了试玩自动补给。规则、命名、图鉴、订单与价格见[自由调配](free_tea_recipes.md)。

教学配方页左栏显示原料和固定成品，右栏显示可用配方、选料和数量。点配方完整替换材料并重置杯数为 1；“最大”同时受原料与成品安全计数上限约束。缺料仍可查看原因，制作成功清空托盘。上下键 / Enter 选择、Tab 访问控件，Esc 关闭；按实际库存刷新预览。

## 固定配方试玩

1. F5 新游戏，推进开场后到订单板逐单接取，再到制作台默认页面制作；糖浆由固定配方自动带入。
2. 关闭界面，携带成品到指定顾客按 E；成功后显示非模态短反馈，交付才完成任务并结算。
3. 验证手动选料 / 批量时进入“自由调配 → 教学配方”：红茶、奶精、珍珠、糖浆匹配珍珠奶茶；茉莉绿茶、奶精、椰果、糖浆匹配椰果茉莉奶茶；无小料配方为红茶、奶精、糖浆。
4. 查看缺料、错误组合、未解锁或成品计数溢出的拒绝提示，确认失败不扣库存。仓库实时反映同一会话。
5. 普通重载与店门往返保持库存；新游戏整体重置。原三单队列 API 可在 legacy_shop 及组件测试验证，正式 UI 不显示“下一单 #002”队列行，也不靠该下标判断真实订单完成。

## 当前规则与边界

- 配方表保存在 `src/resources/milk_tea/recipe_book.tres`，`basic_menu.tres` 与 `day1_menu.tres` 共用同一份；订单只保存 `product_id`，运行时由配方表补回材料，避免两套菜单各存一份配方漂移。
- 配方按材料多重集匹配，与点选顺序无关，允许同种材料出现多次；命中即产出对应成品。
- 每杯按照配方中的出现次数消耗原料，批量需求为单杯份数乘以杯数；点击配方会包含糖浆，手动混料时仍需自行选择糖浆；本阶段不提供温度、糖度和用量调节。
- 批量制作通过一次 `try_exchange` 整体扣料并入库。兼容队列仍只推进连续且已接取的同品种订单；正式订单通过实际库存和交付回执判断，与该队列顺序无关。
- 原料不符、库存不足、成品达到数量上限、制作重入时均不扣库存、不推进订单。
- `WarehouseInventory` 和 `TeaProduction` 由既有 GameState Autoload 持有，MainGame 只绑定服务；UI 仅展示数据并发出单杯材料列表与整数杯数，合成判定与提交全部在服务层完成。切换、重进或重载场景均保留库存、成品与队列；只有显式新游戏重置整个会话。完整快照与生命周期见 [统一经营会话](business_session.md)，没有文件存档、正式补货 UI 或 AI 配方；本节的原三单教学只发物品奖励，正式 Day 1 的收入与剧情解锁见前述独立说明。
- `TaskDelivery` 复用任务状态、库存和物品奖励；订单板接取首单，制作不自动完成。`tests/verify_task_delivery.gd` 覆盖交付拒绝、一致性和重复奖励保护。
- GameState 业务事实为任务各自的完成 flag、`delivery.<order_id>.completed` 回执与 `shop.orders_completed` 最高进度。正式 Day 1 使用独立订单和接取 flag，库存及回执沿用既有整局快照。见 [Gameplay Bridge](../systems/gameplay_bridge.md)。
- 仓库和订单板沿用现有交互入口；已配置的剧情交互仍优先由 StoryDirector 路由。

## 配方选择与批量提交实现

`TeaProduction.preview_craft(materials, quantity = 1)` 以单杯材料匹配配方，再计算整批缺料和成品容量；`get_max_craftable(materials)` 返回每种原料可供杯数与成品剩余容量的最小值。`craft(materials, quantity = 1)` 是唯一提交入口，校验杯数范围、配方解锁与库存后，先准备订单进度，再一次交换整批材料和成品；同步通知期间保留重入锁，交换失败恢复订单进度。原有单杯调用无需修改。

请求依次经过 CraftingPanel → ShopPopup → ShopUI → MainGame，由宿主调用共享制作服务；界面不直接扣料。右侧列表来自 `get_available_recipes()`，用物品 ID 保存选择；配方需求、解锁条件和成品名称继续读取现有资源。数量控件即时提交编辑，库存变化会重新计算上限、刷新配方可做杯数与预览。制作成功清空托盘，结果显示实际入库杯数；成品交付和剧情事实仍由原有任务流程处理。

成熟案例参考：[Minecraft 官方制作指南](https://www.minecraft.net/en-us/article/how-craft) 使用配方书，选择配方后自动排列所需材料；本项目沿用选配方填料、缺料仍可查看的方式。[Factorio 官方 Wiki 的手工制作](https://wiki.factorio.com/Crafting) 在界面右侧选择配方，支持单个、五个和尽可能多地制作，缺少的资源会有提示。本项目采用显式杯数输入和「最大」按钮，让鼠标与键盘都能发现批量操作；保留确认步骤，点击配方只填料。批量使用即时原子提交，与当前制作规则一致，没有引入持续计时队列。

## 验证

- `Godot --headless --path . --script tests/verify_tea_recipes.gd`：两套菜单配方校验、预览四种结果、自由合成与订单推进、未命中/缺料的原子性、重入与成品容量回滚、`make_drink` 订单入口，批量杯数合法性、整批缺料和容量拒绝、一次通知与重入、连续已接订单计数，以及配方填料、最大数量、补货刷新和两档分辨率适配。
- `Godot --headless --path . --script tests/verify_warehouse_inventory.gd`：库存与发现、非法输入、原子扣料、JSON 往返、隐藏属性、实时 UI 刷新、正式聚落与独立店铺的共享会话。
- `Godot --headless --path . --script tests/verify_tea_production.gd`：实际 UI 面板、配方校验、库存扣减、重开进度、无小料订单、结束保护、缺货原子性、制作不会写入交付事实、重复通知去重，以及队列结束后的自由合成。
- `Godot --headless --path . --script tests/verify_milk_tea_shop.gd`：原有移动、障碍、三个交互入口与移动锁回归。
- 非 headless 运行 `verify_tea_recipes.gd` 并附加 `-- --capture`，批量界面截图保存到 `.godot/tea_batch_640.png` 与 `.godot/tea_batch_1280.png`。
- 非 headless 运行制作验证并附加 `-- --capture`，截图保存到 `.godot/tea_production.png` 与 `.godot/tea_production_complete.png`，不纳入提交。

## Godot 4.7 官方 API 依据

- [SpinBox](https://docs.godotengine.org/en/4.7/classes/class_spinbox.html)：整数 `step`、最小/最大值和 `update_on_text_changed` 用于即时更新杯数；配方切换使用继承自 Range 的 `set_value_no_signal()` 避免重复刷新。

- [ItemList](https://docs.godotengine.org/en/4.7/classes/class_itemlist.html)：原料与成品共用一个列表，`add_item(text, icon, selectable)` 生成不可选段头，`set_item_metadata()` 存物品 ID 与类型，`item_clicked`/`item_activated` 区分鼠标与键盘激活，`set_item_disabled()` 标记缺货。
- [GridContainer](https://docs.godotengine.org/en/4.7/classes/class_gridcontainer.html)、[ScrollContainer](https://docs.godotengine.org/en/4.7/classes/class_scrollcontainer.html)：已选材料按两列排布，材料过多时只滚动不撑破弹窗。
- [Control](https://docs.godotengine.org/en/4.7/classes/class_control.html)：`custom_minimum_size` 与 `size_flags_*` 控制左右分栏，`grab_focus()` 让列表获得键盘焦点。
- [Theme](https://docs.godotengine.org/en/4.7/classes/class_theme.html)：`add_theme_constant_override()` 只在制作台模式收窄边距与标题，不修改共享场景的默认值。
- [Resource](https://docs.godotengine.org/en/4.7/classes/class_resource.html)：配方保存为外部资源，运行时深拷贝返回，避免修改共享目录。
