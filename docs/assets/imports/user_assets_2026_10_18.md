# 2026-10-18 奶茶与原料素材导入清单

本批来自用户提供的四个 ZIP、一个 DOCX 和一个 Excel。38 个有效图片条目按内容去重为 36 张 PNG；两包重复的老火烧和琥珀酒复用同一路径。原始图片不裁切、不缩放、不重新编码。27 个明确对应的图标已同步到 basic_menu 与 day1_menu，未改配方、属性、价格、库存或解锁条件。

## 来源与处理

来源为用户提供附件，未附独立授权文件，本记录不推定额外的第三方许可。ZIP 按 UTF-8 标志或 CP437 还原字节后解码 UTF-8；跳过目录、`__MACOSX/` 与 `._*`。人类饮品原文件名含 CR/LF，重命名为运行时 ID 的英文文件名；酒品文件名尾部「2」不视为新物品。异世界原料中的不明版本保留 pixellab 标识，不推断加工状态。

- 成品放 `assets/ui/milk_tea/products/`；原料、酒品放 `assets/ui/milk_tea/ingredients/`；未明确用途的版本放其 `variants/`。
- 橘子果酱保留为 `orange_jam.png`，不冒充配置中的苹果果酱；苔痕青缺图。窟窟糖芋和萤火伞版本暂不绑定。
- 旧 SVG 仍保留：教学物品仍有引用，也可作历史占位资源；只替换与新素材明确对应的现有目录项。
- DOCX/Excel 保留原始字节于 `docs/design/source/`；正文与表格快照、旧稿关系及设计差异见[更新说明](../../design/milk_tea_recipe_update_2026_10_18.md)。原始 DOCX 内的 12 张表格预览图原样提取到 `docs/design/captures/milk_tea_recipe_system/`，未生成新的表格截图。

图片使用 Godot 默认 Texture2D 无损导入、关闭 mipmaps，提交相应 `.import`；过滤模式遵循项目现有 CanvasItem 设置，不在图片导入配置里虚构过滤参数。依据 [Godot 4.7 图片导入文档](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html)。

## 图片来源映射

| 原始 ZIP | 包内路径 | 项目路径 | 尺寸 | SHA-256 |
| --- | --- | --- | --- | --- |
| 人类奶茶.zip | `人类奶茶/经典珍珠奶茶\r\n.png` | `assets/ui/milk_tea/products/classic_boba_milk_tea.png` | 32×32 | `97473f6839ae1650b7d3a95149650416a1e7e1b9b109dbf9addc91a397cdc88c` |
| 人类奶茶.zip | `人类奶茶/草莓奶绿\r\n.png` | `assets/ui/milk_tea/products/strawberry_milk_green_tea.png` | 32×32 | `e428270da75bc04ccaa73798dd5c59c11042076c94224feee84ecf3461054f52` |
| 人类奶茶.zip | `人类奶茶/冰吸薄荷拿铁\r\n.png` | `assets/ui/milk_tea/products/iced_mint_latte.png` | 32×32 | `1460bf197bbd0f42a9d58e1fb6d42996f04c29fcc5371e1b1d56078e6523aae0` |
| 人类奶茶.zip | `人类奶茶/苹果奶绿\r\n.png` | `assets/ui/milk_tea/products/apple_milk_green_tea.png` | 32×32 | `55d8a2019c89540830454a70a2315c1913c601145f044eaba80e2335596d2931` |
| 人类奶茶.zip | `人类奶茶/咖啡可可冰奶\r\n.png` | `assets/ui/milk_tea/products/coffee_cocoa_ice_milk.png` | 32×32 | `98db2fdfa1966d38ff54646dc8da9cf1459593edd7e8bda61809580d94dce833` |
| 人类奶茶.zip | `人类奶茶/薄荷巧脆奶茶\r\n.png` | `assets/ui/milk_tea/products/mint_choc_milk_tea.png` | 32×32 | `b0ef7a0ed43315509cf8ca8dd70517601ea68909a3b13a56eabdef2555428a66` |
| 哥布林酒品.zip | `哥布林酒品/暴徒熔岩老火烧.png` | `assets/ui/milk_tea/ingredients/brute_lava_firebrew.png` | 32×32 | `79d38c218d78fb1c4b58f9777908c3576d47d849e58fd188f2e38f7eafbe2810` |
| 哥布林酒品.zip | `哥布林酒品/纯正哥布林老火烧 2.png` | `assets/ui/milk_tea/ingredients/goblin_firebrew.png` | 32×32 | `4ff7cf140804666fedc127cade9a997dcc0083fdb8a31a4ff45a9d0bd09c2aac` |
| 哥布林酒品.zip | `哥布林酒品/格里芬圣血祭酒.png` | `assets/ui/milk_tea/ingredients/griffin_sacred_wine.png` | 32×32 | `b73206df0a8acc9232cb9d6bd6b889fc45765ded5dae60bf966f26897ae40092` |
| 哥布林酒品.zip | `哥布林酒品/格里芬琥珀酒 2.png` | `assets/ui/milk_tea/ingredients/griffin_amber_wine.png` | 32×32 | `a6f07bd49a831bb0ea89cfe14c467b9e26cde4e6969b34b47213787c4bb33392` |
| 哥布林酒品.zip | `哥布林酒品/劣质酸苔麦酒.png` | `assets/ui/milk_tea/ingredients/sour_moss_ale.png` | 32×32 | `d3660d98663d4a60515311b2e71d73b3dee14337f0ffcd83d60ce342131dbb57` |
| 异世界原料.zip | `异世界原料/炽舌椒.png` | `assets/ui/milk_tea/ingredients/scorch_tongue_pepper.png` | 32×32 | `a17e9b2cb83162ab946b3d81c45a62b4ab44071ef761c2cdde36b91d60967fa3` |
| 异世界原料.zip | `异世界原料/格里芬琥珀酒.png` | `assets/ui/milk_tea/ingredients/griffin_amber_wine.png` | 32×32 | `a6f07bd49a831bb0ea89cfe14c467b9e26cde4e6969b34b47213787c4bb33392` |
| 异世界原料.zip | `异世界原料/蜜珀晶.png` | `assets/ui/milk_tea/ingredients/honey_amber_crystal.png` | 32×32 | `107efd1903215280b10257b3eea6d881c5079e1d940fb04bf351f0392d26f63d` |
| 异世界原料.zip | `异世界原料/幻金菇.png` | `assets/ui/milk_tea/ingredients/phantom_gold_mushroom.png` | 48×48 | `558afda5978b298d0d0b35b1bdfb15b1ccfa4c9b1ee89556cc017e0d7c8dbfd1` |
| 异世界原料.zip | `异世界原料/格里芬之血.png` | `assets/ui/milk_tea/ingredients/day1_griffin_blood.png` | 32×32 | `c2526fbe7effe022c40c5ba0dd8ac75f8a90fa327034b4481ee02ab167008808` |
| 异世界原料.zip | `异世界原料/纯正哥布林老火烧.png` | `assets/ui/milk_tea/ingredients/goblin_firebrew.png` | 32×32 | `4ff7cf140804666fedc127cade9a997dcc0083fdb8a31a4ff45a9d0bd09c2aac` |
| 异世界原料.zip | `异世界原料/幻彩小方.png` | `assets/ui/milk_tea/ingredients/rainbow_cube.png` | 32×32 | `53c7674b3fdd0802041510a57e1d8b878a4bb7ba66f4d356f418bee6169141fe` |
| 异世界原料.zip | `异世界原料/红斑咬木.png` | `assets/ui/milk_tea/ingredients/red_mottled_wood.png` | 32×32 | `b360e498c50ad736b2056fc2c367d17aab4aa776453a8acadcff03242ee57f93` |
| 异世界原料.zip | `异世界原料/醒神菇/pixellab-object-ecfa90e2.png` | `assets/ui/milk_tea/ingredients/variants/insomnia_mushroom_ecfa90e2.png` | 48×48 | `7eb578d58d8f6b9bb094acfd639d0071cb44c97f285a27da90952e1857c9eb48` |
| 异世界原料.zip | `异世界原料/醒神菇/醒神菇.png` | `assets/ui/milk_tea/ingredients/insomnia_mushroom.png` | 32×32 | `a692c52ec5d910f055f7bf182edf9a06edd4f8acff86b3fbe01e536432b9239a` |
| 异世界原料.zip | `异世界原料/醒神菇/pixellab-object-6c36a3dc.png` | `assets/ui/milk_tea/ingredients/variants/insomnia_mushroom_6c36a3dc.png` | 48×48 | `ee064a0cd15fb4bc2b4f9bade4b8809d1279feb8841eb1c0d523186d541e36c0` |
| 异世界原料.zip | `异世界原料/醒神菇/pixellab-object-cf17c46e.png` | `assets/ui/milk_tea/ingredients/variants/insomnia_mushroom_cf17c46e.png` | 48×48 | `6500c61aa0a84d7cfaf697f4d72637bec3d63e3c3aeff799aa1bc4b1f89141e5` |
| 异世界原料.zip | `异世界原料/萤火伞/pixellab-object-2615bab7.png` | `assets/ui/milk_tea/ingredients/variants/firefly_cap_2615bab7.png` | 48×48 | `004df9a4cab6fbcea1e437557ee253a15abaeaccdfc7d903e9ef314bd15c03e5` |
| 异世界原料.zip | `异世界原料/萤火伞/pixellab-object-c29a126c.png` | `assets/ui/milk_tea/ingredients/variants/firefly_cap_c29a126c.png` | 48×48 | `612351f3970e063f13921083a76bf24147555fc6bd3850a29d743154f1986255` |
| 异世界原料.zip | `异世界原料/萤火伞/pixellab-object-cfbac151.png` | `assets/ui/milk_tea/ingredients/variants/firefly_cap_cfbac151.png` | 48×48 | `2b9414778d68497128431fa417b992b6b7cbd4472526b74130a55cec3df6ee02` |
| 异世界原料.zip | `异世界原料/窟窟糖芋/pixellab-object-b1d70e61.png` | `assets/ui/milk_tea/ingredients/variants/sugar_yam_b1d70e61.png` | 32×32 | `7b63cbdb770286c59a725ae9c7ce455383b9d7d5eb0860d044290eb2d45ae4b9` |
| 异世界原料.zip | `异世界原料/窟窟糖芋/pixellab-object-2f72a1ed.png` | `assets/ui/milk_tea/ingredients/variants/sugar_yam_2f72a1ed.png` | 32×32 | `55b3b72dfa7d2d4e15218ca54d0747c82a7636800873f106e3249a3c5c125243` |
| 现实食材.zip | `现实食材/黑糖波霸珍珠.png` | `assets/ui/milk_tea/ingredients/brown_sugar_boba.png` | 32×32 | `8910c4b9c979bca44096081d1b2a29b86d23557144064a7ad732e7341a52356e` |
| 现实食材.zip | `现实食材/植脂末奶茶底.png` | `assets/ui/milk_tea/ingredients/creamer_milk_tea_base.png` | 32×32 | `6ab63cd26ae82f77b9cf680a999461d9ff7724ebb83c04961bd3b947f067f76c` |
| 现实食材.zip | `现实食材/浓缩速溶咖啡原浆.png` | `assets/ui/milk_tea/ingredients/instant_coffee_concentrate.png` | 32×32 | `714ae8a3a857087612274a820b7e9e9b851871c64436966d649904368bc28af2` |
| 现实食材.zip | `现实食材/橘子果酱.png` | `assets/ui/milk_tea/ingredients/orange_jam.png` | 32×32 | `1d188bf8d82356609d6384f21494befe79152051fdc1f19b9286d3deee5a08a1` |
| 现实食材.zip | `现实食材/工业绿茶清汤.png` | `assets/ui/milk_tea/ingredients/industrial_green_tea.png` | 32×32 | `f7173c6f7b8f85577e6708702cea2d3d55c99e68e2bccaf9b5b221bfbe7aa71b` |
| 现实食材.zip | `现实食材/可可粉.png` | `assets/ui/milk_tea/ingredients/cocoa_powder.png` | 32×32 | `fd725a2bf67006483b13b251371672f53fe2e054c5aaab6048a7bfc937aee543` |
| 现实食材.zip | `现实食材/代可可脂薄荷巧脆碎.png` | `assets/ui/milk_tea/ingredients/mint_choc_crisp.png` | 32×32 | `a3db6b7d72d9ae409fa7a64870194fa2cd9a9addbf45690063cdced0db4c81db` |
| 现实食材.zip | `现实食材/冰块.png` | `assets/ui/milk_tea/ingredients/ice.png` | 32×32 | `7cc9aa25535b4eef4de65922f3bd68ea3a7d296a4978d89bf93f64c2ccb963eb` |
| 现实食材.zip | `现实食材/荧绿薄荷糖浆.png` | `assets/ui/milk_tea/ingredients/mint_syrup.png` | 32×32 | `f1d61f04a435bec5003867d47767123b2510b28d3512e502f52ce4e576089c1a` |
| 现实食材.zip | `现实食材/草莓果酱.png` | `assets/ui/milk_tea/ingredients/strawberry_jam.png` | 32×32 | `41d0596777e0aa8cca26d98229b6087e21310df92f78b18e80c6cd8615daaa01` |

## 文档附件

| 原始文件 | 项目路径 | SHA-256 |
| --- | --- | --- |
| （更新版）🧋奶茶配方系统设计文档+(1).docx | `docs/design/source/milk_tea_recipe_system_revised_2026_10_18.docx` | `16555351585061b36cca72a9c3f3ba3dcee538a360a5bd4e8c94813278ab5a5d` |
| （更新版）🧋异世界食材与酒水配置表_哥布林奶茶配方+(1).xlsx | `docs/design/source/recipe_ingredients_revised_2026_10_18.xlsx` | `715c9ae438b0076ce0dd800e946c431bb88f797c26da59d9c7d0cf8e7c4b4788` |

## 局部验证与查看入口

本次只改变图标引用。校验源文件哈希、PNG 解码与尺寸、所有新增引用、两份菜单绑定一致性、Markdown 相对链接与 diff；运行 Godot 资源导入及 `tests/verify_otherworld_catalog.gd` 检查目录可解析。具体执行结果以本次交付汇报为准。

编辑器 FileSystem 中可直接预览 `assets/ui/milk_tea/products/` 和 `ingredients/`。游戏内通过已有仓库查看已发现的对应条目；新物品初始未发现时不会仅因补图而出现。未做人工 F6 交互验收，不将静态检查作为试玩通过。

## 本次实际检查结果

- 38 个包内图片条目与 36 张入库 PNG 哈希对应；两个原始文档与下载文件逐字节一致。12 张 DOCX 原表预览图与原文件一致，另从其内嵌工作表转录完整单元格，补足预览中被裁掉的内容。
- 修改的 Markdown 相对链接、文本格式与 `git diff --check` 通过。两份菜单除图标及纹理声明外，其余运行时字段保持一致。
- Godot 4.7.2 完成 36 张新 PNG 导入；直接加载检查通过 36 张纹理和两份菜单各 27 个一致的图标绑定。
- `verify_otherworld_catalog.gd`：`OTHERWORLD_CATALOG: PASS (291 checks)`。
- 首轮导入在扫描 autoload 时出现新纹理尚未导入的加载报错，导入完成后的直接加载检查已通过。环境还报告 macOS 系统证书读取、沙箱外日志和编辑器设置写入失败，以及编辑器退出资源泄漏诊断；这些诊断未作为通过项。
- 未运行完整回归或人工 F6：本次没有更改玩法规则和状态契约。原始 DOCX/Excel 未重新排版或导出，不将其原有版式描述为本次修复。
