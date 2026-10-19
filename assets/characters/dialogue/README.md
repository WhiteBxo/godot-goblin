# 对话立绘

2026-10-19 用户提供的 `558d9ee2b5c3e94bd1672251d4769457.zip` 与
`胖哥布林受难集(1).zip` 中的透明插画。来源文件逐字节保存于 `source/`，
原压缩包路径见 [来源表](source/sources.json)。附件由用户提供供本项目使用，
未附独立许可证文件。

| 文件 | 角色 |
| --- | --- |
| `guard_portrait.png` | 醉酒守卫／守卫：铁桶盔、背酒桶，与场景人物一致；原文件名为 `？.png` |
| `tavern_portrait.png` | 酒馆老板：围裙、举酒杯 |
| `casino_portrait.png` | 赌场老板：红外套、金项链 |
| `common_goblin_portrait.png` | 普通哥布林顾客：瘦身形、背包 |
| `fat_goblin_sick_portrait.png` | 第二天休养中的胖哥布林：出汗、不适表情 |

以上是对话插画，与地图像素小人、头像资源分别使用。默认角色绑定由
`DialogueManager.speaker_portraits` 提供；胖哥布林的不适表情由第二天正式剧情工程
的对白行指定。旧 `src/resources/dialogue/guard_portrait.tres` 是像素头像资源，
不再用于对话立绘。

使用 `python tools/art/prepare_npc_portraits.py` 可重新生成显示文件：只裁去透明外边距，
保留四像素余量，不缩放、不重绘、不改角色内容。Godot `.import` 设置随资源提交。
