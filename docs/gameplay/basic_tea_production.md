# 初级奶茶制作

F5 进入标题菜单，选择“新游戏”进入 [Day 1 正式流程](day_01_stages_01_02.md)；F6 可单独运行店铺 `src/core/main.tscn` 或聚落 `src/core/settlement.tscn`。原三单教学验收使用 `src/debug/story/legacy_shop.tscn`。走到奶茶制作台按 E 打开制作界面；操作弹窗时停止移动，Esc 或返回按钮关闭后恢复移动。新游戏重置整局，普通场景重载不重置，详见 [启动与新游戏](../guides/game_entry.md)。

## 制作界面

制作台默认进入“按订单制作”：左侧选择已接饮品订单，右侧订单笺显示需求、缺口和固定制作按钮；配方自动带入，确认只制作一杯。已有成品足够时提示直接交付，材料委托不进入制作列表。详见[订单系统](order_system.md)。

“自由调配”为次级页签，保留以下手动选料与批量操作：

- 左栏「原料」按茶底、奶基底、糖浆、小料、其他材料排序，缺货原料仍显示并标「缺货」、不可点选；「已有成品」列出仓库中的奶茶与杯数，当前订单需要的成品带「当前订单」标记。
- 右栏顶部列出当前已解锁配方与可制作杯数，无需先拥有成品；点击配方完整替换已选材料并将杯数重置为 1。未解锁配方隐藏，缺料或成品库存已满的配方仍可选择并查看原因。
- 「已选材料」展示「本批需求 / 当前库存」，每行「×」从单杯配方移除一份，「清空」清空；下方是预览、杯数输入框、「最大」、`制作 N 杯并入库` 按钮与结果提示。数量变化即时更新总用料；最大杯数同时受每种原料余量与成品容量限制。
- 鼠标左键单击左栏原料加入一份，超过库存不再加入；单击成品查看名称、杯数与配方，`一键重做` 把该配方填回右栏。
- 键盘：列表获得焦点时上下键移动、Enter/E 加入；右侧配方列表上下键选择并自动填料；Tab 可访问配方、数量、「最大」和制作等控件。
- 界面只在制作台模式收窄弹窗边距；仓库与订单板保持原有留白。

## 旧队列兼容验收

以下 #001～#003 是 TeaProduction 旧队列 API 的验收记录；正式页面不显示该队列行，也不靠队列位置决定订单完成。当前交互请按前述订单系统说明验收。需验证手动配料时先切到“自由调配”。

1. 初始显示订单 #001 珍珠奶茶。左栏依次点选红茶、奶精、珍珠、糖浆，预览显示「→ 珍珠奶茶（成品）×1（计入当前订单）」，点击合成后成品入库，红茶、奶精、珍珠、糖浆各减少 1 份，订单切到 #002。
2. 点击右侧配方，检查材料自动填入且杯数为 1；改为 3 杯，材料需求同步乘以 3，确认制作后入库 3 杯并扣除整批材料。点击「最大」应填入当前可制作的最大杯数，切换配方重新从 1 杯开始。
3. 只选部分原料、组合不成已知配方、缺料或成品容量不足时，制作按钮禁用并提示原因；服务层再次校验，失败不扣任何材料、不推进订单。
4. 点击左栏「珍珠奶茶（成品）」查看详情，`一键重做` 应把红茶、奶精、珍珠、糖浆按配方填回右栏；缺料时预览提示不足份数。
5. 按 Esc 退出，到仓库按 E 查看已扣减的基础库存；回制作台应继续订单 #002，不能重复提交 #001 的制作请求；交付仍需携带成品到胖哥布林按 E。
6. #002 用茉莉绿茶、奶精、椰果、糖浆；#003 用红茶、奶精、糖浆（不加小料）。全部完成后订单行显示完成杯数，仍可继续自由合成任意已知配方。
7. 初始已发现的教学食材为红茶、茉莉绿茶、奶精、珍珠、椰果、糖浆。仓库可按全部、人类食材、异世界食材、剧情物品筛选；默认异世界列表为空，未发现材料不出现。制作只增加成品；指定 NPC 成功交付后才写 GameState 的完成事实并发放物品奖励，失败和关窗不写成功；不写入见闻录。

## 当前规则与边界

- 配方表保存在 `src/resources/milk_tea/recipe_book.tres`，`basic_menu.tres` 与 `day1_menu.tres` 共用同一份；订单只保存 `product_id`，运行时由配方表补回材料，避免两套菜单各存一份配方漂移。
- 配方按材料多重集匹配，与点选顺序无关，允许同种材料出现多次；命中即产出对应成品。
- 每杯按照配方中的出现次数消耗原料，批量需求为单杯份数乘以杯数；点击配方会包含糖浆，手动混料时仍需自行选择糖浆；本阶段不提供温度、糖度和用量调节。
- 批量制作通过一次 `try_exchange` 整体扣料并入库。兼容队列仍只推进连续且已接取的同品种订单；正式订单通过实际库存和交付回执判断，与该队列顺序无关。
- 原料不符、库存不足、成品达到数量上限、制作重入时均不扣库存、不推进订单。
- `WarehouseInventory` 和 `TeaProduction` 由既有 GameState Autoload 持有，MainGame 只绑定服务；UI 仅展示数据并发出单杯材料列表与整数杯数，合成判定与提交全部在服务层完成。切换、重进或重载场景均保留库存、成品与队列；只有显式新游戏重置整个会话。完整快照与生命周期见 [统一经营会话](business_session.md)，没有新增文件存档、补货或 AI 配方；本节的原三单教学只发物品奖励，正式 Day 1 的收入与剧情解锁见前述独立说明。
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
