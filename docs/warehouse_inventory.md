# 仓库与共享库存（第一阶段）

## 数据与生命周期

`basic_menu.tres` 是唯一食材目录及教学默认配置。`TeaMenu.ingredients` 使用 `Array[IngredientDefinition]`，可在 Inspector 编辑 ID、名称、图标、origin、category、稀有度、风味标签、战斗属性、特殊效果和获取来源。origin 为 `human` / `otherworld`；category 为 `tea` / `milk` / `syrup` / `topping` / `product` / `material`，两者独立。战斗属性和效果目前只作为描述数据，不实现战斗或效果执行系统。

`material` 用于不在奶茶配方里的采集材料。目录现有唯一的异世界材料是醒神菇 `insomnia_mushroom`（`origin = otherworld`、稀有），默认 0 份且未发现；只有夜间采集点入库时才 `discovered`，此后在仓库的「异世界食材」筛选里可见。采集与交付见 [采集与任务物资提交](gathering.md)。

`initial_stock` 单位为份，六种初始数量保持 12 / 12 / 12 / 8 / 8 / 10。`initial_discovery` 的键是初始已发现的食材 ID，值是已知属性组列表。默认六种人类材料均已知，没有新增异世界剧情内容。新增食材只需编辑该资源；没有初始库存或发现配置的食材默认数量为零且未发现。

GameState Autoload 持有 WalletTransactions（其内部拥有唯一的 WarehouseInventory）和一个 TeaProduction。钱包交易、制作与交付复用同一库存。MainGame 在正式聚落 `settlement.tscn` 与独立店铺 `main.tscn` 中绑定同一份库存和制作服务：

```text
basic_menu.tres → WarehouseInventory（数量、发现、已知属性组）
                     ↑ 原子扣料             ↓ changed / 脱敏 view
                 TeaProduction          ShopUI → ShopPopup → WarehousePanel
                 （订单进度）                ↑ 制作请求 + 订单 ID
                     ↓ changed
                  GameState（服务所有者、剧情与交付事实）
```

关闭弹窗、切换场景、重进店铺和场景重载均不创建新服务或重置状态。显式新游戏整体重置经营与剧情。未新增 Autoload；完整归属、接口与重启边界见 [统一经营会话](business_session.md)。演示 TeaMaking 仍为场景本地教学，不消耗正式库存。

## 库存服务 API

| API | 行为 |
| --- | --- |
| `get_definition(id)` | 返回定义副本；未知 ID 返回 null |
| `get_stock(id)` | 返回份数；未知 ID 查询返回 0，不创建条目 |
| `is_discovered(id)` / `get_discovery(id)` | 查询发现状态及已知属性组；未知 ID 返回 false / 空字典 |
| `get_ingredients(origin = "")` | 返回该来源下所有已发现材料的展示 view，包括零库存 |
| `get_ingredient_view(id)` | 未发现返回空字典；未知属性组返回 `["???"]` |
| `add_ingredient(id, amount)` | 增加正整数份数，同时发现材料，不自动揭示属性 |
| `has_materials({id: amount})` | 整组检查，拒绝空组、未知 ID、未发现材料、非法数量或不足 |
| `try_consume({id: amount})` | 全部检查通过后统一扣料；成功仅发出一次 changed |
| `discover(id)` | 登记发现，不增加数量；已发现返回 false |
| `discover_property(id, group)` | 发现材料并揭示指定属性组；重复或未知组返回 false |
| `to_dict()` / `restore_state(data)` | 版本化快照和原子恢复；不读写文件 |

变更 API 失败返回 false，恢复失败返回 `ERR_INVALID_DATA`，都不改状态、不发出通知。ID 必须为目录中的 String，数量必须为 int，拒绝 bool、float、字符串、零、负数及超出安全计数范围的值；每项最大计数为 2147483647，只用于防溢出，不存在仓库容量玩法。定义、发现查询和快照使用副本，调用者不能通过返回的容器修改库存或共享 Resource。

发现粒度为四个属性组：`flavor_tags`、`combat_attributes`、`special_effects`、`acquisition_sources`。每组独立解锁；已知的空组显示「无」，未知组显示 `???`。仓库只使用服务返回的脱敏 view，不读取静态隐藏描述。发现一种材料不会自动揭示其特殊效果或获取来源。

## 制作提交与 UI

TeaProduction 保留 `get_stock`、`get_ingredients`、`get_order`、`get_completed_count`、`make_drink` 等 API。独立使用时先 `configure(inventory)`；未配置不能制作，不能再次绑定另一份库存重置营业进度。

`make_drink(recipe, order_id = "")` 先验证当前订单和配方，将重复 ID 汇总成所需份数，再检查整组库存。提交阶段没有 await，订单进度与全部扣料在通知前完成，失败则保留原状态。提交锁持续到同步通知结束，监听器不能重入制作。旧的单参数调用仍按当前订单制作；正式 UI 始终传递显示的订单 ID，拒绝过期请求。订单全部完成后拒绝继续制作。制作成功增加 `category=product` 成品，不写交付事实。TaskDelivery 在指定 NPC 交互时校验任务并通过 `try_exchange` 合并扣成品与发放物品奖励；重复 changed 不会完成任务。详见 [成品交付](task_delivery.md)。

WarehousePanel 位于现有 ShopPopup 内，使用现有 theme、返回按钮、UIManager focus 和移动锁。三个筛选项是全部 / 人类食材 / 异世界食材。左侧图标、名称、数量，右侧详情可滚动；缺货仍可查看详情。库存 changed 自动刷新仓库列表及制作台选项，订单变化刷新订单板。UI 不保存或修改库存。图标是本次直接编写的 16×16 SVG 像素风源文件，位于 `assets/ui/milk_tea/ingredients/`，随附 Godot `.import` 设置，无需生成派生图片。

## 序列化边界

```json
{
  "schema_version": 1,
  "ingredients": {
    "black_tea": {
      "quantity": 12,
      "discovered": true,
      "known_properties": ["flavor_tags", "combat_attributes", "special_effects", "acquisition_sources"]
    }
  }
}
```

示例仅展示一个条目；真实快照必须完整包含目录中的全部 ID。恢复前验证版本、ID 集、计数、发现与属性组，任何条目失败则全部不变；相同快照不重复通知。支持 `JSON.stringify` / `JSON.parse_string` 往返后的整数表示，拒绝小数、无穷值及非法发现状态。

库存子快照不包含静态定义、订单进度或剧情数据，不能单独作为完整营业存档。GameState v2 快照已统一包含库存、成品、制作订单 ID 和剧情/交付事实，完整营业恢复使用 GameState.restore_state。没有数据库、存档界面或自动存档。

## 验证与试玩

项目引擎为 Godot 4.7.2。macOS 本机可使用 `/Applications/Godot.app/Contents/MacOS/Godot`，以下以 `Godot` 代指可执行文件：

```sh
Godot --headless --path . --script tests/verify_warehouse_inventory.gd
Godot --headless --path . --script tests/verify_tea_production.gd
Godot --headless --path . --script tests/verify_gameplay_bridge.gd
Godot --headless --path . --script tests/verify_milk_tea_shop.gd
Godot --headless --path . --script tests/verify_shop_equipment.gd
Godot --headless --path . --script tests/verify_ui_manager.gd
Godot --headless --path . --script tests/verify_game_state.gd
Godot --headless --path . --script tests/verify_main_game.gd
Godot --headless --path . --script tests/verify_settlement.gd
Godot --headless --path . --script tests/verify_interaction_feedback.gd
```

Gameplay Bridge 测试会在 user:// 写临时 JSON，需要允许写入该目录。仓库测试包括两种正式入口、640×360 / 1280×720 布局、未知属性、分组消耗、非法输入、快照往返、重复订单 ID 和同步重入。异世界属性用测试内构造的 Resource 验证，不添加正式剧情食材。

2026-10-17 使用 Godot 4.7.2 实测以上十个脚本全部通过：仓库 125 checks、Gameplay Bridge 246 checks、UIManager 47 checks、GameState 120 checks、主场景 72 checks、设备 36 checks、交互反馈 46 checks；制作、移动及聚落验证均 PASS。仓库另外在 Metal Forward+ 图形模式通过 125 checks，已检查两个入口的渲染截图。沙箱内的 macOS 证书读取/编辑器设置写入提示与业务断言无关；Gameplay Bridge 临时 user:// 写入在允许该目录写入后重跑通过。

非 headless 运行仓库测试附加 `-- --capture`，输出 `.godot/warehouse_main.png` 和 `.godot/warehouse_settlement.png`，不提交缓存截图。F5 或 F6 店铺场景后，E 打开仓库查看默认六种材料，筛选异世界应为空；Esc 后移动恢复。制作 #001 后成品入库，红茶/奶精/珍珠/糖浆各减一，重开仓库仍保持扣料，订单板与制作台均显示 #002；按原教学配方制作三杯后不能重复制作；首单在胖哥布林交付才结算。

## Godot 4.7 官方依据

- [Resource](https://docs.godotengine.org/en/4.7/classes/class_resource.html)：资源按路径缓存共享，因此运行时状态独立保存，查询返回副本。
- [GDScript exported properties](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_exports.html#resources)：自定义 Resource 与类型化 Resource 数组可通过 Inspector 编辑。
- [ItemList](https://docs.godotengine.org/en/4.7/classes/class_itemlist.html)：使用 item metadata 保存稳定 ID，固定图标尺寸；程序 select 后显式更新详情，不依赖用户选择信号。
- [Object / ConnectFlags](https://docs.godotengine.org/en/4.7/classes/class_object.html#enum-object-connectflags)：默认连接立即调用监听器，因此制作提交在通知前更新完整状态，并在通知期间保留重入锁。

钱包、购买、奖励与库存一起纳入 GameState v2 快照，详见 [钱包与原子交易](wallet_transactions.md)。原有库存增减与发现 API 保持兼容；购买和奖励应使用交易服务。
