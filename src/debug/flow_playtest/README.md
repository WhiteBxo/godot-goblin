# 独立流程试玩（Debug / TEST）

在 Godot 4.7 打开 [flow_playtest.tscn](flow_playtest.tscn)，按 **F6**。入口不实例化 MainGame 或正式地图，不加载 StoryDirector、正式剧情或 pending 编排。初始画面等待玩家点击，不自动播放整条流程。

## 操作与可观察结果

1. 点击「营业开始」：真实顾客从测试入口走到柜台；到达动作成功后才开放订单板。
2. 打开「订单板 · 接单」，在真实订单 UI 中接取测试珍珠奶茶订单。Esc 取消不会接单。
3. Esc 返回，打开「制作台 · 制作」，在「按订单制作」点击「制作 1 杯并入库」。红茶、奶精、珍珠、糖浆各消耗 1，成品入库；余额仍为 40，订单尚未交付。自由调配入口会提示切回测试订单，不扣原料。
4. Esc 返回，可打开「真实仓库」检查成品。点击「真实交付」后成品减少 1，测试收入 +20；顾客真实走回入口并隐藏，离场后才开放关店。
5. 点击「主动关店」：经 DayPhase 从白天进入夜晚，不会自动关店。
6. 点击「测试酒 9币 · 库存1」：通过钱包实时报价购买测试酒，余额 60 → 51，酒入库，商家库存变成 0。
7. 分别点击赌场第 1 局、第 2 局：固定净结算 +12 / -7；首局另发糖浆 1。余额依次为 63、56。没有随机、下注或赔率机制，每局必须手动结算一次。
8. 点击「交酒 · 免除测试债务」：通过真实材料交付消耗刚买的测试酒，产生交付回执后测试债务 60 → 0，余额仍为 56。完成画面可查仓库或重新试玩。

所有弹窗可用鼠标和 Esc 操作。后续动作按当前阶段开放，弹窗打开时面板动作锁定。按「重新试玩」重建本地会话；停止 F6 或退出中途动作也不会写入正式状态。

## 复用与测试规则边界

| 环节 | 实际复用 / 测试夹具 |
| --- | --- |
| 会话与库存 | 独立实例化现有 GameState；钱包、制作、交付共用其唯一库存，正式 autoload 不参与 |
| 接单与制作 | TaskCatalog、TaskJournal、OrderBoardModel、TaskDelivery、TeaProduction；真实 ShopUI / ShopPopup / 订单板 / 制作页 / 仓库 |
| 顾客到达与离开 | 现有顾客场景与 ActorDirector，等待 ActorAction 成功结果，动作失败停止流程 |
| 营业轮次 | 开始营业和单顾客准入是测试门控；正式营业、客流调度规则未在本入口定义 |
| 主动关店 | 玩家点击后调用真实 DayPhase.enter_night；不冒充正式关店剧情 |
| 酒馆购买 | get_product_quotes / get_product_quote 和 purchase；测试商品、价格、库存由夹具提供，单次购买数量为 1 |
| 两局赌场 | 第 1 局用 claim_reward，第 2 局用 spend_money，复用真实原子交易与幂等请求；固定净额和奖励均为测试规则 |
| 债务免除 | 尚无正式债务服务；本夹具定义「交测试酒 1 → 免除测试债务 60」，通过 TaskDelivery 材料交付产生回执；债务显示由该回执推导，不直接写完成 flag |

所有测试 ID、订单、金额、奖励、库存、顾客资源与位置集中在 [flow_fixture.gd](flow_fixture.gd)。夹具只复制菜单配置容器，复用现有原料定义及配方，不修改共享 Resource，不生成正式配置。流程编排与 UI 分别位于 [flow_session.gd](flow_session.gd)、[flow_panel.gd](flow_panel.gd)，宿主只负责组装、请求连接与角色动作。

GameState 新增可选 `TeaMenu` 构造参数，默认调用仍使用原有菜单；reset / restore 使用实例自己的配置。试玩会话仅由本宿主持有，无文件写入，无正式 autoload 的 reset / restore 操作。Release 在创建任何试玩服务或 UI 前退出；未接入正式入口或剧情。

## 验证记录（2026-10-18）

- Godot **4.7.2.stable**。新增 [verify_flow_playtest.gd](../../../tests/verify_flow_playtest.gd) 在实际 Metal / Forward+ 窗口通过 **75 项**检查；以视口鼠标输入操作真实按钮，以取消输入关闭弹窗，人工检查初始、顾客到达、接单、制作、仓库、完成画面。640×360 逻辑分辨率、1280×720 窗口下按钮完整可见。此前无窗口运行也通过了核心流程和布局检查。
- 覆盖缺成品 / 错目标交付、接单取消、制作不等于交付、重复请求、余额不足不推进、报价和库存变化、顾客真实到离场、主动关店、两次结算和免债回执，以及共享资源 / 正式 GameState 隔离、测试会话 reset / restore、重载和动作中途退出。
- 相关回归通过 18 个脚本：`verify_game_state`、`verify_business_session`、`verify_wallet_transactions`、`verify_task_delivery`、`verify_tea_production`、`verify_warehouse_inventory`、`verify_order_board`、`verify_order_ui`、`verify_day_phase`、`verify_ui_manager`、`verify_game_entry`、`verify_main_game`、`verify_day1_world_flow`、`verify_gameplay_bridge`、`verify_task_system`、`verify_free_recipes`、`verify_story_director`、`verify_debug_build`。需 `user://` 临时文件的既有测试在获得执行权限后重跑，未把沙箱写入失败当成通过。
- 已对照未修改的 GameState 基线：`verify_day1_stages_01_02.gd` 同样存在 1 项倒茶音效计数失败；`verify_story_authoring.py` 同样在旧 `cinematic.opening/steps[9]` 顾客移动受阻 / 超时处失败（之前 4 项通过），后续 Python 检查未执行。两项均非本次新增失败。
- 未进行 Release 导出运行；`verify_debug_build` 仅证明 Debug 侧边界，不能当成 Release 验收。未验证正式地图通行、正式客流 / 营业规则、酒馆 UI、下注 / 随机赌场、正式债务规则、正式剧情完整闭环及磁盘存档。这些内容不由测试夹具定义或发布。

复现命令（仓库根目录，`godot` 替换为本机 Godot 4.7 可执行文件）：

```sh
godot --headless --path . --script res://tests/verify_flow_playtest.gd
godot --path . --script res://tests/verify_flow_playtest.gd -- --flow-captures
```

第二条会运行自动化验收并将 6 张运行截图保存到 `/tmp/goblin_flow_*.png`；自动化仅存在于测试脚本，F6 入口保留每一步玩家操作。

本次核对的 Godot 4.7 官方契约：[可选构造参数与场景实例化](https://docs.godotengine.org/en/4.7/classes/class_object.html#class-object-private-method-init)、[视口本地坐标输入与 GUI 路由](https://docs.godotengine.org/en/4.7/classes/class_viewport.html#class-viewport-method-push-input)。因此构造参数保留默认值，输入验证明确使用视口坐标。

## 组合流程文件恢复验证（2026-10-18）

使用已有 GameState v4 完整原生快照边界，测试适配层以 `FileAccess.store_var(snapshot, false)` 写入真实文件，关闭文件后由独立 Godot 进程 `get_var(false)` 读取，再交给 `restore_state`。仅在购买 / 制作 / 交付 / 结算公开方法返回、业务提交锁释放后取快照；顾客离场可以仍在等待。没有在提交通知内部保存，没有定义正式存档点或增加正式存档系统。

复现（仓库根目录）：

```sh
python3 tests/verify_flow_persistence.py
# 其他 Godot 安装位置可增加 --godot /absolute/path/to/godot
```

[Python 驱动](../../../tests/verify_flow_persistence.py) 创建独占临时目录，启动 1 个写入进程和 8 个全新读取进程，所有业务存档与引擎日志都用显式临时路径，结束后清理。复用本入口、Fixture 菜单和隔离 GameState；不读取或修改玩家存档，不 reset / restore 正式 autoload。`project.godot` 不变；本机 Godot 的 `--user-data-dir` 不生效，因此不以该参数作为隔离依据。[Godot 测试](../../../tests/verify_flow_persistence.gd) 不写 `user://`。

| 文件检查点 | 恢复后的业务 / 可继续操作 | 余额 / 酒 / 糖浆 / 商店余量 |
| --- | --- | --- |
| 顾客交付已提交、尚在离场 | 茶任务 completed，交付回执保留；可主动关店 | 60 / 0 / 1 / 1 |
| 主动关店后重建场景 | 保持夜晚，等待酒馆购买 | 60 / 0 / 1 / 1 |
| 购买已提交、尚未更新成功展示 | 根据购买回执开放首局，不再次购买 | 51 / 1 / 1 / 0 |
| 第一局结算、第二局尚未开始 | 首局领奖及请求回执保留，只开放第二局 | 63 / 1 / 2 / 0 |
| 原夹具第二局固定亏损已结算、未免债 | 第二次扣款回执保留，等待交酒 | 56 / 1 / 2 / 0 |
| 债务已经免除 | 两个任务 completed，交付计数 2，债务 0 | 56 / 0 / 2 / 0 |
| 完成后新游戏 | 完整快照等于新建夹具默认值，任务未激活、回执清空、白天 | 40 / 0 / 2 / 1 |
| 第二局奖励已到账、尚未免债（补充业务探针） | 奖励请求与 claim 回执保留，查询回执后继续真实交酒免债 | 68 / 1 / 3 / 0 |

前六个检查点的红茶、奶精、珍珠各剩 1，成品为 0；新游戏恢复各 2。所有恢复都比较完整快照，逐项查询余额、物品、原料、商店余量、营业昼夜、任务终态、交付计数和业务回执，恢复不发 `transaction_finished`、`delivered` 或 `event_completed`。重复扣款、购买、同请求 / 换请求领奖、茶与酒交付都被拒绝且完整快照不变；未完成检查点继续办理到免债，再核对最终业务结果。

**补充探针的范围**：现有可玩赌场夹具是固定 +12 / -7，并没有第二局奖励。本次仅在测试新建的菜单副本中注入 `test_flow_second_reward_probe`（钱 +5、糖浆 +1），从真实首局文件恢复，用现有 `claim_reward` 提交后另存文件并跨进程恢复。它验证第二笔奖励到账与免债之间的业务边界，不修改共享 Resource、原试玩规则或正式赌场；其续办消费者直接查询回执后调用真实 TaskDelivery，不代表默认试玩面板支持此奖励变体。

基线及修复：未改动的 HEAD 上，七个原流程读取检查点中六个已经正确恢复业务数据，却仍停在本地 `READY`，只有新游戏正确。缺陷位于本试玩适配层：阶段和展示日志未从持久事实重建。`FlowSession.resume_business()` 现在在组装、`state_restored` 和 `state_reset` 时查询任务事实、制作记录、DayPhase 及交易回执；不会重放成功通知、再次提交业务或改写任务终态。额外取消测试还复现了旧到达回调污染新游戏，以及旧离场回调覆盖已恢复营业阶段；增加会话代次校验，丢弃替换状态之前的异步结果。

恢复的范围是业务进度。交付前后演员的位置、移动时间与剧情演出游标不在 GameState 快照中；在新场景恢复已交付状态后直接开放关店，既不重播交付，也不声称顾客离场演出已恢复。F6 仍按上方步骤手动游玩；文件验证由测试驱动调用公开服务，不新增存读档按钮。正式地图、酒馆 UI、正式赌场 / 债务服务及未接线剧情没有因此获得验收。

本次实际验证（Godot 4.7.2.stable，headless）：

- 组合文件恢复：**408 项，0 失败**（写入进程 48；八个读取进程依次 50、50、51、52、53、54、30、20）。最后只调整异步取消用例后重跑写入侧；读取侧代码与检查点业务未变，沿用此前通过结果。
- `verify_flow_playtest.gd`：75 项通过；`verify_debug_build.gd`：97 项通过，仍不等于真实 Release 导出验收。
- 直接相关回归：`verify_game_state.gd` 124 项、`verify_business_session.gd` 48 项、`verify_task_delivery.gd` 69 项及 `verify_day_phase.gd` 均通过。
- `verify_business_session` 退出时有 6 个 ObjectDB / 3 个 Resource 未释放诊断；用仅还原本任务适配层到 HEAD 的独立基线复跑，也有未释放诊断（8 / 4），不是本任务新增的通过条件失败。macOS 沙箱的 CA 证书读取提示也在基线存在，与业务断言无关，未据此扩大修复。
- 未重跑完整项目回归、正式剧情和图形截图验收：改动仅在独立 Debug 编排及其测试，不涉及核心快照格式、正式玩法或画面布局。上文历史记录的 Day 1 音效 / 旧剧情演出失败，本次未重跑，也不宣称消除。

实现依据：[Godot 4.7 原生 Variant 文件序列化](https://docs.godotengine.org/en/4.7/tutorials/io/binary_serialization_api.html)说明 `store_var/get_var` 的类型序列化边界；该页标注部分内容尚未针对 4.7 更新，本次以实际 4.7.2 文件跨进程往返补充验证。[信号连接契约](https://docs.godotengine.org/en/4.7/classes/class_object.html#enum-object-connectflags)用于区分提交通知与恢复后的主动状态查询。
