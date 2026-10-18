# GameState

`src/core/game_state.gd` 作为 `GameState` Autoload 加载，先于游戏场景创建，跨场景保留数据。它不处理 UI、输入、剧情演出或文件存档，也不在场景切换时自动 reset。现有 ShopInteraction、ShopUI、Player 无需修改。

## 数据与公开 API

| 数据 | 默认值 | 读取 | 修改 |
| --- | --- | --- | --- |
| 当前天数 | `1` | `current_day: int` | `set_current_day(value: int) -> bool`，或属性赋值；必须 ≥ 1 |
| 剧情阶段 | `""`（尚未选择） | `story_stage: String` | `set_story_stage(value: String) -> bool`，或属性赋值 |
| 剧情标记 | 空 | `has_flag(key: String) -> bool`、`get_flag(key: String, default_value: bool = false) -> bool`、`get_flags() -> Dictionary[String, bool]` | `set_flag(key: String, value: bool = true) -> bool` |
| 通用变量 | 空 | `has_variable(key: String) -> bool`、`get_variable(key: String, default_value: Variant = null) -> Variant`、`get_variables() -> Dictionary[String, Variant]` | `set_variable(key: String, value: Variant) -> bool` |
| 单次事件 | 空 | `is_event_completed(event_id: String) -> bool`、`get_completed_events() -> Array[String]` | `complete_event(event_id: String) -> bool` |

- 标记、变量和事件 ID 都要求至少两段命名空间，每段为合法 identifier，推荐 `snake_case`，如 `day1.order_checked`、`shop.customer_count`。阶段 ID 由后续剧情系统定义，不预设 enum。
- setter 和 `complete_event` 返回 `true` 表示实际修改，重复值或无效输入返回 `false`，不发 signal。缺失与显式 `false` / `null` 可以通过 `has_*` 区分；首次保存显式值属于修改。
- 变量允许 `null`、`bool`、`int`、有限 `float`、`String`、`Array` 和字符串键的 `Dictionary`，嵌套深度最多 32。拒绝 Object、Resource、Callable、非有限数字和循环容器。`int` 与 `float` 的类型变化也视为修改，包括嵌套值。
- 集合存储在内部；容器输入、读取结果和快照均复制，外部修改副本不会修改 GameState。修改副本后需要再次调用 setter。
- `reset_state() -> bool` 恢复所有默认值，清空单次事件；本来就是默认状态时返回 `false` 且静默。新游戏应显式调用，普通切换场景不调用。

GameState 通过 `get_transactions()` 提供 WalletTransactions；经营服务复用其库存，钱包、制作、交付及重置/恢复通知期间拒绝重入交易。

GameState 还通过 `get_warehouse_inventory()` / `get_tea_production()` 持有唯一的跨场景经营服务。新游戏优先调用 `start_new_game() -> Error`，同时初始化库存、成品、制作队列与剧情，并取消本地演出；`reset_state` 为兼容接口，也重置整个会话。详见 [统一经营会话](../gameplay/business_session.md)。

## Signal

- `state_changed()`：任何实际修改后发一次，订阅方重新查询需要的数据。
- `event_completed(event_id: String)`：首次完成事件后发一次。
- `state_reset()`：实际 reset 后发一次。
- `state_restored()`：恢复了不同状态后发一次。

每次操作先完成数据修改，再同步发 `state_changed`，最后发对应的事件/reset/restore signal。恢复和 reset 是整体操作，订阅者只会看到完整状态，不会收到逐字段通知。恢复已完成事件不会发 `event_completed`，避免读档重播演出。订阅方宜只读取状态，将进一步写入安排到后续操作，避免同步 signal 内递归修改状态。

## 后续接入

[StoryDirector（P0-2）](story_director.md) 已通过 MainGame 的交互路由接入，按 JSON 条件读取状态并在步骤中调用状态 API。GameState 不反向依赖交互点或主场景内部路径。其他协调组件也可以按以下方式使用：

```gdscript
# 协调组件确认“查看订单”成功后：
GameState.set_flag("day1.order_checked")
GameState.set_variable("shop.customer_count", 3)
if GameState.complete_event("day1.first_order"):
	# 首次完成通知由状态订阅者处理。
	pass

# UI 等订阅方：连接后先刷新一次，之后响应修改。
GameState.state_changed.connect(_refresh_from_state)
_refresh_from_state()
```

`to_dict() -> Dictionary` 返回 `schema_version = 4` 的独立原生 Variant 快照，包含 `current_day`、`story_stage`、`flags`、`variables`、`completed_events`（排序后的字符串数组）、`business`（profile_id、v3 库存子快照、制作订单 ID 前缀及自由制作请求回执）及 `economy`（钱包、同一库存、商人余量、交易与领奖回执）。`restore_state(data: Dictionary) -> Error` 先检查全部字段、版本、命名空间、值类型及经营数据，再整体替换；无效数据返回 `ERR_INVALID_DATA`，保留原状态且无通知；相同状态返回 `OK` 且无通知，事件数组顺序不影响比较。所有八个字段必需；`business.inventory` 与 `economy.inventory` 必须完全一致，顶层额外字段忽略。旧 v1 缺少经营状态，拒绝恢复以免覆盖或猜测剧情对应的物品状态。旧完整 v2/v3 可迁移，补空配方成品、图鉴和自由制作请求回执，保留已有开封次数；v2 另补 tutorial 配置与古怪金币空条目。详见[配方快照边界](../gameplay/free_tea_recipes.md#快照与迁移)。

当前提供完整 v4 内存快照接口，没有文件读写或存档格式选择。后续存档适配层需保留 Variant 类型；普通 JSON 会将数字解析为浮点数，不能直接保证原生快照类型往返，应在适配层编码/恢复类型后再调用 `restore_state`。

## 验证

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_game_state.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_milk_tea_shop.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_shop_camera.gd
```

独立测试使用新的状态实例验证默认值、读写、通知去重、嵌套数据隔离、重置、完整恢复及非法快照的原子拒绝，并用最小场景切换验证真实 Autoload 的生命周期。

实现依据为 Godot 4.7 官方文档：[Autoload 的创建时机与跨场景生命周期](https://docs.godotengine.org/en/4.7/tutorials/scripting/singletons_autoload.html)、[Dictionary 引用语义和深拷贝](https://docs.godotengine.org/en/4.7/classes/class_dictionary.html#class-dictionary-method-duplicate)、[Signal](https://docs.godotengine.org/en/4.7/classes/class_signal.html)。

## 钱包与库存

`get_transactions()` 返回跨场景 WalletTransactions，统一管理钱包、购买与实际奖励领取，复用现有仓库。`to_dict()` 的 economy 同时保存余额、库存、商店余量与领取记录；reset_state 一起重置，restore_state 先校验整包再发布通知。详见 [交易接口、原子性与委托待确认规则](../gameplay/wallet_transactions.md)。
