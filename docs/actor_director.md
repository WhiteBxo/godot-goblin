# ActorDirector（P0）

`ActorDirector` 是场景内的角色表现组件，放在 `Systems`；实例化的角色放在宿主注入的 `World/EntityRoot`。它不读取剧情 JSON，不管理剧情条件、flag 或事件状态，也不是新的剧情调度器。

实现：`src/core/actors/actor_director.gd`、`actor_action.gd`。`MainGame.get_actor_director()` 提供正式场景的实例，并默认注册 `player`。本次没有修改 StoryDirector 的指令或 JSON schema。

## 公开 API

注册、配置接口同步返回 `Error`（查询接口除外）。失败诊断见 `last_error`。

| 接口 | 用途 |
| --- | --- |
| `configure(entity_root: Node2D)` | 注入生成角色的父容器，不查找其他模块内部路径 |
| `actor_register(actor_id: StringName, actor: PlayerController) -> Error` | 注册已进入场景且 ready 的角色；ID 和实例均不可重复 |
| `actor_unregister(actor_id: StringName) -> Error` | 取消该角色当前动作并解除注册；不删除角色，生成角色也可借此交给宿主管理 |
| `get_actor(actor_id) -> PlayerController` | 返回角色；不存在、退出或正在删除时返回 null |
| `is_actor_controlled(actor_id) -> bool` | 是否有该 Director 持有的角色接管 |
| `register_position(position_id: StringName, marker: Marker2D) -> Error` | 将稳定位置名绑定到宿主传入的 Marker2D；不允许重复 ID |
| `unregister_position(position_id)` | 删除位置名绑定，不中断已接受的动作 |
| `cancel_action(action: ActorAction, reason = "Action cancelled")` | 按请求句柄中断；旧句柄不能取消同角色的新动作 |
| `cancel_all(reason = "Performance cancelled")` | 中断该 Director 的所有未完成动作 |

以下表现接口**始终返回独立的 `ActorAction` 句柄**，包括参数错误、忙碌、角色缺失等失败请求。

| 接口 | 参数与行为 |
| --- | --- |
| `actor_spawn(actor_id, scene: PackedScene, target)` | 在目标处实例化并注册；场景根必须继承 PlayerController；ID 必须未使用 |
| `actor_move(actor_id, target, speed = 120.0, timeout = 15.0)` | 直线趋近目标；速度为世界像素/秒，总超时为游戏秒；必须有限且 > 0 |
| `actor_face(actor_id, direction: StringName)` | `up`、`down`、`left`、`right`，复用现有朝向和 idle 动画 |
| `actor_show(actor_id)` / `actor_hide(actor_id)` | 切换整个角色的可见性；隐藏不改变碰撞或注销角色 |
| `actor_emote(actor_id, symbol = "!", duration = 0.8)` | 在角色头顶浮动并淡出 Label；支持 `!`、`?` 等文字；duration 必须有限且 > 0 |

`target` 支持世界坐标 `Vector2`、场景中的 `Marker2D` 或注册的 `String/StringName` 位置名。不接受 NodePath。接受请求时保存目标的世界坐标快照，因此移动 Marker 不会让角色追踪它；若 Marker 在动作完成前退出或删除则失败。重复位置名注册被拒绝，需先注销再替换。所有 Vector2 坐标必须有限。

`actor_spawn`、face、show、hide 在下一次物理 tick 执行，允许调用方在返回后连接信号或取消。spawn 设置好父容器内的局部坐标再进入场景，兼容已平移/旋转/缩放的 EntityRoot。

## 结果和完成 Signal

```gdscript
# ActorDirector
signal action_finished(action: ActorAction)
signal actor_control_changed(actor_id: StringName, controlled: bool)

# ActorAction：每个请求只发一次，包括失败、取消与退出
signal finished(action: ActorAction)
```

句柄包含 `id`（此 Director 内唯一）、`actor_id`、`command`、`completed`、`succeeded`、`error: Error`、`reason: String`。`wait() -> ActorAction` 可用于正在执行或已经完成的动作。不要直接等待全局完成信号而忽略句柄：其他角色可以同时演出。

结果在清理后设置；信号延迟通知，确保拒绝请求也不会在 API 返回前漏发信号。`finished` 中可安全发起下一动作。Director 存活时转发全局 `action_finished`；Director 被释放后，持有的句柄仍完成并通知自己的 `finished`。宿主退出时应同时取消自己的后续步骤；退出后的调用会得到失败句柄。

| 结果 | 含义 |
| --- | --- |
| `OK` | 完成，`succeeded = true`，reason 为空 |
| `ERR_BUSY` | 同角色动作互斥，或另一个 Director 已持有该角色 |
| `ERR_DOES_NOT_EXIST` | 角色/目标缺失、Marker 中途退出、表情显示被意外删除 |
| `ERR_INVALID_PARAMETER` / `ERR_INVALID_DATA` | 参数无效、重复生成或角色场景根不兼容 |
| `ERR_UNCONFIGURED` | Director 或生成容器不可用 |
| `ERR_TIMEOUT` | 移动被阻挡、无法接近目标或总时间超限 |
| `ERR_SKIP` | 调用方取消、角色解除注册/退出或 Director 退出；reason 说明来源 |

多个角色并行时，使用句柄中的 `reason/error` 判断各自结果；`last_error` 仅供观察最近一次操作诊断。

## 调用示例

由共同父场景完成注册；路径只出现在组装代码，不写入剧情数据：

```gdscript
var actors := main_game.get_actor_director()
actors.register_position(&"shop_door", door_marker)
actors.register_position(&"counter", counter_marker)

var spawn := actors.actor_spawn(&"customer_01", customer_scene, &"shop_door")
await spawn.wait()
if not spawn.succeeded:
	push_warning(spawn.reason)
	return

var move := actors.actor_move(&"customer_01", &"counter", 80.0, 8.0)
await move.wait()
if not move.succeeded:
	push_warning(move.reason)
	return

await actors.actor_face(&"player", &"left").wait()
await actors.actor_emote(&"customer_01", "!", 1.0).wait()
# 中断时保存并传入原句柄：actors.cancel_action(move, "Story cancelled")
```

StoryDirector 现已接入全部 actor 指令，使用 ActorAction 的完成 Signal 和 generation 防护。JSON `target` 支持注册位置 ID 或 `[x, y]`，`actor_spawn` 额外使用 `scene` 资源路径；不解析 NodePath。共享位置表新增公开 `get_position(position_id) -> Marker2D`，供镜头解析相同的 Marker。完整语法、默认等待与取消边界见 [Cinematic Integration](story_director.md#演出-json-指令)。

## 移动、互斥和输入锁

所有可演出的角色复用 `PlayerController`。NPC 场景设 `accepts_player_input = false`，不需要新的 NPC 行为脚本。原玩家场景默认仍为 true；日常输入、加减速、斜向归一化、动画步相和速度参数不变。

PlayerController 提供 `claim_performance_control` / `release_performance_control`、`set_performance_facing`、`move_performance` 和 `get_emote_offset` 给导演调用。控制权以弱引用绑定 Director；同一角色即使被两个 Director 注册，也只有一个能接管。同角色的 move/face/show/hide/emote 保守地共用一个动作槽，不排队或隐式覆盖；需要中断时先 `cancel_action` 再发新动作。不同角色可以并行。

演出移动在 `_physics_process` 内设置 `velocity`，速度上限为请求值，并按最后一帧剩余距离收敛。它调用原控制器的 `_move_velocity`，ShopPlayer 使用 `move_and_slide()`，CavePlayer 保留原有小步通行查询与 `move_and_collide()`；没有 Tween 角色位置或强行吸附终点。距目标 <= 0.5 世界像素认为到达；滑墙、绕不过障碍、洞穴通行查询失败等情况由停滞时间或总超时返回失败。不执行寻路或动态避障，路线应由关卡提供可直达的 Marker。

`blocked_timeout` 默认 1 秒：连续没有接近目标即失败，微小速度下阈值按速度缩放。总 `timeout` 默认 15 秒，即使角色仍在移动也不会无限等待。角色显式停用处理时等待至总超时。Director、移动时钟和表情 Tween 随 Systems 暂停；暂停游戏不消耗动作超时。

MainGame 统一计算“对白活跃 OR 剧情忙碌 OR player 正被 ActorDirector 接管”。首次锁定保存移动与交互状态，最后一个锁释放时恢复原值。演出移动由专用接管通道执行，允许在对白/剧情锁定日常输入时移动；不修改 `movement_enabled` 的语义，也不会提前解开其他系统的锁。`actor_control_changed` 用于自定义宿主复用这一协调方式。

## 生命周期和所有权

取消、失败、成功均先停止移动、恢复朝向 idle、释放控制权；表情 Tween 显式 `kill()` 并删除临时 Label，再完成结果。重复取消无副作用。已完成的显隐和朝向不会被取消回滚。

角色 `tree_exiting` 自动取消动作并注销；目标退出在物理 tick 检测。Director `_exit_tree` 取消所有动作、断开注册回调、清理位置引用，释放它生成且仍注册的角色；外部注册的玩家/NPC 保留。`actor_unregister` 可显式转移生成角色的生命周期给宿主。单个子系统退出和整个场景退出均有测试。

## Demo 和验证

在 Godot 4.7.2 编辑器打开 `src/debug/actors/actor_demo.tscn`，按 F6。Demo 独立于正式关卡及 StoryDirector，复用现有玩家素材，顾客用暖色调区分，无新增外部美术。

1. 顾客出现在左下方门口，向柜台行走。
2. 主角由面向上转为面向左侧顾客。
3. 顾客头顶浮出 `!`，短暂停留后淡出。
4. 顾客转身走回门口并隐藏。
5. 显示 Complete 后 WASD 恢复；Replay 重播，Cancel 可中断移动或表情并恢复主角控制。

PowerShell（`$godot` 替换为本机 Godot console 可执行文件路径）：

```powershell
& $godot --path . res://src/debug/actors/actor_demo.tscn
& $godot --headless --path . --fixed-fps 60 --script res://tests/verify_actor_director.gd
# 实际渲染并在 TEMP 保存 godot-goblin-actor-demo.png：
& $godot --path . --fixed-fps 60 --script res://tests/verify_actor_director.gd -- --capture
```

新增测试覆盖注册/生成、变换父容器、四方向动画、显隐、并行、双导演竞争、输入接管、精确速度、参数失败、真实物理墙与洞穴规则、停滞/总超时、暂停、表情清理、回调重入、取消、角色/Director/场景移除、MainGame 锁叠加与完整 Demo。Headless 通过 165 项检查；实际 D3D12 Forward+ 渲染模式通过 166 项（含截图保存），截图已检查。

相关现有测试 `verify_player.gd`、`verify_milk_tea_shop.gd`、`verify_dialogue.gd`（69 项）、`verify_story_director.gd`（147 项）、`verify_game_state.gd`（120 项）、`verify_shop_camera.gd` 均通过。`verify_player_visuals.gd` 也在实际 D3D12 Forward+ 下通过全部 68 帧渲染检查。

已知既有测试限制：`verify_main_game.gd` 假设主场景仍为洞穴，且 `base_speed`、`saved_query`、`previous_mode` 存在类型推断解析错误；`MainGame.get_player() -> CharacterBody2D` 的相关返回类型在本次改动前已存在。此次未修改旧测试或主场景选择，当前店铺 MainGame 的接入与锁生命周期由新增测试及原有对白、剧情、店铺测试覆盖。

## Godot 4.7 官方依据

- [CharacterBody2D](https://docs.godotengine.org/en/4.7/classes/class_characterbody2d.html)：velocity 使用像素/秒，`move_and_slide()` 在物理帧调用，内部处理时间步和碰撞，不能再给 velocity 乘 delta。
- [Node](https://docs.godotengine.org/en/4.7/classes/class_node.html)：处理/暂停模式和 `tree_exiting` 生命周期；退出时清理控制权与异步资源。
- [Tween](https://docs.godotengine.org/en/4.7/classes/class_tween.html)：只给表情显示做动画，绑定 Director 的生命周期与暂停，取消时显式 kill，重新演出创建新 Tween。
- [Marker2D](https://docs.godotengine.org/en/4.7/classes/class_marker2d.html)、[PackedScene](https://docs.godotengine.org/en/4.7/classes/class_packedscene.html)、[Label](https://docs.godotengine.org/en/4.7/classes/class_label.html)：可编辑位置锚点、场景实例化和临时文字表情。
