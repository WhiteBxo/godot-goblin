# 角色原始插画

以下四张图片来自用户于 2026-10-16 提供的附件，按角色分类并改为可读文件名。原始文件逐字节保留，包含原始格式、尺寸、白色背景及表情图中的文字。对话使用下文的独立透明派生素材，未替换玩家动画。

| 项目文件 | 原附件文件名 | 内容 |
| --- | --- | --- |
| `apron_man/apron_man_full_body.jpg` | `238e33c7bf6cde8e5bf763c5d46dca8e.jpg` | 围裙男子全身立绘 |
| `apron_man/apron_man_expressions.jpg` | `b4f68f2503831f993770fce2170d0dc2.jpg` | 围裙男子六种表情，保持整图 |
| `fat_goblin/fat_goblin_smiling.png` | `4999cd3e056940b8f652e8346cc89858.png` | 胖哥布林微笑立绘 |
| `fat_goblin/fat_goblin_laughing.jpg` | `06c4342a5b0035de16f04cc441012206.jpg` | 胖哥布林大笑立绘 |

随图提交 Godot 生成的 `.import` 设置；`.godot/` 下的派生缓存由编辑器重新生成。使用默认的 2D Texture2D 导入、无损压缩和关闭 mipmaps，避免再次有损压缩插画。现有玩家动画素材说明见 `player/README.md`。

对话立绘已由 `src/core/dialogue/dialogue_manager.gd` 的 `speaker_portraits` 接入：主角（含内心独白）使用 `apron_man/player_neutral_portrait.png`，胖哥布林使用 `fat_goblin/fat_goblin_smiling_portrait.png`；单句可指定 `fat_goblin/fat_goblin_laughing_portrait.png`。`fat_goblin/` 内的四张图是**胖哥布林专属**，普通哥布林（`common_goblin` 及其甲/乙/丙、顾客）与酒馆、赌场老板使用各自独立立绘，不得复用这套图，详见 [立绘专属说明](fat_goblin/README.md)。这三张为透明 RGBA PNG，原始图片和六表情整图保留。主角在左侧、NPC 在右侧，图片下半身被对话框遮住。规则与试玩入口见 [对话系统](../../docs/systems/dialogue_system.md)。

透明派生素材于 2026-10-16 使用内置 imagegen 编辑模式分别处理对应原图。每张使用相同提示词，可从原图重新执行；生成式编辑可能存在细微笔触变化，应以已提交 PNG 为显示依据：

> Edit target: the supplied character illustration. Remove ONLY the white background and all ground shadows / ground marks outside the character, creating a clean transparent RGBA cutout of the complete full-body character. Preserve the exact original character identity, facial expression, pose, silhouette, clothing, colors, ink outlines, proportions, and illustration style. Do not redesign, mirror, crop limbs, or add anything. Tight framing around the full character with only a small transparent margin. Output a single character on genuine transparent background, no checkerboard painted into the image.

在 Godot FileSystem 面板打开对应图片，可检查立绘和表情整图。重新导入可在项目根目录执行 `godot --headless --editor --path . --import --quit`（`godot` 需指向本机 Godot 4.7 可执行文件）。

导入规则参照 [Godot 4.7 官方图片导入文档](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html)：JPEG 与 PNG 均可作为 Texture2D 导入，JPEG 格式不支持透明通道。

## 游戏人物场景

全部 31 张 NPC 动画图集已接入 8 类可复用人物场景，按剧情身份放入聚落并注册给 ActorDirector。人物映射、缺帧 fallback、F6 预览入口和再生成方式见 [游戏人物说明](../../docs/assets/characters.md)。

## 攻击与无背包走路动画

2026-10-17 附件已导入为四套 SpriteFrames，共 15 段动作、159 帧；来源映射、F6 预览、播放约定和复现命令见 [哥布林动作资源](goblin_actions/README.md)。

## 普通顾客走路与待机

2026-10-17 用户附件已导入男、女顾客 12 张原始图集。正式人类顾客现于生成时按男、女各 50% 选择外观，同一实例保持外观；女顾客也保留独立复用场景。来源、逐帧映射、复现命令与 F6 入口见
[普通顾客素材接入](../../docs/assets/characters.md#普通男女顾客2026-10-17)。

2026-10-19 新增用户提供的守卫、酒馆老板、赌场老板、普通顾客及胖哥布林不适立绘，来源和裁边处理见 [对话立绘](dialogue/README.md)。对话插画与地图像素小人、头像分别使用。

## 赌场侍卫（2026-10-19）

`侍卫2(1).zip` 已接入独立赌场侍卫，三向行走与立绘均使用附件原图，原守卫继续使用自己的素材；切帧、来源与预览见 [侍卫说明](npc/casino_sentry/README.md)。当前尚未进入正式流程的角色素材见 [使用盘点](../../docs/assets/characters.md#角色素材使用盘点2026-10-19)。

## 格里芬剧情物品素材归类更正（2026-10-19）

用户确认原按附件名暂称“猫鸡”的图片属于格里芬相关剧情物品，已移至 `assets/story/griffin/`，不计入人物素材；来源与用途边界见 [格里芬素材说明](../story/griffin/README.md)。

## 聚落补充与儿童（2026-10-20）

已保留侍卫、祈祷者、酒鬼旧 / 修订版、小男孩和女孩六包的 46 张原 PNG，并接入八类人物。原图放各 `npc/<角色>/source/`，每个 `sources.json` 记录 ZIP 条目与 SHA-256；两酒鬼的修订原件放 `source/revised/`，正式显示使用修订版。用户附件未附独立许可证。

透明裁边、最近邻等比切帧只作用于派生图；男孩 / 女孩比成人矮，女孩混合方向图集分别选帧。映射、缺帧回退和复现见[人物接入](../../docs/assets/characters.md#2026-10-20-聚落补充角色)，正式九组 NPC 接线与画面见[实施记录](../../docs/development/story_supplement_2026_10_20.md)。
