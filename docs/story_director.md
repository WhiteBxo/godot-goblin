# StoryDirector（P0-2）

`src/core/story/story_library.gd` 负责 JSON 加载和完整校验；`story_director.gd` 只调度步骤。MainGame 在 `Systems` 创建 StoryDirector，传入原有 DialogueManager；Director 通过 `/root/GameState` 取得已有 Autoload，不创建第二份状态。正式入口不加载第一天示例、不自动播放剧情。

## 接入与公开接口

```gdscript
var director := game.get_story_director()
if director.load_events("res://src/resources/story/day1_demo_events.json") == OK:
	var error := director.request_event("day1.intro")
	if error != OK:
		print(director.last_error)
```

需要同时加载事件引用的对白目录，例如 Demo 中的 `day1_demo_dialogues.json`；未知对白在执行到对应步骤时失败，不偷偷切换 Manager 的目录。

| API | 行为 |
| --- | --- |
| `configure(manager: DialogueManager, can_start: Callable = Callable())` | 注入场景内 Manager 和可选宿主准入检查；重新配置先取消旧演出 |
| `load_events(path: String = "") -> Error` | 空参数使用 `event_file`；完整验证后替换目录，失败保留旧数据；busy 时拒绝 |
| `request_event(id: String) -> Error` | 同步检查并占用演出；`OK` 表示已接受，最终结果看 signal |
| `request_interaction(interaction_id: String) -> Error` | JSON 顺序选择第一个符合条件且未完成的路由；无路由为 `ERR_DOES_NOT_EXIST` |
| `is_busy() -> bool` | 从接受请求到成功/失败收尾之前为 true |
| `cancel_event(reason: String = "Cancelled")` | 取消所属对白、停顿和音效；idle 时静默 |
| `get_choice(dialogue_id: String, line_id: String) -> String` | 当前/最近一次演出的选项 ID；未选择为空；下一次成功接受事件时清空 |
| `is_starting_dialogue() -> bool` | 供宿主准入判断：busy 期间仅放行 Director 自己启动的对白 |
| `last_error: String` | 最近请求/加载错误或失败事件的 ID、步骤下标及原因 |

常见错误：`ERR_BUSY`（演出、对话或 ShopUI 占用）、`ERR_UNCONFIGURED`（缺少场景/Manager）、`ERR_DOES_NOT_EXIST`（未知事件或无匹配路由）、`ERR_UNAUTHORIZED`（条件不满足）、`ERR_ALREADY_EXISTS`（单次事件已完成）。文件和格式错误保留 Godot Error，附 `last_error` 诊断。等待和运行错误通过结束 signal 报告。

Signals：

- `event_started(event_id)`：同步发出，第一步尚未执行。
- `event_finished(event_id, succeeded, reason)`：每次已接受事件最终只发一次；失败时 `reason` 包含事件和步骤位置。
- `event_completed(event_id)`：仅成功发出，先于 `event_finished`；单次事件此时已写入 GameState。
- `step_started(event_id, index, command)`、`step_skipped(event_id, index, reason)`：零起始步骤下标，用于测试和诊断。音效缺失会先 started 再 skipped。
- `choice_received(event_id, dialogue_id, line_id, choice_id)`：接收并保存原 Manager 的 `choice_selected` 后发出，早于下一步。

Signal 同步调用。收尾期间拒绝递归启动新事件，串联事件请使用 `call_deferred`。`event_finished` 回调中 `is_busy()` 已为 false，方便宿主恢复控制，但同步 `request_event` 仍返回 `ERR_BUSY`。

## JSON 格式

```json
{
  "version": 1,
  "events": {
    "day1.intro": {
      "once": true,
      "conditions": {
        "day": 1,
        "flags": {"day1.intro_finished": false},
        "not_completed_events": ["day1.intro"]
      },
      "steps": [
        {"command": "dialogue", "id": "day1.opening"},
        {"command": "wait", "seconds": 0.8},
        {"command": "play_sfx", "path": "res://src/debug/story/strange_knock.tres"},
        {"command": "dialogue", "id": "day1.reaction"},
        {"command": "set_flag", "key": "day1.intro_finished", "value": true},
        {"command": "set_stage", "value": "day1.investigate"}
      ]
    }
  }
}
```

事件 ID、flag key 和前置事件 ID 遵循 GameState 的命名空间规则。`once` 默认 true，只有全部步骤成功才调用 `GameState.complete_event`；`once: false` 可重复执行，不进入单次事件集合。`trigger` 为可选的交互 ID，如 `orders`、`storage`、`tea_station`。

`conditions` 的各字段为 AND：`day` 为正整数精确匹配，`stage` 精确匹配 `story_stage`，`flags` 为 bool 字典（缺失 flag 视为 false），`completed_events` 全部已完成，`not_completed_events` 全部未完成。省略表示不限。事件条件仅在接受请求时检查。

每步可带 `when`，在该步骤执行时重新判断以上条件；还可根据本次演出内已收到的选项决定是否执行：

```json
{"command": "set_flag", "key": "day1.order_checked", "when": {
  "choice": {"dialogue": "day1.orders_after", "line": "board", "id": "investigate"}
}}
```

`choice` 只允许在步骤 `when` 中使用。一个对话行若多次选择，保留最近一次结果；未选择时不匹配。跨事件分支应通过条件步骤写入 flag。此处为线性步骤的条件执行，不实现复杂分支图。

| command | 必填参数 | 行为 |
| --- | --- | --- |
| `dialogue` | `id`：非空字符串 | 调用原 Manager 并等待自然结束；取消、无法启动或引用缺失则整段失败 |
| `wait` | `seconds`：有限数字 ≥ 0 | 使用可停止的单次 Timer；0 在下一 process tick 继续 |
| `set_flag` | `key`：命名空间字符串 | `value` 为 bool，默认 true；设置相同值视为成功 |
| `set_stage` | `value`：字符串 | 调用 `set_story_stage`；相同阶段视为成功 |
| `play_sfx` | `path`：`res://` 路径 | 非阻塞 AudioStreamPlayer；文件缺失或不是 AudioStream 时发 skipped 并继续 |

目录必须包含 `version: 1` 和 `events` 对象；事件必须有非空 `steps`。未知字段、未知指令、非法类型、负等待值及非法命名空间均拒绝，并报告事件/步骤位置。对白 ID 在 runtime 由 DialogueManager 验证，音效允许留空素材路径对应的占位文件名（路径本身必须是 `res://`）。现有导出 preset 的 `*.json` 已覆盖新数据；以后改用选择场景导出时，必须显式包含 JSON 及其动态引用的音效资源。

## 生命周期、输入与交互

Director 每个 process tick 执行一个步骤；对白结束和 Timer timeout 只安排下一步，避免同步回调递归 dispatch。Timer 和 Director 随 `Systems` 暂停；没有悬挂的 `await` coroutine。取消停止 Timer、清除待执行步骤并停止所属音效；音效正常结束或演出收尾时释放。

对白取消、UI/Manager/Director 移除、宿主场景退出和 GameState reset/restore 均安全取消。不失败回滚已执行的 flag/stage；最终成功标记应放在末尾。失败不记录事件完成，允许重试。缺失音效是唯一的资源容错步骤，缺失事件 JSON 或对白会报错。

MainGame 的 `_refresh_input_lock` 统一计算“对白活跃 OR 剧情忙碌”，只在首次锁定时保存移动和交互状态，整段演出结束后恢复原值。Director 不直接管理玩家输入。停顿中独立对白被宿主 guard 拒绝，ShopUI 已打开时剧情请求也被拒绝。

ShopInteraction 接受可选 Callable `event_handler(interaction_id) -> bool`，先询问路由。仅无匹配事件时返回 false 并继续原 ShopUI，已处理或拒绝的剧情请求返回 true，避免一按 E 同时打开两种弹窗。正式场景目录为空，三个交互仍使用原 UI；Demo 仅接管 `orders`。没有新增交互组件或依赖具体 UI 子节点路径。

## Demo 与验证

直接运行 `src/debug/story/story_demo.tscn`（编辑器 F6），或：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . res://src/debug/story/story_demo.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_story_director.gd
```

1. 自动显示开场独白，E/空格/Enter 显示全文，再次按下结束对白。
2. 观察停顿 0.8 秒，WASD 和店铺交互不可用；听到两次低沉敲击声，再显示反应对白。
3. 结束后能恢复移动，订单板改为调查对白；选择“记下这件怪事”设置 `day1.order_checked`。
4. 在开场 Esc 取消，或用上方“中止演出”按钮在停顿时取消；调查订单板显示开场前对白。可点“启动开场”重试，成功后不可重复。
5. 仓库和制作台继续打开原弹窗。剧情 Demo 不 reset 跨场景 GameState；需要全新测试时重新启动进程。

示例仅演示第一天流程文档的经营背景与异常引子，不代表完整剧情定稿。两次敲击是本项目原创的程序合成占位音效，无外部素材来源；可用 `python3 tools/story/generate_demo_knock.py` 确定性重建。它只在 Demo/测试中引用。

测试覆盖条件组合、校验失败保留旧数据、严格顺序、真实对白等待、选项条件、暂停、单次去重、重复事件、输入恢复、资源失败、取消、节点移除及真实订单/仓库/制作台路由。可在非 headless 运行测试时添加 `-- --capture`，在 `/private/tmp/story-demo-intro.png` 和 `story-demo-orders.png` 保存画面。

## 添加演出指令

在 `StoryLibrary._step` 增加 command 和必要参数的类型/范围校验，在 `StoryDirector._process` 的 match 中调用独立 handler。同步指令执行后由现有尾部安排下一步；异步指令只在完成信号中调用 `_schedule_next`，取消路径须停止所属资源，并通过当前运行 generation 防止同步取消后继续执行。扩展时同时添加有效/无效数据测试及取消测试，避免把角色、镜头或 UI 的具体节点路径写入 Director。

实现依据 Godot 4.7 官方文档：[Node 的退出顺序与 process mode](https://docs.godotengine.org/en/4.7/classes/class_node.html)、[Timer 的停止和 timeout](https://docs.godotengine.org/en/4.7/classes/class_timer.html)、[JSON 解析和错误诊断](https://docs.godotengine.org/en/4.7/classes/class_json.html)、[AudioStreamPlayer 的 finished 与 stop](https://docs.godotengine.org/en/4.7/classes/class_audiostreamplayer.html)。Timer.stop 不发 timeout、AudioStreamPlayer.stop 不发 finished，因此取消显式清理；退出信号同步通知宿主释放锁。
