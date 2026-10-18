# 仓库与共享库存（第一阶段）

## 数据与生命周期

`basic_menu.tres` 与 `day1_menu.tres` 保存相同物品定义，分别带 tutorial / day1 配置；GameState 选定配置后所有场景共用一份库存，不各建目录副本。两菜单引用同一份 recipe_book.tres 与 recipe_rules.tres。IngredientDefinition 支持来源、类别、稀有度、图标、形态、加工、描述、价格、配方计算与投掷字段，见[旧表映射](../design/otherworld_data_mapping.md)和[新数据层](milk_tea_recipe_data.md)。

origin 为 human / otherworld；category 为 tea / milk / syrup / topping / product / material / story_item。固定成品使用 product，金币使用 story_item，新表原料与酒品按目录定义；动态配方杯单独存 drinks，不伪造为静态 IngredientDefinition。描述性战斗属性不会自动执行效果，饮品投掷只消费明确生成的 throw 参数。

六种教学食材初始为 12 / 12 / 12 / 8 / 8 / 10 份，已发现并知晓原属性；新表食材、酒品及剧情材料通常初始 0 份且未发现。醒神菇已不是唯一异世界条目；采集示例仍使用它，见[采集](gathering.md)。入库会发现材料，但不会自动揭示四个属性组。

原料表内的 22 种原料现支持每份 5 次，旧教学原料、成品与剧情物品仍为每份 1 次。库存新增 `get_uses`、`has_uses`、`try_spend_uses`，仓库显示当前份与总剩余次数；现有教学制作和交付继续按整份扣除。字段、换份规则和迁移详见[奶茶配方数据层](milk_tea_recipe_data.md)。

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

`make_drink(recipe, order_id = "")` 保留旧队列兼容：校验当前订单、重复材料总量及库存，成功更新制作前缀，队列结束后拒绝该入口。当前正式按单 / 教学配方 UI 使用 craft(materials, quantity)，可以按库存自由安排已接订单；三槽自由制作使用 craft_formula，并按次扣料。

各提交入口在同步通知前完成整组扣料、成品及对应制作记录；失败不留部分修改，通知期间拒绝重入。制作不写交付事实。TaskDelivery 的正式交付通过 GameState.commit_delivery 合并扣物品 / 配方杯、钱与物品奖励、完成事实和回执；独立测试库存保留 try_exchange 兼容路径。详见[成品交付](task_delivery.md)。

WarehousePanel 位于现有 ShopPopup 内，使用现有 theme、返回按钮、UIManager focus 和移动锁。筛选项为全部 / 人类食材 / 异世界食材 / 剧情物品；动态配方成品列在“全部”中。左侧图标、名称、数量，右侧详情可滚动；缺货仍可查看详情。库存 changed 自动刷新仓库列表及制作台选项，订单变化刷新订单板。UI 不保存或修改库存。图标使用目录绑定的 SVG 或用户导入 PNG，食材与成品分别位于 assets/ui/milk_tea/ingredients/ 和 products/；来源与未匹配素材见[导入记录](../assets/imports/user_assets_2026_10_18.md)。仓库与图鉴列表图标为 32×32，详情显示 64 像素等比预览；动态配方使用中性杯 custom_drink.svg 并展示已知原料缩略图，不借用另一款固定饮品立绘。

## 序列化边界

```json
{
  "schema_version": 3,
  "ingredients": {
    "black_tea": {
      "quantity": 12,
      "used": 0,
      "discovered": true,
      "known_properties": ["flavor_tags", "combat_attributes", "special_effects", "acquisition_sources"]
    }
  },
  "drinks": {},
  "encyclopedia": {}
}
```

示例仅展示一个条目；真实快照必须完整包含目录中的全部 ID。恢复前验证版本、ID 集、计数、当前份已用次数、发现与属性组，任何条目失败则全部不变；相同快照不重复通知。旧库存 v1 迁移为 `used = 0`，旧 v1/v2 均补空 `drinks` 与 `encyclopedia`；动态配方字段见[自由调配](free_tea_recipes.md#快照与迁移)。支持 `JSON.stringify` / `JSON.parse_string` 往返后的整数表示，拒绝小数、无穷值及非法发现状态。

库存子快照不包含静态定义、订单进度或剧情数据，不能单独作为完整营业存档。GameState v4 快照统一包含库存、配方成品与图鉴、制作订单 ID / 自由制作请求回执和剧情/交付事实，并支持旧库存子快照迁移；完整营业恢复使用 GameState.restore_state。没有数据库、存档界面或自动存档。

## 验证与试玩

以下十脚本结果属于 2026-10-17 的库存批次；当前数据、页面和订单流程已更新，本轮文档维护未复跑。

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

非 headless 运行仓库测试附加 `-- --capture`，输出 `.godot/warehouse_main.png` 和 `.godot/warehouse_settlement.png`，不提交缓存截图。当前试玩：F5 新游戏，开场结束后 E 打开仓库查看初始六项，异世界筛选为空；接单并制作后原料减少、成品增加，指定顾客交付后成品减少。普通进出店和重载保留状态。

新表原料取得后显示每份次数与剩余次数；动态杯在“全部”显示，售空仍可在手册图鉴查看。固定配方和三槽自由制作是不同入口，详见[制作](basic_tea_production.md)与[自由配方](free_tea_recipes.md)。

## Godot 4.7 官方依据

- [Resource](https://docs.godotengine.org/en/4.7/classes/class_resource.html)：资源按路径缓存共享，因此运行时状态独立保存，查询返回副本。
- [GDScript exported properties](https://docs.godotengine.org/en/4.7/tutorials/scripting/gdscript/gdscript_exports.html#resources)：自定义 Resource 与类型化 Resource 数组可通过 Inspector 编辑。
- [ItemList](https://docs.godotengine.org/en/4.7/classes/class_itemlist.html)：使用 item metadata 保存稳定 ID，固定图标尺寸；程序 select 后显式更新详情，不依赖用户选择信号。
- [Object / ConnectFlags](https://docs.godotengine.org/en/4.7/classes/class_object.html#enum-object-connectflags)：默认连接立即调用监听器，因此制作提交在通知前更新完整状态，并在通知期间保留重入锁。

钱包、购买、奖励与库存一起纳入 GameState v4 快照，详见 [钱包与原子交易](wallet_transactions.md)。原有库存增减与发现 API 保持兼容；购买和奖励应使用交易服务。
