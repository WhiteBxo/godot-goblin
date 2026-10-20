# 2026-10-18 卷轴与格里芬剧情物品素材导入

本批来自用户 2026-10-18 提供的 1 个 ZIP（`好多猫鸡还是鸡猫(2).zip`）、2 张 PNG 和 1 张剪贴板 JPG，共 22 个文件。原始图片不裁切、不缩放、不重新编码；仅把 ZIP 内中文/提示词碎片文件名改为 ASCII，内容逐字节保留。本批只做导入与归类，**没有接线**：不改菜单、配方、任务、仓库界面、存档或任何 Actor 场景。

2026-10-19 分类更正：用户确认该 ZIP 图片是格里芬相关剧情物品素材，原按附件名暂称“猫鸡”的归类不准确。现已移到 `assets/story/griffin/`，候选文件前缀改为 `griffin_`；下表项目路径同步更新，原附件名、原始条目、图片字节与 SHA-256 保留。

## 来源与处理

ZIP 内文件名不带 UTF-8 标志，按 CP437 还原字节后以 UTF-8 解码；跳过目录、`__MACOSX/` 与 `._*`。方向帧直接使用原文件名（`east`、`north-east` 等）；其余 11 张原名是生成提示词碎片（`六`、`帘`、`精致的2`……），按内容 SHA-256 前 8 位重命名为 `griffin_<hash>.png`，映射见表。

## 归类

- **卷轴图标** → `assets/ui/story/scroll_icon.png`（32×32）。当前目录里没有对应的卷轴/文书物品定义，暂不绑定 `IngredientDefinition`。
- **格里芬之血（高清版）** → `assets/ui/milk_tea/ingredients/variants/day1_griffin_blood_64.png`（64×64）。现有运行时图标 `day1_griffin_blood.png` 仍是 32×32，本张作为变体保留，未替换；若要用作仓库详情图，需要先给定义加详情图字段或改引用。
- **格里芬剧情物品素材** → `assets/story/griffin/`：8 张 34×34 方向帧 + `variants/` 下 11 张 32×32 候选。映射与未接线说明见[格里芬素材 README](../../../assets/story/griffin/README.md)。
- **卷轴长图** → `docs/design/source/scroll_document_mockup_2026_10_18.jpg`（1329×764）。图上中文正文已烘焙进像素，只能作设计参考，不能当运行时背景配动态文本。

## 图片来源映射

| 原文件 | 项目路径 | 尺寸 | SHA-256 |
| --- | --- | --- | --- |
| `好多猫鸡还是鸡猫/2.5D_pixel_art_prop_sheet_Stardew_Valley_style._A.png` | `assets/story/griffin/variants/griffin_9f6d4fe8.png` | 32×32 | `9f6d4fe822113fa5c6d997d1e05650c62a0f207b64c2a8fd90690ecc4f6266a9` |
| `好多猫鸡还是鸡猫/east.png` | `assets/story/griffin/east.png` | 34×34 | `7a8fb6dc7e48768b88fb81a0aa5ab7602d71f0e73da92039e3a4837578350c2a` |
| `好多猫鸡还是鸡猫/north-east.png` | `assets/story/griffin/north-east.png` | 34×34 | `6c97326113c56c26e6aa398d6e1bc8c87723ea1917091e87d646186495604db8` |
| `好多猫鸡还是鸡猫/north-west.png` | `assets/story/griffin/north-west.png` | 34×34 | `ec3785740ffd815c206c14801de4288b884522f880b3ee5ac97ab8f9c7d23140` |
| `好多猫鸡还是鸡猫/north.png` | `assets/story/griffin/north.png` | 34×34 | `7efc1ea33bc9ac8bc6923454035e6ec0865c58e5b38afc5524c1b6e555e7d68b` |
| `好多猫鸡还是鸡猫/south-east.png` | `assets/story/griffin/south-east.png` | 34×34 | `c83875cda5c43b0f622ad82ebd5cc6e07c6d81d6c8a0c84b92bce95c8a046144` |
| `好多猫鸡还是鸡猫/south-west.png` | `assets/story/griffin/south-west.png` | 34×34 | `0f076b828bf51a6a9fda2ff40e33b86c4cb8f576215f60307db08a5170ccdccf` |
| `好多猫鸡还是鸡猫/south.png` | `assets/story/griffin/south.png` | 34×34 | `447443aae6d3e8649f42330add90e13bd5e62ceb0825449265778e305821f0b7` |
| `好多猫鸡还是鸡猫/west.png` | `assets/story/griffin/west.png` | 34×34 | `460ba3a8b7709d3be5d4ba1f067819a23d77d0ceb68416b03f969c9f49fa6126` |
| `好多猫鸡还是鸡猫/五.png` | `assets/story/griffin/variants/griffin_e3bb0779.png` | 32×32 | `e3bb07790a29b298197fbac713bcac3efb65ca6dc1e78bd79f31dd56b44cf56f` |
| `好多猫鸡还是鸡猫/六.png` | `assets/story/griffin/variants/griffin_1246ecf5.png` | 32×32 | `1246ecf5e5eccaac0c5c175b66cd089f7465d32a0e119a55c423881ec2e8fdc6` |
| `好多猫鸡还是鸡猫/布.png` | `assets/story/griffin/variants/griffin_239aedcd.png` | 32×32 | `239aedcd8a437880a1b58b95ddb1174dfe2d72ff8548acedf6e977e0e16f7233` |
| `好多猫鸡还是鸡猫/帘.png` | `assets/story/griffin/variants/griffin_8c2f499b.png` | 32×32 | `8c2f499bac259ef93e4c3b1c54e3540a62e7c16cb71a1b9b2e40768afd0b8905` |
| `好多猫鸡还是鸡猫/的.png` | `assets/story/griffin/variants/griffin_1e7ecb4e.png` | 32×32 | `1e7ecb4e31a3ad9481bb8515ffe5a80ba2b7fc86259daf04f52a4faf7c030d3b` |
| `好多猫鸡还是鸡猫/破.png` | `assets/story/griffin/variants/griffin_bdc4d020.png` | 32×32 | `bdc4d0208bfeed2d25ed53a135d19c97726ced0eb93535e3881c38ef415316be` |
| `好多猫鸡还是鸡猫/精致的.png` | `assets/story/griffin/variants/griffin_c1886523.png` | 32×32 | `c18865232d2f09400c5c3bc68e92fcc6fb9b095d86353817cb67570f208cbab6` |
| `好多猫鸡还是鸡猫/精致的2.png` | `assets/story/griffin/variants/griffin_e0ba6bf3.png` | 32×32 | `e0ba6bf32de5218fe4ebc6f4a78252e191bb880ef2b8299b6bfdbd62371fa1ef` |
| `好多猫鸡还是鸡猫/色.png` | `assets/story/griffin/variants/griffin_6b0f7677.png` | 32×32 | `6b0f7677a0181c91aacb6ddee6332c5ea5e5b430921995aca30714cff71dc8a4` |
| `好多猫鸡还是鸡猫/颜.png` | `assets/story/griffin/variants/griffin_5b5b3811.png` | 32×32 | `5b5b38115d7c5fb443ed4a152f909fffe44882d713f8e69752c2a232e4add6f7` |
| `卷轴(2).png` | `assets/ui/story/scroll_icon.png` | 32×32 | `d30311e2d65acede27aa437f8405f46b5698f31eec03b68aa2c7ae546f99083f` |
| `格里芬之血(2).png` | `assets/ui/milk_tea/ingredients/variants/day1_griffin_blood_64.png` | 64×64 | `98b98b177f4e447218d7d86ff8ae4d7a960794e8065bd2aa05c6076f62e06113` |
| 剪贴板图片 `clipboard-2026-10-18T14-53-14-679Z-c1879ba5.jpg` | `docs/design/source/scroll_document_mockup_2026_10_18.jpg` | 1329×764 | `08264a1abfe394bf9f686baef02cd78132ef9d6400d597a310022c19ee69c7ea` |

## 导入设置

图片使用 Godot 默认 Texture2D 导入（`compress/mode=0` 无损、`mipmaps/generate=false`），随图提交 `.import`；像素显示沿用项目 CanvasItem 的最近邻过滤，不在导入配置里另设过滤参数。依据 [Godot 4.7 图片导入文档](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html)。
