# 通用 Developer Console

已增加 F3 →「流程测试」：前两天真实检查点独立试玩、当前目标与演出限制、问题报告、补钱／补物品、快速制作及场景内定位。操作见下文“前两天测试工作流”。

已增加 F3 →「编排」：结构化工程、步骤表单 / JSON、对白编辑、排序和撤销、保存生成与独立窗口预览。完整操作与来源切换见[游戏内剧情编排](../guides/story_editor.md)。已迁移的前两阶段以工程为正式来源；下文原事件页仍可重载和触发运行时产物。

Godot 4.7.2，默认收起。F3 打开/关闭，Esc 关闭；沿用共享像素字体与暖棕主题，面板位于屏幕右侧。仅 `DebugRuntime.is_enabled()` 为 true 时由 MainGame 装配。F3 的 `debug_toggle_console` action 只在 Debug 工具创建时注册到内存 InputMap，不修改项目输入配置。

## 功能与操作

| 分区 | 内容 |
| --- | --- |
| 状态 | 当前宿主场景路径、关卡、玩家世界坐标、FPS、GameState 当前天数和剧情阶段；打开时约每 0.2 秒刷新 |
| 角色 | 1×、2×、4×、8× 移速，返回当前关卡公开出生点，确认重启当前宿主；重启保留 GameState |
| 流程测试 | 当前流程／检查点试玩／作弊调试三个子页；整段跳转用真实检查点在独立进程恢复，当前会话作弊全部记录日志 |
| 剧情 / 状态数据 | flags、variables、已完成事件的只读快照；StoryDirector 已加载事件数、当前事件和从 0 开始的步骤序号、最近错误 |
| 剧情 / 事件日志 | 跨场景单例 `DevLog` 的环形缓冲（最多 500 条，跨过门与场景重载保留）：每条含时间、来源（剧情 / 对话 / 业务 / 任务 / Bridge / 引擎 / 调试写入）、级别（信息 / 警告 / 错误）与正文；顶部“来源”下拉按分区过滤，“导出”写 `user://logs/devtools_YYYYMMDD_HHMMSS.log`，“清空日志”清空共享缓冲 |
| 剧情 / 事件 | 已加载事件列表（id、已完成标记、条件是否满足、步骤数、可选 trigger）；“重新加载”重读宿主实际加载的 JSON，“触发…”先确认再关闭面板后触发，拒绝时在结果行显示 Director 的 `last_error` 原文 |
| 业务 / 钱包 | 余额、`is_busy()`，以及最近 5 条 `transaction_finished` 的 code、message、余额与 request_id；只订阅信号，不重放历史交易 |
| 业务 / 仓库 | 按菜单顺序列出全部物品：名称（id）、`get_stock()`、`is_discovered()`；0 库存与未发现条目同样显示 |
| 业务 / 产出 | `get_order_text()` 的当前订单文本、`get_completed_count()` 已完成杯数、`is_submitting()` 是否提交中 |
| 业务 / 任务 | 当前主线任务与目标、`get_active_tasks()` 进行中列表，以及按交付对象归组的 `TaskDelivery.get_requirement(order_id)` 需求 |
| 业务 / Bridge | `GameplayBridge.get_runtime_status()`：已载入 phase 数、是否启用、当前阶段 id、是否等待、是否允许开始剧情、续接中的事件与 `last_error` |
| 写状态 / flag | Key + true/false 下拉，调用 `GameState.set_flag()`；返回 false 时回显是“值未变化”还是“Key 不符合 a.b 命名空间” |
| 写状态 / variable | Key + 值文本，按 true/false → bool、整数 → int、小数 → float、其余 → String 解析后调用 `set_variable()`，回显实际写入的类型 |
| 写状态 / 已完成事件 | event_id，调用 `GameState.complete_event()`；重复或非法 id 明确提示 |
| 写状态 / 剧情阶段 | 阶段列表读取 `day1_stages_01_02_phases.json` 的 `phases[]`，下拉显示 `id · completion.flag`；按钮只写该阶段的完成条件 flag，然后刷新 |
| 写状态 / 会话 | `GameState.start_new_game()` 之前先展开确认框，文案写明会清空钱包、库存、任务与剧情进度 |

文本可滚动、选择和复制，日志不会强制跳回顶部。没有 GameState、StoryDirector、已加载事件或角色能力时明确显示不可用/未加载，并禁用对应角色操作。观察不会加载事件、发起剧情或补造事件数据；绑定前已经发出的信号也不会补造历史日志。被拒绝的 request 没有 event_finished 信号，其原因显示在最近错误，不伪造失败日志。

业务页是纯观察口径：只调用 `get_balance()`、`is_busy()`、`get_stock()`、`is_discovered()`、`get_definition()`、`get_order_text()`、`get_completed_count()`、`is_submitting()`、`get_current_main_task()`、`get_active_tasks()`、`get_orders()`、`get_requirement()`、`get_runtime_status()` 和 `to_dict()` 这类只读 getter，不写钱包、库存、任务或剧情，也不调用 `craft()`、`deliver_to()`、`accept_order()`、`load_phases()`、`request_event()` 或 `phase_started` 相关路径。任一服务缺失时该分区显示“…不可用”，不补造数据、不报错、不崩。

仓库按菜单顺序取 `to_dict().ingredients` 的键序，因为 `get_ingredients()` 只返回已发现条目，列不出未发现与 0 库存物品；逐项值仍走 `get_stock()`、`is_discovered()` 与 `get_definition()`。任务页的交付需求来自 `TaskDelivery.get_orders()` 的 `order_id` 与 `get_requirement(order_id)`，按 `target_object_id` 归组到任务：`TaskJournal` 的投影只有交付对象、没有 `order_id`，因此面板展示实际订单 id 而不臆造任务与订单的对应关系。

交付结算走 `GameState.commit_delivery()` → `prepare_delivery()` / `_replace()`，它不产生 `transaction_finished`。所以钱包页余额会随交付刷新，但“最近交易”只记录 `add_money` / `spend_money` / `purchase` / `claim_reward` 这类请求，不把非交易流程伪装成交易结果。

Console 在 UIManager 中注册为 DebugLayer 的 modal screen。打开后 MainGame 原有的模态/剧情/Actor 合并锁禁用玩家移动及交互；底层 UI 的焦点、鼠标和处理状态由 UIManager 保存/恢复。Console 自己不取得全局暂停：P 在面板内被消费，关闭后保留原有暂停、剧情和移动禁用状态。面板打开期间，E、M、Tab 对应的聚落动线、F2 等玩法或专用调试操作不会穿透；Tab/方向键供 GUI 导航。速度下拉菜单使用原生 popup，F3 也能从 popup 关闭 Console。

“写状态”页限定为 GameState 的公开事实入口：flag、variable、已完成事件、phase 完成条件 flag，以及确认后的会话重置。“流程测试”的补钱、补物品与快速制作另经钱包、库存和制作服务的公开 API；不直接改任务终态。会话重置放在面板内的确认框之后，文案明确会清空钱包、库存、任务与剧情进度，首次点击不会清空；重启按钮同样先显示确认与取消。

写入前统一走 `_allowed("can_control")` 这一套守卫：剧情 busy、对话 active、演出控制角色期间，写状态页所有控件禁用，并显示宿主给出的具体原因；拒绝也发生在 API 内，不只是禁用按钮。每次成功写入与每次拒绝都写入来源为“调试写入”的日志（拒绝为警告级“被拒绝 · …”），正常流程的剧情、对话、业务记录与注入状态因此可以区分。

“剧情 / 事件”页只读取 `StoryDirector` 的公开查询：`get_event_ids()` 提供已加载 ID（排序仅用于显示，`request_interaction` 仍按 JSON 顺序选取第一个合格事件），`get_event_summary(id)` 给出 `once`、步骤数、`conditions_met` 和 `completed`。`completed` 直接读 GameState 的 `completed_events`，`conditions_met` 用与 `request_event` 相同的条件判断，但只做观察、不消耗 `once`、不拒绝请求；因此一次已完成的事件仍会照常被拒绝，条件不满足的事件也照常显示为“条件不满足”。

列表按 Console 的 0.2 秒刷新节流重建，且只在行内容变化时写入视图，避免每帧解析 JSON 和打断选中项。“重新加载”使用 `get_event_source_path()`——即宿主最近一次成功加载的路径（未加载时回退到 `event_file`）——调用 `load_events(相同路径)`，因此不会换成另一个文件，也不会改动 Day1 宿主在 checkpoint 里加载的目录。剧情文案保存在对白目录里，所以同一次重载还会按 `DialogueManager.get_dialogue_source_path()`（最近一次成功加载的对白路径，空表示从未加载）重新加载对白，文案改动才能立刻看到；对白正在进行时跳过并在结果行说明。busy 或收尾中由 `load_events` 自身返回 `ERR_BUSY`，面板显示该返回值与 `last_error` 原文，不自行编造原因。

“触发…”会先展开确认框，写明会锁定输入并可能移动角色/镜头；确认后 Console 先关闭自身（释放 modal，宿主准入检查才能放行），再调用 `request_event(id)`。返回非 `OK` 时面板重新打开并原样显示 `error_string(error)` 与 `last_error`（例如 `ERR_ALREADY_EXISTS` 对应 “Story event already completed: …”）。重载与触发都追加来源为“调试写入”的“调试重载事件 / 调试重载失败 / 调试触发事件 / 调试触发失败”日志；StoryDirector 五个信号的正文格式保持不变，只是多了来源与级别前缀。

“阶段进入”只写 `completion.flag`。核对实际读取路径（`gameplay_bridge.gd` 的 `_eligible()` / `_save_flag_wait()`）后的结论：`GameplayBridge` 观察到该 flag 后自行写入 `completion_flag`，并用它作为 `next_event` 的完成条件，所以 Console 不写 `completion_flag`，也不调用 StoryDirector 或 Day1ShopController 的任何方法。推进还要求 `story_stage == phases[].stage` 且 `after_event` 已完成；这两项不写入——它们由剧情事件自身的 `set_stage` 和前序事件完成产生。当前阶段不匹配时，写入的 flag 处于“预置”状态，等流程到达该阶段（数据里 `allow_existing: true`）时自动完成。跨阶段直接跳转需要外部改写 `story_stage`，而 `GameplayBridge` 会把外部阶段变更判定为失效并停止等待（`verify_gameplay_bridge.gd` 已固化为期望行为），因此面板不提供跳转，只提供“写入所选阶段的完成条件”，按 1→2→3 逐段推进即可跳过经营与对话的重复劳动。

## 前两天测试工作流

1. 编辑器 F5 → 新游戏或继续游戏 → F3 →「流程测试」。工具沿用 Debug 门控；Release 不创建页面。当前流程页显示真实主线目标、阶段、Bridge 等待和写入限制；卡住时点击“导出并复制问题报告”。报告包括完整状态、宿主与坐标、剧情状态、Bridge、当前目标、存档目录和最近 500 条日志，并预留复现步骤／预期／实际结果。
2. 在“检查点试玩”点击“后台生成两天检查点”。编辑器 Godot 独立 headless 进程运行 `verify_two_day_flow.gd --ordinary-order`，生成到 `user://developer_flow/run_…`；使用独立验证存档，不读写正式存档。进程有 36000 帧上限；未写成功完成标记的批次不会出现在列表，失败时查看页面显示的 `generation.log`。
3. 结束后点击刷新。列表包含第一天 8 个、第二天 18 个现场；第一天覆盖首位客人、哥布林单客、三人组、硬币调查、首次出街、胖哥布林订单、潜入前及血奶茶制作；第二天覆盖营业等待、关店、酒馆、赌场、特调和守卫交付。第三／四天交接夹具不列入前两天测试台。
4. 选择现场并启动。新窗口通过 `GameEntry.continue_game()` 与既有完整存档校验／恢复进入游戏；每次复制到单独 `user://developer_flow/play_…` 目录，后续自动存档写入该目录，原始夹具保留。新窗口仍可 F3 打开工具。再次从相同检查点启动即可复测。
5. “作弊调试”提供 +100G、从真实物品目录选择并补充 1–100 份、当前已解锁配方一键制作一杯，以及定位到当前场景可见且启用的交互对象附近。定位检查地图通行与玩家实体碰撞，不自动执行 E 交互或产生跨场景旅行事实；缺安全落点时拒绝。制作消耗真实原料，仍需接单和指定交付；缺料先补物品。整段跳过使用检查点，局部 flag／事件操作沿用“写状态”页。

作弊影响当前窗口会话及其后续自动存档，建议在独立试玩窗口使用。演出、对白、角色接管、场景初始化或切换期间拒绝作弊；缺服务／目录时禁用对应按钮。操作成功或拒绝均记录为“调试写入”。报告在 `user://developer_flow/report_…txt`；系统支持剪贴板时同时复制，headless 保留文件导出能力。页面底部显示结果，长路径可悬停查看完整内容。独立试玩和生成仅支持具有 editor 功能标签的 Debug 引擎，导出 Debug 游戏不具备生成入口。

### 2026-10-19 验证

- `verify_two_day_flow.gd --ordinary-order --save-fixtures=…`：372 项通过；生成 28 个真实存档，其中前两天 26 个。
- `verify_two_day_persistence.gd` 对新增第一天 8 个现场逐个冷启动：每个 8 项，共 64 项通过。
- `verify_flow_test_tools.gd`：无夹具 9 项通过；带第二天 `wait_festival` 夹具的 Windows / Compatibility 图形检查通过，覆盖目录筛选、非法路径、真实补钱／补料／制作、忙碌与工具关闭门控、定位不写旅行事实、模态锁及关闭恢复；截图在本地 `.godot/flow_test_panel.png` 与 `.godot/flow_test_page_1.png`、`.godot/flow_test_page_2.png`。
- 最终后台生成入口的独立进程冒烟验证：26 个前两天现场可读，父进程 GameState 前后相同；夹具已准备在当前机器的 `user://developer_flow/` 下，可直接刷新列表使用。
- `flow_test_runner.gd` 独立进程恢复 `wait_guard` 成功，恢复前后原夹具 SHA256 一致，使用独立 `play_…` 存档目录。
- `verify_developer_tools.gd`、`verify_debug_build.gd`、`verify_main_game.gd` 通过。未执行无关模块全仓回归、正式 Release 导出或真人完整两天步行／听感验收。

部分 headless 恢复退出时仍有 ObjectDB／资源释放诊断（本轮第一天独立恢复 4 对象／1 资源），与既有恢复记录同类；断言与退出诊断分开记录。后续模块与图形运行无脚本解析错误。

实现依据：[Godot 4.7 PhysicsBody2D.test_move](https://docs.godotengine.org/en/4.7/classes/class_physicsbody2d.html#class-physicsbody2d-method-test-move) 在指定 transform 检查碰撞且不移动，启用 recovery_as_collision 检测重叠；[DisplayServer](https://docs.godotengine.org/en/4.7/classes/class_displayserver.html) 通过功能检测后写剪贴板。独立进程使用 [OS.create_process](https://docs.godotengine.org/en/stable/classes/class_os.html#class-os-method-create-process) 的参数数组与默认隐藏控制台；4.7 OS 页面在本次文档服务不可访问，补查官方 stable 页并在本地 4.7.2 实测。

## 装配与公开接口

- `MainGame._create_debug_components()` 在聚落、奶茶店或洞穴的玩家、出生点、镜头及剧情服务初始化完成后调用，正式初始化不依赖 Console。
- 洞穴布局覆盖仍由 `CaveDemoController` 在绑定移动查询前应用，其余洞穴工具在初始化后启动；`SettlementPreview` 仍独立管理聚落全图和动线。
- `DeveloperTools.configure(set_multiplier, get_multiplier, panel, context = {})` 保留原来的两个 Callable 接口。重绑断开旧面板与 StoryDirector 连接，保留目标已有倍率。倍率能力缺失返回 ERR_UNCONFIGURED，但观察仍可使用；工具关闭或面板无效时返回 ERR_UNCONFIGURED 并隐藏。
- 写状态页的公开入口是 `write_flag()`、`write_variable()`、`complete_event()`、`enter_phase(index)`、`reset_session()`，全部返回 bool，拒绝原因写进面板结果行与“调试写入”日志。`get_phases()` 返回阶段数据的只读副本；阶段列表在 `configure()` 时从 `PHASES_PATH` 读取，phase id 不写进 GDScript。
- 业务页的公开入口是 `DeveloperTools.bind_business_services(context)`：context 注入 `transactions`、`inventory`、`production`、`tasks`、`delivery`、`bridge` 六个场景服务，`MainGame._create_debug_components()` 用既有的 `get_transactions()`、`get_warehouse_inventory()`、`get_tea_production()`、`get_task_journal()`、`get_task_delivery()`、`get_gameplay_bridge()` 提供；缺失或类型不符时只让对应分区显示不可用，业务代码本身不改。
- `transaction_finished` 在 `_bind_transactions()` 中先断开再连接，工具离树时解除；结果只保留最近 5 条，重绑到同一钱包对象时不丢历史，换对象或缺失时清空，避免展示过期结果。
- `GameplayBridge.get_runtime_status()` 返回独立只读字典（enabled、phase_count、phase_id、stage、next_event、waiting、inflight、allows_story_start、last_error），只读现有字段：不触发 `load_phases()`、不请求 `next_event`、不改等待与预置状态，写法与 `StoryDirector.get_runtime_status()` 一致。
- context 注入 `status`、`respawn`、`restart`、`can_control`、`can_restart` Callables，以及 `state`、`story`、`dialogue`、`ui_manager` 场景服务。角色与重启能力分别判定；当前宿主不是 SceneTree.current_scene 时禁用重启。
- `PlayerController` 统一公开 `set_speed_multiplier()`、`get_speed_multiplier()`、`get_movement_speed()` 与 `teleport_to()`，CavePlayer 和 ShopPlayer 继承；瞬移停止现有运动，各子类刷新自己的镜头。Console 不写玩家、GameState 或剧情私有变量。
- `StoryDirector.get_runtime_status()` 返回独立只读数据，不调用 Loader，不改变 dispatch。`bind_story_director()` 现在把订阅转交 `DevLog`：Console 只保留引用用于页面观察，换场景或重载时重绑，旧场景离树不会拆掉新宿主的订阅。
- 事件页的公开入口是 `reload_story_events()`、`trigger_story_event(event_id)` 与 `get_event_message()`；它们只用 `StoryDirector` 的 `get_event_ids()`、`get_event_summary()`、`get_event_source_path()`、`load_events()`、`request_event()` 和 `last_error`，不读 `_library`、不写事件数据、不重排事件顺序。`trigger_story_event()` 只应在面板确认之后调用，它自己会先 `close_panel()`。
- UIManager 的可选 `uses_native_gui_input()` view 接口允许 Console 使用原生 OptionButton/TextEdit 导航；既有业务界面继续使用原来的输入路由。
- 通用 controller 挂 Systems，使用 Always；panel 挂 DebugLayer（50）。Release 不创建通用或场景专用调试节点，不注册 F3 action，不处理调试请求；MCPRuntimeProbe 的 Release 策略保持不变。
- 日志侧新增两条公开入口：`DeveloperTools.get_log()` / `export_log()`，以及 `DebugLog`（autoload `DevLog`）的 `record()`、`get_entries()`、`get_lines()`、`count()`、`clear()`、`export_file()`、`bind_services()`。按项目惯例用 `/root/DevLog` 取实例，类型与常量由 `class_name DebugLog` 提供。

## 跨场景调试日志（DevLog）

日志不再挂在 Console 节点上：`reload_current_scene` 会重建 `DeveloperTools`，每次过门又由 `GameEntry.travel_to_scene` 新实例化 `MainGame`，挂在 `Systems` 下的缓冲会跟着清零——而“正在重启”和“刚过完门”恰好是最需要日志的时刻。因此缓冲上移为 autoload：

- `src/debug/developer_tools/debug_log.gd`（autoload `DevLog`，`class_name DebugLog`）只做四件事：环形缓冲、来源/级别分区、信号订阅、导出。它不写游戏存档，也不参与 `GameState` 快照。
- 缓冲固定 500 条，每条 `{time, source, level, text}`，超出后从头部丢弃。`clear()` 清空共享缓冲，任何 Console 实例读到的都是同一份结果。
- 单行格式：`[HH:MM:SS] 来源 · 级别 · 正文`，例如 `[18:12:03] 剧情 · 错误 · 事件失败 day1.first_drink · 对话已取消`。
- 订阅来源：StoryDirector 五个信号（正文沿用原有中文格式）、`DialogueManager.dialogue_ended`（取消记为警告）、`WalletTransactions.transaction_finished`（保留 code/message，拒绝记为警告）、`TaskDelivery.delivered` 与 `delivery_failed`、`GameplayBridge.phase_started` 与 `continuation_failed`，以及引擎报错。
- 订阅由 `DevLog.bind_services(context)` / `bind_story_director()` 维护：重绑时先拆自己那一组；目标已释放时只丢弃记录、不碰它的信号（未加类型的 `Variant` 变量，避免对已释放实例做 `is` 判定）；同一实例重复绑定不会产生重复连接。旧场景离树不解除全局订阅，否则会拆掉新场景刚绑好的来源。
- 回调里只做一次入队：格式化与取时间在锁外完成，临界区只有数组追加与截断；Console 仍按 0.2 秒节流读取，并只在文本变化时写视图。
- 导出：`export_file(source = "")` 写 `user://logs/devtools_YYYYMMDD_HHMMSS.log`，文件头记录导出时间、来源过滤、条数与容量，正文是过滤后的行；返回 `{ok, path, absolute, count, error}`。面板“导出”导出当前来源视图，成功显示相对与绝对路径，失败同时显示路径与错误原因，不静默。
- 引擎报错：4.7 提供 `Logger`（`_log_error` / `_log_message`）与 `OS.add_logger()`；DevLog 在 `_ready` 装一个 logger，把 `push_error`、`push_warning`、脚本错误与 shader 报错记为“引擎”来源。`print` / `printerr` 走 `_log_message`，属于正常输出，不进缓冲。回调可能来自任意线程，所以缓冲读写共用一把 `Mutex`，并用重入标记挡住“记录自身报错”的递归。4.7.2 实测签名：`_log_error(function, file, line, code, rationale, editor_notify, error_type, script_backtraces)`，`error_type` 0=ERROR、1=WARNING、2=SCRIPT、3=SHADER；`code` 携带错误文本或 `ERR_FAIL_*` 的条件，`rationale` 携带补充说明。
- Release：autoload 节点仍在（项目配置以 `*` 注册），但 `_ready()` 第一条就是 `DebugRuntime.is_enabled()` 判定并直接返回——不装 logger、不订阅任何信号、不产生日志内容、不写文件。运行时关闭 `debug/developer_tools/enabled` 走同一条判定：`record()`、`bind_services()`、`export_file()` 全部拒绝，面板导出显示失败原因。
- 业务侧唯一改动是 `TaskDelivery` 新增 `delivery_failed(order_id, reason)` 信号（原先只有成功时的 `delivered`，失败只体现在返回的 Dictionary 里）；返回值与既有 `delivered` 行为不变，失败原因因此可被订阅而不必轮询。

## 试玩与自动验收

1. F5 从标题新游戏进入正式奶茶店；也可打开 src/core/main.tscn 或 src/core/settlement.tscn 后 F6。新进程聚落沿用 tutorial，正式出店延续 day1 会话。
2. 开始时不应出现 Console。F3 打开，观察各页签；调速后关闭，移动速度应改变，回出生点应停止残余运动且镜头重新对齐。
3. 展开面板时按住移动、E、P、M、F2；角色和底层 UI 不响应。Esc/F3 关闭后恢复控制。在店铺弹窗、剧情 busy 或暂停中打开/关闭，原状态应保留。
4. 在真实宿主正常触发剧情后查看事件日志；无剧情目录的独立宿主显示“未加载剧情事件”；正式前段有已加载事件，后章接管后的当前目录为空骨架。展开角色页的重启确认，取消不重启，确认重启保留 GameState。
5. 业务页同步：奶茶店宿主（`src/core/main.tscn`，`day1_story_enabled = true`）开场结束后 F3 → “业务”。接单前“任务”页应显示 `day1.order_human`、当前目标与“交付要求：day1_human：珍珠奶茶（成品） ×1”，“产出”页显示 `订单 #001 · 珍珠奶茶 × 1`、已完成 0 杯。做一杯后“已完成：1 杯”、仓库成品变 1 且原料减少；交付给人类顾客后钱包余额 0 → 10、任务列表清空、仓库成品回到 0，“最近交易”仍为空（交付结算不产生 `transaction_finished`，见上）。
6. Day 1 阶段跳过：F5 从标题进入新游戏（`src/core/main.tscn`，`day1_story_enabled = true`），等开场演出结束；F3 → “写状态”页 → 阶段下拉选 `day1.first_drink_tutorial · day1.human_settled` → “写入完成条件并刷新”，结果行应显示已写入完成条件 flag；也可直接在 flag 行填同一 Key 选 true 应用。关闭面板后 `GameplayBridge` 写入 `day1.human_done` 并请求 `day1.first_goblin`，第二阶段开始；再对 `day1.goblin_settled` 做一次即进入第三阶段。剧情 busy 或对话进行中，“写状态”页应整体禁用并显示“剧情演出进行中/对话进行中”等具体原因。
7. 事件页热重载：运行 `src/core/main.tscn`（Day 1 宿主），等开场演出结束；F3 → 剧情 → 事件，列表应列出 `day1_stages_01_02.json` 的事件及条件、步骤数。选中一个事件 → “触发…” → 确认，面板应先关闭再开始演出，日志出现“事件开始 …”。修改 `src/resources/dialogue/day1_stages_01_02.json` 的对应台词（或 `src/resources/story/day1_stages_01_02.json` 的步骤）后回到事件页点“重新加载”，结果行显示“已重新加载 …；对白 …”；再次触发即可看到新内容，不必重启宿主，也不必从第一阶段重走。重复触发已完成的一次性事件应被拒绝，结果行原样显示 “Story event already completed: …”。
8. 跨场景日志：从标题进入店铺宿主（`src/core/main.tscn`，Day 1），触发一段剧情让日志出现“事件开始 …”；再走到门口过门到聚落（或按 C 类门口交互），在聚落按 F3 → 剧情 → 事件日志：过门前的记录仍在，并且过门后又追加了新宿主自己的记录。把“来源”切到“引擎”只剩引擎行，切回“全部来源”恢复完整视图。点“导出”，结果行显示 `已导出 N 条到 user://logs/devtools_YYYYMMDD_HHMMSS.log（C:/Users/…/logs/devtools_….log）`，打开该绝对路径应看到同样的行；若目录不可写，结果行必须同时给出路径与错误原因。
9. 洞穴宿主运行 `tests/verify_main_game.gd` 验证：F2 墙体、M 全图/跟随、移速及地图查询保持既有行为。`cave_demo.tscn` 本身是需要注入依赖的组件。裸 `src/levels/milkTea/milk_tea_shop.tscn` 同样只是地图资源；独立游戏宿主为 `src/core/main.tscn`。

```sh
godot --headless --path . --script tests/verify_developer_tools.gd
godot --headless --path . --script tests/verify_debug_build.gd
godot --headless --path . --script tests/verify_main_game.gd
godot --headless --path . --script tests/verify_ui_manager.gd
godot --headless --path . --script tests/verify_story_director.gd
godot --headless --path . --script tests/verify_player.gd
godot --headless --path . --script tests/verify_milk_tea_shop.gd
godot --headless --path . --script tests/verify_settlement.gd
godot --headless --path . --script tests/verify_gameplay_bridge.gd
```

`verify_debug_build.gd` 分别组装聚落、奶茶店和洞穴；Debug 还逐一关闭工具重测，并实际确认重载奶茶店宿主。Release 分支保留出生、移动、无调试节点、MCP 停止、按键无效及布局参数无效的断言。洞穴通行数以保存的 TileMap 地板为基准，替代旧测试已经过时的 6309 个 JSON 格子假设。

真实构建验收须在临时项目副本中纳入 tests 脚本和 fixtures，使用匹配版本模板分别导出 Debug/Release，再以 `--script res://tests/verify_debug_build.gd -- --original-layout` 运行。正式导出仍排除 tests。编辑器关闭工具或编辑器加载 Release PCK 都不等同于运行 Release executable。

2026-10-17 验证：工具 33 项、构建/输入 97 项、洞穴架构 72 项、UIManager 47 项、StoryDirector 163 项、Gameplay Bridge 246 项，以及玩家、奶茶店、聚落测试通过，三个 Console 页签已用有渲染的 Godot 窗口截图检查。额外 `verify_cinematic_integration.gd` 为 286 项、5 失败；未修改 HEAD 的临时副本复现相同五项：角色移动终点、顾客移动受阻及关联开场完成/时长/阶段断言。本次保留原断言，不调整地图与剧情来掩盖失败。机器缺少 export templates，真实 Debug/Release 导出运行尚未覆盖。

2026-10-17 写状态页：`verify_developer_tools.gd` 91 项 0 失败（新增断言覆盖 flag/variable/事件写入、busy 与禁用工具拒绝、阶段进入只写完成条件 flag、重置确认，以及来源为“调试写入”的日志），`verify_debug_build.gd` 97 项 0 失败（Release 不创建节点、不注册 F3 的边界未变）。

2026-10-17 业务页：同一次 `verify_developer_tools.gd` 91 项 0 失败中的新增断言覆盖钱包余额与交易 code/message、最近 5 条上限、仓库菜单顺序与 0 库存未发现条目、产出订单文本、任务交付需求、Bridge 阶段与 `last_error`、服务缺失时逐分区显示不可用，以及 refresh 前后 `GameState.to_dict()` 与任务投影完全不变（观察不改变业务）。`verify_debug_build.gd` 97 项 0 失败。店铺宿主实测（做一杯并交付）截图为 `artifacts/console_business_01_order_production.png` ～ `08_after_delivery_inventory.png`，数值与订单/任务状态同步变化。

2026-10-17 跨场景日志：`verify_developer_tools.gd` 152 项 0 失败（新增断言覆盖两个独立 Console 实例共享同一缓冲、跨实例清空、旧宿主释放后继续累积、七类来源与三档级别、来源过滤不改缓冲、导出文件落地且含关键行、导出路径命名、禁用状态不订阅/不记录/不写文件）；`verify_debug_build.gd` 97 项 0 失败；`verify_task_delivery.gd` 69 项 0 失败（新信号不改变既有返回与 `delivered` 行为）。以上均用本机 `Godot_v4.7.2-stable_win64` headless 实跑，Release 真实导出仍受限于缺少 export templates。

2026-10-17 事件页：`verify_developer_tools.gd` 118 项 0 失败（新增断言覆盖事件 id 列表、条件/步骤数/完成状态投影、未知 ID 返回空、重载复用宿主真实路径后列表随之变化、重载同时刷新对白目录、触发前确认、成功触发与 `ERR_ALREADY_EXISTS` / `ERR_BUSY` 原文回显、busy 时重载被拒绝、观察不自动 load）；`verify_story_director.gd` 163 项、`verify_dialogue.gd` 154 项、`verify_debug_build.gd` 97 项、`verify_main_game.gd` 73 项均 0 失败。事件页仅跑 headless 测试与 `--headless --editor` 场景导入，未做有渲染窗口截图；热重载的可见文案变化需按上文第 7 步手动确认。

## 本次使用的官方文档

- [4.7 InputEvent 分发](https://docs.godotengine.org/en/4.7/tutorials/inputs/inputevent.html)：`_input` 先于 GUI 和 `_unhandled_input`；使用 InputMap actions，消费事件阻止专用调试工具接收。
- [4.7 Input](https://docs.godotengine.org/en/4.7/classes/class_input.html)：Input 单例轮询不受事件 handled 状态影响，因此玩家移动另外通过宿主合并锁禁止。
- [4.7 Window.window_input](https://docs.godotengine.org/en/4.7/classes/class_window.html#class-window-signal-window-input)：下拉 popup 独占输入时仍能接收 F3 并关闭 Console。
- [4.7 Control 焦点与 mouse_filter](https://docs.godotengine.org/en/4.7/classes/class_control.html)：modal 捕获鼠标，焦点管理沿用 UIManager，文本和选项保留原生交互。
- [4.7 暂停与 process mode](https://docs.godotengine.org/en/4.7/tutorials/scripting/pausing_games.html)：Console 使用 Always，在原有暂停中仍可查看；不擅自解除全局暂停。
- [4.7 Logger](https://docs.godotengine.org/en/4.7/classes/class_logger.html) 与 [4.7 OS.add_logger](https://docs.godotengine.org/en/4.7/classes/class_os.html#class-os-method-add-logger)：引擎日志接口可接入，因此“引擎”来源用真实回调实现，不做轮询或 `var_to_str` 之类的假实现。
- [4.7 singletons / autoload](https://docs.godotengine.org/en/4.7/tutorials/scripting/singletons_autoload.html)：跨场景状态放 autoload；本项目在 `--script` 模式下无法解析 autoload 全局名，所以按既有惯例用 `/root/DevLog` 取实例，类型由 `class_name` 提供。
