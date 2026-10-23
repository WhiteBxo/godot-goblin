# 异世界食材与酒品：源稿到运行时映射

> 2026-10-19：本文继续描述旧来源的实际 ID 与字段映射。现行设计改以 [2.0 原料](recipe_ingredients_revised.md)和[新经济规则](milk_tea_economy_revised.md)为准；当前导入器仍读 10-18 附件，尚未导入经营 T 编号，勿将下文“已同步”理解为新经济已上线。开发差距见[实现方案](milk_tea_economy_implementation_plan.md)。

运行时字段映射基线：2026-10-17；图标引用更新：2026-10-18。旧源稿 [otherworld_ingredients_and_drinks.xlsx](source/otherworld_ingredients_and_drinks.xlsx)，运行时目录 [day1_menu.tres](../../src/resources/milk_tea/day1_menu.tres)，校验脚本 [verify_otherworld_catalog.gd](../../tests/verify_otherworld_catalog.gd)。

本文件记录旧源稿到现有运行时的映射。2026-10-18 新增的[原料规则表](recipe_ingredients_revised.md)与[配方专项设计](milk_tea_recipe_system_revised.md)作为后续设计依据，其数值、市场价格和使用次数已通过[原料导入工具](../gameplay/milk_tea_recipe_data.md)同步到两个菜单；下表仍专门记录旧表 price / 描述等来源字段，不要把本文旧字段当成新版设计。旧表保留 W/H 数据与图鉴描述等互补内容，见[更新说明](milk_tea_recipe_update_2026_10_18.md)。

## 接入范围

- 已接入：四张表共 33 行源稿，落在 31 个运行时物品上 —— 「异世界原料配置表」F01–F12、「酒品」W01–W05、「现实食材」C01–C10、「人类奶茶配方」H01–H06。
- 异世界原料与酒品登记为 otherworld / material，现实食材为 human，六款人类饮品为 `product`。
- 除教学六项外，新条目初始库存 0、未发现；采集、购买或剧情交付取得后才会在仓库出现。
- `basic_menu.tres` 与 `day1_menu.tres` 共用同一份 `recipe_book.tres`，因此新增的六款配方与成品在两个菜单里都存在；教学局的初始库存与订单未变。
- 未接入的 P 类见文末。

## 已接入条目

| 源稿行 | 运行时 ID | 名称 | 稀有度 | 形态 | 加工 | 标价 | 获取方式 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| F01 | `moss_green` | 苔痕青 | 普通 | 液体 | 免加工 | — | 湿润区域石壁采集 |
| F02 | `sugar_yam` | 窟窟糖芋 | 普通 | 固体 | 切丁、切块 | — | 厨房备料区购买或代订 |
| F03 | `insomnia_mushroom` | 醒神菇 | 稀有 | 固体 | 榨汁 | — | 胖哥布林任务、委托 NPC 购买 |
| F04 | `firefly_cap` | 萤火伞 | 稀有 | 固体 | 切块、榨汁 | — | 大树根部、树荫下采集 |
| F05 + W02 | `goblin_firebrew` | 纯正哥布林老火烧 | 优秀 | 液体 | 免加工 | 4 | 酒馆直接购买 |
| F06 + W04 | `griffin_amber_wine` | 格里芬琥珀酒 | 史诗 | 液体 | 免加工 | 100 | 醉酒守卫任务、酒馆购买（使者八折 80） |
| F07 | `red_mottled_wood` | 红斑咬木 | 优秀 | 固体 | 切丁、免加工 | — | 赌场区域购买或赌博 |
| F08 | `honey_amber_crystal` | 蜜珀晶 | 优秀 | 固体 | 切块 | — | 赌场区域购买或赌博 |
| F09 | `day1_griffin_blood` | 格里芬之血 | 传奇 | 液体 | 免加工 | — | day1 偷窃任务（长老住所）；运行时 ID 沿用 Day 1 剧情侧已有的命名 |
| F10 | `phantom_gold_mushroom` | 幻金菇 | 史诗 | 固体 | 切块 | — | 醉酒守卫任务并赢得赌局后挑选 |
| F11 | `rainbow_cube` | 幻彩小方 | 史诗 | 胶体 | 切丁 | — | 赢得赌局后挑选 |
| F12 | `scorch_tongue_pepper` | 炽舌椒 | 稀有 | 固体 | 切丁、榨汁 | — | 公共火塘周围地面、石缝采集 |
| W01 | `sour_moss_ale` | 劣质酸苔麦酒 | 普通 | 液体 | 免加工 | 1 | 源稿未写，按酒馆供给理解但未写入配置 |
| W03 | `brute_lava_firebrew` | 暴徒熔岩老火烧 | 稀有 | 液体 | 免加工 | 15 | 源稿未写，同上 |
| W05 | `griffin_sacred_wine` | 格里芬圣血祭酒 | 传奇 | 液体 | 免加工 | 不公开 | 源稿未写，同上 |
| C01 | `creamer_milk_tea_base` | 植脂末奶茶底 | — | — | — | — | 现实食材表无稀有度与形态列 |
| C02 | `industrial_green_tea` | 工业绿茶清汤 | — | — | — | — | 同上 |
| C03 | `mint_syrup` | 荧绿薄荷糖浆 | — | — | — | — | 同上 |
| C04 | `instant_coffee_concentrate` | 浓缩速溶咖啡原浆 | — | — | — | — | 同上 |
| C05 | `brown_sugar_boba` | 黑糖波霸珍珠 | — | — | — | — | 同上 |
| C06 | `mint_choc_crisp` | 代可可脂薄荷巧脆碎 | — | — | — | — | 同上 |
| C07 | `ice` | 冰块 | — | — | — | — | 同上 |
| C08 | `cocoa_powder` | 可可粉 | — | — | — | — | 同上 |
| C09 | `apple_jam` | 苹果果酱 | — | — | — | — | 同上 |
| C10 | `strawberry_jam` | 草莓果酱 | — | — | — | — | 同上 |
| H01 | `classic_boba_milk_tea` | 经典珍珠奶茶（成品） | — | — | — | — | 成品无图鉴描述，文案取配方表「风味特点」 |
| H02 | `mint_choc_milk_tea` | 薄荷巧脆奶茶（成品） | — | — | — | — | 同上 |
| H03 | `coffee_cocoa_ice_milk` | 咖啡可可冰奶（成品） | — | — | — | — | 同上 |
| H04 | `apple_milk_green_tea` | 苹果奶绿（成品） | — | — | — | — | 同上 |
| H05 | `strawberry_milk_green_tea` | 草莓奶绿（成品） | — | — | — | — | 同上 |
| H06 | `iced_mint_latte` | 冰吸薄荷拿铁（成品） | — | — | — | — | 同上 |

“—”表示源稿该行没有这一列（原料表没有标价，酒品表没有获取方式），不是漏填。

## 字段映射

| 源稿列 | 运行时字段（`IngredientDefinition`） | 处理方式 |
| --- | --- | --- |
| 原料ID / 酒品编号 | `source_ids` | 原样保留 `F01`、`W02` 这类编号，供反查与测试；一物多行时并列 |
| 食材正式名称 / 酒品名称 | `display_name` | 原文照抄 |
| 形态 | `form` | 原文照抄：液体、固体、胶体 |
| 支持加工方式 | `processing_methods` | 按源稿的「, 」拆成数组 |
| 稀有度档位 / 品质等级 | `rarity` | 只保留中文档位，`(T1)` 一类编码不入运行时 |
| 口感风味 | `flavor_tags` | 按「，」拆成短词，去掉句末句号 |
| 获取方式 | `acquisition_sources` | 整句照抄 |
| 图鉴描述 | `description` | 整段照抄，发现物品后才显示 |
| 标价（金币） | `price` | 整数金币；`0` 表示源稿没有公开标价（W05） |

## 重复登记的处理

F05 与 W02、F06 与 W04 是同一件东西在两张表各登记一次。运行时合并为一个物品，信息互补：

- 名称、稀有度、标价、口感、图鉴描述取自「酒品」表，因为该表才是带价格与品质等级的正式记录。
- 获取方式取自「原料配置表」，酒品表没有这一列。
- 两边的编号都写进 `source_ids`，可追溯回两行源稿。

## 美术资源

2026-10-18 已将 27 个明确对应的专属 PNG 同步绑定到两份菜单，覆盖六款 H 成品、九种 C 原料及十二种异世界原料/酒品。C09 苹果果酱仍沿用旧图标：来源只有「橘子果酱」，不直接替代。F01 苔痕青缺图；F02 窟窟糖芋和 F04 萤火伞仅提供多个未命名版本，暂保留原有图标。醒神菇使用包内明确命名的图片，其他版本保留。来源、尺寸与 SHA-256 见[本批素材清单](../assets/imports/user_assets_2026_10_18.md)。

## 未接入

| 源稿表 | 内容 | 未接入原因 |
| --- | --- | --- |
| 哥布林奶茶配方 P01–P10 | 仅 P 编号，其余 11 列全空 | 没有名称、原料、工艺与效果，无法生成资源 |
| 现实食材的稀有度与形态 | 10 行缺列 | 「现实食材」表只有 5 列，没有稀有度、形态与加工列，运行时留空，不猜测数值 |
| 酒品的获取方式 | 5 行缺列 | 「酒品」表没有获取方式列，运行时留空，不猜测来源 |
| 酒类定位（最低档日常酒、黑市私酿、祭祀特供等） | 5 条 | 运行时没有对应字段，已有类目、稀有度与标价足以覆盖当前仓库与制作用途；需要商店或见闻录消费时再加字段 |

## 消费方

- [WarehouseInventory](../../src/gameplay/milk_tea/warehouse_inventory.gd) 按菜单建立物品目录，负责数量与发现状态；`get_ingredient_view` 一并给出形态、加工、标价与图鉴描述。
- [WarehousePanel](../../src/UI/milk_tea/warehouse_panel.gd) 展示上述字段；详情按两列排版（左列弱化的字段名、右列值），风味与获取方式在取得实物时揭示，战斗属性与效果仍按发现组遮罩，未解锁显示 `???`，目录里为空的组不显示。
- [TeaProduction](../../src/gameplay/milk_tea/tea_production.gd) 允许把新材料当作自由组合原料；六款人类配方引用 C 系原料，异世界原料已可进入三槽自由配方（F09 等禁止项除外）；自由杯与固定 H 成品分别记录。
- [GatheringService](../../src/gameplay/gathering/gathering_service.gd) 已支持把采集点接到任意目录内原料；现有八个夜光菌丛采集点仍是醒神菇，未改动，因为酒馆委托 `tavern.insomnia_order` 依赖它们。
- [TeaRecipe](../../src/resources/milk_tea/tea_recipe.gd) 的 `required_flag` 决定配方是否进入会话目录：六款人类配方挂 `business.profile.day1`，[GameState](../../src/core/game_state.gd) 选到 day1 档案时发布该事实，教学会话看不到它们；血液特调同时要求 day1.s05.blood_acquired、day1.s05.returned_shop 和 S06 阶段；材料实际消耗仍由制作服务校验。
- 两个菜单资源必须同步：`basic_menu.tres` 是共享库存目录，`day1_menu.tres` 带正式订单队列，两者共用同一份配方簿，任何条目缺一处就会出现「菜单里有、仓库里查不到」。

## 待定

- 格里芬之血、幻彩小方、幻金菇的稀有度与图鉴描述目前随物品发现即显示。系统总纲要求关键属性首次显示为 `???`，稀有度尚不是独立解锁组，接入时需要先定揭示规则。
- 源稿里 `稀有(T2)` 与 `优秀(T2)` 并存，运行时按字面保留两个名字，尚未统一枚举档位。
