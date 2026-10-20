# 胖哥布林像素小人

地图像素小人，与专属对话立绘（[`../fat_goblin/`](../../fat_goblin/README.md)）、
不适立绘（[`../dialogue/`](../dialogue/README.md)）分别使用。

| 文件 | 用途 | 帧数 |
| --- | --- | --- |
| `idle_sheet_01.png` | 侧向右、待机 / 行走 | 16 |
| `idle_sheet_02.png` | 正面与背面、待机 / 行走 | 16 |
| `idle_sheet_03.png` | 大笑表情 `emote_laugh` | 16 |
| `sick_retch_sheet.png` | 喝下格里芬之血后坐地反胃 `sick_retch` | 16 |
| `sick_sit_sheet.png` | 第二天起坐地休养 `sick_sit` | 9 |
| `mood_pleading_sheet.png` | 求主角收下食材时合十拜托 `pleading` | 12 |
| `mood_worried_sheet.png` | 嘀咕"食材怎么奇形怪状"时摸额头苦恼 `worried` | 12 |
| `mood_happy_sheet.png` | 吃完奶茶摸肚子满足 `happy` | 12 |

## 受难集图集来源（2026-10-20）

用户提供的 `哥布林npc：有特定对话，不能重复利用的npc(1).zip`，两份图集逐字节保存为
上表文件，未裁切、未缩放、未重绘；原包内同名文件与既有图集布局一致，因此不需要派生图：

| 项目文件 | ZIP 条目 | SHA-256 |
| --- | --- | --- |
| `sick_retch_sheet.png` | `哥布林npc：有特定对话，不能重复利用的npc/胖哥布林/胖哥布林受难集/胖哥布林受难集/胖胖坐地上🤢🤮.png` | `ff2c604847e330c6b08dd7f0362d21a6748fd11febc5f1913eb8d1cdb1b00ec7` |
| `sick_sit_sheet.png` | `哥布林npc：有特定对话，不能重复利用的npc/胖哥布林/胖哥布林受难集/胖哥布林受难集/胖胖坐在地上待机.png` | `bd1b2a28f7340c59b5e7bc447c4cd6e1508ba4de82585d5a6d83847637750f8f` |
| `mood_pleading_sheet.png` | `.../胖哥布林受难集/胖哥布林受难集/胖胖拜托🙏.png` | `00e61dc0cc66c4767bc3003e341283eceffcf00ecae2d5322b76d76a9af7bd0c` |
| `mood_worried_sheet.png` | `.../胖哥布林受难集/胖哥布林受难集/胖胖苦恼😥.png` | `5d47b2c207b51ec28f4d70160a5b3ec93c8e7ced444a71abf0e33549f0b3ac76` |
| `mood_happy_sheet.png` | `.../胖哥布林受难集/胖哥布林受难集/胖胖吃饱.png` | `50bc0ca09fe4b414fcdef46a40a4c4938df36965b06b91b46a9544db5c8591b8` |

附件未附独立许可证，授权以用户提供为准。

## 切帧与状态切换

- 两份图集都是 6 列、88px 步距、64×64 帧的画布（`sick_sit_sheet.png` 只有两行），
  与 `idle_sheet_*.png` 完全同构；`fat_goblin_sick_frames.tres` 沿用同一套
  `AtlasTexture` 区域，脚底锚点与像素倍率因此和常态完全一致。
- 待机节奏按原包未指定，取 `sick_retch` 6 FPS、`sick_sit` 5 FPS。
- 状态由 `src/gameplay/characters/fat_goblin.gd` 的 `set_health()` / `set_mood()` 切换，剧情事实到状态的
  投影在 `Day1WorldController._fat_goblin_health()` 与 `_fat_goblin_mood()`：喝下格里芬之血倒地
  （`day1.s06.blood_collapsed`）为 `COLLAPSED`，第二天起为 `RESTING`，救治成功
  （`signature.S06.rescued_in_time`）回到 `NORMAL`。
- 第一天的情绪按阶段投影：`day1.s04`（含 `wait_order`，他上门求主角收下食材并等着喝）为
  `PLEADING`，`day1.s04.wait_taste`（"这食材怎么奇形怪状的？"）为 `WORRIED`，
  `day1.s04.wait_map`（喝完奶茶、递地图）为 `HAPPY`，其余阶段为 `NEUTRAL`。
- **身体状态优先于情绪**：`COLLAPSED` / `RESTING` 期间 `set_mood` 不生效，由 `FatGoblin`
  的 `_frames_for_pose()` 保证。
- 三套情绪图集同受难集一样是 6 列、88px 步距、64×64 帧，只在 `fat_goblin_mood_frames.tres`
  里按 12 帧（两行）切；情绪帧没有朝向，播放期间不参与走路与转向。
- 没有朝向的坐姿帧不参与走路与转向播放；角色自身不判断剧情，只接收状态。

替换图集时同时改 `fat_goblin_sick_frames.tres` 的区域与帧数；导入设置沿用默认 2D
Texture2D、无损压缩、关闭 mipmaps，重新导入在项目根目录执行
`godot --headless --editor --path . --quit`。
