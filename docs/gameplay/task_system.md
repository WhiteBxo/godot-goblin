# 任务 / 委托系统（P0）

日期：2026-10-17。实现依据为当前工作区，Godot 4.7.2。本文先于实现建立，验证后补充实测记录。

> 后续实现已增加 [成品携带与指定 NPC 交付](task_delivery.md)：首单不再制作后自动交付，订单板接取、成品入库、NPC 校验、任务完成及物品奖励均以该文和当前源码为准。下文保留 P0 实现时的架构记录与历史实测结果。

> 后续 UI 已增加 [委托列表与详情](task_panel.md)：可通过 HUD 按钮或 J 键查看全部活动任务。本文中的“P0 不提供列表”保留为历史实现范围。

## 仓库审查与复用

- 当前 project.godot 的正式入口为 src/core/settlement.tscn；src/core/main.tscn 是独立店铺。两者复用 MainGame。docs/development/development_status_2026_10_16.md 的入口、经营能力描述已落后于源码。
- GameState 是唯一跨场景事实源，保存 day、story_stage、flags、variables、completed_events。setter 先提交数据，再同步 state_changed；reset/restore 也先发此信号。没有文件存档。
- MainGame 在 Systems 装配库存、真实 TeaProduction、DialogueManager、StoryDirector、GameplayBridge；五个 CanvasLayer 的 layer 为 10/20/30/40/50。输入锁合并 UI modal、对白、演出与角色控制，不归任务模块。
- TeaProduction.make_drink 校验当前订单 ID、配方和库存，原子扣料并提交订单后发 changed。MainGame 读取已完成数，写 shop.order_001_delivered 等 flag 和 shop.orders_completed 的最高值，重复通知不重复计数。WarehouseInventory 独立维护实际库存与发现信息。TeaMaking 是另一种 Demo 配方会话，不可当成真实交付。
- ShopInteraction 只选择/分派交互，StoryDirector 先尝试路由；ERR_DOES_NOT_EXIST 才回退 ShopUI。interaction_succeeded 对剧情而言仅代表请求获准，不能当成剧情或订单完成。新增的订单板事实只在 ShopUI 确实展示 orders 时写入。
- StoryLibrary 完整验证 JSON 后原子替换，last_error 含上下文；StoryDirector 的 set_flag 和成功事件 complete_event 已能提供激活/结束事实。任务不发起任何剧情。
- GameplayBridge v2 等待真实 flag，并在 process 边界续播，保留 modal/暂停/取消/restore 规则。任务不另建等待器。
- UIManager 负责屏幕注册和弹窗栈；通用开发工具仅 Debug，已有 GameState 只读查看和有界事件日志可观察任务。任务 HUD 是只读、无焦点、忽略鼠标的 HudLayer 子场景，无须改 UIManager。
- CaveMap 从场景 TileMapLayer 建立通行信息；目前没有与店铺稳定接通的剧情出入口/地下拾取、潜行或小地图接口。ScreenTransition 是独立视觉组件，不等于已实现地图切换。既有 GameState 测试验证 Autoload 跨场景保留。
- 已核对 [Day 1 执行规格](../design/day_01_development_spec.md)、[原始流程](../design/day_01_story_flow.md)、[修改稿](../design/day_01_story_flow_revised.md)、[试编排稿](../design/day_01_scene_01.md) 及 order_bridge_demo 的 Story/Dialogue/Phase 和测试。剧情方向包括胖哥布林、神秘文书与格里芬之血；这些内容尚未发布，不能据此生成正式拾取结果或宣称 Day 1 完成。

## 职责与状态流转

TaskCatalog（静态 JSON 和严格校验）→ TaskJournal（只读投影）→ TaskHUD（当前主线与首个未完成必需目标）。无新增 Autoload、进度存档或任务执行器。

定义描述“要做什么”；GameState 记录“已经发生什么”；Story JSON 决定演出与阶段；实际玩法决定业务是否成功。任务 ID 不替代 story_stage，也不会反向推动它。

状态按顺序计算：激活条件不成立为 inactive，不进入活动列表；成立且完成条件不成立为 active；两者均成立为 completed。即使收到孤立完成事实，未激活任务仍隐藏。所有目标完成只使 current_objective 为空，HUD 显示等待后续剧情；只有明确 flag/已完成事件可决定最终完成。已完成任务退出当前主线 HUD，但可通过 get_task 查询。

当前目标是定义顺序中的首个未完成 required 目标；可选目标照常投影但不阻挡当前目标。多个主线同时 active 时按目录顺序选择第一个，未做追踪切换 UI。

没有永久锁存：reset、restore 或业务纠正撤销事实后，投影随之恢复。错误配方/缺货保持原目标，重试由原业务负责；关闭窗口既不完成也不失败。P0 不增加 failed/abandoned 状态或奖励重放。剧情取消不回滚已经写入的 flag，这是原 StoryDirector 的语义；结束事实应放在成功演出的末尾，或直接引用完整成功事件。restore 不自动重播剧情，Bridge 恢复仍须显式 load_phases。

TaskJournal.configure 注入同一个 GameState 与已验证 Catalog，立即计算。仅连接 state_changed 即可覆盖 reset/restore，不双重订阅附加信号。进入树时连接、离树时断开；重新 configure 先断旧连接，返回值与投影深拷贝。只有投影内容变化才发 projection_changed，刷新从不写状态。Catalog 在 configure 时复制为一份只读定义快照；热更新须显式重新 configure。

## JSON v1 Schema

所有对象拒绝未知字段；不做字符串/布尔/数字的隐式转换。名字使用至少两段合法 identifier 的命名空间（沿用 StoryLibrary.is_namespaced），推荐 snake_case。所有文本去空白后须非空。数组有序，ID 不可重复。文件或任一字段错误整体拒绝，保留旧目录，last_error 指明 tasks[index]/字段。

| 对象/字段 | 类型 | 必填/默认 | 约束 |
| --- | --- | --- | --- |
| 根 version | number | 必填 | 精确为 1，接受 JSON 解析后的 1.0，不接受 bool |
| 根 tasks | array<Task> | 必填 | 可为空；非空条目全部验证后替换 |
| Task id | string | 必填 | 唯一、命名空间 ID |
| Task type | string | 必填 | main / commission |
| Task title、description | string | 必填 | 非空文本 |
| Task activate_when | Condition | 必填 | 单一基础条件 |
| Task complete_when | Condition | 必填 | 仅 flag / event_completed，须为明确的结束事实 |
| Task objectives | array<Objective> | 必填 | 非空，至少一个 required，局部 ID 唯一 |
| Task location_id | string | 可选/省略 | 必须存在于宿主注入的 locations 注册表，不接受空串 |
| Task difficulty | string | 可选/省略 | low / medium / high；未填表示未定 |
| Task rewards | RewardInfo | 可选/省略 | 只供显示，不结算、不制定经济数值 |
| Task reveal_when | Condition | 可选/立即揭示 | 隐藏时标题/描述为 ???，地点/评级/奖励不外泄 |
| Objective id | string | 必填 | 局部合法 identifier，推荐 snake_case |
| Objective text | string | 必填 | 非空文本 |
| Objective complete_when | Condition | 必填 | 三种基础条件之一 |
| Objective required | bool | 可选/true | 可选目标不阻挡当前必需目标 |
| Objective location_id | string | 可选/省略 | 同地点注册表 |
| Objective reveal_when | Condition | 可选/立即揭示 | 隐藏文本为 ???，不返回真实地点或计数 |
| RewardInfo text | string | 必填 | 已确认的奖励说明；未定奖励直接省略 rewards |
| RewardInfo reveal_when | Condition | 可选/立即揭示 | 隐藏 text 为 ???；没有发奖能力 |

Condition 为以下三种精确形状，不支持 AND/OR/任意表达式：

| type | 其他必填字段 | 计算 |
| --- | --- | --- |
| flag | key: namespaced string | GameState.get_flag(key) == true，缺失为 false |
| event_completed | id: namespaced string | GameState.is_event_completed(id) |
| variable_at_least | key: namespaced string、value: finite number > 0 | 变量为有限 int/float 且 >= value；缺失/错误类型为未完成 |

load_file/load_json 的可选 references 字典只允许 events、locations 两个数组（默认空）。条目必须为唯一 namespaced ID。event_completed 的 ID 必须属于 events；location_id 必须属于 locations，缺失引用均报错。事件列表由宿主已加载的 StoryLibrary.get_event_ids() 提供，不能把未加载的事件猜成存在。flag/variable 为动态事实，没有静态注册表，只校验命名空间，无法检查拼写是否符合未来剧情意图。

P0 奖励采用文字元数据，以避免伪造尚未确定的金币/物品数值。未来发奖必须由有幂等保证的业务模块确认后写事实，扩展 Schema 再增加结构化奖励。地点 ID 是符号接口；references 不带坐标，不代表已实现地图标记。

## 文件与公开接口

| 文件 | 职责 |
| --- | --- |
| src/core/tasks/task_catalog.gd | load_file/load_json(text, references) → Error；get_tasks() 返回静态定义副本；last_error 提供诊断 |
| src/core/tasks/task_journal.gd | configure(catalog, state) → Error；refresh()；get_task(id)、get_active_tasks()、get_current_main_task()；projection_changed 无参数 |
| src/resources/tasks/tasks.json | 唯一正式目录，包含首笔订单任务，不包含测试/地下剧情 |
| src/UI/tasks/task_hud.gd、task_hud.tscn | bind_journal(journal)，显示当前主线/首个必需目标；260 逻辑像素最大宽度，小视口缩窄 |
| src/core/main.gd | 在 Systems/HudLayer 装配 Journal/HUD，公开 get_task_journal；监听真实订单板展示，复用原有交付映射 |
| src/UI/milk_tea/shop_ui.gd | 新增 point_opened(id: StringName)，成功 present 后通知宿主；不负责写 GameState |
| src/debug/tasks/task_demo.gd、task_demo.tscn | F6 可试玩验收宿主，仅 Debug；使用隔离测试 fixture，退出恢复进入前的 GameState |
| tests/fixtures/tasks.json | 条件、隐藏信息和地点/评级/奖励的测试数据 |
| tests/fixtures/task_story.json、task_phases.json | 原 StoryLibrary/StoryDirector/Bridge 的隔离激活、交互与结束 fixture |
| tests/verify_task_system.gd | 独立校验、投影、生命周期、真实业务和 F6 宿主验证 |
| tests/verify_main_game.gd、verify_dialogue.gd | 更新新增 HUD 的架构断言；分别验证对白无写入与订单板仅写查看事实 |

所有新 GDScript 都带 Godot 生成的 .uid。没有调整 project.godot、autoload、插件、输入、库存/订单 runtime、正式剧情 Markdown/JSON 或地图。

投影的 Task view 含 id/type/status/revealed/title/description/location_id/difficulty/rewards/objectives/current_objective；缺少可选地点/评级返回空字符串，无奖励返回空字典。Objective view 含 id/text/completed/required/revealed/location_id/progress/target；只有已揭示的计数条件才返回数字 progress/target，其余为 null。progress 为 0 到 target 的显示值；原 GameState 数值不变。没有当前必需目标返回空字典。隐藏状态不会把原始条件、文本、地点或计数交给 HUD，稳定 ID 与完成 bool 仍可用于选择和状态显示；这不是防止玩家读取游戏资源的保密机制。

## 首笔订单纵向切片

唯一正式目录 src/resources/tasks/tasks.json 定义 shop.first_order，type=main：

1. 剧情通过 set_flag 写 task.shop.first_order.active 后显示任务。P0 正式入口不自动写此 flag，不加载 Demo。
2. 玩家通过原回退 UI 打开 orders，ShopUI.point_opened → MainGame 写 shop.orders_viewed；仅靠近、打开仓库/制作台、被剧情拒绝都不算查看订单。
3. 原 TeaProduction 成功交付 → 原 MainGame 事实映射 shop.order_001_delivered → 目标即时更新。计数目标可直接读 shop.orders_completed，不复制计数。
4. 剧情显式写 task.shop.first_order.completed（或未来定义改用已验证的结束事件）→ 正式完成。目标完成和 UI 刷新不会自动执行这一步。

测试专用激活/结束事件和 phase 放在 tests/fixtures，使用真实 StoryLibrary、StoryDirector、GameplayBridge 和订单业务验证。它们不进入正式目录和宿主，不更改既有 Day 1 Markdown/对白/Beat 映射。

奶茶店、聚落、洞穴的 MainGame 使用同一个 TaskJournal/TaskHUD。场景重建时从 GameState 重算，无独立场景进度；库存/队列仍沿用原有会话生命周期，任务不将其伪装成经营存档。

## 地下委托扩展与排除范围

type=commission、location_id、difficulty、rewards 和 reveal_when 已能表达任务详情元数据；任务与每个目标可分别揭示内容。未来调查/拾取/潜行模块先确认业务成功，再通过现有协调层写 namespaced flag/variable，Journal 即可投影；需要演出续播时使用现有 Bridge。实际持有物由库存模块保证，Journal 不扣料、不生成掉落、不执行投掷/搜索/贿赂/战斗。

“潜入长老居所调查异常”只作为设计方向，不放入当前正式目录，不编造坐标、奖励、拾取或地图。未来地点注册表应由真实关卡/小地图服务提供，P0 无地图导航与标记渲染。奖励说明、完整目标列表、地点/评级可经 get_task/get_active_tasks 查询；P0 HUD 只展示当前主线/当前目标和计数，不提供完整任务图鉴或委托列表。

普通委托刷新频率/数量、难度经济数值、卫兵感知、投掷参数、特调效果、贿赂金额和容器随机掉落均待设计；没有新增通用脚本语言、并行任务图编辑器、第三方引擎、存档 UI、奖励结算或交互重构。

## 验证与验收

独立 tests/verify_task_system.gd 沿用 SceneTree + _check + 非零退出码风格。覆盖非法 schema/重复 ID/引用和原子加载，未激活隐藏、基础条件、当前必需目标、隐藏信息、显式完成、重复通知、只读性、reset/restore、Catalog/返回值隔离、Journal/HUD 重绑及离树/重建断连；在 MainGame 使用真实按钮/订单板和库存验证成功/失败/关闭，再用隔离 Story/phase 验证显式激活、等待、续播和结束。

回归执行 GameState、StoryDirector、GameplayBridge、TeaProduction、WarehouseInventory、UIManager、MainGame、MilkTeaShop、Settlement、Dialogue、InteractionFeedback、DebugBuild/DeveloperTools 与地图/转场相关测试。运行当前 Godot 4.7.2，本机不在 PATH，使用实际 exe 路径。已有失败需区分基线，不能篡改原断言使其通过。

试玩：F6 src/core/main.tscn，或 F5 当前聚落。默认无任务提示；现有 Debug 面板仅能查看状态。使用独立 src/debug/tasks/task_demo.tscn 的 F6 测试宿主，由隔离 fixture 明确激活任务后，查看订单板、正确制作第一杯可切换/完成目标；错误选择不推进，关闭弹窗恢复移动；普通宿主中任务仍 active，只有显式结束事实后 HUD 隐藏；测试宿主通过原 Bridge 运行明确的 fixture 结束事件。暂停/模态与对白按原宿主规则工作。画面需检查暖棕主题、窄屏换行、鼠标穿透与文本遮挡。

## 参考原则与 API 依据

- [REDkit quest nodes](https://cdprojektred.atlassian.net/wiki/spaces/W3REDkit/pages/6327742/HOW-TO%3A%2BUse%2Bquest%2Bnodes)：参考阶段、条件、等待和事实分工，不移植完整图引擎。匿名页面只返回目录摘要，未将不可见的完整节点规格作为实现依据。
- [RPG Maker MZ event commands](https://rpgmakerofficial.com/product/MZ_help-en/01_10.html)：复用既有共享开关/变量和公共事件职责，不为任务复制状态。
- [Yarn Spinner connecting to your game](https://yarnspinner.dev/docs/godot/gdscript/05-connecting-to-your-game/)：区分执行命令与只读查询；继续使用本仓库 StoryDirector，无新增依赖。
- [Godot 4.7 Resources](https://docs.godotengine.org/en/4.7/tutorials/scripting/resources.html)：静态数据与节点行为分离；沿用本仓库 JSON Catalog 风格和深拷贝隔离，不共享可变进度。
- [Godot 4.7 Signal](https://docs.godotengine.org/en/4.7/classes/class_signal.html)：同一 Callable 不能重复连接；连接前检查、离树主动断连，Object 释放也会自动断连。
- [Godot 4.7 Control](https://docs.godotengine.org/en/4.7/classes/class_control.html)：HUD 的所有 Control 忽略鼠标、无焦点，容器负责排版，沿用外部 Theme。

## 实测记录

执行环境：Godot 4.7.2.stable.official.ed1daf0bf；本机可执行文件为 C:/Users/TempAdmin/Documents/Codex/2026-09-30/wo/work/godot/Godot_v4.7.2-stable_win64_console.exe。以下 godot 代表该完整路径。

~~~powershell
godot --headless --path . --script tests/verify_task_system.gd
godot --path . --script tests/verify_task_system.gd -- --capture
~~~

最终独立任务测试：194 项，0 失败。第二条在项目默认 D3D12 / Forward+、RX 6700 XT 图形窗口中通过相同 194 项。另在 OpenGL Compatibility 中执行过前一版 194 项，0 失败。已查看截图 .godot/task_system/02_delivery_target.png、03_waiting_story.png、00_counter_narrow.png，检查暖棕主题、目标/等待文本、320×360 逻辑视口和无裁切；所有 HUD Control 无焦点并忽略鼠标。截图与缓存不提交。

相关回归实际通过：

| 测试脚本（tests/） | 结果 |
| --- | --- |
| verify_game_state.gd | 120 项，0 失败 |
| verify_story_director.gd | 163 项，0 失败 |
| verify_gameplay_bridge.gd | 246 项，0 失败 |
| verify_warehouse_inventory.gd | 125 项，通过 |
| verify_ui_manager.gd | 47 项，0 失败 |
| verify_main_game.gd | 72 项，0 失败（含洞穴宿主） |
| verify_dialogue.gd | 125 项，0 失败 |
| verify_interaction_feedback.gd | 46 项，0 失败 |
| verify_developer_tools.gd | 33 项，0 失败 |
| verify_debug_build.gd | Debug 模式 97 项，0 失败；不等于真正 Release 导出验收 |
| verify_editable_map.gd | 29 项，0 失败 |
| verify_screen_transition.gd | 54 项，0 失败 |
| verify_tea_production.gd | PASS |
| verify_milk_tea_shop.gd | PASS |
| verify_settlement.gd | PASS |
| verify_player.gd | PASS |
| verify_shop_camera.gd | PASS |

除文档表中另行说明的命令外，回归均用 godot --headless --path . --script tests/<name>.gd。

既有失败：verify_cinematic_integration.gd 原脚本的 /private/tmp 路径在 Windows 无法写入，先在 .godot 下建立只替换该临时文件路径的副本再执行。结果为 286 项、5 失败：原角色移动断言、顾客在 (1470, 560) 前受阻以及由此引发的时长/后续步骤/到达断言。独立临时工作区保留用户地图/玩家/配置改动，并将本次修改的 MainGame、ShopUI 和两份既有测试还原为任务开始前 HEAD 源码，复跑同样得到这 5 项失败。未调整碰撞、路线、剧情时长或降低原断言。

verify_cave_editor.gd 为 EditorScript，普通 --headless --script 和附加 --editor 均被 CLI 拒绝（只接受 SceneTree/MainLoop）；未在真实 Script 面板运行其 _run()，不记为通过。实际地图运行回归由 EditableMap 和 MainGame 洞穴宿主覆盖。未执行真实 Release 导出、完整 Day 1 通关、地下拾取/潜行、奖励结算或地图导航验收，这些未被实现。

python -X utf8 tests/verify_story_authoring.py --godot <上述 exe>：首个 cinematic.opening case 因同一顾客路线阻断，报告 2 项错误后停止，后续 cases 未执行。独立基线同样在首例报告这 2 项错误。故不能宣称旧编排全套检查通过；新任务 fixture 与真实 StoryDirector/Bridge 的执行由独立 194 项任务检查覆盖。

导入扫描成功注册三个新全局类；--editor --import 退出时有编辑器/插件资源未释放诊断，未定位其来源，正常任务与直接回归运行无 SCRIPT ERROR。没有把 import 的退出诊断算作玩法测试通过。

工作期间其它流程新增音乐提交 27f958f，HEAD 从 54a21f8 前进；按这 8 个并发提交路径重建对照后，原暂存区输出与保存的哈希一致，确认本任务未改用户暂存内容。原有 19 项变更做过内容哈希对照；随后奶茶店场景又有外部出生点/节点 UID 更新，共享菜单/Theme/地面资源也发生外部更新，均予保留，不回滚。

针对更新后的当前工作区，额外重跑任务系统、TeaProduction、WarehouseInventory、UIManager、MainGame、Dialogue、MilkTeaShop、Settlement、InteractionFeedback 共 9 个测试，全部通过；默认 D3D12 / Forward+ 图形任务测试也再次通过 194 项，截图已刷新。其余表列回归是在这些并发场景/资源更新前执行，未声称最后再次运行。

按本次用户附件要求，本任务未暂存、未创建 commit、未 push；无关新文档与并发提交也全部保留。
