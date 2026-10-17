# 角色原始插画

以下四张图片来自用户于 2026-10-16 提供的附件，按角色分类并改为可读文件名。原始文件逐字节保留，包含原始格式、尺寸、白色背景及表情图中的文字。对话使用下文的独立透明派生素材，未替换玩家动画。

| 项目文件 | 原附件文件名 | 内容 |
| --- | --- | --- |
| `apron_man/apron_man_full_body.jpg` | `238e33c7bf6cde8e5bf763c5d46dca8e.jpg` | 围裙男子全身立绘 |
| `apron_man/apron_man_expressions.jpg` | `b4f68f2503831f993770fce2170d0dc2.jpg` | 围裙男子六种表情，保持整图 |
| `goblin/goblin_smiling.png` | `4999cd3e056940b8f652e8346cc89858.png` | 哥布林微笑立绘 |
| `goblin/goblin_laughing.jpg` | `06c4342a5b0035de16f04cc441012206.jpg` | 哥布林大笑立绘 |

随图提交 Godot 生成的 `.import` 设置；`.godot/` 下的派生缓存由编辑器重新生成。使用默认的 2D Texture2D 导入、无损压缩和关闭 mipmaps，避免再次有损压缩插画。现有玩家动画素材说明见 `player/README.md`。

对话立绘已由 `src/core/dialogue/dialogue_manager.gd` 的 `speaker_portraits` 接入：主角（含内心独白）使用 `apron_man/player_portrait.png`，胖哥布林使用 `goblin/goblin_smiling_portrait.png`；单句可指定 `goblin/goblin_laughing_portrait.png`。这三张为透明 RGBA PNG，原始图片和六表情整图保留。主角在左侧、NPC 在右侧，图片下半身被对话框遮住。规则与试玩入口见 [对话系统](../../docs/systems/dialogue_system.md)。

透明派生素材于 2026-10-16 使用内置 imagegen 编辑模式分别处理对应原图。每张使用相同提示词，可从原图重新执行；生成式编辑可能存在细微笔触变化，应以已提交 PNG 为显示依据：

> Edit target: the supplied character illustration. Remove ONLY the white background and all ground shadows / ground marks outside the character, creating a clean transparent RGBA cutout of the complete full-body character. Preserve the exact original character identity, facial expression, pose, silhouette, clothing, colors, ink outlines, proportions, and illustration style. Do not redesign, mirror, crop limbs, or add anything. Tight framing around the full character with only a small transparent margin. Output a single character on genuine transparent background, no checkerboard painted into the image.

在 Godot FileSystem 面板打开对应图片，可检查立绘和表情整图。重新导入可在项目根目录执行 `godot --headless --editor --path . --import --quit`（`godot` 需指向本机 Godot 4.7 可执行文件）。

导入规则参照 [Godot 4.7 官方图片导入文档](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html)：JPEG 与 PNG 均可作为 Texture2D 导入，JPEG 格式不支持透明通道。

## 游戏人物场景

全部 31 张 NPC 动画图集已接入 8 类可复用人物场景，按剧情身份放入聚落并注册给 ActorDirector。人物映射、缺帧 fallback、F6 预览入口和再生成方式见 [游戏人物说明](../../docs/assets/characters.md)。

## 攻击与无背包走路动画

2026-10-17 附件已导入为四套 SpriteFrames，共 15 段动作、159 帧；来源映射、F6 预览、播放约定和复现命令见 [哥布林动作资源](goblin_actions/README.md)。
