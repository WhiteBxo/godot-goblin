# 设计原始附件

原始附件保持上传内容，不在源文件内改写数值、布局或备注。设计规则与当前运行时能力分开记录。

| 文件 | 用途与版本关系 |
| --- | --- |
| [爆品配方开发可视版](signature_recipes_development_2026_10_19.xlsx) | 2026-10-19 用户新附件；S01–S10 共 10 款、15 字段。完整转录与规则差异见[爆品配置](../signature_recipes_revised.md)，未接入运行时。 |
| [2.0 原料配置表](recipe_ingredients_revised_2026_10_19.xlsx) | 2026-10-19 用户新附件，22 条有效原料、21 字段；相比 10-18 只修正七项等级编号。可读现行表见[原料配置](../recipe_ingredients_revised.md)。 |
| [经营与战斗经济 PDF](milk_tea_economy_revised_2026_10_19.pdf) | 2026-10-19 用户新附件，17 页；现行整理、源内冲突见[经济规则](../milk_tea_economy_revised.md)，实施安排见[实现方案](../milk_tea_economy_implementation_plan.md)。 |
| [奶茶配方系统 V0.1 DOCX](milk_tea_recipe_system_revised_2026_10_18.docx) | 2026-10-18 新增的配方专项设计；含 12 个内嵌 Excel 表对象。可读转录见[正文](../milk_tea_recipe_system_revised.md)。 |
| [10-18 原料规则表](recipe_ingredients_revised_2026_10_18.xlsx) | 旧来源原样保留；22 种原料、21 字段。当前运行时导入器仍读取此版本；现行设计表已切到 10-19。 |
| [食材与酒水旧表](otherworld_ingredients_and_drinks.xlsx) | 2026-10-17 导入的运行时来源基线，保留 W/H 配方和图鉴等互补信息；重叠原料设计以更新表为准。 |
| [Day 2 剧情 PDF](day_02.pdf) | 剧情原稿，本批未更改。 |
| [卷轴文书设计稿](scroll_document_mockup_2026_10_18.jpg) | 2026-10-18 的 1329×764 卷轴示意图，正文已烘焙进像素，仅作参考；同批素材归类见[导入记录](../../assets/imports/2026-10-18_story_and_creature_assets.md)。 |

10-18 表 22 种原料的现有导入、自由配方和图鉴分别见[数据层](../../gameplay/milk_tea_recipe_data.md)与[自由配方](../../gameplay/free_tea_recipes.md)。本次爆品新表仅归档与转录，尚未进入运行时；10-18 当时范围保留在[历史更新说明](../milk_tea_recipe_update_2026_10_18.md)。

## 2026-10-19 来源核对

| 仓库归档名 | 用户文件原名 | SHA-256 |
| --- | --- | --- |
| `signature_recipes_development_2026_10_19.xlsx` | `异世界食材与酒水配置表_爆品配方（开发可视版）(1).xlsx` | `316be164015fd54bb30e974c50131a3fa9891b16a2acf9a00b7d4be2104ba444` |
| `recipe_ingredients_revised_2026_10_19.xlsx` | `🧋（2.0）异世界食材与酒水配置表_哥布林奶茶配方+(1).xlsx` | `9f04503d05c74a031d9d79aec5c04bd0d2bec98c0f6df72d81a598b40fea10b7` |
| `milk_tea_economy_revised_2026_10_19.pdf` | `💸奶茶店经济系统与战斗奶茶定价规则.pdf` | `0eec717229865c7fc1c874ae2bd4ee998473d4f3da07c12085e06176bb813b30` |

归档仅规范文件名，内容逐字节保留。PDF 的定价表、固定菜单及 Day 1–4 流程表包含图片表格，已结合页面图像核对，不能仅凭纯文本提取跳过表格。
