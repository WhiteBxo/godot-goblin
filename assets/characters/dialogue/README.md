# 对话立绘

2026-10-19 用户提供的 `558d9ee2b5c3e94bd1672251d4769457.zip` 与
`胖哥布林受难集(1).zip` 中的透明插画。来源文件逐字节保存于 `source/`，
原压缩包路径见 [来源表](source/sources.json)。这些插画与地图像素小人、头像资源均由项目作者本人制作，
属作者自有素材，可随本项目及其构建物（含对外试玩包）一并分发，不涉及第三方授权。

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

第一天逐位接待的顾客只有一张原画（`common_goblin_portrait.png`，素材包里仅此一张普通哥布林）。
其余个体由它**只换上衣与包袱的配色**派生：皮肤、裤子、描边、木桶、纸牌、鞋都保持原画，
不是重绘、不是拉伸，也不覆盖原图。

| 文件 | 使用者 | 布料配色 |
| --- | --- | --- |
| `common_goblin_portrait.png` | 赌徒哥布林；另有泛称「哥布林顾客」（第二天散客） | 原画棕 |
| `goblin_timid_portrait.png` | 胆小的哥布林；第一场泛称「哥布林」 | 冷蓝灰 |
| `goblin_preacher_portrait.png` | 说教的哥布林 | 暗紫 |
| `goblin_collector_portrait.png` | 爱收集的哥布林 | 酒红 |
| `goblin_worker_portrait.png` | 领工钱的哥布林 | 赭黄 |
| `goblin_unlucky_portrait.png` | 倒霉的哥布林 | 原色带褪成脏灰 |
| `goblin_runner_portrait.png` | 跑腿的哥布林 | 深青 |

复现：`python tools/art/tint_goblin_portraits.py`（输出默认写回本目录）。脚本用
「R − G > 16」选出棕色布料像素、只重映射色相，并把 y ≥ 1080 以下整段排除，
所以裤子和手里提的东西不会被染。换底图时要重新量那条分界线。
七个并排效果见 [立绘变体对照](../../../docs/assets/captures/goblin_portrait_variants.png)。

补画了独立立绘后，直接改 `DialogueManager.speaker_portraits` 里对应的键即可，剧情数据不用动。

2026-10-20 的 `哥布林npc：有特定对话，不能重复利用的npc(1).zip` 再次附带同一张
`胖哥布林受难集/🤢🤮.png`，与 `source/fat_goblin_sick.png` 逐字节一致
（SHA-256 `b7731ad6b73382b70804d512bbca95f70cdb30c9a000919814c57e352c740b7a`），
因此不另存副本，显示文件保持不变。

使用 `python tools/art/prepare_npc_portraits.py` 可重新生成显示文件：只裁去透明外边距，
保留四像素余量，不缩放、不重绘、不改角色内容。Godot `.import` 设置随资源提交。
