# 两天版发布前置清单（2026-10-20）

范围：只发布第一天 + 第二天主线的构建。部分 NPC 美术仍在制作，清单把"缺美术"与"缺工程收尾"分开列。

## 结论

流程本身是通的：`verify_two_day_flow` 493 项 0 失败（真实宿主、真实交易，窗口模式 1 分 42 秒，截图在 `.godot/two_day_shots/`）。现在缺的是**收尾与打包卫生**，不是玩法。

按下面的 P0 处理完就能出一个可交付的两天试玩版；P1 可以放到下一版。

## P0：发布前必须做

### 1. 没有结尾

现状：第二天最后一句对白之后，剧情设 `day2.completed`，弹出标题卡「第三天 · 早晨 · 委托交接」，进入 `day3.handoff`，随后弹章末回顾。玩家关掉回顾后落在**第三天**，可以继续营业、办理三个交接委托；到第四天这些委托全部 `expired`，之后没有任何内容，也没有任何收尾，只能自己退游戏。

证据：`src/resources/story/day2_stages_01_05.json` 的 `day2.s05.unsolved` 事件；`src/core/story/chapter_gameplay.gd:356` 的回顾触发；`.godot/two_day_shots/day3_handoff.png`、`day4_expired.png`。

回顾页已经写了「前两天主线已完成。继续后可办理第三天已有委托，后续主线尚未开放。」——文案是对的，但玩家能继续走进去，却走不到任何一个"结束"。

建议二选一：

- **收在第二天**：回顾页按钮从「继续 · 委托交接」改成「结束本版」，关闭后回标题；`day3.handoff` 不进场景，三个 day3 委托（`day3.procurement` / `day3.festival` / `day2.casino.debt`）不激活。
- **收在第三天**：把第三天明确做成"交接日"（只有三个委托，没有剧情），在三天夜结束后加一张「两日终」标题卡 + 回标题；HUD 需要常驻天数，否则玩家不知道自己在第几天。

两方案都要回答：回顾页之后还有没有演出。现在完全没有。

### 2. 应用身份仍是占位

- `project.godot` 的 `config/name="godot-goblin"`，窗口标题、任务栏、进程名都是这个。
- 没有 `config/icon`，仓库里也没有 `icon.svg`：导出的 exe 会带 **Godot 默认图标**，启动画面也是引擎默认。
- 没有 `config/version`。

标题画面已经是《洞窟深处的奶茶店》（`src/UI/title/title_menu.tscn`），这三项和它对不上，玩家第一眼就能看出来。

注意 exe 名由 `config/name` 决定：改成中文名，产物会变成 `洞窟深处的奶茶店.exe`。要英文文件名就用英文 `config/name` + `config/name_localized`。

### 3. 导出配置没填、打包内容没筛

- `export_presets.cfg` 两个预设的 `export_path` 都是空的。
- `exclude_filter` 只排了 docs/tools/tests 与素材源目录，**没有排 `src/debug/` 与 `addons/`**。上一次构建（`dist/build_logs/godot-goblin-windows-20261020-024027-67ff0716-export.log`）打进 3113 个文件，其中 `src/debug/` 134 个、`addons/` 247 个（含 `addons/godot_mcp`、GDQuest 格式化插件）。
- 产物：exe 109MB + pck 152MB，目录 250MB。pck 的大头是聚落 8192×9216 整图与 RPG Maker 图集，短期可接受，能在发布说明里写清楚。

**这两块不能直接加进 `exclude_filter`**：`MCPRuntimeProbe` 是 `project.godot` 的 autoload，指向 `addons/godot_mcp/runtime/mcp_runtime_probe.gd`；`src/debug/developer_tools/debug_runtime.gd` 被 `main.gd` 与标题菜单调用，`debug_log.gd` 是 `DevLog` autoload。先排除会让正式包启动就找不到脚本。

第一版建议：**保持全量打包，只确认 `DebugRuntime` 在正式包里关掉面板**（`is_enabled()` 用 `OS.has_feature("debug")` 兜底，正式包恒为 false）。真要瘦身，得把 `debug_runtime.gd` / `debug_log.gd` 挪到 `src/core/`、摘掉 `MCPRuntimeProbe` autoload 和 `apply_release_policy` 里的探针分支，属于小重构，不要压在发版前一天做。

### 4. 立绘缺口（美术在做的部分）

按当前对白数据统计，**没有立绘**的说话人与句数：

| 说话人 | 句数 | 出现在 |
| --- | --- | --- |
| 诗人 | 22 | 赌场、酒馆支线 |
| 哥布林哲人 | 14 | 聚落支线 |
| 吆喝的 / 懂行的 / 老练的摊主 | 6 + 6 + 6 | 集市三个摊主 |
| 军人 | 4 | 兵营 |
| 倒霉的哥布林 | 3 | 第一天顾客 |
| 赌徒 / 爱收集的 / 说教的 / 领工钱的哥布林 | 2 + 4 + 1 + 1 | 第一天顾客 |
| 跑腿的哥布林、哥布林、顾客 | 2 + 2 + 1 | 零散 |

主角、胖哥布林、胖哥布林（不适）、守卫、侍卫、酒馆/赌场老板、集市母亲、祈祷者两人、小孩两人、仓库两卫、醉鬼、买醉者、格里芬使者都有立绘。

两条路，选一条：

- **等美术**：补齐后把图放进 `assets/characters/dialogue/`，在 `src/core/dialogue/dialogue_manager.gd` 的 `speaker_portraits` 加键；单句覆盖走对白数据的 `portrait` 字段。
- **先发**：这五类人在对白里没有立绘时不显示头像（`set_portrait(null)` 会隐藏），阅读不会断，但同场景里"有人有图、有人没图"很显眼。如果着急发，优先补第一天五位顾客（他们是主线），支线的诗人/哲人/军人可以后补。

其余美术缺帧（不影响两天主线能玩通，但会被看出来）：胖哥布林只有待机、没有四向行走与背面；守卫没有独立待机（用行走首帧）；守卫长没有真正的侧面行走；年迈祈祷者只有静坐。详见 `docs/assets/characters.md`。

### 5. 一条主流程测试需要判定

`tests/verify_day1_stages_01_02.gd` 现在 16 项失败，集中在 `_make()`（制作台 submit 路径）与 `_deliver()`（靠近顾客按 E 交付）两处，例：`Human first order really pays 10`、`Each successful production triggers exactly one pour sound`、`Actual reach and focus select goblin_b`。

同一条路径另有两条全绿：`verify_day1_playability` 108 项、`verify_two_day_flow` 493 项（后者在真实宿主里走完两天并交付 15 张订单）。所以要么是这条测试的交互几何/断言过期，要么是某处只在面板路径上坏。**发布前要给出结论**，不能带着"不知道是不是真坏"发。

其余既有失败（本轮未新增）：`verify_warehouse_inventory` 1、`verify_character_records` 2、`verify_map_ui` 4、`verify_ui_theme` 主题审计。

## P1：建议这一版顺手处理

- **回顾页数字**：自动化流程跑完显示「记录了 0 种自创饮品 · 1 位人物」。两天里只有第二天解锁 1 条人物记录（`character_unlock` 全库只有 1 处）。要真人试玩确认正常通关的数字；如果确实这么少，要么补几条人物记录，要么把这一行换成不依赖收集量的说法。
- **没有天数显示**：HUD 只有金币与今日订单，第三天开始玩家不知道自己第几天。收在第三天的方案必须补。
- **设置里没有全屏 / 分辨率**：`settings_panel.gd` 只有音乐、音效、对白速度、自动播放。桌面版建议加「全屏 / 窗口」。
- **只有一首日常 BGM**：`assets/audio/music/` 只有 `start.ogg` 与 `daily_milk_tea.ogg`，第二天与第三天同一首。
- **菜单里的「雇佣系统」是禁用项**（`chapter_actions_hud.gd:21`，tooltip「暂时还不能雇佣哥布林。」）：本版不开放就隐藏，别在菜单里长期摆一个灰的。
- **店名与游戏名不是同一个**：HUD 左上写「小小奶茶店」（`shop_ui.tscn` 的 `help_text`），标题画面是「洞窟深处的奶茶店」。是设定就留着，不是就统一。
- **`config/version` 与发布说明**：试玩版建议带版本号，存档与反馈对得上。

## 美术并行时怎么接

角色接入是一条固定流水线，美术产出后照做即可：

1. 原图放 `assets/characters/npc/<角色>/`，来源与 SHA-256 记进该目录的 `sources.json`。
2. 改 `src/gameplay/characters/character_catalog.json`（身份、帧数、FPS、动作映射）。
3. `python3 tools/characters/build_character_frames.py` 重建 SpriteFrames（不动场景与位置）。
4. 继承场景 `rpg_*.tscn` 只负责半尺寸，不用重做。
5. 立绘放 `assets/characters/dialogue/`，在 `speaker_portraits` 加键。
6. 用 F6 的 `src/debug/characters/character_gallery.tscn` 对照比例与脚底，再跑 `verify_characters.gd`。

授权：现有角色素材来自用户提供的附件，仓库里已注明"未附独立许可证"。对外发布前需要确认这些图可以随包分发。

## 发布动作（照做即可）

```sh
# 1. 全量回归（跑前先清 .godot/test_logs，运行器删 50+ 文件会触发 SAFE_DELETE 拦截）
python tests/run_all.py

# 2. 导出（模板需先安装；export_path 填 dist/<名称>）
"<Godot>" --headless --path . --export-release "Windows Desktop" dist/godot-goblin-windows.exe

# 3. 冒烟：新游戏 → 第二天结束 → 回顾页 → 结束路径
#    读档、设置、退出各走一遍
```

发布前逐条核对：

- [ ] 窗口标题、任务栏图标、启动画面不是 Godot 默认
- [ ] `export_path` 已填，产物进 `dist/`（已在 `.gitignore`）
- [ ] 正式包里开发者面板打不开（F3 无效），`DevLog` 不写文件
- [ ] 两天流程能从头走到结尾，并且**有明确的结束**
- [ ] 新游戏、继续、读档、设置、退出五条路径都通
- [ ] `verify_two_day_flow`、`verify_day1_playability` 全绿；其余失败项有结论
- [ ] 发布说明写清楚：本版只含前两天，第三方美术未定稿

## 附：本轮实测

| 测试 | 结果 |
| --- | --- |
| `verify_two_day_flow` | 493 项 0 失败（窗口模式，含截图） |
| `verify_day1_playability` | 108 项 0 失败 |
| `verify_dialogue` | 264 项 0 失败 |
| `verify_later_story_authoring` | 218 项 0 失败 |
| `verify_rpg_chapter_maps` | 216 项 0 失败 |
| `verify_title_music` | 25 项 0 失败 |
| `verify_day1_stages_01_02` | 16 项失败（待判定） |
