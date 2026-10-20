# 任务、委托与订单投影

> 当前已增加[日程推进与任务持久结果](../systems/schedule_and_task_results.md)：完成、失败、过期、取消均由 GameState 锁存；下文 P0 的“没有永久锁存”仅保留为历史范围。TaskCatalog v1 的可选 fail_when/deadline/allow_cancel 和快照 v5 以新接口文档及源码为准。

核对日期：2026-10-18。TaskCatalog 校验静态定义，TaskJournal 只读投影 GameState，TaskDelivery 执行交付；订单板与手册读取同一事实。真实操作见[订单](order_system.md)、[交付](task_delivery.md)与[手册委托页](task_panel.md)。

## 归属与状态

定义说明目标，GameState 保存已经发生的事实，Story 控制演出和阶段，实际业务提交成功结果。任务 ID 不代替 story_stage；UI 与 Journal 不写完成事实或自行发奖。

TaskJournal 状态为 inactive / active / completed / failed / expired / cancelled：激活条件不满足则隐藏；激活且完成条件不满足为 active；两者满足为 completed；`fail_when`、`deadline` 与 `allow_cancel` 提交的终态由 GameState 锁存并覆盖投影。孤立完成事实不激活任务。首个未完成 required 目标是 current_objective；全部目标完成但最终条件未满足时等待后续事实。终态与回执规则见[日程与任务结果](../systems/schedule_and_task_results.md)。

普通当前主线按目录顺序选取；订单追踪由 OrderBoardModel 与 ui.tracked_order_id 补充，TaskHUD 优先显示当前主线的标题和目标，缺少主线时显示有效追踪订单。点击任务卡直接进入任务日志，旁侧持续显示真实钱包余额；模态打开时暂时隐藏。手册活动页与订单板已完成记录用途不同，不把任务列表当历史账本。

reset / restore 后按事实重新投影，已提交交付有独立回执保护，不能仅撤销任务完成 flag 再领奖。Journal configure 时复制 Catalog，绑定唯一 GameState.state_changed；查询返回深拷贝，投影实际变化才发 projection_changed。服务可随场景重建。

## JSON v1 Schema

Loader 位于 src/core/tasks/task_catalog.gd。顶层为 version=1 和 tasks 数组，允许空目录；未知字段、重复 ID、无效类型或引用整包拒绝并保留旧目录。load_files 先合并多个章节，再统一验证任务和订单 ID 唯一。

| 对象 / 字段 | 要求 |
| --- | --- |
| Task id / type | 唯一命名空间 ID；main 或 commission |
| title / description | 必填非空文本 |
| activate_when | 单个基础 Condition |
| complete_when | 必填 flag 或 event_completed；delivery 任务必须为 flag |
| objectives | 非空，局部 id 唯一，至少一个 required 目标 |
| reveal_when | 可选；未揭示时标题、描述及相关元数据遮蔽 |
| location_id | 可选，属于 references.locations；符号引用不自动提供坐标 |
| difficulty | 可选 low / medium / high |
| delivery | 可选，见下节 |
| rewards | 可选；text 必填非空，reveal_when 可选；items 为物品正整数表，money 为 0～2147483647 的整数 |
| Objective | id 为合法 identifier；text、complete_when 必填；required 默认 true，location_id / reveal_when 可选；hint 可选（任务指引：怎么操作，与 text 的任务项目分开，不写进 text） |

Condition 保持三种精确形状，不支持 AND / OR / 任意表达式：

| type | 参数 | 计算 |
| --- | --- | --- |
| flag | key：命名空间 | get_flag(key) 为真 |
| event_completed | id：命名空间且属于 references.events | 对应事件已完成 |
| variable_at_least | key：命名空间、value：有限数且 >0 | 当前有限数字达到阈值；不可用于最终完成条件 |

references 仅接受 events / locations 数组，条目唯一且为命名空间 ID。动态 flag / variable 仅校验键形状，拼写及写入责任仍需对照业务。

### 交付与奖励

每个 delivery 含唯一 order_id、真实 target_object_id，以及 product_id / items / drink 三者恰好一个；前两个标识符不可含点号。accepted_flag 可选，且为命名空间事实。

- product_id：静态 product 成品，默认一件。
- items：多物品正整数数量清单。
- drink：配方、基底、标签和最低口味等动态要求，引用和资格在绑定共享库存时继续校验，见[自由订单](free_tea_recipes.md#通用订单)。

Journal 只展示 rewards.text 和揭示状态，不执行结算。TaskDelivery 的真实交付经 GameState.commit_delivery 一次提交扣物品 / 杯、钱与物品奖励、完成事实、回执、批次和交付计数；自由饮品未显式配置 money 时按饮品售价，显式零也覆盖默认售价。普通非交付任务不因 Journal 显示 completed 自动发奖；独立领奖走 WalletTransactions 配置。

## 目录与正式接入

| 位置 | 当前职责 |
| --- | --- |
| src/resources/tasks/day1_stages_01_02.json | day1 的五笔 S01–S02 订单及门控 S06 特调，共 6 条 |
| src/resources/tasks/day1_stages_03_06.json | 后章扩展目录，当前 tasks 为空；MainGame 合并加载两文件 |
| src/resources/tasks/tasks.json | tutorial 的 shop.first_order 与 tavern.insomnia_order 两条示例，不是唯一正式剧情目录 |
| src/core/tasks/order_board_model.gd | 可接取 / 进行中 / 已完成订单、需求、库存、配方及追踪的只读投影 |
| src/UI/tasks/task_hud.tscn | 正式当前目标与订单追踪 HUD，由 MainGame 装配 |
| src/UI/handbook/ | 委托、异闻录、饮品图鉴共用模态和右上入口；J 是委托页快捷键 |
| src/UI/tasks/task_panel.gd | 活动任务详情；TaskPopup / TaskButton 保留独立预览用途 |
| src/core/main.gd | 注入依赖、接取 / 追踪请求与角色名字；不把制作通知转换为假交付 |

正式新游戏从标题进入 S01–S02；订单由各阶段揭示后逐笔接取。只有打开 orders 成功时写 shop.orders_viewed，查看本身不接单。固定制作只增加成品，指定顾客交付才写任务完成和 delivery.<order_id>.completed。群单按 setup 中明确的订单集合聚合，不能用 shop.orders_completed 总量替代。

Task view 包含 id/type/status/revealed/title/description/location_id/difficulty/rewards/objectives/current_objective，已揭示交付任务还带脱敏 delivery。Objective view 含 completed/required/revealed/location_id/progress/target/hint；隐藏内容不返回真实文本、位置或计数。这是显示边界，不是资源加密。

任务日志的详情把两者分开显示：text 是任务项目（要做什么），hint 是任务指引（按哪个键、找谁、走哪条路）。目标行只写叙事目标，按键步骤不混进 text，避免把设计者视角的操作说明当成任务内容剧透。

## 验证与试玩

候选检查：verify_task_system.gd、verify_task_delivery.gd、verify_task_panel.gd、verify_order_board.gd；真实界面使用 verify_order_ui.gd，动态订单使用 verify_free_recipes.gd。按[验证分级](../../tests/AGENTS.md)选最小相关范围，本轮文档维护未运行这些测试。

F5 新游戏可观察逐单接取、制作、交付与 HUD；F6 src/debug/tasks/task_panel_demo.tscn 可检查隐藏 / 长文 / 多任务。legacy_shop 的 tutorial 首单为珍珠奶茶交胖哥布林、糖浆奖励 1，不等于正式人类首单。

下列记录保留 P0 当时的环境、数量及失败，不能据其中旧入口、旧实现范围推断当前能力。

## 历史实测记录（2026-10-17）

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

## 手册入口与解锁

首个已公开活动任务出现时（包含第一天首笔奶茶订单），宿主将 `ui.handbook.tasks_unlocked` 设为 true。`TaskJournal.has_started_tasks()` 只读查询已公开的活动或完成任务；初次接入、目录重绑定和旧快照恢复均据此补齐解锁事实。Journal 和 UI 不持有另一份可写进度。任务清空后入口保留，新游戏随 GameState 整体重置后隐藏。

`MainGame.open_tasks()` 与 J 键打开统一手册的委托页，未解锁返回 ERR_UNAVAILABLE；手册图标首次优先委托，之后记住当前场景上次页签。`TaskPanel.set_embedded(close_button)` 复用原列表与详情并移除独立遮罩/标题栏，空列表焦点回到共享关闭按钮。正式模态 screen 为 `handbook`，`tasks` / `chronicle` 为其业务别名，切页不释放玩家权限。界面契约见 [UI 系统](../systems/ui_system.md)。
