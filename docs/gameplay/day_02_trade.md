# Day 2 酒馆购买与固定赌局结算

核对日期：2026-10-18，Godot 4.7.2。本轮提供独立组件、购买弹窗和隔离验证；正式入口尚未接线。未修改 GameState、钱包底层、任务 Schema / 实例、正式剧情、地图或 MainGame。自由赌博机器独立待定。

## 现有事务支持与边界

[WalletTransactions](wallet_transactions.md) 已支持整数单价、免费商品、限量 / 不限量库存、整笔扣款入库、失败无修改、成功请求跨类型去重、奖励领取以及完整会话快照恢复。成功请求 ID 保存在钱包；失败请求可在条件修正后用原 ID 重试。

当前没有报价 / 商品配置查询、运行时改价、折扣资格或多个商品共用商人余量接口。不会用“先全价购买再退款”、拆开扣款和发物，或建立另一套余额 / 库存来模拟折扣。

`TavernPurchase.compile_products(offers)` 将显式原价、显式折后整数价编译为现有 `TeaMenu.products`。这支持会话开始前已经确定的折扣，未定义浮点比例和舍入规则。正式菜单仍为空，组件不会自行采用原稿的标价或推导折后价。

**集成负责人需协调的钱包扩展**：若剧情中途才取得折扣，需要钱包在一次事务中校验价格 / 资格、更新同一商品的余量并记录请求。还需只读报价接口，让显示与钱包使用同一个配置源。该扩展会影响报价、购买校验和恢复后的折扣事实；本轮未修改底层，也未擅自新增底层契约。

## 酒馆接口与配置

文件：`src/core/economy/tavern_purchase.gd`。

| 接口 | 用途 |
| --- | --- |
| `compile_products(offers) -> Dictionary` | 纯编译，返回 `{ok, products}`；失败不提供部分商品 |
| `configure(wallet, offers) -> Error` | 注入已有共享钱包及同一份静态报价；复制配置，不重置任何会话状态 |
| `get_offers() -> Array[Dictionary]` | 目录、原价、实际单价、实时余量与物品显示名的独立副本；remaining = -1 表示不限量 |
| `get_balance() -> int` | 查询共享余额 |
| `purchase(product_id, quantity, request_id) -> Dictionary` | 直接调用钱包原子购买，保留钱包回执与错误码 |
| `changed` | 余额 / 库存 / 恢复变化通知，用于重新投影 |

`offers` 结构为 `product_id -> {item_id: String, price: int, discounted_price?: int, stock?: int}`。price 必填；discounted_price 必须显式给出最终整数价且不大于原价；省略表示原价。stock 省略表示不限量，0 表示售罄。数量、价格与库存上限沿用钱包。所有物品必须存在于共享库存目录。

装配顺序：从确认后的同一份 offers 调用 compile_products，将 products 合入会话创建所用的 TeaMenu，再由已有 GameState 创建唯一钱包；场景组件和 UI 注入该钱包及同一份 offers。不得运行中修改 Resource 并期待现有钱包自动变价，也不得在正式场景新建 WalletTransactions 替代共享会话。

configure 检查物品与钱包默认有限余量是否匹配；**钱包没有公开商品配置查询，因此无法核验注入报价中的价格 / item_id 是否与钱包内部配置完全相同**。集成必须提供钱包构造时的同源配置；只读报价接口协调前，不接入会动态变化的正式价格。静态配置不存入第二份存档，恢复时仍以同一目录创建服务。

UI 为 `src/UI/trade/tavern_purchase_popup.tscn`，继承 UIScreen，组合 ModalShell，使用现有主题。宿主调用 `popup.configure(purchase)`，在 PopupLayer 注册 `ScreenIds.TAVERN_PURCHASE` 模态，再调用 UIManager.open_screen。玩家移动锁仍由宿主根据已有模态状态协调。

界面显示余额、原价 / 折后价、数量、合计、实时余量和实际失败原因。确认请求 ID 在一次购买意图中稳定；成功后禁止重复确认，点击“再买一笔”或主动改变商品 / 数量才开始下一笔。失败保留 ID 可重试。关闭只结束本地确认，不撤销已提交交易。

## 两局固定结果与债务

文件：`src/core/economy/fixed_story_casino.gd`。通过现有 GameState 原子剧情拾取入口复用 WalletTransactions 的库存草稿提交，债务结果复用 [A 的持久任务接口](../systems/schedule_and_task_results.md)。组件不缓存可写进度。

`configure(state, full_catalog, config)` 接收 **完整合并的 TaskCatalog**，沿用 TaskJournal.configure 的绑定方式；不得以赌场子目录覆盖其他任务。config 必填：

- `debt_task_id`：目录中稳定的债务实例 ID；activate_when 必须是显式 flag。
- `loss_receipt`、`win_receipt`：不同的命名空间 flag，不得与债务激活、接单、完成或失败 flag 重合。
- `reward_items`：已确定的非空 `{共享物品ID: 正整数数量}`；缺失奖励拒绝配置。组件不提供默认奖励或选择方式。

| 接口 | 提交与恢复约定 |
| --- | --- |
| `settle_first_loss()` | 通过 commit_story_interaction 同次提交第一局回执、债务 activate_when flag 和已有 accepted_flag；不扣金币、不发物、不自动将债务置为 failed。已截止或已有终态拒绝 |
| `settle_second_win()` | 要求第一局已结算且债务仍可继续；原子提交全组奖励、真实库存与第二局回执。后一个物品满仓时，前一个也不发放；失败可重试 |
| `waive_debt(reason)` | 第二局成功后单独执行；调用 settle_task_result(task_id, "cancelled", reason)。只有目录显式允许取消且无其他终态候选时成功；不写伪造完成 flag，不消费奶茶 |
| `get_status()` | 查询 `{first_settled, second_settled, debt_result}`；恢复 / 重建后直接读取，不依赖重播信号 |

输、赢和免除是三个可恢复业务边界，对应剧情动作分别调用；组件没有编排对白和演出。第二局奖励成功、免除尚未执行时恢复，只续办 waive_debt，不能再发奖励。取消结果由 A 保存 `{status, day, phase, reason}`；failed / expired / completed 等已有终态不会被免除覆盖。

结果字典包含 ok/code/message/items/money_delta；赌场本轮 money_delta 恒为 0，真实赌资规则未定义。成功时 items 是本次真实入库的奖励；重复结算明确失败，不伪装为再次成功。

## 待定输入与接线清单

| 输入 / 接线 | 当前状态 |
| --- | --- |
| 酒馆正式商品 ID、最终整数价格、折扣资格 / 生效点、限量库存 | 目录已有琥珀酒；原稿的标价、八折推导与“最后一瓶”未写入正式经济配置，须确认后提供 |
| 赌场实际奖励清单、数量、自由挑选还是固定发放 | 未确定；由宿主先取得确认后的完整 bundle，本轮不实现选择器 |
| 债务任务实例、十杯奶茶的实际交付定义 | 接 A 的目录与结果接口；不新增正式任务 JSON |
| “第二天 / 第三天”的债务期限、昼夜及 at/after 边界 | 冲突待定；组件不补 deadline，日程推进仍由 A 接口的调用方决定 |
| 免除策略 | 宿主提供明确 allow_cancel=true 的目录；缺失权限时免除拒绝，保持原结果 |
| 正式接线 | 集成负责人装配共享服务、注册购买弹窗、接真实交互；在对应剧情动作调用两局及免除接口，并选择安全存档边界 |
| 恢复 | 只调用完整 GameState.restore_state；同源静态配置重建组件，查询持久事实，不重放已结算动作 |
| 自由赌博机器 | 独立待定：下注单位、概率、赔率、退出、破产、重复请求、可恢复状态均未实现 |

## 验证与试玩

候选命令：`Godot --headless --path . --script res://tests/verify_day2_trade.gd`。测试内的价格、奖励数量和测试任务均为隔离夹具，不能复制到正式 Day 2 配置。

图形检查：运行同一脚本，去掉 --headless 并加 `-- --capture`，生成 `.godot/day2_trade_success_640.png`、`day2_trade_success_320.png`、`day2_trade_sold_out_640.png`、`day2_trade_sold_out_320.png`。F6 打开 popup 场景可检查空配置布局；注入服务后，选数量购买，观察余额不足；补足余额购买最后库存后观察售罄；成功后重复确认不再扣钱，Esc 或关闭按钮退出模态。

实际执行均使用 `D:/download/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64_console.exe`：

| 检查 | 结果 |
| --- | --- |
| `verify_day2_trade.gd` | headless 62 项、D3D12 Forward+ 图形 62 项，均 0 失败；覆盖缺钱、售罄、重入 / 重复请求、真实多物品奖励、满仓拒绝、债务激活 / 接单 / 取消权限、完整原生文件往返、恢复后续办免除与新游戏 |
| `verify_wallet_transactions.gd` | 108 项，0 失败；原有原子提交、提交失败、余额 / 库存上限与快照契约保持通过 |
| `verify_schedule_results.gd` | 100 项，0 失败；直接依赖的 A 任务结果与恢复契约通过 |
| `verify_ui_manager.gd` / `verify_ui_theme.gd` | 47 / 215 项，均 0 失败 |
| 图形布局 | 已查看全部 4 张成功 / 售罄截图；640×360、320×360 的列表、折后价、回执反馈和按钮无截断，窄屏正常换行 |
| 交互 | 自动驱动选择、未提交的数量文本、购买 / 再买、取消 / 关闭、重开与默认焦点；均通过。未进行人工键鼠试玩 |

日志与截图保存在 `.godot/day2_*`，不提交。编辑器导入成功，退出时报告 ObjectDB / resource 未释放诊断；本轮实际模块及图形测试日志没有 SCRIPT ERROR 或失败。正式 Day 2 剧情未接线，未执行正式通关、Release 导出、自由赌博或与本轮无关的完整项目回归。

## Godot 4.7 官方依据

- [Dictionary.duplicate](https://docs.godotengine.org/en/4.7/classes/class_dictionary.html#class-dictionary-method-duplicate)：字典传引用，配置、投影和回执容器使用独立副本。
- [Signal](https://docs.godotengine.org/en/4.7/classes/class_signal.html)：连接去重、离树断开；提交完成后通知，不能在同步观察回调中重复结算。
- [SpinBox.apply](https://docs.godotengine.org/en/4.7/classes/class_spinbox.html#class-spinbox-method-apply)：点击购买前提交尚未按 Enter 的数量输入；数量控件只提供整数步进。
- [Control focus](https://docs.godotengine.org/en/4.7/classes/class_control.html#class-control-property-focus-mode)：沿用 UIScreen / UIManager 的焦点、键鼠和取消生命周期。
