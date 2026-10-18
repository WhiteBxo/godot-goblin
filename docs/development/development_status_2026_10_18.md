# 项目开发现状（2026-10-18）

核对基线：`88684ac`。本页根据 `project.godot`、入口、宿主、玩法服务及当前资源做静态核对；本轮仅维护文档，没有运行引擎、项目测试、人工试玩或 Release 导出。下方功能状态表示源码与配置存在，历史测试记录单列。

## 入口与可玩范围

F5 → `src/UI/title/title_menu.tscn` → 新游戏 → `src/core/main.tscn`。自动演出与真实接单、制作、交付交替，当前正式内容仅覆盖 Day 1 的 S01–S02。五单完成后写 `day1.stages_01_02_completed`，停在 `day1.investigate_coins`，可以经店门往返聚落。

S03–S06 已有章节宿主和部分业务能力，但 `day1_stages_03_06.json` 的 events、对白 dialogues、Bridge phases、setup 的 auto_events / derived_facts / scene_setups，以及后四阶段任务文件的 tasks 均为空。不能将提交标题、能力测试或六阶段草稿当成完整 Day 1 发布。Day 2 有 PDF、五阶段初稿和 D 编号 pending，没有正式运行内容。

| 能力 | 当前实际范围 | 剩余边界 / 文档 |
| --- | --- | --- |
| 标题与新游戏 | 新游戏、退出、暂停返回标题；标题音乐淡入淡出与 15 秒间隔重播 | 没有继续、文件存档或设置；[入口](../guides/game_entry.md) |
| S01–S02 | 1 名人类、1 名首位哥布林、甲乙丙群客；五单交付后余额 +10、古怪金币 4 枚 | 人类为红衣顾客；群体完成按独立回执聚合；[流程](../gameplay/day_01_stages_01_02.md) |
| 订单 | 逐单接取、按单制作、暖纸订单笺、追踪 HUD、共享成品、非模态交付反馈 | 未接单不因查看而接取；没有通用随机来客 / 拒单 / 超时营业；[订单](../gameplay/order_system.md) |
| 制作与库存 | 固定配方、手动选料和批量制作；唯一跨场景库存；新表原料按次消耗 | 制作只入库，交付才结算；[制作](../gameplay/basic_tea_production.md)、[库存](../gameplay/warehouse_inventory.md) |
| 自由配方与图鉴 | 3 槽、重复辅料、独立加冰、确定性名称 / 口味 / 标签 / 成本、配方杯与首次图鉴 | 原料不会自动补给；正式爆品表为空，正式目录未发自由订单；[自由配方](../gameplay/free_tea_recipes.md) |
| 经济与交付 | 物品、钱、任务事实和回执原子提交；三类需求；钱包按当前会话提供只读商品报价 | 市场价是计算数据，没有正式购买 UI；古怪金币不与钱包兑换；[交易](../gameplay/wallet_transactions.md)、[交付](../gameplay/task_delivery.md) |
| 昼夜与采集 | DayPhase 昼夜迁移，夜转昼加一天；8 个 once / daily 采集点 | 无自动时钟、期限、failed / abandoned；醒神菇委托为 tutorial 示例；[日程](../systems/day_phase.md)、[采集](../gameplay/gathering.md) |
| 调查与 S06 业务 | 文书关闭回执、一次取血、真实返店、特调门禁和胖哥布林交付 | 独立 Debug Demo 可验证；缺正式事件、用量和异常演出；[世界流程](../gameplay/day_01_world_flow.md) |
| 潜入与投掷 | 感知、投币分心、火把命中混乱、检查点重试；配方杯六种效果及修饰 | 正式地图缺火把、四职责角色、支付、可燃物和撤离绑定，保持 PENDING；[潜入](../gameplay/day_01_stealth.md)、[饮品投掷](../gameplay/drink_throw_effects.md) |
| 聚落与地图 UI | 连续 16 区域、双向店门、昼夜显隐；已知区域轮廓和真实入口映射 | M 地图须显式 unlock_map；S04 尚未接线，任务未配地点；[聚落](../levels/settlement/README.md)、[地图 UI](../systems/ui_system.md#正式聚落地图) |
| 手册 | 委托、异闻录、饮品图鉴共用一个模态；各页独立解锁 | 空白词条保留空白，知识与物品属性不自动全揭示；[任务面板](../gameplay/task_panel.md)、[异闻录](../gameplay/chronicle.md) |
| 演出与编排 | Story / Dialogue v1、Bridge v2，角色 / 镜头 / 音频 / 标题卡；F3 编辑工程与独立预览 | 前两阶段工程为正式来源，后四阶段仅草稿；[编排](../guides/story_editor.md) |
| 音频与 UI | 23 个音效基础 ID、43 个变体，标题及日常音乐，统一交互声音；Theme / ModalShell | 自动脚步、循环环境与出入口声音未启用；[音效库](../assets/sound_library.md)、[UI](../systems/ui_system.md) |

## 状态与配置依据

- 引擎系列 4.7，仓库历史验收使用 4.7.2；Forward Plus，Windows D3D12；640×360 逻辑视口、1280×720 默认窗口、整数缩放。
- autoload 为 GameState、DevLog、MCPRuntimeProbe、PhantomCameraManager；业务服务与演出服务仍按既有生命周期分别归 GameState 和 MainGame。
- GameState 完整快照 v4；库存子快照 v3，含按次消耗、动态 drinks 和 encyclopedia；制作含 formula_requests。完整 v2/v3 可迁移，剧情 v1 和损坏 / 局部包拒绝。没有跨进程保存入口。
- `basic_menu.tres` / `day1_menu.tres` 共用配方簿与规则资源。22 种新表原料已接入口味、资格、市场价与每份 5 次；教学材料仍按份。格里芬之血不允许普通自由配方，加冰仅影响命名变体，不授予地雷。
- 正式 day1 任务目录合并前后两章文件，目前前章 6 条（五单与门控 S06 特调），后章 0 条；tutorial 的 `tasks.json` 有首单和醒神菇示例。不同配置不能混当同一剧情链。
- 玩家与 NPC 的实体层为世界 1、玩家 2、NPC 3；可见 NPC 脚底阻挡玩家，隐藏角色退出实体层。潜行输入目前改变速度 / 动画，感知由另行配置的潜入服务负责。

## 试玩入口

| 入口（F6） | 可观察内容 |
| --- | --- |
| `src/core/main.tscn` | 正式五单剧情；取消前段演出后通过“继续剧情”恢复边界 |
| `src/debug/story/legacy_shop.tscn` | tutorial 固定配方、订单和首单交付 |
| `src/core/settlement.tscn` | 聚落通行，F7 Debug 全图、Tab 路线、F4 昼夜；正式地图默认锁定 |
| `src/debug/story/day1_world_flow_demo.tscn` | 准备夜间 S05，调查文书 / 取血 / 返店，再到 S06 制作交付；非完整潜入 |
| `src/debug/stealth/drink_throw_demo.tscn` | 隔离库存和角色夹具的投掷、腐蚀、守卫状态与重试 |
| `src/debug/ui/ui_kit.tscn` / `src/debug/audio/sound_library_demo.tscn` | 主题组件 / 音效试听 |

旧洞穴是地图和调试组件；`tests/verify_main_game.gd` 构建洞穴 fixture。消失街道、第五阶段概念图、模块化素材库均有独立说明，它们不自动成为正式 S03 / S05 的宿主。

## 验证记录与限制

本轮检查覆盖 123 份项目自有 Markdown、745 个本地链接 / 锚点，未发现失效引用；18 项源码 / 数据与文档的静态事实核对通过，格式及 git diff --check 通过。未运行引擎或项目测试，也未在线逐一验证外部站点链接。各模块保留的 check 数是其当时环境与提交的记录，不累加、不视作当前全量通过。

最近实现记录可追溯到[章节系统](../gameplay/day_01_world_flow.md#工作区收尾核验2026-10-18)、[订单](../gameplay/order_system.md#试玩与验证)、[自由配方](../gameplay/free_tea_recipes.md#2026-10-18-验证记录)、[投掷](../gameplay/drink_throw_effects.md#验证与试玩)、[交互音频](../assets/sound_library.md#交互接入验证2026-10-18)。这些记录覆盖各自模块；没有一份记录证明当前基线全项目或完整六阶段已通过。

历史记录包含以下问题，当前文档任务未复跑或修复：

- Cinematic 顾客向 `(1470, 560)` 移动受阻，阻断旧集成及 `verify_story_authoring.py` 首例。
- 部分旧场景 / 设备测试读取 `PromptBar.text`，而控件公开接口为 `get_text()`；不同后续记录对原脚本和临时适配脚本的执行范围不同，不能据一次通过认定全部旧断言已修正。
- 旧 floor / walls 脚本将奶茶店宿主强转 CaveMap；洞穴模块文档保留适用范围。
- 交互音效批次记录 `verify_dialogue.gd` 的快照断言失败及隔离基线复现。
- `verify_cave_editor.gd` 是 EditorScript；`verify_player_visuals.gd` 需要实际渲染，不能当普通 headless 脚本使用。
- 部分导入 / 退出存在 MCP 或 Ogg 资源保留诊断；真实 Release 包、完整人工通关和听感仍需对应环境单独验收。旧洞穴版本的 Release 记录只证明当时边界。

## 文档维护范围

核对期间合入 65cfc35（仓库 / 制作 / 图鉴图像）及 88684ac（钱包商品报价）；相关说明同步到新基线，其他流程的源码与测试提交保留。

本轮核对根 README、文档中心、项目自有 Markdown、模块规范及随资源说明。发现过期的入口、业务状态、Schema、操作和来源约定时就地修订。当前优先级见[系统优先级](system_priority.md)，待确认决策继续使用 [P 编号](../story_authoring/day_01_integration_pending.md) 与 [D 编号](../story_authoring/day_02_integration_pending.md)。

原始剧情与设计转录、DOCX / PDF / Excel、生成提示词、日期导入记录、生成的音效映射、第三方 README 和许可证保留来源内容；适用关系由索引和当前模块说明解释。本轮不修改结构化工程、运行时数据、Beat 映射或散列，不将文档整理冒充重新编排。
