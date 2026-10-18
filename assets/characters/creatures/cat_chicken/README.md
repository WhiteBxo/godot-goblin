# 猫鸡素材（2026-10-18 导入）

来源为用户 2026-10-18 提供的 `好多猫鸡还是鸡猫(2).zip`。19 张 PNG 按原始字节保存，不裁切、不缩放、不重新编码；ZIP 文件名按 CP437 → UTF-8 还原后重命名为 ASCII。

- **方向帧**：`east` / `north-east` / `north` / `north-west` / `west` / `south-west` / `south` / `south-east`，34×34，屏幕方向命名（北=上）。
- **候选变体**：`variants/` 下 11 张 32×32，原名是生成提示词碎片，改用内容哈希命名。
- **未接线**：当前没有 Actor、NPC 场景或动画图集引用这些图片，也没有生成 SpriteFrames。接入前先确认角色身份、比例与图集切分方式，见 [角色资源说明](../../README.md) 与 [人物接入规范](../../../../docs/assets/characters.md)。

| 原始文件名 | 项目路径 | 尺寸 |
| --- | --- | --- |
| `east.png` | `east.png` | 34×34 |
| `north-east.png` | `north-east.png` | 34×34 |
| `north.png` | `north.png` | 34×34 |
| `north-west.png` | `north-west.png` | 34×34 |
| `west.png` | `west.png` | 34×34 |
| `south-west.png` | `south-west.png` | 34×34 |
| `south.png` | `south.png` | 34×34 |
| `south-east.png` | `south-east.png` | 34×34 |
| `六.png` | `variants/cat_chicken_1246ecf5.png` | 32×32 |
| `帘.png` | `variants/cat_chicken_8c2f499b.png` | 32×32 |
| `颜.png` | `variants/cat_chicken_5b5b3811.png` | 32×32 |
| `色.png` | `variants/cat_chicken_6b0f7677.png` | 32×32 |
| `五.png` | `variants/cat_chicken_e3bb0779.png` | 32×32 |
| `的.png` | `variants/cat_chicken_1e7ecb4e.png` | 32×32 |
| `布.png` | `variants/cat_chicken_239aedcd.png` | 32×32 |
| `破.png` | `variants/cat_chicken_bdc4d020.png` | 32×32 |
| `精致的.png` | `variants/cat_chicken_c1886523.png` | 32×32 |
| `精致的2.png` | `variants/cat_chicken_e0ba6bf3.png` | 32×32 |
| `2.5D_pixel_art_prop_sheet_Stardew_Valley_style._A.png` | `variants/cat_chicken_9f6d4fe8.png` | 32×32 |

完整 SHA-256 与同批其他素材见 [导入记录](../../../../docs/assets/imports/2026-10-18_story_and_creature_assets.md)。

导入使用 Godot 默认 Texture2D 设置（无损压缩、关闭 mipmaps），随图提交 `.import`；像素显示沿用项目 CanvasItem 的最近邻过滤，不在图片导入配置里另设过滤参数。
