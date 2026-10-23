# 2026-10-23 补充食材贴图导入

来源：用户提供的 `补充食材贴图(1).zip`。原 PNG 字节完整保留，不裁切、不重编码、不缩放；跳过 `__MACOSX` 元数据。ZIP 文件名按 CP437 → UTF-8 还原。附件未附独立许可证，不据此推定额外授权。

压缩包 SHA-256：`21c2ff5015142b2e67f6c142ef3d55f09c4ba8339f5db008a47c3303d1ee25b4`。

8 张图均为 32×32，接入 `basic_menu.tres` 与正式流程的 `day1_menu.tres`，供库存、原料图鉴及制作界面读取。苹果酱对应现有物品 `apple_jam`（苹果果酱）；茉莉绿茶对应 `green_tea`，不替换另一个物品“工业绿茶清汤”。苔痕青的物品图标改用本批独立图片，地图采集点继续使用既有图集裁片。旧 SVG 保留。

| ZIP 内原文件名（均在 `补充食材贴图/`） | 物品 ID | 项目文件 | SHA-256 |
| --- | --- | --- | --- |
| 糖浆.png | `syrup` | [syrup.png](../../../assets/ui/milk_tea/ingredients/syrup.png) | `2de43359b9214b267ec2c437f9c0a8c3049ba8791793ddadbac7ef151f1409d8` |
| 苹果酱.png | `apple_jam` | [apple_jam.png](../../../assets/ui/milk_tea/ingredients/apple_jam.png) | `537a8201a53f6185b143946f533e0767ae197a81c2a0bf93c135483b3e3b161f` |
| 奶精.png | `creamer` | [creamer.png](../../../assets/ui/milk_tea/ingredients/creamer.png) | `3b033210b3ea2c344e3279b39f0c7b1d35884435d15335fd186bf740205d030a` |
| 苔痕青.png | `moss_green` | [moss_green.png](../../../assets/ui/milk_tea/ingredients/moss_green.png) | `4c8f4332d6ec95820600d1a865773e2a4091f2f43ddc028bdf7643c4b560c33e` |
| 红茶.png | `black_tea` | [black_tea.png](../../../assets/ui/milk_tea/ingredients/black_tea.png) | `fd1d5101faf1c1d2e00f88c9ab1de9b831133631f17add5e1de6e9bdc37ab8d4` |
| 椰果.png | `coconut` | [coconut.png](../../../assets/ui/milk_tea/ingredients/coconut.png) | `945600b4b5e490881bc898e3b3e36b78cd2d7d2f3ef7f3afcde812c3abe8e593` |
| 珍珠.png | `pearl` | [pearl.png](../../../assets/ui/milk_tea/ingredients/pearl.png) | `8910c4b9c979bca44096081d1b2a29b86d23557144064a7ad732e7341a52356e` |
| 茉莉绿茶.png | `green_tea` | [green_tea.png](../../../assets/ui/milk_tea/ingredients/green_tea.png) | `479de2a3e242ea9bdb5399021d23d4478940afb5e7fecdd0400257d39e4dd853` |

复现：按上表将 ZIP 中对应 PNG 原样写入项目路径，再由 Godot 4.7 编辑器导入生成 `.import` 设置。游戏内取得／发现相应物品后，在库存或原料图鉴选择条目，可看到新的列表图标与详情图。初始库存、发现规则、配方与物品属性保持原配置。

## 实际验证

- 8 张 PNG 与 ZIP 内原图逐字节一致；来源链接与 Git diff 格式检查通过。
- Godot 4.7.2 资源导入退出码 0，生成 8 份 `.import` 设置；编辑器退出时仍有既有 495 个 ObjectDB 实例 / 10 个资源未清理提示。
- OpenGL 实际渲染验证通过：两份菜单共 16 处图标绑定、8 个物品的库存列表与详情选择、原料图鉴展示，以及工业绿茶清汤的原图引用。对比 HEAD，所有物品的非图标字段保持一致。
- `python tools/milk_tea/import_recipe_ingredients.py --check` 仍报告两份菜单 STALE（22 行），与本次之前已确认的结果相同，未扩大任务修改食材数据。
- 本次仅替换图片引用，未运行完整玩法回归。纹理作为现有 `Texture2D` 字段直接接入，用法见 [Godot 4.7 Texture2D](https://docs.godotengine.org/en/4.7/classes/class_texture2d.html)。
