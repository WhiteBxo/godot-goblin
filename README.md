# Godot Goblin

Godot 4.7 / GDScript 的奶茶店剧情冒险项目。F5 进入标题菜单，“新游戏”进入奶茶店并自动播放 **Day 1 前两阶段**：人类顾客、首位哥布林和三人群客共五单，制作入库后向指定顾客交付。完成后停在金币调查边界，可出店探索聚落；S03–S06 的正式剧情数据仍为空骨架，尚不能完整通关 Day 1。

当前功能与缺口见 [2026-10-18 项目现状](docs/development/development_status_2026_10_18.md)，完整资料见 [文档中心](docs/README.md)。本页依据源码静态核对，历史测试记录不代表本次重新运行通过。

## 快速开始

1. 安装 Godot 4.7 系列标准版（GDScript，无需 .NET），导入根目录 [project.godot](project.godot)，等待首次资源导入。
2. 按 **F5**，点击“新游戏”或用 Tab / Enter 操作标题菜单。
3. 用 E / Enter / 空格推进开场；到订单板按 E，选择并接取订单，再到制作台按单制作。
4. 关闭制作界面，携带成品到指定顾客按 E 交付。制作与交付分开，收入和物品奖励在交付时结算。

当前配置为 **Forward Plus**，Windows 使用 **D3D12**；逻辑视口 640×360，默认窗口 1280×720，`canvas_items` 整数缩放。中文字体随项目提供。入口、显示、autoload、插件与输入以 `project.godot` 为准。

在仓库根目录启动（`godot` 替换为本机可执行文件；PowerShell 带空格路径使用 `& "完整路径"`）：

```sh
godot --editor --path .
godot --path .
```

## 操作与试玩

| 操作 | 按键 / 方式 | 结果与条件 |
| --- | --- | --- |
| 移动 / 奔跑 / 潜行 | WASD 或方向键 / Shift / Ctrl | 八方向移动；Ctrl 优先；玩家受世界和可见 NPC 脚底碰撞阻挡 |
| 地点与顾客交互 | 靠近后 E | 提示框显示当前对象；订单、仓库、制作、交付沿用同一分发入口 |
| 对白与选择 | E / Enter / 空格；方向键或鼠标 | 补全文字、推进、确认分支 |
| 关闭 / 暂停 | Esc；P 暂停 | 关闭顶层弹窗；无弹窗时 Esc 暂停；可返回标题 |
| 任务与手册 | J / 右上角手册图标 | 解锁后查看委托、异闻录；首次自由制作后开放饮品图鉴 |
| 正式聚落地图 | M / 地图按钮 | 仅在聚落且显式解锁后可用；当前 S04 剧情尚未调用解锁 |
| 投掷 | F，鼠标指定落点 | 需要可用潜入服务；正式聚落配置仍缺失，独立饮品投掷 Demo 可试玩 |
| 开发工具 | F3 | Debug Console，含状态、事件、业务和剧情编排 |
| 聚落开发预览 | F7 / Tab / F4 | Debug 全图、路线、昼夜；M 留给正式地图 |

标题“新游戏”清空整局，暂停返回标题只退出场景；普通进出店铺、重载和 F3 重启保留经营会话。当前没有文件存档、自动读档或“继续游戏”。详见 [启动与新游戏](docs/guides/game_entry.md) 和 [统一经营会话](docs/gameplay/business_session.md)。

制作台默认“按订单制作”；切到外层“自由调配”后，内层有“教学配方”和“自由调配”：前者是固定配方手动选料与批量制作，后者是三槽自由配方及独立加冰选项。新表原料默认未发现、库存为零，不会为了试玩自动补给。见 [制作](docs/gameplay/basic_tea_production.md)、[订单](docs/gameplay/order_system.md)、[自由配方](docs/gameplay/free_tea_recipes.md)。

## 独立入口

编辑器打开对应场景后按 **F6**；停止进程再运行会创建新内存会话。

| 场景 | 用途 |
| --- | --- |
| [main.tscn](src/core/main.tscn) | 正式奶茶店与 S01–S02；有进度的 tutorial 会话继续原配置 |
| [settlement.tscn](src/core/settlement.tscn) | 16 区域的连续聚落；新进程直接运行沿用 tutorial 配置，正式流程出店则延续 day1 |
| [legacy_shop.tscn](src/debug/story/legacy_shop.tscn) | 旧三单队列与首单交付教学，关闭正式剧情 |
| [day1_world_flow_demo.tscn](src/debug/story/day1_world_flow_demo.tscn) | 准备夜间 S05，验证文书、取血、返店、S06 特调；潜入显示缺口提示 |
| [drink_throw_demo.tscn](src/debug/stealth/drink_throw_demo.tscn) | 隔离夹具中的配方杯投掷、守卫效果、腐蚀及重试 |
| [dialogue_demo.tscn](src/debug/dialogue/dialogue_demo.tscn) / [story_demo.tscn](src/debug/story/story_demo.tscn) | 独立对白与短事件演示 |
| [actor_demo.tscn](src/debug/actors/actor_demo.tscn) | 角色生成、移动、表情和取消 |
| [player_actions_preview.tscn](src/debug/player_actions_preview/player_actions_preview.tscn) | 四向待机、走路、奔跑、潜行、蹲伏、投掷动画 |
| [ui_kit.tscn](src/debug/ui/ui_kit.tscn) | 共享 Theme、模态组件与订单笺 |
| [sound_library_demo.tscn](src/debug/audio/sound_library_demo.tscn) | 43 个音效变体与日常音乐试听 |
| [modular_assets_gallery.tscn](src/debug/modular_assets/modular_assets_gallery.tscn) | 208 张透明家具、道具与墙体素材 |
| [disappeared_street_demo.tscn](src/debug/disappeared_street/disappeared_street_demo.tscn) | 消失街道的独立美术与通行试玩 |

旧洞穴 [cave_demo.tscn](src/debug/cave_demo/cave_demo.tscn) 是需宿主注入地图和玩家的调试组件；当前没有独立洞穴游戏入口。TileMap 编辑及适用测试见 [洞穴说明](docs/levels/cave_demo/README.md)。

## 目录与模块边界

```text
src/
├─ core/          # 入口、共享状态、剧情、角色、镜头、音频、任务、导航与日程
├─ gameplay/      # 玩家、NPC、交互、采集、制作、库存、房间与潜入
├─ levels/        # 奶茶店、聚落、旧洞穴和独立街道地图
├─ UI/            # 标题、HUD、手册、地图、订单、对白、暂停和转场
├─ resources/     # Resource、菜单、配方、TileSet、运行时 JSON 与主题
├─ shaders/       # Shader
└─ debug/         # 独立 Demo、预览、截图及开发工具
assets/           # 原始和运行素材、来源及许可证
addons/           # 第三方插件
docs/             # 指南、接口、玩法、关卡、素材、设计及开发记录
tools/            # 离线生成、导入、素材处理和编排工具
tests/            # 模块验证与隔离夹具
```

MainGame 组装 `Systems`、`World/LevelRoot`、`EntityRoot`、`EffectRoot` 和五个屏幕层；地图不执行剧情或业务。GameState 是唯一跨场景事实源，持有共享库存、制作与钱包。完整内存快照为 **v4**，库存子快照为 **v3**；完整 v2/v3 可迁移，只有剧情的 v1 拒绝恢复。详见 [GameState](docs/systems/game_state.md)。

## 验证与协作

按 [验证分级](tests/AGENTS.md) 选择与改动相关的检查，以下仅为入口示例：

```sh
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/verify_day1_stages_01_02.gd
godot --headless --path . --script res://tests/verify_order_board.gd
godot --headless --path . --script res://tests/verify_free_recipes.gd
godot --headless --path . --script res://tests/verify_drink_throw.gd
```

画面、交互及听感需在有渲染环境中观察；自动化不能代替人工验收。已知历史失败与环境限制见 [现状记录](docs/development/development_status_2026_10_18.md#验证记录与限制)。纯文档维护只检查内容、链接、格式和 diff。

- [export_presets.cfg](export_presets.cfg) 有 Windows Desktop 预设，导出前安装匹配模板并设置输出路径；JSON 和指定字体许可证已纳入，docs/tools/tests 与部分素材源目录排除。
- 仓库启用 GDScript formatter、Godot MCP、Phantom Camera；`.godot/` 缓存不提交，必要的 `.import` 与 `.uid` 随源文件管理。
- 剧情前两阶段以结构化工程为正式来源；未迁移内容仍以 Markdown 编排。见 [编排指南](docs/guides/story_editor.md)、[对接约定](docs/design/day_01_integration_contract.md)、[pending](docs/story_authoring/day_01_integration_pending.md)。
- 开发、提交和模块规范见 [AGENTS.md](AGENTS.md)。文档只描述源码已具备的能力；设计稿、历史快照、原始附件和第三方许可保留各自来源。
