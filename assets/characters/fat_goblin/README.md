# 胖哥布林立绘（专属）

来源：用户于 2026-10-16 提供的「胖哥布林与主角立绘」附件，原始文件逐字节保留，导入记录见 [用户素材导入](../../../docs/assets/imports/user_assets_2026_10_17.md)。素材授权以用户提供为准。

| 文件 | 用途 |
| --- | --- |
| `fat_goblin_smiling.png` | 原始白底立绘（微笑） |
| `fat_goblin_laughing.jpg` | 原始白底立绘（大笑） |
| `fat_goblin_smiling_portrait.png` | 对话用透明 RGBA 微笑立绘 |
| `fat_goblin_laughing_portrait.png` | 对话用透明 RGBA 大笑立绘 |
| `source/fat_goblin_img_6420.jpeg` | 附件原始编号图，保持不变 |

## 使用范围

这四张图是 `fat_goblin` 这一名角色的专属形象，对应 `character_catalog.json` 的 `fat_goblin`（显示名「胖哥布林」），由 `src/core/dialogue/dialogue_manager.gd` 的 `speaker_portraits["胖哥布林"]` 引用。

- 普通哥布林（`common_goblin` 及剧情中的哥布林甲/乙/丙、哥布林顾客等）与酒馆老板、赌场老板没有立绘，对白中只显示姓名与文本，**不得**借用这套图充数。
- 新增角色需要立绘时，先在 `assets/characters/` 下建立自己的目录并入图，再接 `speaker_portraits`；不要复用本目录文件。
- `tests/verify_dialogue.gd` 会检查非「胖哥布林」说话人没有配置该立绘，改动映射前先看该断言。

处理方式见 [角色 README](../README.md)：透明派生图用同一段去除白底和地面阴影的提示词生成，原图不被覆盖。重新导入可在项目根目录执行 `godot --headless --editor --path . --quit`。
