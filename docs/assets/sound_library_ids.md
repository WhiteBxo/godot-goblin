# 音效 ID 与资源映射（生成文件）

由 `tools/audio/generate_sound_pack.py` 生成。基础 ID 指向首变体；重复播放通过 `choose_variant()` 选择非连续重复的变体 ID。

| 基础 ID | 名称 | 变体 ID / 资源路径 / 秒 |
| --- | --- | --- |
| `ui.hover` | 菜单悬停 | `ui.hover` → `res://assets/audio/ui/hover.wav` (0.110) |
| `ui.confirm` | 确认操作 | `ui.confirm` → `res://assets/audio/ui/confirm.wav` (0.290) |
| `ui.cancel` | 取消操作 | `ui.cancel` → `res://assets/audio/ui/cancel.wav` (0.290) |
| `ui.dialogue` | 对话文字 | `ui.dialogue.01` → `res://assets/audio/ui/dialogue_01.wav` (0.110)<br>`ui.dialogue.02` → `res://assets/audio/ui/dialogue_02.wav` (0.110)<br>`ui.dialogue.03` → `res://assets/audio/ui/dialogue_03.wav` (0.110) |
| `shop.door_bell` | 店门双音铃 | `shop.door_bell` → `res://assets/audio/shop/door_bell.wav` (1.598) |
| `shop.order_open` | 展开纸质订单 | `shop.order_open` → `res://assets/audio/shop/order_open.wav` (0.450) |
| `shop.tea_pour` | 倒入奶茶 | `shop.tea_pour.01` → `res://assets/audio/shop/tea_pour_01.wav` (1.427)<br>`shop.tea_pour.02` → `res://assets/audio/shop/tea_pour_02.wav` (1.421) |
| `shop.sealer` | 封口机压合 | `shop.sealer` → `res://assets/audio/shop/sealer.wav` (1.547) |
| `player.step_wood` | 木地板脚步 | `player.step_wood.01` → `res://assets/audio/player/step_wood_01.wav` (0.340)<br>`player.step_wood.02` → `res://assets/audio/player/step_wood_02.wav` (0.340)<br>`player.step_wood.03` → `res://assets/audio/player/step_wood_03.wav` (0.340)<br>`player.step_wood.04` → `res://assets/audio/player/step_wood_04.wav` (0.340) |
| `player.step_stone` | 石地脚步 | `player.step_stone.01` → `res://assets/audio/player/step_stone_01.wav` (0.340)<br>`player.step_stone.02` → `res://assets/audio/player/step_stone_02.wav` (0.340)<br>`player.step_stone.03` → `res://assets/audio/player/step_stone_03.wav` (0.340)<br>`player.step_stone.04` → `res://assets/audio/player/step_stone_04.wav` (0.340) |
| `story.knock` | 门后神秘三连敲 | `story.knock.01` → `res://assets/audio/story/knock_01.wav` (1.283)<br>`story.knock.02` → `res://assets/audio/story/knock_02.wav` (1.274) |
| `story.impact` | 剧情冲击 | `story.impact` → `res://assets/audio/story/impact.wav` (1.388) |
| `ui.failure` | 交互失败 | `ui.failure` → `res://assets/audio/ui/failure.wav` (0.293) |
| `ambience.drip` | 远处滴水 | `ambience.drip.01` → `res://assets/audio/ambience/drip_01.wav` (0.813)<br>`ambience.drip.02` → `res://assets/audio/ambience/drip_02.wav` (0.813) |
| `ambience.rock_scrape` | 岩石摩擦 | `ambience.rock_scrape` → `res://assets/audio/ambience/rock_scrape.wav` (1.100) |
| `story.goblin` | 哥布林含糊嘀咕 | `story.goblin.01` → `res://assets/audio/story/goblin_01.wav` (0.950)<br>`story.goblin.02` → `res://assets/audio/story/goblin_02.wav` (0.950)<br>`story.goblin.03` → `res://assets/audio/story/goblin_03.wav` (0.950) |
| `ambience.shop` | 奶茶店室内循环 | `ambience.shop` → `res://assets/audio/ambience/shop.wav` (12.000) |
| `ambience.cave` | 地下洞穴循环 | `ambience.cave` → `res://assets/audio/ambience/cave.wav` (12.000) |
| `music.daily_milk_tea` | 奶茶店日常 BGM | `res://assets/audio/music/daily_milk_tea.ogg`；首次从 0 播放，末尾回到 68.279 秒循环 |
