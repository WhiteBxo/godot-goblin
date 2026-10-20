# 项目音效素材来源与许可

本次音效原始库及其派生成品来源于用户提供的三个 CC0 包。原文件保存在 `source/`，成品保存在 `ui/`、`shop/`、`player/`、`story/`、`ambience/`；不再使用旧项目程序合成 WAV。

| 原始包 | 作者 | 来源与许可证据 |
| --- | --- | --- |
| 80-CC0-RPG-SFX.zip | rubberduck | [OpenGameArt 发布页 / CC0](https://opengameart.org/node/86018) |
| tinysized.zip | Vehicle / Jan Schupke | [发布页 / CC0](https://opengameart.org/content/fantasy-sound-effects-tinysized-sfx)，以及 `source/tinysized/readme.txt` |
| accessory.zip | Vehicle / Jan Schupke | [发布页 / CC0](https://opengameart.org/content/fantasy-accessory-sfx-library)，以及 `source/accessory/readme.txt` |

CC0 1.0 Universal 完整条款：[legal code](https://creativecommons.org/publicdomain/zero/1.0/legalcode)。保留作者来源便于追踪。本项目对上述素材所做裁剪、调音、组合及循环处理也以 CC0 提供，不对源素材添加额外许可条件，不提供担保。

`source/manifest.json` 记录包名、包 SHA-256 及完整 335 个原文件哈希；`manifest.json` 记录 43 个成品的来源、处理配方和哈希。可复现步骤见 [音效库](../../docs/assets/sound_library.md)。此声明不适用于项目代码、字体、图像、下述独立音乐或测试音乐夹具。

## 作者自制的奶茶日常音乐

`music/daily_milk_tea.ogg` 来自此前用户提供的 `daily_milkTea.ogg`，继续保持原音频和 68.279 秒原生循环起点。本次没有重新授权或替换；上述第三方 CC0 声明不适用于此曲。

## 作者自制的标题音乐

`music/start.ogg` 于 2026-10-18 由项目作者本人制作并提供（源文件 `D:/reaper/REAPER Media/start.ogg`），用于本项目标题界面。原样复制，无转码或裁剪；淡入淡出由播放器完成。属作者自有素材，随本项目及其构建物（含试玩包）一并分发，不涉及第三方授权。

SHA-256：`a6366c55ce5de090eee1f25ba44a9fdc62cf60104c86d8121eb76c52b8357dde`。

## 作者自制的结尾音乐（2026-10-20）

`music/two_days_end.wav` 于 2026-10-20 由项目作者本人制作并提供（源文件 `D:/download/Pixel-Quest-Adventure-mixdown-00-00_01-30-1x.wav`），用于两天版结尾卡。原样复制，未转码、未裁剪，长度 90.000 秒，44.1 kHz 立体声；导入时按项目默认的 QOA 压缩（`compress/mode=2`）生成运行时采样，非循环。属作者自有素材，随本项目及其构建物（含试玩包）一并分发，不涉及第三方授权。

SHA-256：`174ac84c4fad0396b2701ef59ca147b242ee5293f974e282ba88340cecd3beda`。

## 素材授权状态（2026-10-20 确认）

角色插画、立绘、像素小人与上述三首音乐均由项目作者本人制作，作者已明确表示这些素材可随项目及其构建物（含对外试玩包）一同分发，不涉及第三方授权。第三方素材仅限本文件开头列出的三个 CC0 音效包，以及 `assets/fonts/` 下各自携带 OFL 许可证的字体。对外发布时不需要再取得额外授权。
