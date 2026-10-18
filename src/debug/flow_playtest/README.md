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
