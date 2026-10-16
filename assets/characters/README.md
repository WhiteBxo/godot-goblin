# 角色原始插画

以下四张图片来自用户于 2026-10-16 提供的附件，按角色分类并改为可读文件名。文件内容逐字节复制，保留原始格式、尺寸、白色背景及表情图中的文字；未抠图、裁切、缩放或重新压缩。作为独立纹理资源导入并用于对话立绘，未替换玩家动画。

| 项目文件 | 原附件文件名 | 内容 |
| --- | --- | --- |
| `apron_man/apron_man_full_body.jpg` | `238e33c7bf6cde8e5bf763c5d46dca8e.jpg` | 围裙男子全身立绘 |
| `apron_man/apron_man_expressions.jpg` | `b4f68f2503831f993770fce2170d0dc2.jpg` | 围裙男子六种表情，保持整图 |
| `goblin/goblin_smiling.png` | `4999cd3e056940b8f652e8346cc89858.png` | 哥布林微笑立绘 |
| `goblin/goblin_laughing.jpg` | `06c4342a5b0035de16f04cc441012206.jpg` | 哥布林大笑立绘 |

随图提交 Godot 生成的 `.import` 设置；`.godot/` 下的派生缓存由编辑器重新生成。使用默认的 2D Texture2D 导入、无损压缩和关闭 mipmaps，避免再次有损压缩插画。现有玩家动画素材说明见 `player/README.md`。

对话立绘已由 `src/core/dialogue/dialogue_manager.gd` 的 `speaker_portraits` 接入：主角（含内心独白）使用围裙男子全身图，胖哥布林使用微笑图。大笑图可通过单句 `portrait` 指定；六表情整图仍保留为原始素材。显示时等比缩放，不修改源图。规则与试玩入口见 [对话系统](../../docs/dialogue_system.md)。

在 Godot FileSystem 面板打开对应图片，可检查立绘和表情整图。重新导入可在项目根目录执行 `godot --headless --editor --path . --import --quit`（`godot` 需指向本机 Godot 4.7 可执行文件）。

导入规则参照 [Godot 4.7 官方图片导入文档](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_images.html)：JPEG 与 PNG 均可作为 Texture2D 导入，JPEG 格式不支持透明通道。
