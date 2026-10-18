# Godot Goblin

Godot 4.7 / GDScript 项目，当前默认进入标题菜单，选择“新游戏”后进入奶茶店。启动框架暂不自动播放剧情，完整 Day 1 仍待接入。

使用 Godot 打开 project.godot，按 F5 运行。标题菜单支持鼠标、Tab 和 Enter；游戏内 WASD / 方向键移动，E 交互，Esc 关闭弹窗或暂停。暂停菜单可以返回标题，再次选择“新游戏”会重置整局。见 [启动与新游戏](docs/guides/game_entry.md)。

新版洞窟聚落保留在 `src/core/settlement.tscn`，可打开后按 F6 运行：15 个功能区域与奶茶店共用连续平地。开发模式下 M 切换全图与跟随视角，Tab 切换剧情动线。见 [新版聚落说明](docs/levels/settlement/README.md)。

原奶茶店 MVP 保留在 `src/core/main.tscn`，旧洞穴轮廓调试组件保留在 `src/debug/cave_demo/cave_demo.tscn`；奶茶店可按 F6 单独运行，洞穴组件需由宿主注入关卡和玩家。

独立家具、道具与墙体库提供 208 张透明 PNG 和独立场景。打开 `src/debug/modular_assets/modular_assets_gallery.tscn` 后按 F6 检查；使用方法与素材清单见 [模块化素材说明](docs/assets/modular_assets/README.md)。

## 快速开始

1. 安装 Godot 4.7 系列标准版（GDScript，无需 .NET）。
2. 在 Godot 项目管理器中导入根目录的 `project.godot`，等待首次资源导入完成。
3. 按 **F5** 进入标题菜单，选择“新游戏”进入奶茶店；奶茶店和聚落仍可分别打开 `src/core/main.tscn`、`src/core/settlement.tscn` 后按 F6 单独运行。
4. 使用 WASD 或方向键移动，靠近仓库、制作台或订单板，按 E 查看对应信息。

当前配置使用 **Forward Plus** 渲染器，Windows 图形驱动为 **D3D12**；逻辑视口为 640 × 360，默认窗口为 1280 × 720。引擎、显示和输入设置以 [project.godot](project.godot) 为准。

也可在项目根目录通过命令行启动。下文假设 `godot` 已加入 PATH；否则替换为本机 Godot 可执行文件路径，PowerShell 中带空格的路径需使用 `& "完整路径"` 调用。

```powershell
# 打开编辑器
godot --editor --path .

# 运行默认主场景
godot --path .
```

仓库随附 GDScript formatter、Godot MCP 和 Phantom Camera 插件，已在项目配置中启用。常规试玩通过 Godot 编辑器运行即可。

## 操作与试玩

| 操作 | 按键 / 方式 | 可观察结果 |
| --- | --- | --- |
| 开始新游戏 | 标题菜单点击 / Tab 后 Enter | 清空上一局进度并进入奶茶店 |
| 暂停与返回标题 | Esc / P 暂停，选择“返回标题” | 退出当前场景；再次新游戏才重置会话 |
| 移动 | WASD / 方向键 | 八方向移动，斜向不加速，墙体与家具阻挡角色 |
| 地点交互 | 靠近金色标记，按 E | 打开仓库、制作台或订单板信息界面 |
| 关闭店铺弹窗 | Esc / 返回按钮 | 关闭界面并恢复移动；弹窗期间停止移动 |
| 对话推进（对话 Demo） | E / Enter / 空格 | 补全逐字文本或推进对白 |
| 选择对话分支（对话 Demo） | 上下方向键后确认 / 点击选项 | 进入对应分支 |

奶茶店已接入基础配方制作、库存扣减和订单交付，使用方式见 [基础制作说明](docs/gameplay/basic_tea_production.md)。主场景已创建对话、剧情和角色演出组件，但不会自动播放 Day 1 开场剧情，也没有接通奶茶店与洞穴之间的出入口。

## 独立 Demo

在编辑器中打开对应场景，按 **F6** 运行当前场景：

| 场景 | 用途 |
| --- | --- |
| [dialogue_demo.tscn](src/debug/dialogue/dialogue_demo.tscn) | 逐字对白、选项分支、取消及移动控制恢复 |
| [story_demo.tscn](src/debug/story/story_demo.tscn) | 自动播放开场示例，演示等待、音效、状态写入及订单板调查分支 |
| [actor_demo.tscn](src/debug/actors/actor_demo.tscn) | 顾客生成、移动、转向、表情和离场，可重播或取消 |
| [player_walk_preview.tscn](src/debug/player_walk_preview/player_walk_preview.tscn) | 玩家步行动画预览 |

例如，从命令行启动剧情 Demo：

```powershell
godot --path . res://src/debug/story/story_demo.tscn
```

洞穴地图保留地板、河道、墙体轮廓和通行查询，格子保存在关卡场景的 `TileMapLayer` 中。`src/debug/cave_demo/cave_demo.tscn` 是需要宿主注入关卡与玩家的调试组件，不是独立游戏入口。F2 切换墙体、M 切换全图 / 跟随视角等操作仅用于启用了该组件的 Debug 洞穴场景，当前奶茶店入口不提供这些功能。洞穴编辑、布局导入与截图流程见 [洞穴说明](docs/levels/cave_demo/README.md)。

## 目录结构

```text
src/
├─ core/          # MainGame 入口、GameState、对话、剧情与角色演出协调
├─ gameplay/      # 玩家控制、交互组件等玩法模块
├─ levels/        # 奶茶店、洞穴场景及关卡专属数据
├─ UI/            # 店铺界面、对话界面等
├─ resources/     # TileSet、对白与剧情事件 JSON 等共享资源
├─ shaders/       # Shader 与相关配置
└─ debug/         # 独立 Demo、动画预览及开发工具
assets/           # 地图、角色、字体、音效等素材
addons/           # 随项目提交的第三方插件
docs/             # 分类文档中心：指南、系统、玩法、关卡、素材、设计与开发记录
tools/            # 地图与角色素材处理等离线工具
tests/            # 自动化验证脚本与测试数据
```

`MainGame` 负责装配 `Systems` 与 `World`：关卡、动态实体和世界特效分别放入 `LevelRoot`、`EntityRoot`、`EffectRoot`。屏幕 UI 使用 HUD、弹窗、暂停、转场、调试五个独立层；暂停菜单由启动流程接入，屏幕转场组件可独立验证。跨场景状态由 `GameState` autoload 管理，[存档系统](docs/systems/save_system.md)提供单槽自动检查点、有效备份与标题继续游戏；当前支持 Day 1 已发布操作阶段，后续章节需配套恢复现场。

## 验证

按修改范围选择已有验证脚本。首次检出后可先通过无界面编辑器导入资源：

```powershell
godot --headless --editor --path . --quit

# 店铺、玩家与镜头
godot --headless --path . --script res://tests/verify_milk_tea_shop.gd
godot --headless --path . --script res://tests/verify_player.gd
godot --headless --path . --script res://tests/verify_shop_camera.gd

# 状态、对话、剧情与角色演出
godot --headless --path . --script res://tests/verify_game_state.gd
godot --headless --path . --script res://tests/verify_dialogue.gd
godot --headless --path . --script res://tests/verify_story_director.gd
godot --headless --path . --script res://tests/verify_actor_director.gd
```

画面与交互还需在有渲染环境的运行窗口中试玩；自动化脚本不能替代视觉验收。地图编辑器、洞穴及 Debug / Release 边界验证的额外条件见各模块说明。上述命令是验证入口，不代表当前工作区已全部通过。

通用开发者面板在聚落和奶茶店入口均可按 F3 打开，提供状态、角色控制及只读剧情观察；仅 Debug 创建。操作、接线和验收见 [Developer Console](docs/development/developer_console.md)。

## 导出与协作

- [export_presets.cfg](export_presets.cfg) 提供 `Windows Desktop` 预设；导出前安装与本机引擎匹配的导出模板，并选择输出路径。
- 导出配置包含运行时 JSON 和指定字体许可证，排除 `docs/`、`tools/`、`tests/`。离线素材处理工具不应成为游戏启动依赖。
- `.godot/` 是本地缓存，不提交；源素材、必要的 `.import` 设置和脚本 `.uid` 随项目管理。
- 静态洞穴地图以场景保存的格子为准，JSON 导入须显式执行，避免覆盖手工编辑的布局。
- 开发约定、目录职责、调试边界和提交规范见 [AGENTS.md](AGENTS.md)。

## 文档导航

完整清单、分类职责与文件命名规则见 **[文档中心](docs/README.md)**。按当前工作选择入口：

| 目的 | 文档入口 |
| --- | --- |
| 启动与试玩 | [启动和新游戏](docs/guides/game_entry.md)、[奶茶店](docs/levels/milk_tea_mvp.md)、[聚落](docs/levels/settlement/README.md) |
| 编写与编排剧情 | [简版写作指南](docs/guides/story_authoring_fields_quick_guide.md)、[工作流](docs/guides/story_authoring_workflow.md)、[全部指令](docs/guides/story_authoring_commands.md) |
| 接入 Day 1 | [内容依据与对接约定](docs/design/day_01_integration_contract.md)、[待定清单](docs/story_authoring/day_01_integration_pending.md) |
| 查看公共 API | [系统说明](docs/README.md#系统与公共接口)：状态、对话、剧情、角色、镜头、音频、UI、转场 |
| 查看玩法与验收 | [玩法模块](docs/README.md#玩法模块)：制作、库存、交易、任务、采集、见闻录 |
| 编辑地图或处理素材 | [关卡与地图](docs/README.md#关卡与地图)、[素材与导入](docs/README.md#素材与导入) |
| 查看策划与原稿 | [设计与剧情源稿](docs/README.md#设计与剧情源稿)，含原始 PDF / Excel 附件 |
| 调试与了解开发记录 | [开发者面板](docs/development/developer_console.md)、[审查与历史记录](docs/README.md#开发工具与记录) |
| 参与协作 | [AGENTS.md](AGENTS.md)、[文档分类与命名规范](docs/README.md#分类与命名规范) |

设计稿描述目标功能，模块文档中的历史实测不代表当前工作区已重新通过验收。2026-10-16 的开发现状已标为历史快照；当前入口与配置以代码、场景和 `project.godot` 为准。素材来源与授权随对应资源维护。
