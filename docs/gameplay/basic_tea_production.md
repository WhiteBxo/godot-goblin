# 初级奶茶制作

F5 进入标题菜单，选择“新游戏”进入 [Day 1 正式流程](day_01_stages_01_02.md)；F6 可单独运行店铺 `src/core/main.tscn` 或聚落 `src/core/settlement.tscn`。原三单教学验收使用 `src/debug/story/legacy_shop.tscn`。走到奶茶制作台按 E 打开制作界面；操作弹窗时停止移动，Esc 或返回按钮关闭后恢复移动。新游戏重置整局，普通场景重载不重置，详见 [启动与新游戏](../guides/game_entry.md)。

## 制作界面

制作台弹窗分为左右两栏，左选右合成：

- 左栏「原料」按茶底、奶基底、糖浆、小料、其他材料排序，缺货原料仍显示并标「缺货」、不可点选；「已有成品」列出仓库中的奶茶与杯数，当前订单需要的成品带「当前订单」标记。
- 右栏顶部显示当前订单（配方与常温少糖），中间「已选材料」按每种原料一行展示份数，每行「×」移除一份，「清空」清空；下方是配方预览、`合成并入库` 按钮与结果提示。
- 鼠标左键单击左栏原料加入一份，超过库存不再加入；单击成品查看名称、杯数与配方，`一键重做` 把该配方填回右栏。
- 键盘：列表获得焦点时上下键移动、Enter/E 加入；Tab 在列表、重做、清空、移除、合成与返回之间切换。
- 界面只在制作台模式收窄弹窗边距；仓库与订单板保持原有留白。

## 验收步骤

1. 初始显示订单 #001 珍珠奶茶。左栏依次点选红茶、奶精、珍珠、糖浆，预览显示「→ 珍珠奶茶（成品）（计入当前订单）」，点击合成后成品入库，红茶、奶精、珍珠、糖浆各减少 1 份，订单切到 #002。
2. 只选部分原料或组合不成已知配方时，预览提示「这不是已知配方」，合成不扣库存、不推进订单。
3. 点击左栏「珍珠奶茶（成品）」查看详情，`一键重做` 应把红茶、奶精、珍珠、糖浆按配方填回右栏；缺料时对应行标黄并提示不足份数。
4. 按 Esc 退出，到仓库按 E 查看已扣减的基础库存；回制作台应继续订单 #002，不能重复提交 #001 的制作请求；交付仍需携带成品到胖哥布林按 E。
5. #002 用茉莉绿茶、奶精、椰果、糖浆；#003 用红茶、奶精、糖浆（不加小料）。全部完成后订单行显示完成杯数，仍可继续自由合成任意已知配方。
6. 初始已发现的教学食材为红茶、茉莉绿茶、奶精、珍珠、椰果、糖浆。仓库可按全部、人类食材、异世界食材、剧情物品筛选；默认异世界列表为空，未发现材料不出现。制作只增加成品；指定 NPC 成功交付后才写 GameState 的完成事实并发放物品奖励，失败和关窗不写成功；不写入见闻录。

## 当前规则与边界

- 配方表保存在 `src/resources/milk_tea/recipe_book.tres`，`basic_menu.tres` 与 `day1_menu.tres` 共用同一份；订单只保存 `product_id`，运行时由配方表补回材料，避免两套菜单各存一份配方漂移。
- 配方按材料多重集匹配，与点选顺序无关，允许同种材料出现多次；命中即产出对应成品。
- 每杯每种原料各消耗 1 份，糖浆必须手动选择，不再自动加入；本阶段不提供温度、糖度和用量调节。
- 命中当前订单的成品时推进订单；未命中订单的组合仍可合成并入库存，订单队列全部完成后依旧可以自由合成。
- 原料不符、库存不足、成品达到数量上限、制作重入时均不扣库存、不推进订单。
- `WarehouseInventory` 和 `TeaProduction` 由既有 GameState Autoload 持有，MainGame 只绑定服务；UI 仅展示数据并发出材料列表，合成判定与提交全部在服务层完成。切换、重进或重载场景均保留库存、成品与队列；只有显式新游戏重置整个会话。完整快照与生命周期见 [统一经营会话](business_session.md)，没有新增文件存档、补货或 AI 配方；本节的原三单教学只发物品奖励，正式 Day 1 的收入与剧情解锁见前述独立说明。
- `TaskDelivery` 复用任务状态、库存和物品奖励；订单板接取首单，制作不自动完成。`tests/verify_task_delivery.gd` 覆盖交付拒绝、一致性和重复奖励保护。
- GameState 业务事实为 `shop.order_001_delivered` 等任务完成 flag（当前仅配置首单交付） 与 `shop.orders_completed` 最高进度；只适用于当前固定教学队列，不代表跨天订单或完整库存存档。见 [Gameplay Bridge](../systems/gameplay_bridge.md)。
- 仓库和订单板沿用现有交互入口；已配置的剧情交互仍优先由 StoryDirector 路由。

## 验证

- `Godot --headless --path . --script tests/verify_tea_recipes.gd`：两套菜单配方校验、预览四种结果、自由合成与订单推进、未命中/缺料的原子性、重入与成品容量回滚、`make_drink` 订单入口，以及双栏界面的选料、移除、重做、合成与两档分辨率适配。
- `Godot --headless --path . --script tests/verify_warehouse_inventory.gd`：库存与发现、非法输入、原子扣料、JSON 往返、隐藏属性、实时 UI 刷新、正式聚落与独立店铺的共享会话。
- `Godot --headless --path . --script tests/verify_tea_production.gd`：实际 UI 面板、配方校验、库存扣减、重开进度、无小料订单、结束保护、缺货原子性、制作不会写入交付事实、重复通知去重，以及队列结束后的自由合成。
- `Godot --headless --path . --script tests/verify_milk_tea_shop.gd`：原有移动、障碍、三个交互入口与移动锁回归。
- 非 headless 运行制作验证并附加 `-- --capture`，截图保存到 `.godot/tea_production.png` 与 `.godot/tea_production_complete.png`，不纳入提交。

## Godot 4.7 官方 API 依据

- [ItemList](https://docs.godotengine.org/en/4.7/classes/class_itemlist.html)：原料与成品共用一个列表，`add_item(text, icon, selectable)` 生成不可选段头，`set_item_metadata()` 存物品 ID 与类型，`item_clicked`/`item_activated` 区分鼠标与键盘激活，`set_item_disabled()` 标记缺货。
- [GridContainer](https://docs.godotengine.org/en/4.7/classes/class_gridcontainer.html)、[ScrollContainer](https://docs.godotengine.org/en/4.7/classes/class_scrollcontainer.html)：已选材料按两列排布，材料过多时只滚动不撑破弹窗。
- [Control](https://docs.godotengine.org/en/4.7/classes/class_control.html)：`custom_minimum_size` 与 `size_flags_*` 控制左右分栏，`grab_focus()` 让列表获得键盘焦点。
- [Theme](https://docs.godotengine.org/en/4.7/classes/class_theme.html)：`add_theme_constant_override()` 只在制作台模式收窄边距与标题，不修改共享场景的默认值。
- [Resource](https://docs.godotengine.org/en/4.7/classes/class_resource.html)：配方保存为外部资源，运行时深拷贝返回，避免修改共享目录。
