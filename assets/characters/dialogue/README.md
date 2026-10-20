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
| `fat_goblin_sick_portrait.png` | 胖哥布林不适：出汗、捂腹。喝下格里芬之血倒地后（第一天 S06）与第二天休养共用 |

以上是对话插画，与地图像素小人、头像资源分别使用。默认角色绑定由
`DialogueManager.speaker_portraits` 提供；胖哥布林的不适表情由第二天正式剧情工程
的对白行指定。旧 `src/resources/dialogue/guard_portrait.tres` 是像素头像资源，
不再用于对话立绘。

2026-10-20 的 `哥布林npc：有特定对话，不能重复利用的npc(1).zip` 再次附带同一张
`胖哥布林受难集/🤢🤮.png`，与 `source/fat_goblin_sick.png` 逐字节一致
（SHA-256 `b7731ad6b73382b70804d512bbca95f70cdb30c9a000919814c57e352c740b7a`），
因此不另存副本，显示文件保持不变。

使用 `python tools/art/prepare_npc_portraits.py` 可重新生成显示文件：只裁去透明外边距，
保留四像素余量，不缩放、不重绘、不改角色内容。Godot `.import` 设置随资源提交。
