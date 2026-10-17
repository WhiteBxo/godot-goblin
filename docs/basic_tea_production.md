# 初级奶茶制作

F5 从正式聚落入口 `src/core/settlement.tscn` 运行，或 F6 单独运行店铺场景 `src/core/main.tscn`。走到奶茶制作台，按 E 打开饮品制作界面。两个入口都由 MainGame 装配营业会话；操作弹窗时停止移动，Esc 或返回按钮关闭后恢复移动。

## 验收步骤

1. 初始显示订单 #001 珍珠奶茶。分别选择红茶、奶精、珍珠，点击「制作并入库」。提示成品已入库，任务保持未完成，红茶、奶精、珍珠、糖浆各减少 1 份，切换至订单 #002。
2. 制作前未选齐或选择错误茶底，点击制作时应提示原料不符，库存和订单均保持原状。
3. 按 Esc 退出，到仓库按 E 查看已扣减的基础库存；回制作台应继续订单 #002，不能重复提交 #001 制作请求；交付仍需携带成品到胖哥布林按 E。
4. #002 选择茉莉绿茶、奶精、椰果；#003 选择红茶、奶精、不加小料。全部完成后显示完成杯数，制作按钮禁用。
5. 初始已发现的教学食材为红茶、茉莉绿茶、奶精、珍珠、椰果、糖浆。仓库可按全部、人类食材、异世界食材筛选；默认异世界列表为空，未发现材料不出现。查看图标、数量和详情，缺货材料仍在列表中。制作只增加成品；指定 NPC 成功交付后才写 GameState 的完成事实并发放物品奖励，失败和关窗不写成功；不写入见闻录。

## 当前规则与边界

- 三笔订单和库存是可调整的教学默认值，保存于 `src/resources/milk_tea/basic_menu.tres`，并非最终经营数值。
- 每杯所列原料各消耗 1 份。常温、少糖固定，糖浆自动加入；本阶段不提供温度、糖度和用量调节。
- 原料不符、库存不足、订单全部完成时均不扣库存。完成后成品进入库存；交付任务另在指定 NPC 交互时结算，详见 [成品交付](task_delivery.md)。
- `WarehouseInventory` 和 `TeaProduction` 由 MainGame 创建于 Systems；制作系统注入库存服务，不再自行维护库存。UI 仅展示数据和发出制作请求，提交带有当前订单 ID，过期订单和同步重入被拒绝。场景内关闭弹窗保留进度，重启主场景重置；仅预留库存序列化接口，没有新增存档流程、补货玩法、收入、AI 配方或剧情解锁内容。详见 [仓库与共享库存](warehouse_inventory.md)。
- `TaskDelivery` 复用任务状态、库存和物品奖励；订单板接取首单，制作不自动完成。`tests/verify_task_delivery.gd` 覆盖交付拒绝、一致性和重复奖励保护。
- GameState 业务事实为 `shop.order_001_delivered` 等任务完成 flag（当前仅配置首单交付） 与 `shop.orders_completed` 最高进度；只适用于当前固定教学队列，不代表跨天订单或完整库存存档。见 [Gameplay Bridge](gameplay_bridge.md)。
- 仓库和订单板沿用现有交互入口；已配置的剧情交互仍优先由 StoryDirector 路由。

## 验证

- `Godot --headless --path . --script tests/verify_warehouse_inventory.gd`：库存与发现、非法输入、原子扣料、JSON 往返、隐藏属性、实时 UI 刷新、正式聚落与独立店铺的共享会话。
- `Godot --headless --path . --script tests/verify_tea_production.gd`：实际 UI 按钮、配料校验、库存扣减、重开进度、无小料订单、结束保护、缺货原子性以及制作不会写入交付事实、重复通知去重。
- `Godot --headless --path . --script tests/verify_milk_tea_shop.gd`：原有移动、障碍、三个交互入口与移动锁回归。
- 非 headless 运行制作验证并附加 `-- --capture`，截图保存到 `.godot/tea_production.png` 与 `.godot/tea_production_complete.png`，不纳入提交。

## Godot 4.7 官方 API 依据

- [OptionButton](https://docs.godotengine.org/en/4.7/classes/class_optionbutton.html)：选项 metadata 存储食材 ID，禁用缺货选项；程序调用 `select()` 不触发用户的 `item_selected` 信号，提交时直接读取当前选择。
- [Control](https://docs.godotengine.org/en/4.7/classes/class_control.html)：使用容器管理布局、`grab_focus()` 保持返回按钮的键盘操作；弹窗移至 PopupLayer 前显式保留 theme，因为新父层不再继承 ShopUI 的主题。
- [Resource](https://docs.godotengine.org/en/4.7/classes/class_resource.html)：菜单保存为外部资源；运行时深拷贝库存和返回的配方，避免修改共享 Resource。
