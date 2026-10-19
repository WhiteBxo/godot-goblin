# 两天版发布前置清单（2026-10-20）

范围：只发布第一天 + 第二天主线的构建。部分 NPC 美术仍在制作。

## 结论

流程和收尾都通了：`verify_two_day_flow` 496 项 0 失败，`verify_two_day_persistence` 33 个检查点冷启动恢复。剩下的门槛是**美术**与**打包**，不是玩法。

## 已定并已落地

### 1. 结尾收在第二天（完成）

原来的洞：第二天结束弹回顾页，玩家能继续走进第三天，第四天三个委托全部过期，界面只剩金币，没有任何收尾。

现在：

- 剧情把换日卡从「第三天 · 早晨 · 委托交接」改成「两日终 · 第 1—2 天 · 完」（`docs/story_authoring/day2_stages_01_05_project.json` 的 `day2.s05.unsolved`，产物重编）。
- 回顾页按钮从「继续 · 委托交接」改成「结束本版」，正文补一栏**待续**，列出期限落在第三天的未了委托（七日祭食材、赌场十杯奶茶、醒神菇）。
- 关掉回顾后进入结尾卡 `src/UI/hud/two_days_end.tscn`：黑底 → 标题《洞窟深处的奶茶店》→ 交付数量与结余 → 「感谢试玩 · 后面的故事还没写」→「返回标题」。卡自己负责淡入淡出，站住后回车/Esc 淡出并回标题。
- 结尾曲：用户提供的 90 秒 `assets/audio/music/two_days_end.wav`（QOA 导入，非循环），登记为 `music.two_days_end`。进场先把店内环境音淡出，再用 1 秒淡出旧 BGM、1 秒淡入终曲。
- 旧存档：停在 `day3.handoff` 的档读进来会重新弹回顾与结尾卡，不会掉进空白；只有真的按「返回标题」才写 `ui.two_days_end_seen`，中途退出再读档会再看一次结尾。

### 2. 应用身份（完成；图标按决定先不换）

- `config/name="洞窟深处的奶茶店"`、`config/version="0.1.0"`。窗口标题、任务栏名、导出 exe 名都跟着变。
- 副作用：Godot 的 `user://` 目录按项目名生成，改名后旧目录的存档不再被读到。发布前只有内部试玩档，属于可接受；对外发过版本之后不能再改。
- 图标与启动画面仍是 Godot 默认（用户决定本版先不换）。

### 3. 「雇佣系统」菜单项（完成）

菜单里那个灰的「雇佣系统」是**从未实现的通用界面**（没有场景、没有注册，`main.gd` 一直把它的导航权限写死为 false），已从菜单移除。第二天的雇人不是它：代购专款到账后，章节行动里会出现「临时委托 跑腿的哥布林 · 专款支付 30G 货款＋5G 跑腿费」，这条保留。

### 4. 店名（决定）

保留两个名字：游戏叫《洞窟深处的奶茶店》，HUD 店招是「小小奶茶店」。

## 发布门槛

### 5. 立绘补齐（用户决定：等美术齐了再发）

按当前对白数据，**没有立绘**的说话人与句数：

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

补齐方式：图放 `assets/characters/dialogue/`，在 `src/core/dialogue/dialogue_manager.gd` 的 `speaker_portraits` 加键；单句覆盖走对白数据的 `portrait` 字段。

### 6. 导出与打包（未做）

- `export_presets.cfg` 的 `export_path` 仍是空的。
- `exclude_filter` 没排 `src/debug/`（134 个文件）与 `addons/`（247 个文件），上一次构建共 3113 个文件、pck 152MB、目录 250MB。
- **不能直接加排除**：`MCPRuntimeProbe` 是 `project.godot` 的 autoload，指向 `addons/godot_mcp/runtime/mcp_runtime_probe.gd`；`src/debug/developer_tools/debug_runtime.gd` 被 `main.gd` 与标题菜单调用，`debug_log.gd` 是 `DevLog` autoload。要瘦身得先把这两个挪到 `src/core/`、摘掉 autoload 与 `apply_release_policy` 里的探针分支，属于小重构，不建议压到发版当天做。第一版保持全量打包即可，`DebugRuntime` 在正式包恒为关。

### 7. 一条主流程测试需要判定

`tests/verify_day1_stages_01_02.gd` 16 项失败，集中在 `_make()`（制作台 submit）与 `_deliver()`（靠近顾客按 E），例：`Human first order really pays 10`、`Each successful production triggers exactly one pour sound`、`Actual reach and focus select goblin_b`。

同一条路径另有两条全绿：`verify_day1_playability` 108 项、`verify_two_day_flow` 496 项（后者在真实宿主里走完两天、交付 15 张订单）。要么这条测试的交互几何/断言过期，要么某处只在面板路径上坏，发布前要给出结论。

其余既有失败（本轮未新增）：`verify_warehouse_inventory` 1、`verify_character_records` 2、`verify_map_ui` 4、`verify_ui_theme` 主题审计。

## 观察项（不阻塞）

- **回顾页数字**：自动化流程跑完是「0 种自创饮品 · 1 位人物」。全库只有 1 处 `character_unlock`（第二天的醉酒守卫），自创饮品只有在玩家主动确认自制配方时才会进图鉴。需要一次真人试玩看正常通关的数字；如果仍是 0/1，要么补人物记录，要么把这一行换成不依赖收集量的说法。
- **没有天数显示**：HUD 只有金币与今日订单。收在第二天后影响变小，但换日仍只有标题卡提示。
- **设置里没有全屏 / 分辨率**：只有音乐、音效、对白速度、自动播放。
- **只有两首循环曲 + 一首结尾曲**：`start.ogg`（标题）、`daily_milk_tea.ogg`（白天，第二天共用）、`two_days_end.wav`（结尾）。
- **美术缺帧**：胖哥布林只有待机、没有四向行走与背面；守卫没有独立待机；守卫长没有真正的侧面行走；年迈祈祷者只有静坐。详见 `docs/assets/characters.md`。
- **素材授权**：角色素材来自用户附件，仓库已注明"未附独立许可证"；结尾曲同样未声明许可。对外发布前需要确认可以随包分发。

## 美术并行时怎么接

1. 原图放 `assets/characters/npc/<角色>/`，来源与 SHA-256 记进该目录的 `sources.json`。
2. 改 `src/gameplay/characters/character_catalog.json`（身份、帧数、FPS、动作映射）。
3. `python3 tools/characters/build_character_frames.py` 重建 SpriteFrames（不动场景与位置）。
4. 继承场景 `rpg_*.tscn` 只负责半尺寸，不用重做。
5. 立绘放 `assets/characters/dialogue/`，在 `speaker_portraits` 加键。
6. F6 打开 `src/debug/characters/character_gallery.tscn` 对照比例与脚底，再跑 `verify_characters.gd`。

## 发布动作

```sh
# 1. 全量回归（跑前清 .godot/test_logs，运行器删 50+ 文件会触发 SAFE_DELETE 拦截）
python tests/run_all.py

# 2. 两天流程与存档（真实进程，约 5 分钟）
python tests/verify_two_day_persistence.py --godot "<Godot>" --fixtures-directory .godot/two_day_fixtures

# 3. 导出（模板需先安装；export_path 填 dist/<名称>）
"<Godot>" --headless --path . --export-release "Windows Desktop" dist/<名称>.exe

# 4. 冒烟：新游戏 → 第二天结束 → 回顾 → 结尾卡 → 返回标题；读档、设置、退出各走一遍
```

逐条核对：

- [ ] 窗口标题是《洞窟深处的奶茶店》，exe 名与发布说明一致
- [ ] `export_path` 已填，产物进 `dist/`（已在 `.gitignore`）
- [ ] 正式包里开发者面板打不开（F3 无效），`DevLog` 不写文件
- [ ] 两天流程能走到结尾卡，按「返回标题」回到菜单，结尾曲完整播放
- [ ] 停在第三天交接的旧档读进来会弹回顾与结尾卡
- [ ] 新游戏、继续、读档、设置、退出五条路径都通
- [ ] `verify_two_day_flow`、`verify_day1_playability`、`verify_two_day_persistence` 全绿；其余失败项有结论
- [ ] 发布说明写清楚：本版只含前两天，美术未定稿

## 附：本轮实测

| 测试 | 结果 |
| --- | --- |
| `verify_two_day_flow` | 496 项 0 失败（窗口模式，含截图） |
| `verify_two_day_persistence` | 33 个检查点冷启动恢复，0 失败 |
| `verify_day1_playability` | 108 项 0 失败 |
| `verify_dialogue` | 264 项 0 失败 |
| `verify_later_story_authoring` | 218 项 0 失败 |
| `verify_rpg_chapter_maps` | 216 项 0 失败 |
| `verify_title_music` | 25 项 0 失败 |
| `verify_day1_stages_01_02` | 16 项失败（待判定） |
