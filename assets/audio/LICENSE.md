# 项目音效素材来源与许可

本次音效原始库及其派生成品来源于用户提供的三个 CC0 包。原文件保存在 `source/`，成品保存在 `ui/`、`shop/`、`player/`、`story/`、`ambience/`；不再使用旧项目程序合成 WAV。

| 原始包 | 作者 | 来源与许可证据 |
| --- | --- | --- |
| 80-CC0-RPG-SFX.zip | rubberduck | [OpenGameArt 发布页 / CC0](https://opengameart.org/node/86018) |
| tinysized.zip | Vehicle / Jan Schupke | [发布页 / CC0](https://opengameart.org/content/fantasy-sound-effects-tinysized-sfx)，以及 `source/tinysized/readme.txt` |
| accessory.zip | Vehicle / Jan Schupke | [发布页 / CC0](https://opengameart.org/content/fantasy-accessory-sfx-library)，以及 `source/accessory/readme.txt` |

CC0 1.0 Universal 完整条款：[legal code](https://creativecommons.org/publicdomain/zero/1.0/legalcode)。保留作者来源便于追踪。本项目对上述素材所做裁剪、调音、组合及循环处理也以 CC0 提供，不对源素材添加额外许可条件，不提供担保。

`source/manifest.json` 记录包名、包 SHA-256 及完整 335 个原文件哈希；`manifest.json` 记录 43 个成品的来源、处理配方和哈希。可复现步骤见 [音效库](../../docs/assets/sound_library.md)。此声明不适用于项目代码、字体、图像、下述独立音乐或测试音乐夹具。

## 用户提供的场景音乐（2026-10-20 更新）

用户本次提供奶茶店、洞穴整体音乐、赌场、酒馆、长老居所、集市和 `end.ogg` 共七首音乐，作为项目独立音乐使用；按用户要求接入本项目，不属于前述 CC0 音效包，也未随本次文件附带单独的许可证文本。

原始 Ogg 逐字节保存在 `source/music/`，英文文件名与原始名称、SHA-256 对照见 `music/processing_manifest.json`。游戏使用 `music/` 下的派生 Ogg：保持立体声、原采样率与原速，统一平均电平并保护峰值；六首场景曲裁掉结束静音/淡出后交叉淡化循环，结尾曲保留完整 90 秒并关闭循环。配方与重建步骤见 [音乐处理说明](music/README.md)。

此前奶茶曲的 68.279 秒循环起点已取消；旧 `two_days_end.wav` 保留供作者对照，但不再注册或导出，游戏使用新 Ogg 结尾曲。

## 作者自制的标题音乐

`music/start.ogg` 于 2026-10-18 由项目作者本人制作并提供（源文件 `D:/reaper/REAPER Media/start.ogg`），用于本项目标题界面。原样复制，无转码或裁剪；淡入淡出由播放器完成。属作者自有素材，随本项目及其构建物（含试玩包）一并分发，不涉及第三方授权。

SHA-256：`a6366c55ce5de090eee1f25ba44a9fdc62cf60104c86d8121eb76c52b8357dde`。

## 素材授权状态（2026-10-20 确认）

角色插画、立绘、像素小人与当时登记的三首音乐均由项目作者本人制作，作者已明确表示这些素材可随项目及其构建物（含对外试玩包）一同分发，不涉及第三方授权。第三方素材仅限本文件开头列出的三个 CC0 音效包，以及 `assets/fonts/` 下各自携带 OFL 许可证的字体。对外发布时不需要再取得额外授权。
