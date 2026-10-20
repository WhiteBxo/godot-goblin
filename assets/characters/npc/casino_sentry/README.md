# 赌场侍卫素材

2026-10-19 用户附件 `侍卫2(1).zip`。身份依据最新[聚落补充稿](../../../../docs/design/settlement_dialogue_supplement_revised.md)“赌场：侍卫”，正文说话人名为“护卫”。独立 Actor ID 为 `casino_sentry`，不替换醉酒守卫、宅邸守卫或守卫长。

附件中的四张 PNG 逐字节保存，忽略 `__MACOSX`；文件映射与 SHA-256 见 [来源表](source/sources.json)。附件由用户提供供本项目使用，未附独立许可证文件。

| 文件 | 原附件路径 | 用途 |
| --- | --- | --- |
| `run_up.png` | `侍卫2/合并图片.png` | 背向行走，10 帧 |
| `run_down.png` | `侍卫2/合并图片 2.png` | 正向行走，13 帧 |
| `run_right.png` | `侍卫2/合并图片 3.png` | 右向行走，15 帧；向左镜像 |
| `source/portrait.png` | `侍卫2/侍卫2.png` | 原始透明插画，2048×1870 |
| `portrait.png` | 从原始插画派生 | 仅裁透明边（`317,0,1564,1640`），保留四像素余量，不缩放、不重绘 |

2026-10-21 立绘更正：守卫长的大块头和 `侍卫2` 的行走图不是同一角色，赌场对话里一眼就能看出小人与立绘对不上。立绘改回同一附件里的 `侍卫2/侍卫2.png`——铁盔、大眼、瘦长手臂，与行走图的尖顶铁盔是同一设计。10-20 用过的守卫长原图没有留在本目录以免再次误用，需要时从 `commit aa3fe02a` 的 `source/portrait.png` 取回。

行走图为 64×64 帧、88 像素步长，逐行读取有效格，排除尾部空格。行走 8 FPS；没有独立待机图，四向 `idle_*` 使用对应行走首帧。基础场景等比显示为 128 世界像素画布，RPG 继承场景为 64；脚底锚点、NPC 输入隔离与显隐碰撞沿用 SettlementCharacter。

重新导入三张行走图并重建帧资源（路径替换为附件实际路径；原始立绘按来源表从附件取出）：

```sh
python tools/characters/build_character_frames.py --catalog src/gameplay/characters/sentry_catalog.json --archive "侍卫2(1).zip"
```

省略 `--archive` 只重建 SpriteFrames。立绘裁切矩形记录在来源表 `portrait_crop`，可用 Pillow `Image.open(source).crop(tuple(portrait_crop)).save(output)` 重现。

正式赌场在既有 `casino_guard_a` 锚点 `(120, 552)` 实例化 `rpg_casino_sentry.tscn`；原守卫仍引用 `npc/guard/` 动画与原有对话立绘。DialogueManager 将“侍卫”“护卫”绑定到本目录的 `portrait.png`。本次接入素材与 NPC 场景，补充稿的分支对话尚未编排为运行时事件，交互沿用普通 NPC 的忙碌反馈。

F6 打开 `src/debug/characters/character_gallery.tscn`，第二排最右侧是侍卫，自动循环四向移动与待机。F6 打开 `src/core/casino.tscn`，从入口向左上走到地毯左端查看正式尺寸、站位与碰撞。
