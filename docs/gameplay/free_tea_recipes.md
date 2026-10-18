# 自由调配、饮品图鉴与交付（第二期）

> 2026-10-19：自由配方已使用持久槽位报价和首次爆品 150G 原子奖励，纯人类组合不可登记。正式爆品配置为空；加冰不改价。当前集成和迁移见[整合记录](../development/two_day_integration_2026_10_19.md)。

实现依据为[奶茶配方系统设计](../design/milk_tea_recipe_system_revised.md)，原料来源及按次库存见[第一期数据层](milk_tea_recipe_data.md)。本期接入自由制作、配方成品、图鉴及通用订单要求；参数生成后的守卫效果现已由[第三期执行器](drink_throw_effects.md)接入。

## 规则与配置

`src/resources/milk_tea/recipe_rules.tres` 是槽位数、普通售价、爆品表和投掷参数的共享入口，两个菜单的 `TeaMenu.recipe_rules` 引用它。当前 `slot_count = 3`，每杯必须且只能有一个基底，最多再加两个辅料；辅料可空、可重复。`RecipeRules.MAX_SLOTS = 3` 同时限制新配方计算、报价与界面，旧配置即使设置更大的槽位数也不能突破三槽上限，不改变配方 ID。已有较长配方仍可读取，但不能重做或重新报价。

`DrinkFormula.evaluate(materials, lookup, rules, enforce_slots = true, iced = false)` 是无副作用的计算入口，`materials` 第一项为基底，其余为辅料。基底必须同时允许作为基底和用于普通配方；全部原料都必须允许普通配方。F09 格里芬之血不进入自由制作，已有剧情特调继续使用教学规则。

`can_be_base`（可作为基底）与 `free_recipe_allowed`（普通配方可用）是独立条件：第一槽额外检查基底资格，后两槽只检查普通配方资格，不因原料也具备基底资格而拒绝。槽位决定本杯角色，多个具备基底资格的原料不会变成多个基底。例如 `[instant_coffee_concentrate, creamer_milk_tea_base]` 使用咖啡基底、植脂末辅料，名称仍以“咖啡”结尾；交换两者后改为“奶茶”结尾，且配方 ID 不同。经营报价仍另需至少一种哥布林原料，纯人类组合的已有报价限制不变。

- 六项口味以基底数值起算；每份辅料某项数值达到 3 才加到该项。重复辅料分别贡献。
- 风味、口感、特殊效果三组标签分别合并去重。
- 名称依次拼接基底、辅料名称、基底后缀；相同辅料重复两份使用“**双重**”前缀。更多份使用数量加“重”。
- 配方身份由基底和排序后的辅料列表生成 SHA256。交换辅料顺序不生成新库存或图鉴条目；更换基底或数量会改变身份。重复制作沿用首次发现的原料顺序及名称。加冰作为名称变体单独保留库存与图鉴，避免与不加冰的杯子混名；不加冰的既有 ID 保持不变。
- 售价由 EconomyRules + FormulaPricing 逐槽计算；预览只读区间，`GameState.confirm_formula` 首次确认保存实际报价。成本按标准市场价除以次数计算，采购折扣不回填成本。至少含一种可经营哥布林原料，最多三槽。
- 爆品按基底和辅料数量精确匹配，首次实际制作原子领取 150G，不覆盖配方售价。正式 `signatures` 保持空数组，未编造爆品内容。
- 只有十二种已映射原料贡献投掷 `stacks`。区域大小和时长受 `throw_tuning.tres` 上限约束；返回的每份参数保留原值，由后续执行器解释，不能把布尔值或每秒触发间隔直接乘层数。

例如 `[goblin_firebrew, mint_syrup, mint_syrup]` 的甜度为 8、麻痹层数为 2；`[goblin_firebrew, mint_choc_crisp, red_mottled_wood]` 单杯成本为 8G。

## 独立加冰选项

新增约定：冰块不占三个原料槽，从自由调配原料候选中移除，另设“加冰 / 不加冰”，默认不加冰。加冰只在饮品类型后缀前加入“冰”：`xx奶茶 → xx冰奶茶`、`xx特调 → xx冰特调`，茶与咖啡后缀同样适用。

按用户确认，加冰不消耗冰块，不要求持有或发现冰块，不计成本，也不改变六项口味、标签、售价、爆品匹配和投掷参数。配方精确订单接受两种名称变体。原料表中的冰块定义与投掷映射保留为来源数据，独立命名选项不读取它们。已有把冰块放进原料列表的历史成品仍可恢复、查看及交付，其图鉴不允许直接重做；新配方通过服务 API 也不能把冰块塞回原料槽。

制作请求与图鉴回填信号都携带 `iced: bool`。图鉴“放入制作台”同时恢复原料和加冰选择，保存与场景重建后仍保留。

## 制作、库存与图鉴

界面从共享 `TeaProduction` 读取候选与预览，仅发送制作请求。可选原料限已发现且允许普通配方的条目；缺货仍可查看。选择时显示名称、已知风味和 24 像素原料预览，不显示六项内部数值。仓库 / 图鉴的动态杯使用中性杯图标，详情显示原料缩略图；固定成品仍用各自定义的专属图。

| API | 契约 |
| --- | --- |
| `TeaProduction.preview_formula(materials, quantity = 1, iced = false)` | 校验槽位、原料可用次数及成品容量，不修改状态 |
| `TeaProduction.craft_formula(materials, quantity = 1, request_id = "", iced = false)` | 同步提交扣次、配方杯数和首次发现；成功请求 ID 可持久防重放，失败允许重试 |
| `WarehouseInventory.get_formula_choices(base_only = false)` | 返回已发现候选及受发现规则遮蔽的风味 |
| `get_drink_stock(id)` / `get_drink_record(id)` | 查询配方库存及首次发现资料，返回独立数据 |
| `get_drinks(include_empty = false)` | 默认只列持有饮品；传 true 包含已售空的图鉴记录 |

制作成功入库并保存图鉴、回执；仅配置爆品首次实际制作会同时增加 150G，普通制作不加钱，不推进指定 NPC 交付事实。正式宿主的 formula_requested 与固定配方请求均经 MainGame 调用共享服务，并按结果播放 InteractionAudio 的 craft_success / craft_failure；UI 不直接提交库存。扣料、成品和图鉴完成后才发布通知，同步观察者不能重入制作或重置会话。失败不扣料、不新增图鉴、不留下成功请求回执。

仓库“全部”包含动态饮品；手册新增“饮品图鉴”页，发现第一杯后解锁。图鉴展示首次配方、六项数值、标签、价格、成本、首次发现天数和现存杯数。卖空后记录保留。“放入制作台”只回填选择；玩家仍需前往制作台确认制作，不远程扣料。

## 通用订单

`delivery` 必须在 `product_id`、`items`、`drink` 三者中恰好选择一个。自由饮品需求示例（示例不会自动发布正式订单）：

```json
{
  "order_id": "example_drink",
  "target_object_id": "fat_goblin",
  "drink": {
    "base_id": "goblin_firebrew",
    "flavors": ["薄荷"],
    "minimum_taste": {"sweetness": 8}
  }
}
```

也可以用 `"formula": ["goblin_firebrew", "mint_syrup", "mint_syrup"]` 指定精确配方。支持 `base_id`、`flavors`、`textures`、`effects`、`minimum_taste`；同时配置时全部满足，每组标签要求全部包含。基础 JSON 校验在 TaskCatalog，原料引用及基底资格在 TaskDelivery 绑定共享库存时检查。

`TaskDelivery.try_submit(order_id, target_object_id, drink_id = "")` 可指定持有饮品；未指定时自动选择第一种符合要求的饮品，扣一杯。`deliver_to(target)` 沿用同一规则。动态订单的 `get_requirement()` 返回空字典，它只供静态物品需求使用；展示动态需求读取订单的 `drink`，或使用 `DrinkFormula.requirement_text()`。

自由饮品订单默认收入为该饮品售价；显式 `rewards.money` 覆盖此价格，包含显式零，不重复叠加。GameState 与钱包事务一次提交扣杯、奖励、完成事实、回执、批次及交付计数。错误对象、要求不符、未接取、重复交付、余额或奖励容量溢出均整体失败。当前正式任务数据未增加自由订单或新对白，没有柜台直接售卖入口。

## 快照与迁移

GameState 完整快照为 v8；库存子快照为 v6，钱包子快照为 v3：

```text
schema_version: 8
business:
  profile_id: tutorial | day1
  inventory:
    schema_version: 6
    ingredients: {原料ID: {quantity, used, discovered, known_properties}}
    drinks: {配方ID: 杯数}
    encyclopedia: {配方ID: {ingredients: [基底, 辅料...], discovered_day: 天数, iced: true（可选）}}
  production:
    completed_order_ids: [已制作教学订单ID...]
    formula_requests: {成功请求ID: true}
economy:
  inventory: 与 business.inventory 完全相同的独立副本
  ...钱包原有字段
```

图鉴存首次原料顺序、发现天数和加冰选择；`iced` 缺省为 false，旧的双字段记录可直接恢复，无需升级版本。名称、口味和投掷参数从静态配置重算；价格从 economy.recipe_prices 的持久记录读取，图鉴另存 pricing 状态。静态配方平衡改动也会反映在历史饮品上。恢复时校验配方 ID、原料资格、杯数及日期，再整体替换；损坏数据不部分写入。

旧完整 v2/v3 快照补空饮品、空图鉴及空自由制作回执，旧原料已开封次数保留。v2 仍迁移为 tutorial 并补古怪金币空条目；只有剧情的 v1 仍拒绝。独立库存 v1/v2 可迁移到 v3。完整会话使用原生 Variant 保存类型，安全自动保存及继续游戏见[存档系统](../systems/save_system.md)。两分支旧报价和奖励记录按原值迁移，未定价历史不抽 RNG、不补奖。

## 验证与试玩

自动化入口：`godot --headless --path . --script res://tests/verify_free_recipes.gd`。测试覆盖计算、数量与容量、重入及请求重放、完整存储往返、旧快照、订单要求和收入、真实制作与图鉴 UI、场景重建。图形截图可去掉 `--headless` 并增加 `-- --capture`，输出 `.godot/free_recipes/`。

1. F6 `src/core/main.tscn`（正式 Day 1）或 `src/debug/story/legacy_shop.tscn`（教学宿主）；取得允许自由配方的原料后，在制作台按 E，先切外层“自由调配”，再切内层同名“自由调配”页（另一页为“教学配方”）。原料不会为了试玩自动入库；自动化测试自行准备库存。
2. 选择基底和两份相同辅料，在独立冰块选项选择“加冰”，检查预览名称的“冰”在饮品后缀前，制作一杯。观察三个原料按次减少、冰块库存不变、动态饮品入库，教学订单和余额不变。
3. Esc 关闭，打开手册“饮品图鉴”，检查六项数值和库存；点击“放入制作台”，回到制作台应显示同一配方及“加冰”选择。
4. 普通场景切换保留成品、图鉴和开封次数；“新游戏”整体清空。通用自由订单的出售路径由测试配置验证，正式剧情未发布此类订单。

Godot 4.7 的关键依据：[Resource](https://docs.godotengine.org/en/4.7/classes/class_resource.html) 与 [Dictionary.duplicate](https://docs.godotengine.org/en/4.7/classes/class_dictionary.html#class-dictionary-method-duplicate) 用于隔离配置、结果和快照；[TabContainer](https://docs.godotengine.org/en/4.7/classes/class_tabcontainer.html) 管理制作与手册页签；[ScrollContainer.follow_focus](https://docs.godotengine.org/en/4.7/classes/class_scrollcontainer.html#class-scrollcontainer-property-follow-focus) 保证小窗口内滚动内容的键盘焦点可达；[OptionButton.select](https://docs.godotengine.org/en/4.7/classes/class_optionbutton.html#class-optionbutton-method-select) 用于重做回填，不依赖程序选择触发用户输入信号。

### 2026-10-18 验证记录

使用 Godot 4.7.2 Windows，图形检查使用 Compatibility 渲染器。

| 检查 | 结果 |
| --- | --- |
| `verify_free_recipes.gd` | 128 项，0 失败；图形集成在此前 127 项版本通过，最后增加的首次发现入口即时解锁断言在 headless 通过 |
| 相关 Godot 回归 | 27 个脚本通过，覆盖库存、原料、钱包、教学制作、经营会话、任务、状态、入口、手册、见闻录、Day 1、主场景、采集、店铺、UI、Bridge、Director 和开发工具 |
| 原料 Python 测试与导入 `--check` | 10 个测试通过，两个菜单与 22 行原料表一致 |
| 图形检查 | 制作与图鉴的 640×360 / 1280×720 截图已检查；教学制作按钮在小窗口中可由键盘焦点滚动到可见区域 |
| headless 编辑器导入 | 退出码 0，无脚本解析或编译错误；退出仍有 MCP 插件既有的 495 对象 / 10 资源保留诊断 |

两项失败在隔离的 HEAD 副本中复现，未计为通过，也未在本期修改：`verify_scene_travel.gd:84` 读取 `PromptBar.text` 的无效属性；`verify_story_authoring.py` 在 `cinematic.opening/steps[9]` 的 customer 移动超时。未运行无关玩法测试和 Release 导出，本期没有修改其实现或发布配置。

加冰补充验证：`verify_free_recipes.gd` 已扩展至 189 项，图形模式全部通过，制作及图鉴的 640×360 / 1280×720 截图均已检查。另实际通过 15 个相关回归脚本：原料数据、库存、钱包、教学制作、教学配方、经营会话、交付、GameState、手册、MainGame、店铺、UIManager、主题、Day 1 前两阶段和世界流程。格式、链接与 `git diff --check` 通过；原料表和导入工具未修改，因此未重复运行 Python 导入测试。

Day 1 前两阶段的 225 项断言和退出码均通过，但退出仍报告 4 个对象 / 1 个资源保留。verbose 诊断定位到 `assets/audio/music/daily_milk_tea.ogg` 的 Ogg 播放资源，未出现配方或 UI 对象泄漏；本次未修改音频实现，没有将该退出诊断写成已修复。
