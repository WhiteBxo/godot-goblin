# v0.1.0 两日试玩版发布说明（2026-10-20）

交付形态：Windows 试玩包，zip 直接发给试玩者。范围只含第一天 + 第二天主线，美术未定稿。

## 交付物

| 文件 | 大小 | 说明 |
| --- | --- | --- |
| `dist/洞窟深处的奶茶店-v0.1.0-demo-win64.zip` | 131.9 MB | 对外分发的唯一文件 |
| `dist/洞窟深处的奶茶店-v0.1.0-demo-win64.sha256` | — | 校验值，随包一起给出 |
| `dist/洞窟深处的奶茶店-v0.1.0-demo-win64.json` | — | 打包摘要（内容清单、源构建、sha256） |

zip 内结构：

```text
洞窟深处的奶茶店-v0.1.0-demo-win64/
  洞窟深处的奶茶店.exe    104.1 MB
  洞窟深处的奶茶店.pck    101.3 MB
  试玩说明.txt
```

sha256：`fbc508b96748db207b36e83d16bc35ec0b7e315b2ba588f2930548d2c854e87f`

## 版本对应

- 源码 `e52a67ef`（工作树干净时导出），引擎 Godot 4.7.2 stable，release 模板，x86_64。
- 工程 `config/name="洞窟深处的奶茶店"`、`config/version="0.1.0"`。
- 源构建目录 `dist/godot-goblin-release-20261020-1612-e52a67ef/`；上一版 `…-1526-a1fdd20c/` 是群客改动前的构建，已被本版取代。

## 内容范围

第一天 6 阶段 + 第二天 5 阶段主线；第二天结束弹回顾页（按钮「结束本版」）→ 结尾卡《洞窟深处的奶茶店》→「返回标题」。结尾曲 90 秒完整播放。第三天及之后未写。

停在 `day3.handoff` 的旧档读进来会重新弹回顾与结尾卡，不会掉进空白。

## 本轮改动（打包闭环）

0. **第一天第二次来客改成三只哥布林一起进店**（玩法内容修正，详见 [改动记录](day1_group_customers_2026_10_20.md)）。
   原来这句对白写了四个哥布林在聊天，场景里却只出现一个人。现在赌徒、说教的、爱收集的
   三只同时进门，分别站到早就存在的 `day1_group_a/b/c` 三个锚点上，聊完由赌徒点单；
   交付后两只离开，爱收集的留在原地接他那一单。点单者与订单交付目标统一成 `goblin_a`。
1. **重打 zip，修中文文件名乱码**。原 `godot-goblin-release-*.zip` 的条目名是 ANSI 写入且没置 UTF-8 标志位（bit 11），用资源管理器解压会得到 `╢┤┐▀╔ε...` 这类乱码名。新包由 `tools/build/package_demo.py` 生成，逐条校验非 ASCII 条目都带 UTF-8 标志，解压后文件名正确。
2. **新增包内抽检** `tools/build/pck_preflight.py`：解 pck 目录，验证 `basic_menu.tres` 仍是文本资源（未被转二进制）、`奶香／可可香／果香／提神` 四个风味串齐全（2026-10-20 那次导出丢数组字段的回归守卫）、必需条目存在、排除目录没漏进包。
3. **随包写 `试玩说明.txt`**（UTF-8 BOM + CRLF，记事本直接可读）：运行方式、SmartScreen 提示、系统要求、操作键位、存档路径、已知问题、反馈要点。
4. **端到端冒烟**：把 zip 解压到干净目录后直接跑 exe，而不是只验源构建目录。

## 自检结果（本次实际执行）

| 检查 | 命令 / 方式 | 结果 |
| --- | --- | --- |
| 源构建窗口启动 | `洞窟深处的奶茶店.exe --quit-after 400` | 退出码 0，日志无 error |
| 包内资源完整性 | `python tools/build/pck_preflight.py <pck>` | 2537 条目 / 101.3 MB，风味串 4/4，排除目录无泄漏 |
| zip 文件名编码 | `package_demo.py` 内置校验 | 非 ASCII 条目全部带 UTF-8 标志 |
| zip CRC | `ZipFile.testzip()` | 通过 |
| 解压后启动 | 解压 → exe `--quit-after 400 --verbose` | 退出码 0，`title_menu.tscn` + `title_menu.gdc` 正常加载 |
| 两天主线流程 | `verify_two_day_flow.gd`（headless） | 379 项 0 失败，退出码 0 |
| 首日可玩性 | `verify_day1_playability.gd`（headless） | 121 项 0 失败 |
| 两天存档恢复 | `verify_two_day_persistence.py`，33 个检查点 | 0 失败 |
| 第一天阶段 | `verify_day1_stages_01_02.gd`（headless） | 16 项失败，与改动前基线逐条一致（stash 前后各跑一次对照） |
| 群客画面 | `--capture` 窗口模式截图 | 三只并排站柜台前，任务提示「草莓奶绿 → 赌徒哥布林」 |

### 冒烟日志里的 5 条警告

```text
WARNING: Image format RGB8 not supported by hardware, converting to RGBA8.
```

5 张图仍是 RGB8 导入格式，显卡不支持直传，运行时转成 RGBA8。不影响显示，只多一次转换和一点显存。源构建 `-build_info.json` 记的 `error_lines: 0` 只统计 ERROR 行，这批警告一直存在，不是本轮引入。要清掉得把这批图的导入压缩模式改成无损/VRAM，属于素材重导，放到正式发布前一起做。

## 分发时必须让试玩者知道的三件事

1. **未做代码签名**：首次运行会弹 Windows SmartScreen，点「更多信息 → 仍要运行」。`试玩说明.txt` 已写明。
2. **本版只有两天**：玩到第二天结束就是结局，不要以为是卡死。
3. **美术未定稿**：部分次要 NPC 是临时占位，请围绕流程和手感反馈，不必报美术差异。

## 已知问题

素材授权（2026-10-20 已确认，不再是阻塞项）：

- 角色插画、立绘、像素小人、`start.ogg`、`daily_milk_tea.ogg`、`two_days_end.wav` 都由项目作者本人制作，作者已确认可随本项目及其构建物（含对外试玩包）一并分发，不涉及第三方授权。第三方素材只剩三个 CC0 音效包与各自带 OFL 的字体。记录见 [音效与许可](../../assets/audio/LICENSE.md) 与 [对话立绘说明](../../assets/characters/dialogue/README.md)。

不阻塞、随包说明里已列：

- 设置里没有全屏与分辨率，只有音乐、音效、对白速度、自动播放。
- 音乐只有 `start.ogg`（标题）、`daily_milk_tea.ogg`（白天）、`two_days_end.wav`（结尾）。
- 胖哥布林没有四向行走帧，守卫长没有真正的侧面行走，年迈祈祷者只有静坐。
- 结尾回顾页的「解锁人物 / 自创饮品」数字取决于玩家是否主动收集，自动化流程跑出来是 0 种 / 1 位，可能让试玩者觉得收集系统很空。

## 还没做（不影响本版发包）

- **立绘仍缺独立稿**。诗人 22 句、哥布林哲人 14 句、集市三个摊主各 6 句、军人 4 句的立绘
  **早已接上**（`speaker_portraits` 有绑定，本文件早前版本按旧的发布前置清单误列为缺口，
  已更正）。现在真正没有独立立绘的是第一天五位哥布林顾客、跑腿的哥布林和第一场的泛称「哥布林」：
  他们暂时统一用 `common_goblin_portrait.png`，因为素材里只有这一张普通哥布林立绘。
  补画后在 `speaker_portraits` 改对应键即可，剧情数据不用动。

- **`verify_day1_stages_01_02` 16 项失败未判定**：失败集中在制作台 submit 与靠近顾客按 E 交付。同一条路径另有 `verify_day1_playability` 121 项、`verify_two_day_flow` 379 项全绿（本轮 headless 实测），倾向交互几何/断言过期，但结论没坐实。其中 `Actual reach and focus select goblin_b` 是因为该测试仍按「三只各交付一杯、共 5 单」的旧设计写，与当前五位逐位接待的产物不一致。

- 既有失败：`verify_warehouse_inventory` 1、`verify_character_records` 2、`verify_map_ui` 4、`verify_ui_theme` 主题审计。
- macOS 未打包。
- 开发者脚本仍在包内，只靠 release 特性关闭（`DebugRuntime.is_enabled()` 依赖 `OS.has_feature("debug")`，正式模板恒为 false，F3 打不开、`DevLog` 不写文件）。彻底剥离需要把 `DebugRuntime` / `DevLog` 迁到 `src/core/`。

## 复现发包

```sh
# 1. 导出（模板需已安装）
"D:/download/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe" \
  --headless --path . --export-release "Windows Desktop" \
  "dist/godot-goblin-release-<日期>/洞窟深处的奶茶店.exe"

# 2. 抽检包内容
python tools/build/pck_preflight.py "dist/godot-goblin-release-<日期>/洞窟深处的奶茶店.pck"

# 3. 打成对外分发包（同时生成 .sha256 与 .json）
python tools/build/package_demo.py --build-dir "dist/godot-goblin-release-<日期>" --version 0.1.0 --label demo

# 4. 解压到干净目录跑一次
cd "dist/洞窟深处的奶茶店-v0.1.0-demo-win64/解压目录" && ./洞窟深处的奶茶店.exe --quit-after 400
```

## 试玩反馈怎么收

让试玩者按这四点记：卡在哪一步、当时界面、之前有没有读过档、有无截图。集中验证的五个路径是新游戏、继续、读档、设置、退出。
