# 钱包与原子交易

> 2026-10-19 规则更新：以下 10G 教学/正式五单和 20G 自由配方是当前代码行为，不再是后续经济目标。[新经济设计](../design/milk_tea_economy_revised.md)规定人类固定菜单 3G、哥布林保存槽位报价、爆品首次奖励 150G、独立战斗采购；任务奖励与实体金币表现的适配仍需核对。[实现方案](../design/milk_tea_economy_implementation_plan.md)列出事务与存档变更；本次未改余额、定价或任务配置。当前整局快照为 v5，本文后段 v4 属配方阶段接口记录，完整保存现状以[存档系统](../systems/save_system.md)和源码为准。

## 货币规则（2026-10-18 确认）

全游戏只有一种货币，写作 **G**，它就是世界观里的**古怪金币**；所有标价、任务奖励、债务与余额都以 G 为单位，界面通过 `WalletTransactions.CURRENCY_SYMBOL` / `format_money()` 统一显示。

区别只在叙事呈现，不是两套钱：主角第一次拿到它时还不知道那是钱，所以 `strange_coin` 以**剧情物品**入库，详情写「价值未知」；此后卖奶茶收款、投掷消耗、酒馆买酒一律是这同一种钱。面值 **1 枚 = 10G**（`WalletTransactions.COIN_FACE_VALUE`，换算走 `coin_worth()`），没有汇率、不打折。它被认作货币之前只记在库存里；主角弄清价值之后（Day 2 起）按面额并入钱包余额，不需要玩家操作，也不产生额外费用。Day 2 宿主开放前这一并入没有落点，暂按库存保留。

定价基准：普通成品奶茶（珍珠／椰果／原味）**10G 一杯**，Day 1 的五笔订单全部按此结算——人类首单现场付 10G，4 个哥布林单各付 1 枚（4 × 10G）。异世界食材的自由配方沿用 `RecipeRules.ordinary_price` 的 20G，因为它的单杯原料成本已接近这个量级，两者不是同一档商品。

后续独立组件与边界见 [Day 2 酒馆购买与固定赌局](day_02_trade.md)：复用本事务，提供静态折后价购买、真实奖励入库及 A 的债务结果接入；运行时折扣接口仍需集成协调。

## 仓库检查与实现范围

WarehouseInventory 提供共享库存、发现和原子快照；TeaProduction 消费同一库存；TaskJournal 只读投影事实。当前 TaskCatalog.rewards 支持显示 text、物品 items 与普通货币 money；正式 S01 交付收入 10G（1 杯 × 10G），4 个哥布林单各发 strange_coin ×1（4 × 10G = 40G），Day 1 合计 50G。自由饮品订单默认使用配方售价，显式 rewards.money 可覆盖。

经济服务复用 TeaMenu、WarehouseInventory 和 GameState；仍用任务 JSON v1，没有新增 autoload 或文件存档。普通交易接口与正式交付事务共用库存，但由各自稳定回执防重。跨场景余额、库存和领取记录由 GameState 的 WalletTransactions 子节点持有；MainGame 通过公开 getter 获取并注入同一库存。制作进度也由 GameState 持有；钱包、制作和交付复用同一份跨场景经营会话。

## 接口

取得 `MainGame.get_transactions()` 或 `get_node("/root/GameState").get_transactions()`：

| 方法 | 作用 |
| --- | --- |
| `get_balance() -> int` | 查询余额 |
| `get_product_quotes() -> Array[Dictionary]` | 按配置顺序列出有效商品的当前报价，返回独立列表及字典 |
| `get_product_quote(product_id) -> Dictionary` | 只读查询当前会话的商品、物品、实际单价及实时商人余量，返回独立值副本 |
| `add_money(amount, request_id) -> Dictionary` | 经营收入或其他可信业务的入账，金额由调用方业务配置提供 |
| `spend_money(amount, request_id) -> Dictionary` | 普通扣款，禁止负余额 |
| `purchase(product_id, quantity, request_id) -> Dictionary` | 读取商品配置并整笔购买 |
| `claim_reward(reward_id, request_id) -> Dictionary` | 读取奖励配置并整笔发放；带 task_id 时校验任务完成 |
| `get_inventory() -> WarehouseInventory` | 与制作、仓库 UI 共用的库存 |
| `to_dict() / restore_state(data)` | 经济快照；整包游戏恢复使用 GameState 对应接口 |

`amount`、`quantity` 必须为正整数，拒绝浮点、bool、字符串、零和负数。金额、单项库存、商店余量上限均为 2147483647；总价乘法先使用 int64 计算再检查上限。没有额外的格子数、重量或背包容量限制，因为原库存也没有这些规则。

统一结果包含 `ok`、`code`、`message`、`request_id`、`balance`、`money_delta`、`items`。失败时 `money_delta = 0`、`items = {}`；UI 可直接展示 message。`changed` 在完整状态变化后通知；`transaction_finished(result)` 对最外层请求发出一次，包括失败请求。busy 重入请求直接返回失败，不再次发送结果信号，防止监听器无限递归。信号结果和快照均复制容器。

常用失败码：`invalid_parameter`、`duplicate_transaction`、`unknown_product`、`invalid_configuration`、`out_of_stock`、`insufficient_funds`、`amount_overflow`、`invalid_item`、`inventory_full`、`unknown_reward`、`already_claimed`、`task_unavailable`、`task_incomplete`、`commit_failed`、`busy`。

### 商品报价

`get_product_quotes()` 按会话创建时的配置顺序返回有效商品报价列表，每项与单品查询字段一致；无商品时返回空数组。列表不提供配置无效的商品，已知 ID 可通过单品查询取得错误码；售罄商品仍保留在列表中。数组和条目均为新建副本，删除、替换条目或修改字段不会改变内部配置。

`get_product_quote(product_id)` 成功返回 `{ "ok": true, "code": "ok", "message": "", "product_id": String, "item_id": String, "unit_price": int, "stock": int 或 null }`。`unit_price` 是钱包当前静态商品配置的实际扣款单价，不读取物品图鉴的 `price` / `market_price`。`stock` 是当前剩余可售份数，0 表示售罄，null 表示不限量。售罄或余额不足时仍可查询有效报价，报价本身不保证可购买。

未知或无效商品 ID 返回 `{ "ok": false, "code": "unknown_product", "message": "商品不存在。" }`；商品配置无效返回 `invalid_configuration` 和对应 message，失败结果不含报价字段。查询与购买共用商品配置校验。查询不写状态、不消耗请求 ID、不发信号，在同步提交后的通知及会话写锁期间也可读取。返回字典只含标量，调用方可以修改或丢弃副本，不影响钱包配置、余量或后续扣款。每次查询读取实时余量，旧副本不自动更新。

购买协调器和弹窗应注入 GameState 的同一钱包，只保存商品 ID，通过报价显示价格与余量；物品展示信息可用报价的 `item_id` 向同一库存查询定义。打开界面及钱包 `changed` 后重新取报价，不能从 TeaMenu 或图鉴价格维护第二份交易配置。确认时仍只提交 `purchase(product_id, quantity, request_id)`，不传金额或把报价当授权；钱包在锁内重新计算价格并校验余额、商人余量和入库上限。一次确认及其失败重试保持同一个 request_id，成功后的下一笔有意购买才换 ID。

当前仓库未发现额外维护商品报价的交易适配组件。本次仅提供钱包查询接口与后续界面接入契约，不新增购买 UI。正式商品价格、动态折扣资格及舍入规则仍待确认，本接口只投影已有静态 `products`，不从设计稿或物品标价推导交易价格。

## 配置

在现有 `src/resources/milk_tea/basic_menu.tres` 的 TeaMenu Inspector 中配置：

- `initial_balance`：新游戏初始余额，默认 0。
- `products`：商品 ID → `{ "item_id": "black_tea", "price": 整数单价, "stock": 整数余量 }`。item_id 必须存在于同一食材目录。省略 stock 表示不限量；stock 为 0 表示售罄；价格允许显式配置为 0。
- `transaction_rewards`：奖励 ID → `{ "money": 非负整数, "items": {食材ID: 正整数}, "task_id": 可选任务ID }`。纯金币可用空 items，纯物品可将 money 设为 0。task_id 使用现有 TaskCatalog ID，由 MainGame 注入的 TaskJournal 查询状态。找不到任务或任务系统不可用时拒绝发奖。

products 与 transaction_rewards 默认空，保留现有教学库存、订单和叙事奖励文本。普通商店 / 独立领取奖励尚无正式配置，不把测试价格当成正式商店数据。已发布订单的收入定义在所选任务目录，原料 market_price 只用于成本计算，不自动生成 products。自动化测试 `_menu()` 提供完整的独立价格、限量商品和奖励样例。

配置在服务创建时复制，运行中修改 Resource 不会暗中改变已开始的经济会话。任务完成只改变进度；需要发奖的业务显式调用 claim_reward。同一 task_id 即使配置了多个奖励别名也最多领取一次；多件奖励应放入同一奖励定义。

## 原子提交与失败处理

1. 持有同步重入锁，检查 request_id、数量和已完成记录。
2. 在独立快照中校验商品、价格、商店余量、余额、全部奖励物品及库存上限；调整副本中的数量、发现状态、商店余量和领取记录。
3. 通过现有库存的无通知 `restore_state(snapshot, false)` 一次替换全部库存。该接口先校验全部内容，失败不改变库存。只有它成功后才赋值余额、商店余量、请求记录和奖励记录；后续只有容器赋值，没有可失败业务步骤。
4. 状态全部提交后才发送库存与经济通知，最后发送交易结果。此时监听者能查到一致的余额、物品及领取记录。同步通知期间重入交易、恢复经济和 GameState reset/restore 都会被拒绝。

因此不会先扣款再逐项加库存；失败直接丢弃准备好的副本，原状态就是回滚目标。测试用拒绝提交的库存替身验证了最终库存提交失败时也不会扣款、扣商店余量或写入领取记录。奖励中后一个物品非法或满仓时，前一个物品及货币也不发放。

接口用于 Godot 主线程；不支持工作线程并发调用，也不承诺进程崩溃时的磁盘持久性。Inventory 原有增减方法供制作等现有玩法使用；购买及奖励业务应走交易服务，避免自行组合扣款和入库。

## 防重复约定

每笔业务操作必须由调用方提供稳定、非空的 request_id。例如同一购买确认的多次按钮回调和重试都使用同一个 ID；开始下一笔有意购买时才创建新 ID。不要在每次按钮回调里重新生成 ID。服务不能仅按商品去重，否则无法区分重复点击和有意再次购买。

成功 request_id 在所有交易类型间共享并保存，使用同一 ID 重放或改参数均返回 duplicate_transaction。失败请求不消耗 ID，可修正余额、库存或配置后重试。奖励 ID 另有领取记录；改变 request_id 也不能重复领，同一任务的奖励别名同样受保护。重复请求不重发物品，不自动视为成功。

## 存档与兼容

GameState 完整快照当前为 `schema_version = 4`，库存子快照 v3；必需 economy 和 business 字段，包含余额、完整库存、有限商品余量、成功请求记录和奖励领取记录。所有部分先校验，再整体替换；损坏的经济数据也不会改变剧情字段。相同快照静默，读档不会发 transaction_finished 或重播奖励。库存单独变化（包括制作消耗）也进入 GameState 快照。

完整恢复要求同时包含钱包与经营数据，且 economy.inventory 与 business.inventory 一致。只有剧情的旧 v1 或缺字段的局部快照拒绝恢复；完整 v2/v3 支持迁移，规则见[自由配方快照](free_tea_recipes.md#快照与迁移)。start_new_game / reset_state 整体重置经济、制作和剧情数据，普通切场景保留全部进度。

仍使用仓库已有的原生 Variant 快照接口，没有创建第二套生产存档机制。实际文件往返测试使用 FileAccess.store_var/get_var 验证完整 GameState；经济子快照还覆盖 JSON 数字往返。GameState 原有剧情字段仍要求保留 Variant 类型，不能将整包快照直接当普通 JSON 恢复。

## 委托业务待确认

查阅 `docs/design/day_01_story_flow.md` 与 `docs/design/milk_tea_system_and_otherworld_chronicle.md`，目前只确认取得格里芬之血等接取剧情，没有资金结算规则。下列事项需业务设计确认：

| 问题 | 待确认规则 |
| --- | --- |
| 专款归属 | 与个人钱包是否隔离、能否用于普通购买、剩余款如何退回 |
| 预付款 | 发放时机与比例、是否计入报酬、失败或取消时如何退还 |
| 押金 | 冻结还是实际扣款、交付/拒收/取消时何时释放 |
| 违约扣款 | 触发条件与金额来源，余额不足时拒绝、欠款还是从押金扣除 |
| 交付结算 | 扣哪些物品、验收条件、阶段结算还是一次结清、可否重复接取 |
| 中断恢复 | 超时、放弃、读档重试时使用哪个委托实例/阶段作为幂等 ID |
| 货币种类 | 人类与异世界货币是否区分、是否兑换、金额单位 |

WalletTransactions 只提供普通货币、物品和领取事实，不加入专款、冻结、债务、押金或违约状态。委托组件负责资格和结算规则。当前 TaskDelivery 已经通过 GameState.commit_delivery 原子收取交付物并结算钱与物品；不要在业务层连续调用多个交易拼接。尚未定义的专款、退款和期限仍不能由普通钱包推断。

## 验证与试玩

```powershell
godot --headless --path . --script res://tests/verify_wallet_transactions.gd
godot --headless --path . --script res://tests/verify_game_state.gd
godot --headless --path . --script res://tests/verify_warehouse_inventory.gd
godot --headless --path . --script res://tests/verify_task_system.gd
godot --headless --path . --script res://tests/verify_tea_production.gd
godot --headless --path . --script res://tests/verify_milk_tea_shop.gd
```

交易测试覆盖商品列表与单品一致性、未知商品、报价副本隔离、Resource 后续修改隔离、实时/售罄/不限量报价、查询无通知、余额不足与同 ID 重试、重复请求不减余量、恢复后重新报价及购买，以及余额、免费商品、非法参数/配置、钱包和库存上限、多物品奖励、真实任务完成检查、重复领取与别名、同步重入、注入提交失败、JSON 及实际文件往返、损坏存档拒绝、旧/局部快照原子拒绝、跨主场景切换和制作共用库存。

手动回归入口：`src/core/main.tscn` 或 `src/core/settlement.tscn`，F6。打开仓库查看库存，在制作台制作、到指定顾客交付后再开仓库，观察对应原料减少，任务与订单板照常更新。当前没有新增购买按钮或奖励数值；交易行为通过上述测试和公开 API 验收。

## Godot 4.7 官方依据

报价接口核对 [Godot 4.7 Dictionary 文档](https://docs.godotengine.org/en/4.7/classes/class_dictionary.html#class-dictionary-method-duplicate)：字典按引用传递，`duplicate(true)` 递归复制容器但仍共享 Resource。报价因此构造仅含标量的新字典，避免暴露内部配置或 Resource；不依赖只冻结最外层的 `make_read_only()` 来保护嵌套数据。既有事务与生命周期依据：

- [Dictionary.xml / duplicate](https://github.com/godotengine/godot/blob/4.7/doc/classes/Dictionary.xml)：deep=true 会递归复制 Array/Dictionary，Resource 仍共享；交易暂存与快照只存值数据，配置中的 Resource 由既有库存独立复制。
- [Object.xml / emit_signal](https://github.com/godotengine/godot/blob/4.7/doc/classes/Object.xml)：通过既有信号通知观察者，将通知延迟到所有交易参与者提交后。
- [Node.xml / add_child](https://github.com/godotengine/godot/blob/4.7/doc/classes/Node.xml)：子节点随父节点释放；经济库存由跨场景 GameState 持有，避免随 MainGame 销毁。

- [FileAccess.xml / store_var、get_var](https://github.com/godotengine/godot/blob/4.7/doc/classes/FileAccess.xml)：原生 Variant 序列化保留数值类型；文件往返测试保持默认禁用对象解码。
