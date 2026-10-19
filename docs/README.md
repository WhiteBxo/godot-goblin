# 文档中心

本页索引项目维护的全部文档，核对日期 2026-10-19。当前能力先读[两工作树整合记录](development/two_day_integration_2026_10_19.md)：已接通两天剧情和第三天交接，验证及剩余限制单独记录。首次试玩先读[项目 README](../README.md)和[启动与新游戏](guides/game_entry.md)；开发前读[通用协作规范](../AGENTS.md)，再按其中索引读取相关模块的 `AGENTS.md`；编排剧情先读[简版写作指南](guides/story_authoring_fields_quick_guide.md)与[编排工作流](guides/story_authoring_workflow.md)。

## 分类与命名规范

| 目录 | 内容 |
| --- | --- |
| `guides/` | 启动和新游戏、剧情写作、编排工作流与指令参数。 |
| `systems/` | 状态、对话、剧情调度、角色、镜头、音频、UI 与转场。 |
| `gameplay/` | 制作、库存、交易、任务、采集、见闻录和交互反馈。 |
| `levels/` | 奶茶店、聚落和旧洞穴 Demo；截图随对应说明保存。 |
| `assets/` | 人物、音效、模块化素材库和素材导入记录。 |
| `design/` | 策划、分阶段剧情草稿和原始附件；设计目标不等于已实现能力。 |
| `story_authoring/` | Beat 映射、验证清单及待定项；不供游戏运行时加载。 |
| `development/` | 当前项目现状、开发者面板、持续优先级与带日期的历史审查 / 快照。 |
| `disappeared_street/` / `stage_05_concept/` | 独立街道美术试玩 / 第五阶段概念提案；不代表正式剧情已接通。 |

- 目录和文件名使用英文小写 `snake_case`，Markdown 使用 `.md`；中文用于标题与正文。`README.md`、各级 `AGENTS.md` 和许可证沿用约定名称。
- 文件按主题命名，例如 `warehouse_inventory.md`。剧情天数、场次、阶段统一两位数，例如 `day_01_scene_01.md`、`day_01_stages_01_02_draft.md`。
- 版本含义写入名字：`_draft` 为草稿、`_revised` 为修改稿、`_development_spec` 为执行规格、`_pending` 为待定清单；原稿与修改稿均保留，不用“最终版”“新版2”覆盖来源关系。
- 一次性导入记录和历史快照以 `YYYY_MM_DD` 结尾，例如 `user_assets_2026_10_17.md`；持续维护的 API 说明不加日期，文内写明核对日期、版本和验证范围。
- 图片放在对应模块的 `captures/`，PDF、Excel 等策划原始附件放在 `design/source/`，保留原始内容。素材来源与许可证、测试夹具说明仍跟随 `assets/`、`tests/`；第三方说明仍跟随 `addons/`。
- 剧情映射 JSON 保留既有资源 / 事件 ID 对应的文件名，例如 `day1_scene01.json`；移动源稿时同步其引用路径，不为整理文件名改变运行时 ID。音效映射由生成工具维护，移动时同步修改生成目标。
- 文档链接相对当前文档书写；命令和代码中的项目路径相对仓库根目录，Godot 资源路径保留 `res://`。移动文档时同步检查 Markdown 链接、明文路径、生成脚本和截图输出路径。
- 设计描述目标，模块说明描述接口和验收方法，历史记录只证明当时的检查。不同稿件冲突以[Day 1 对接约定](design/day_01_integration_contract.md)和[待定清单](story_authoring/day_01_integration_pending.md)为准；当前入口与配置以代码和 `project.godot` 为准。

## 使用与编排指南

启动和新游戏、剧情写作、编排工作流与指令参数。

| 文档 | 文件 / 说明 |
| --- | --- |
| [启动、整局新游戏与返回标题](guides/game_entry.md) | `game_entry.md` |
| [剧情编排指令速查（v1）](guides/story_authoring_commands.md) | `story_authoring_commands.md` |
| [剧情编排 Markdown 写作规范（简版）](guides/story_authoring_fields_quick_guide.md) | `story_authoring_fields_quick_guide.md` |
| [自然语言剧情编排工作流](guides/story_authoring_workflow.md) | `story_authoring_workflow.md` |
| [游戏内剧情编排](guides/story_editor.md) | F3 手动编排、结构化工程、独立预览与 CLI |

## 系统与公共接口

状态、对话、剧情调度、角色、镜头、音频、UI 与转场。

| 文档 | 文件 / 说明 |
| --- | --- |
| [ActorDirector（P0）](systems/actor_director.md) | `actor_director.md` |
| [AudioManager（剧情演出第一阶段）](systems/audio_manager.md) | `audio_manager.md` |
| [CameraDirector：2D 剧情镜头](systems/camera_director.md) | `camera_director.md` |
| [昼夜、日期与章节准入](systems/day_phase.md) | DayPhase、Day1Access 与当前期限边界 |
| [通用对话系统（P0-1）](systems/dialogue_system.md) | `dialogue_system.md` |
| [GameState](systems/game_state.md) | `game_state.md` |
| [安全检查点存档](systems/save_system.md) | 单槽自动保存、有效备份、继续游戏与阶段恢复契约 |
| [日程推进与任务持久结果](systems/schedule_and_task_results.md) | 营业、代购、赌场接入接口、通知、恢复和 pending |
| [Gameplay Bridge](systems/gameplay_bridge.md) | `gameplay_bridge.md` |
| [ScreenTransition](systems/screen_transition.md) | `screen_transition.md` |
| [店铺与聚落进出](systems/scene_travel.md) | `scene_travel.md` |
| [StoryDirector / P0 Cinematic Integration](systems/story_director.md) | `story_director.md` |
| [项目 UI 系统](systems/ui_system.md) | `ui_system.md` |

## 玩法模块

制作、库存、交易、任务、采集、见闻录和交互反馈。

| 文档 | 文件 / 说明 |
| --- | --- |
| [Day 1 前两阶段正式流程](gameplay/day_01_stages_01_02.md) | `day_01_stages_01_02.md` |
| [Day 1 世界门控、调查与血液特调](gameplay/day_01_world_flow.md) | `day_01_world_flow.md` |
| [Day 1 投掷与守卫反应](gameplay/day_01_stealth.md) | 正式 RPG 首夜潜入、独立守卫与跨室内整次重试 |
| [Day 2 完整流程与试玩](gameplay/day_02_flow.md) | 五阶段主线目标、真实接单／制作／交付、关店购酒、赌场、守卫与存档验证 |
| [饮品投掷与区域效果（第三期）](gameplay/drink_throw_effects.md) | 扣杯、六种效果、区域修饰、可腐蚀物及独立试玩 |
| [初级奶茶制作](gameplay/basic_tea_production.md) | `basic_tea_production.md` |
| [订单板、按单制作与交付追踪](gameplay/order_system.md) | 逐单接取、暖纸订单笺、共享库存与 HUD |
| [营业与顾客调度](gameplay/business_scheduler.md) | 阶段发布、普通／剧情顾客、真实出入场与持久关店 |
| [统一经营会话](gameplay/business_session.md) | `business_session.md` |
| [见闻录基础模块](gameplay/chronicle.md) | `chronicle.md` |
| [人物记录](gameplay/character_records.md) | 人物解锁、情报追加、手册查看与剧情接口 |
| [采集点与任务物资提交](gameplay/gathering.md) | `gathering.md` |
| [2D 交互反馈](gameplay/interaction_feedback.md) | `interaction_feedback.md` |
| [成品携带与指定 NPC 交付](gameplay/task_delivery.md) | `task_delivery.md` |
| [任务日志与奶茶订单](gameplay/task_panel.md) | `task_panel.md` |
| [任务、委托与订单投影](gameplay/task_system.md) | 当前 Schema、目录分工与历史 P0 验证 |
| [钱包与原子交易](gameplay/wallet_transactions.md) | `wallet_transactions.md` |
| [仓库与共享库存（第一阶段）](gameplay/warehouse_inventory.md) | `warehouse_inventory.md` |
| [奶茶配方数据层（第一期）](gameplay/milk_tea_recipe_data.md) | Excel 导入、投掷参数、按次库存与旧快照迁移 |
| [自由调配、饮品图鉴与交付（第二期）](gameplay/free_tea_recipes.md) | 三槽配置、配方计算、动态成品、图鉴及通用订单 |

## 关卡与地图

奶茶店、聚落和旧洞穴 Demo；截图随对应说明保存。

| 文档 | 文件 / 说明 |
| --- | --- |
| [洞穴墙体 demo 接入说明](levels/cave_demo/README.md) | `cave_demo/README.md` |
| [巢穴地图 Tile Demo](levels/cave_demo/source_demo.md) | `cave_demo/source_demo.md` |
| [奶茶店开放房间与遮挡渐隐](levels/milk_tea_map.md) | `milk_tea_map.md` |
| [奶茶店宿主与试玩](levels/milk_tea_mvp.md) | 当前开放房间地图、五单入口、制作与导航 |
| [新版洞窟聚落](levels/settlement/README.md) | `settlement/README.md` |
| [RPG Maker 地图移植与编辑](levels/rpg_maker/README.md) | 四张原生 TileMapLayer 地图、完整源素材、独立试玩与重导入 |
| [消失街道独立试玩](disappeared_street/README.md) | 美术、通行与店门连接示例 |
| [第五阶段概念提案](stage_05_concept/README.md) | 静态概念图及来源差异，非正式可玩关卡 |

## 素材与导入

人物、音效、模块化素材库和素材导入记录。

| 文档 | 文件 / 说明 |
| --- | --- |
| [游戏人物与美术接入](assets/characters.md) | `characters.md` |
| [主角对话立绘：平静 / 说话](assets/imports/player_dialogue_portraits.md) | `imports/player_dialogue_portraits.md` |
| [2026-10-19 古文书与洞窟全图](assets/imports/elder_feedback_2026_10_19.md) | 用户原图、来源散列与显示接入。 |
| [2026-10-18 奶茶与原料素材更新](assets/imports/user_assets_2026_10_18.md) | 36 张 PNG、来源映射与接入边界。 |
| [2026-10-18 卷轴与猫鸡素材导入](assets/imports/2026-10-18_story_and_creature_assets.md) | 22 个文件、归类与未接线边界。 |
| [2026-10-17 用户素材导入清单](assets/imports/user_assets_2026_10_17.md) | `imports/user_assets_2026_10_17.md` |
| [独立家具、道具与墙体素材库](assets/modular_assets/README.md) | `modular_assets/README.md` |
| [Sound Library v1](assets/sound_library.md) | `sound_library.md` |
| [音效 ID 与资源映射（生成文件）](assets/sound_library_ids.md) | `sound_library_ids.md` |
| [后续流程 BGM 缺口与生成提示词](assets/bgm_prompts.md) | 待制作曲目、提示词与接线位置 |

## 设计与剧情源稿

策划、分阶段剧情草稿和原始附件；设计目标不等于已实现能力。

| 文档 | 文件 / 说明 |
| --- | --- |
| [Cinematic 开场（工作流基准稿）](design/cinematic_opening.md) | `cinematic_opening.md` |
| [Day 1 精简版剧情冒险：开发执行规格（Godot 2D）](design/day_01_development_spec.md) | 历史精简执行规格；仅用于范围差异对照。 |
| [Day 1 正式剧情与业务配置约定](design/day_01_integration_contract.md) | 已发布 ID、前段工程来源、后段预留及事务 / 宿主边界。 |
| [新地图与两天流程对接约定](design/two_day_flow_integration_plan.md) | 2026-10-19 用户逐项确认的地图、经济和玩法规则；实现状态另见模块记录。 |
| [第一天与第二天的场景连接约定](design/scene_connections.md) | 空间拓扑约定，不代表全部导航 / 剧情已发布。 |
| [day1_scene01](design/day_01_scene_01.md) | 独立试编排源稿；资源文件名 day1_scene01，事件 ID 为 day1.scene01。 |
| [Day 1 前两个阶段：剧情演出初稿](design/day_01_stages_01_02_draft.md) | 保留来源；现行演出 / 对白以结构化工程为准。 |
| [Day 1 第三至第六阶段：剧情演出初稿](design/day_01_stages_03_06_draft.md) | S03–S06 Beat 化初稿，对白逐字取自修改版；冲突仍按 pending。 |
| [第一天:一杯奶茶引发的异世界生](design/day_01_story_flow.md) | 原 PDF 转录稿，保留原文和开发备注。 |
| [第一天](design/day_01_story_flow_revised.md) | 按 10-19 新附件补入赠送食材与试饮；保留已确认的首次出店与返店流程。 |
| [Gameplay Bridge 独立验收剧情](design/gameplay_bridge_demo.md) | `gameplay_bridge_demo.md` |
| [系统设计文档:奶茶店系统与异世界见闻录](design/milk_tea_system_and_otherworld_chronicle.md) | `milk_tea_system_and_otherworld_chronicle.md` |
| [真实订单 Gameplay Bridge 最小示例](design/order_bridge_demo.md) | `order_bridge_demo.md` |
| [day_02.pdf](design/source/day_02.pdf) | 37 页旧剧情 PDF，保留旧 Beat 来源。 |
| [第二天剧情修改稿](design/day_02_story_flow_revised.md) | 38 页新 PDF 完整转录；新增第二天购买醒神菇对白及配方发现。 |
| [洞窟聚落对话与原料补充稿](design/settlement_dialogue_supplement_revised.md) | 九组 NPC、三名小贩及六条免费采集原文，尚未编排。 |
| [两天剧情与聚落补充更新记录](design/story_source_update_2026_10_19.md) | 三份附件来源、正文差异、配方奖励时限与救治期限等待确认项。 |
| [Day 2 五个阶段：剧情演出初稿](design/day_02_stages_01_05_draft.md) | 由 day_02.pdf 逐字整理的 Beat 化初稿。 |
| [经营与战斗经济规则（10-19）](design/milk_tea_economy_revised.md) | 现行设计：人类 3G、哥布林持久槽位定价、爆品 150G、战斗独立采购及来源冲突。 |
| [爆品配方配置（开发可视版）](design/signature_recipes_revised.md) | S01–S10 十款完整配方、图鉴与发现原文；已接入游戏，按新版专属售价、加冰条件和一次性发现奖励执行。 |
| [新经济实现方案](design/milk_tea_economy_implementation_plan.md) | 经营阶段 1–3 已接通；保留原始差距分析，独立战斗采购待实施。 |
| [奶茶配方系统 V0.1](design/milk_tea_recipe_system_revised.md) | 保留原文与 12 张表格；售价等冲突规则由 10-19 经济方案替代。 |
| [22 种原料 2.0 配置](design/recipe_ingredients_revised.md) | 10-19 原料来源，经营等级、价格及用量已导入运行时。 |
| [2026-10-18 配方资料更新与旧稿处理](design/milk_tea_recipe_update_2026_10_18.md) | 导入当时记录及后续运行时实现入口。 |
| [设计原始附件索引](design/source/README.md) | 10-19 Excel/PDF、新旧来源关系与内容哈希，保留旧稿。 |
| [otherworld_ingredients_and_drinks.xlsx](design/source/otherworld_ingredients_and_drinks.xlsx) | 旧运行时基线及 W/H、图鉴互补资料。 |
| [异世界食材与酒品：源稿到运行时映射](design/otherworld_data_mapping.md) | 已接入的 F/W 条目、字段映射、合并项与未接入原因。 |

## 剧情编排产物

Beat 映射、验证清单及待定项；不供游戏运行时加载。

| 文档 | 文件 / 说明 |
| --- | --- |
| [cinematic_opening.json](story_authoring/cinematic_opening.json) | 生成的 Beat 映射 / 验证清单，保留原资源名。 |
| [day1_scene01.json](story_authoring/day1_scene01.json) | 生成的 Beat 映射 / 验证清单，保留原资源名。 |
| [Day 1 对接待定与能力缺口](story_authoring/day_01_integration_pending.md) | P 编号的已解决 / 部分解决 / 开放状态；不改原稿决定。 |
| [前两阶段结构化工程](story_authoring/day1_stages_01_02_project.json) | 当前演出、对白与 Bridge 的可编辑正式来源。 |
| [前两阶段生成清单](story_authoring/day1_stages_01_02_bridge.json) | 工程散列、Beat 映射、产物路径与验证入口。 |
| [Day 2 对接待定与能力缺口](story_authoring/day_02_integration_pending.md) | Day 2 初稿的待定项（D 编号）。 |
| [Day 1 后四阶段与 Day 2 五阶段编排交接](story_authoring/day_01_02_authoring_handoff.md) | 原交接历史与接口说明；正式工程现已发布，当前状态见整合记录。 |
| [Day 1 S03–S06 Beat 映射](story_authoring/day1_stages_03_06_beat_map.md) | 24 Beat 的来源、事件／Phase 草案、阻塞与实际验证。 |
| [Day 2 S01–S05 Beat 映射](story_authoring/day2_stages_01_05_beat_map.md) | 29 Beat 的来源、事件／Phase 草案、阻塞与实际验证。 |
| [gameplay_bridge_demo_bridge.json](story_authoring/gameplay_bridge_demo_bridge.json) | 生成的 Beat 映射 / 验证清单，保留原资源名。 |
| [order_bridge_demo_bridge.json](story_authoring/order_bridge_demo_bridge.json) | 生成的 Beat 映射 / 验证清单，保留原资源名。 |

## 开发工具与记录

开发者面板、审查、优先级与带日期的历史快照。

| 文档 | 文件 / 说明 |
| --- | --- |
| [试玩反馈处理（2026-10-19）](development/playtest_feedback_pass_2026_10_19.md) | 20 条试玩反馈：接单跳页、群客节奏、HUD/路标/调查页、H01、立绘、左键对白、地图、守卫巡逻与首夜引导。 |
| [前两天引导与对白节奏 A+B（2026-10-19）](development/two_day_guidance_dialogue_2026_10_19.md) | 剧情 Esc 跳过、地图目标落点、存档短暂提示、换日标题卡、长按快进与自动播放。 |
| [轻量常驻 HUD 与统一菜单（2026-10-19）](development/compact_game_menu_2026_10_19.md) | 单行目标、右上角菜单收纳经营／支线／地图／设置，含新旧入口验证与截图。 |
| [前两天体验补完（2026-10-19）](development/two_day_experience_completion_2026_10_19.md) | 支线摘要、可选试饮、祭典变化、便捷返店、关键演出、赌场结果、章末回顾与基础设置。 |
| [RPG 流程优化 A–C 实施（2026-10-19）](development/flow_optimization_abc_2026_10_19.md) | 门口与宅内对象、调查 / 北侧教学、主动商业交互、顺路采集和同款批量制作，含实际检查与画面。 |
| [RPG 角色新尺度下的流程与关卡优化方案（2026-10-19）](development/flow_and_level_review_rpg_scale_2026_10_19.md) | 按 1.0 倍镜头、120 步速与缩小的交互 / 视听范围重审地图、路线与实施优先级，含三张示意图。 |
| [前两天流程体验与地图关卡审查（2026-10-19 历史基线）](development/flow_and_level_review_2026_10_19.md) | `9337cd2` 的旧参数分析；当前尺度与优化顺序以新版方案为准。 |
| [两工作树整合（2026-10-19）](development/two_day_integration_2026_10_19.md) | 单一经济账本、两天剧情、RPG Maker 地图、迁移与验证。 |
| [新版十款爆品接入（2026-10-19）](development/signature_recipes_2026_10_19.md) | 专属售价、加冰匹配、发现奖励、S06 时限、试玩与回归限制。 |
| [第二天反馈修正（2026-10-19）](development/day2_feedback_2026_10_19.md) | 当前任务与金币卡、卧室休养、独立对话立绘与守卫交付提示；含截图及验证。 |
| [前两天体验打磨（2026-10-19）](development/experience_polish_2026_10_19.md) | 制作与交付反馈、守卫警戒可读性、环境与脚步、截图及实际验证。 |
| [前两天操作手感与反馈打磨（2026-10-19）](development/feel_polish_2026_10_19.md) | 投掷准星与命中、警戒张力与被发现冲击、交互/弹窗/对白节拍、镜头前瞻与钱包浮字；含实际检查与试玩步骤。 |
| [首日可玩性修复（2026-10-19）](development/day1_playability_fixes_2026_10_19.md) | 柜台焦点、同款连续制作、说话立绘、出店调查引导与隐藏守卫交互；真实按键和步行验收。 |
| [通用 Developer Console（第一阶段）](development/developer_console.md) | `developer_console.md` |
| [项目开发现状（2026-10-18）](development/development_status_2026_10_18.md) | 10-18 历史快照，基线 88684ac；当前变化见 10-19 整合记录。 |
| [系统开发现状（2026-10-16 历史快照）](development/development_status_2026_10_16.md) | `development_status_2026_10_16.md` |
| [系统设计审查（2026-10-17 历史记录）](development/system_design_review.md) | `system_design_review.md` |
| [系统优先级：当前缺口与后续顺序](development/system_priority.md) | `system_priority.md` |

## 随资源维护的说明

| 文档 | 用途 |
| --- | --- |
| [人物素材](../assets/characters/README.md) | 原图分类、立绘与动画接入 |
| [玩家素材](../assets/characters/player/README.md) | 主角来源、274 帧动作、切帧与投掷服务接入 |
| [哥布林动作资源](../assets/characters/goblin_actions/README.md) | 四套独立动作资源、帧数、复现和预览 |
| [奶茶店地图分层](../assets/map/milk_tea_layers/README.md) | 早期生成式分层记录；现行地图另见开放房间说明 |
| [Fusion Pixel 字体](../assets/fonts/fusion_pixel/README.md) | 字体版本、来源与许可证 |
| [音效许可证](../assets/audio/LICENSE.md) | 三包 CC0 音效、派生资产及用户音乐的独立许可边界 |
| [BGM 测试夹具](../tests/fixtures/bgm_intro_loop.md) | 音频循环测试素材说明 |
| [Godot MCP](../addons/godot_mcp/README.md) / [中文说明](../addons/godot_mcp/README.zh.md) | 随插件保留的第三方文档 |

## 已知同步事项

整理时发现 `story_authoring/day1_scene01.json` 中的 `source_sha256` 与源稿不一致；该差异在本次整理前已经存在，源稿内容本次逐字保留。此前迁移仅修正 source 路径，本轮也未修改该源稿、映射或哈希，不能标记为已重新编排 / 验证通过。后续应结合[Day 1 待定清单](story_authoring/day_01_integration_pending.md)核对执行内容，再按编排工作流更新映射与哈希。
