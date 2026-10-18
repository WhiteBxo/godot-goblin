# 奶茶配方数据层（第一期）

本期提供原料定义、离线导入、投掷参数与按次使用的库存接口。自由调配、配方成品库存和饮品图鉴已由[第二期](free_tea_recipes.md)接入；投掷效果现由[第三期](drink_throw_effects.md)执行。现有教学制作、交付与潜行流程保留。

## 数据来源与导入

- 原料来源：[2026-10-18 原料表](../design/source/recipe_ingredients_revised_2026_10_18.xlsx)，22 行，通过 `IngredientDefinition.source_ids` 对应稳定物品 ID。
- 导入工具：`tools/milk_tea/import_recipe_ingredients.py`，需要 Python 和 `openpyxl`。
- 投掷对应：`tools/milk_tea/throw_roles.json`，记录本次确认的十二种映射。
- 输出：`basic_menu.tres`、`day1_menu.tres`。只更新配方、市场价格、使用次数与投掷字段，保留名称、图标、描述、原有标价、教学配方、库存和订单。

从仓库根执行：

```sh
python tools/milk_tea/import_recipe_ingredients.py
python tools/milk_tea/import_recipe_ingredients.py --check
```

`--check` 不写文件，数据过期时退出码为 1。写入前先检查两个菜单的完整覆盖与唯一映射；坏行、基底与命名冲突、缺列、重复行或漏配时拒绝生成，不先改其中一个菜单。

## 原料字段

`IngredientDefinition` 保留旧字段，新增：

| 字段 | 含义 |
| --- | --- |
| `can_be_base` / `base_suffix` | 可作为基底及命名后缀：奶茶、茶、咖啡、特调 |
| `free_recipe_allowed` | 是否可用于普通自由配方；独立于基底资格 |
| `sweetness` / `sourness` / `bitterness` / `spiciness` / `milkiness` / `booziness` | 六项口味数值 |
| `recipe_flavors` / `recipe_textures` / `recipe_effects` | 配方用短标签；与旧的描述性风味文本分开 |
| `market_price` | 每份市场价；空值记作 -1，不能当作免费；不替代旧 `price` 字段 |
| `uses_per_portion` | 每份可用次数；新表内原料为 5，旧教学原料、成品与剧情物品默认 1 |
| `throw_kind` | 投掷参数键；空字符串表示没有投掷效果 |

F09 格里芬之血可以作为剧情基底，但禁止普通配方使用、市场价格未知、不带投掷效果。所有基底及 F02、C06 均不带投掷效果；食材描述中的“眩晕”等文字不会自动赋予投掷能力。

## 投掷参数

`src/resources/milk_tea/throw_tuning.tres` 集中保存面积、时长上限，以及每种效果和区域修饰的参数。数值是后续执行器的输入，本期不会改变守卫行为。

| 原料 | 参数键 | 含义 |
| --- | --- | --- |
| F04 萤火伞 | `lure` | 每秒引诱 |
| F07 红斑咬木 | `toxic` | Day 1 驱离区域 |
| F12 炽舌椒 | `burn` | 点燃、混乱 |
| C10 草莓果酱 | `corrode` | 延长发现时间、腐蚀可破坏物 |
| C03 荧绿薄荷糖浆 | `paralyze` | 眩晕 |
| F11 幻彩小方 | `hallucinate` | 混乱 |
| C08 可可粉 | `burst` | 扩散、击退 |
| C05 黑糖波霸珍珠 | `sticky` | 粘留、延时 |
| C09 苹果果酱 | `contagion` | 附着、传染 |
| C07 冰块 | `mine` | 地雷化 |
| F08 蜜珀晶 | `vortex` | 聚拢 |
| F10 幻金菇 | `phantom` | 静音、穿墙 |

只有这十二种原料带投掷映射；其中冰块在新自由配方中已改为独立命名开关，不再作为原料选择，也不赋予地雷。重复原料的口味门槛和投掷倍率是两套规则；第一期保存数据，第二期合成受上限约束的投掷参数，第三期执行效果。三个配方槽位及动态生成界面见第二期，教学配方的原料数量保留。

## 库存与兼容

`quantity` 仍是剩余份数，包含最多一份已开封原料；`used` 是该份已用次数。总剩余次数为 `quantity * uses_per_portion - used`。例如两份原料使用两次后：`quantity = 2`、`used = 2`，当前份余 3 次，总计余 8 次。当前份耗尽时自动减一份，再开始下一份。

| API / view | 作用 |
| --- | --- |
| `get_uses(id)` / `get_uses_per_portion(id)` | 总剩余次数、每份次数 |
| `has_uses({id: count})` | 按次检查整组原料 |
| `try_spend_uses(costs, acquired = {})` | 原子扣次并可同时入库整份成品，成功只发一次 `changed` |
| view 的 `uses` / `uses_per_portion` / `current_portion_uses` | 仓库显示总次数、每份次数和当前份余量 |

`get_stock`、`has_materials`、`try_consume`、`try_exchange` 与交易购买继续以份计数。整份扣除优先取未开封份；扣到最后一份时清空 `used`。补货保留当前份已用次数。教学制作仍按旧规则扣整份，避免改动 Day 1 已有订单与剧情。

第一期库存子快照 v2 引入 `used`；第二期库存 v3 增加 `drinks` / `encyclopedia`，整局升级为 v4。旧库存 v1 补 `used = 0`；旧库存 v2 保留开封次数，均补空配方成品和图鉴。完整 v2/v3 快照可迁移，v2 缺金币条目的迁移仍有效。迁移先核对经营与经济库存完全一致，再复制并规范化；不改调用方数据，损坏数据整包拒绝。详见[第二期快照边界](free_tea_recipes.md#快照与迁移)。

## 验证与试玩

```sh
python tests/verify_recipe_ingredients.py
godot --headless --path . --script res://tests/verify_recipe_data.gd
```

第一期新增测试覆盖 Excel 与两个菜单一致、十二种投掷映射、次数耗尽和补货、原子失败、输出满仓、旧快照迁移、损坏数据拒绝及仓库文字刷新。相关回归选库存、钱包、制作、交付、经营会话、GameState 和 Day 1 流程。

仓库试玩入口为 `src/core/main.tscn`，F6 打开仓库。教学食材仍按份显示；取得新表原料后会显示每份 5 次。第二期已新增“自由调配”页，可观察当前份次数递减和耗尽换份；自动化测试覆盖该刷新路径。

实现依据为 [Godot 4.7 Resource.duplicate](https://docs.godotengine.org/en/4.7/classes/class_resource.html#class-resource-method-duplicate) 与 [Dictionary.duplicate](https://docs.godotengine.org/en/4.7/classes/class_dictionary.html#class-dictionary-method-duplicate)：原料定义和嵌套快照使用独立副本，避免运行时扣料或迁移修改共享资源、调用方容器。
