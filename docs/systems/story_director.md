# StoryDirector / P0 Cinematic Integration

自然语言编排入口见 [Story Authoring Workflow](../guides/story_authoring_workflow.md)，全部 JSON 指令/默认参数见 [编排指令速查](../guides/story_authoring_commands.md)。未迁移创作源在 docs/design/；已迁移剧情以 docs/story_authoring 的结构化工程为正式来源，见[游戏内编排](../guides/story_editor.md)。运行时继续使用 Story / Dialogue v1 与 Bridge v2。

`src/core/story/story_library.gd` 负责 JSON 加载和完整校验；`story_director.gd` 只调度步骤。MainGame 在 `Systems` 创建 StoryDirector，传入原有 DialogueManager；Director 通过 `/root/GameState` 取得已有 Autoload，不创建第二份状态。正式新游戏由 Day1ShopController 加载并启动 S01–S02；S03–S06 由 Day1ChapterController 接管但当前数据为空。独立 Demo 不自动进入正式目录。

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
| `configure_cinematic(actors: ActorDirector, cameras: CameraDirector = null)` | 注入现有演出服务；重新配置先取消旧演出；MainGame 默认接入自己的 Director |
| `set_audio_adapter(adapter: StoryAudioAdapter)` | 注入音频适配层；替换前取消旧演出；MainGame 默认接入 AudioManager |
| `set_title_card(card: TitleCard)` | 注入全屏标题卡；替换前取消旧演出；MainGame 在现有 TransitionLayer（40）中创建，位于场景切换遮罩下方；宿主通过 `get_title_card()` 提供引用 |
| `load_events(path: String = "") -> Error` | 空参数使用 `event_file`；完整验证后替换目录，失败保留旧数据；busy 或收尾中拒绝并把原因写入 `last_error` |
| `request_event(id: String) -> Error` | 同步检查并占用演出；`OK` 表示已接受，最终结果看 signal |
| `request_interaction(interaction_id: String) -> Error` | JSON 顺序选择第一个符合条件且未完成的路由；无路由为 `ERR_DOES_NOT_EXIST` |
| `get_event_ids() -> Array[String]` | 只读：已加载事件 ID，按字母序返回，仅用于显示；`request_interaction` 仍按 JSON 顺序选取第一个合格事件。不触发加载 |
| `get_event_summary(id: String) -> Dictionary` | 只读投影：`once`、`trigger`、`step_count`、`conditions_met`、`completed`（读 GameState `completed_events`）；未知 ID 返回空字典 |
| `get_event_source_path() -> String` | 最近一次成功加载的路径，未加载时回退到 `event_file`；供调试工具重载同一个文件 |
| `is_busy() -> bool` | 从接受请求到成功/失败收尾之前为 true |
| `cancel_event(reason: String = "Cancelled")` | 取消所属对白、停顿和音效；idle 时静默 |
| `get_choice(dialogue_id: String, line_id: String) -> String` | 当前/最近一次演出的选项 ID；未选择为空；下一次成功接受事件时清空 |
| `is_starting_dialogue() -> bool` | 供宿主准入判断：busy 期间仅放行 Director 自己启动的对白 |
| `last_error: String` | 最近请求/加载错误或失败事件的 ID、步骤下标及原因 |

常见错误：`ERR_BUSY`（演出、对话或 ShopUI 占用）、`ERR_UNCONFIGURED`（缺少场景/Manager）、`ERR_DOES_NOT_EXIST`（未知事件或无匹配路由）、`ERR_UNAUTHORIZED`（条件不满足）、`ERR_ALREADY_EXISTS`（单次事件已完成）。文件和格式错误保留 Godot Error，附 `last_error` 诊断。等待和运行错误通过结束 signal 报告。

三个只读接口（`get_event_ids`、`get_event_summary`、`get_event_source_path`）只读取已加载目录与 GameState，不调用 Loader、不占用演出、不消耗 `once`、不改变 JSON 顺序；`conditions_met` 复用 `request_event` 的判断规则，但只报告结果，不代为拒绝。它们供 Debug 的 Console「事件」页使用：该页列出目录、按宿主真实路径热重载（同时按 `DialogueManager.get_dialogue_source_path()` 刷新对白目录，让文案改动立即生效），并主动 `request_event` 触发单个事件。热重载只替换目录，不重置 GameState、不重放已执行事件、不改变阶段；`once` 事件的完成标记仍在 GameState 里，所以已完成事件的请求照常返回 `ERR_ALREADY_EXISTS`，界面原样显示该原因。工具仅在 Debug 存在，Release 不创建节点、不注册按键；详见 [Developer Console](../development/developer_console.md)。

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

`conditions` 的各字段为 AND：`day` 为正整数精确匹配，`stage` 精确匹配 `story_stage`，`flags` 为 bool 字典（缺失 flag 视为 false），`completed_events` 全部已完成，`not_completed_events` 全部未完成；`items` 要求当前共享库存不少于指定正整数数量。省略表示不限。事件条件仅在接受请求时检查。

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
| `chronicle_unlock` | `entry_id`：命名空间 ID；`title`：非空字符串 | 调用注入的 ChronicleJournal；重复解锁无副作用 |
| `chronicle_append` | `entry_id`、`record_id`：命名空间 ID；`content`：非空字符串 | 向已解锁条目追加并标为未读；重复记录无副作用。见 [见闻录](../gameplay/chronicle.md) |
| `pay_items` | `items`：物品 ID→正整数；`receipt`：命名空间 flag；可选 `set_flags` | `GameState.commit_item_payment` 一个事务内扣物品、写 flags 与 receipt；receipt 已存在视为已付；不足/忙时整段失败且不扣 |
| `set_phase` | `phase`：`day` / `night` | 经 DayPhase 切换；已在目标阶段视为成功；夜→昼推进 `current_day` |
| `title_card` | `text` 非空；`subtitle`、`seconds`（默认 2.5）、`wait` | 注入的 TitleCard 淡入、停留、淡出；默认阻塞；事件结束时取消仍在显示的卡；服务缺失则整段失败 |
| `play_sfx` | 非空 `id` 或 `res:// path`，二选一 | 经适配层调用 AudioManager；默认非阻塞，`wait: true` 等自然结束；旧 path 保持兼容；资源/服务缺失或池满发 skipped 并继续 |

目录必须包含 `version: 1` 和 `events` 对象；事件必须有非空 `steps`。未知字段、未知指令、非法类型、负等待值及非法命名空间均拒绝，并报告事件/步骤位置。对白 ID 在 runtime 由 DialogueManager 验证，音效允许留空素材路径对应的占位文件名（路径本身必须是 `res://`）。现有导出 preset 的 `*.json` 已覆盖新数据；以后改用选择场景导出时，必须显式包含 JSON 及其动态引用的音效资源。

## 生命周期、输入与交互

Director 每个 process tick 执行一个步骤；对白结束和 Timer timeout 只安排下一步，避免同步回调递归 dispatch。Timer 和 Director 随 `Systems` 暂停；没有悬挂的 `await` coroutine。取消停止 Timer、清除待执行步骤并经适配层停止所属音效；音效正常结束或演出收尾时归还 AudioManager 播放器池。独立场景 BGM 和其他 owner 的音效不受影响。详见 [AudioManager](audio_manager.md)。

对白取消、UI/Manager/Director 移除、宿主场景退出和 GameState reset/restore 均安全取消。不失败回滚已执行的 flag/stage；最终成功标记应放在末尾。失败不记录事件完成，允许重试。声音步骤（含 BGM）的缺失素材/服务采用可选资源容错，缺失事件 JSON 或对白会报错。

MainGame 的 `_refresh_input_lock` 合并模态、对白、剧情、Actor 控制、导航与潜入等已有操作锁，只在首次锁定时保存移动和交互状态，最后一个锁解除后恢复原值。Director 不直接管理玩家输入。停顿中独立对白被宿主 guard 拒绝，ShopUI 已打开时剧情请求也被拒绝。

ShopInteraction 接受可选路由 Callable。MainGame 返回 Error：OK 表示获准，ERR_DOES_NOT_EXIST 才回退原 ShopUI，其他错误消耗请求并报告失败，避免一按 E 同时打开两种弹窗或失败仍发成功反馈。旧 bool handler 兼容 false 回退、true 已处理且成功。正式前段已加载阶段事件，后章仅为空骨架；Demo 的 orders 路由局限对应宿主。详见[交互反馈](../gameplay/interaction_feedback.md)。

## Demo 与验证

本页后文的早期实现测试数量保留历史，不作为本轮文档同步实测。当前正式内容与未发布范围见[项目现状](../development/development_status_2026_10_18.md)。

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

示例仅演示第一天流程文档的经营背景与异常引子，不代表完整剧情定稿。敲击已换成本次 CC0 素材中的木勺敲木碗三连敲；`strange_knock.tres` 嵌入与音效库 `story/knock_01.wav` 相同的 PCM。`python tools/audio/generate_sound_pack.py` 同步重建，原路径只供 Demo/测试兼容使用。来源见 [音效库](../assets/sound_library.md)。

测试覆盖条件组合、校验失败保留旧数据、严格顺序、真实对白等待、选项条件、暂停、单次去重、重复事件、输入恢复、资源失败、取消、节点移除及真实订单/仓库/制作台路由。可在非 headless 运行测试时添加 `-- --capture`，在 `/private/tmp/story-demo-intro.png` 和 `story-demo-orders.png` 保存画面。

## 演出 JSON 指令

MainGame 在现有 `Systems` 中创建各 Director，通过 `configure_cinematic` 注入，不增加 autoload。StoryDirector 只做逐步 dispatch 和结果管理；移动、碰撞、表情、镜头跟随、音频池与淡变仍由原 module 执行。依赖通过现有公开接口注入；正式入口加载自己的剧情配置，不加载 Demo。

所有新演出指令允许 `wait: bool`，默认 **true**；原 `play_sfx` 默认 **false**。`dialogue` 始终等待自然结束，原 `wait` 步骤仍用 `seconds`，这两个旧指令不增加同名 bool 字段。`wait: false` 只启动动作，下一 process tick 执行下一步；Blocking 则等待该次 action 的完成 Signal，而不是估算耗时。

| command | 参数（时间为秒，坐标为全局世界像素） |
| --- | --- |
| `actor_spawn` | `actor` 新 ID、`scene` 为 `res://` 下的 `.tscn`、`target`；根节点必须继承 PlayerController，NPC 应关闭 `accepts_player_input` |
| `actor_move` | `actor`、`target`；`speed` 默认 120（像素/秒）、`timeout` 默认 15，均须正数；复用真实物理移动，不提供寻路 |
| `actor_face` | `actor`、`direction: up/down/left/right` |
| `actor_emote` | `actor`；`symbol` 默认 `!`、`duration` 默认 0.8（须 > 0） |
| `actor_show` / `actor_hide` | `actor` |
| `actor_animate` | `actor`、`animation`（须存在于角色 SpriteFrames）；`hold` 默认 false。非循环动画播完完成，循环动画立即完成；hold 保持姿势到下次演出接管或传送；中断时恢复默认动画 |
| `camera_focus` | `actor` 或 `target`，二选一；`duration` 默认 0.8；到位后继续跟踪存活目标 |
| `camera_move` | `target`；`duration` 默认 0.8；保存位置快照，到位后保持构图 |
| `camera_shake` | `intensity` 默认 2（逻辑视口像素）、`duration` 默认 0.3、`decay` 默认 1.5；三者均 ≥ 0，强度仍受 CameraDirector 上限限制 |
| `camera_zoom` | 正数 `value`；`duration` 默认 0.5；实际缩放受地图边界限制 |
| `camera_reset` | 无必填参数；立即恢复默认 Follow、preferred_zoom、零偏移 |
| `play_bgm` | 注册的音频 `id`；`fade` 默认 0.5、`volume_db` 默认 0；等淡入完成，切换曲目时等淡出与淡入两段完成 |
| `stop_bgm` | `fade` 默认 0；等淡出并停止完成 |
| `fade_bgm` | `volume_db`；`fade` 默认 0.5；仅调整当前 BGM 音量 |

`target` 为已注册 Marker2D 的 ID（如 `counter`），或 `[x, y]`。共同父场景使用 `ActorDirector.register_position` 组装角色和镜头共享的标记表；StoryDirector 通过公开 `get_position` 查询。JSON 不解析 NodePath。`actor_spawn.scene` 是资源路径，不是场景树路径。所有时间和数值必须有限，时间非负，未知字段继续严格拒绝；runtime 引用不存在、移动受阻或超时会失败，诊断包含事件和步骤位置。数据加载失败保留原目录。

```json
{"command": "actor_spawn", "actor": "customer", "scene": "res://src/debug/cinematic/customer.tscn", "target": "door"}
{"command": "camera_focus", "actor": "customer", "duration": 1.2, "wait": false}
{"command": "actor_move", "actor": "customer", "target": "counter", "speed": 90, "timeout": 7}
{"command": "actor_emote", "actor": "customer", "symbol": "!", "duration": 1.2}
{"command": "play_sfx", "id": "cinematic.rumble"}
{"command": "camera_shake", "intensity": 2, "duration": 0.7}
{"command": "camera_reset"}
```

以上每行为独立步骤对象；完整可直接加载的事件见 `src/resources/story/cinematic_opening.json`。对白目录为 `src/resources/dialogue/cinematic_opening.json`。

## 并行、冲突与取消

- **角色**：同角色 move/face/emote/show/hide 共用互斥槽。忙碌或重复 spawn 返回失败，并取消本段已启动的其他动作；不同角色可以并行。需要在移动后转向/表情时，保持 move 默认 `wait: true`。
- **镜头**：位置、zoom、shake 三通道可以并行。JSON 同通道的新动作替换本段旧的 Non-blocking 动作，旧通知被断开；`camera_reset` 显式终止本段所有镜头动作。场景级相机在剧情期间由演出管理，外部直接打断正在等待的镜头动作会导致剧情失败并复位。
- **BGM**：单一通道，新的有效音乐指令替换旧淡变；无效音频资源不打断正在播放的音乐。非阻塞 BGM 的旧完成通知不推进步骤。
- **事件末尾**：等待本段未完成的角色/镜头动作再成功结束，避免 Non-blocking 位于最后一步时立刻被截断。非阻塞声音沿用旧行为，不延长事件；请用 `wait: true` 需要听完的音效或淡变。BGM 只等待过渡，不等待循环曲目自然结束。
- **完成通知**：每个句柄关联 generation、原步骤和等待模式；先从跟踪表移除，再处理成功/失败。同步拒绝/零时长的结果也 deferred 发布，重复 Signal、已退休动作及上一代事件的回调均不能再次推进。
- **取消与退出**：先递增 generation、停 Timer 和 dispatch，断开所属动作回调，再按句柄取消 ActorAction，停止所属声音，复位镜头。删除角色、Marker、演出服务、对白 UI、StoryDirector 或宿主场景，以及 GameState reset/restore 均安全取消；已完成 focus 的目标消失也通过 `camera_recovered` 取消。
- **状态保留**：不回滚已经执行的 flag/stage、spawn、显隐、朝向和已走过的距离。取消已生成的角色会停在原地，生命周期仍归 ActorDirector；退出场景自动清理。Demo 重播前显式清理上一位顾客。无本段句柄的外部角色动作不受取消影响。
- **音乐所有权**：正常结束停止本段 SFX，并将 BGM 留给场景继续播放（包括未完成的非阻塞淡变）；失败、取消时停止本段 SFX 与仍归本段的 BGM。如果外部已经发起更新的音乐请求，保留它。没有音乐步骤的旧剧情不会停止场景 BGM。显式 stop_bgm 或后续音乐指令仍生效。
- **输入**：各 Director 不操作输入锁。MainGame 继续统一计算对白 / 剧情 / player 接管的 OR，最后释放时恢复进入演出前的移动与交互状态，包括原本已禁用的情况。玩家中途删除时也安全释放交互锁；StoryDirector 被移除后，店铺交互安全 fallback 到原 ShopUI。

Timer、ActorDirector、CameraDirector 随 Systems 暂停；AudioManager 保留原有策略，音乐淡变可在暂停中完成，但下一剧情步骤要等 Systems 恢复后执行。音效等待使用声音池的自然完成通知；循环音效若使用 `wait: true` 不会自然结束，作者应使用有限素材或显式取消。

## Cinematic 开场 Demo 与自动化验证

编辑器打开 `src/debug/cinematic/cinematic_demo.tscn`，F6；或执行：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . res://src/debug/cinematic/cinematic_demo.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --log-file /private/tmp/cinematic.log --script res://tests/verify_cinematic_integration.gd
# 实际渲染并保存 /private/tmp/cinematic-opening.png：
/Applications/Godot.app/Contents/MacOS/Godot --path . --log-file /private/tmp/cinematic-visual.log --script res://tests/verify_cinematic_integration.gd -- --capture
```

1. 主角店内独白；每段阅读约 4 秒，E/空格/Enter 先显示全文、再按一次推进。总长约 24 秒；对白保留手动推进，可停留更久。
2. 门铃响，主角面向右侧入口；镜头先展示门口，暖色顾客出现并沿过道走向柜台，镜头平滑跟踪。
3. 顾客停下显示 `!`，地板下两声低沉敲击伴随轻震，随后主角反应对白。
4. 音乐淡出、镜头恢复 Follow，WASD 移动与 E 店铺交互恢复。
5. 随时点击“取消演出 / 恢复控制”；对白期间也可 Esc。检查顾客停止、表情消失、镜头复位且能移动。点击重播会清理旧顾客并重新加载同一段 JSON 流程。

Demo 脚本只注册资源/Marker、加载目录、启动事件和提供重播/取消按钮，没有演出顺序。音效使用本次 CC0 采样：门铃和房间环境直接引用音效库，低沉敲击沿用已更新内容的 Story Demo 兼容资源。Marker 坐标保存在 Demo 场景，未改动正式地图及其碰撞。

新增测试覆盖完整 schema、阻塞和非阻塞的真实动作/顺序、末尾收束、重复通知、角色互斥、镜头替换/reset、BGM 淡入淡出、声音自然结束、缺失资源、重复请求、取消/重试、预先禁用输入、各服务/角色/目标删除、已完成 focus 目标丢失、场景退出和完整 20～30 秒演出。既有 Story Demo 与订单/仓库/制作台路由回归继续由 `verify_story_director.gd` 覆盖。

实现依据 Godot 4.7 官方文档：[Node 的退出顺序与 process mode](https://docs.godotengine.org/en/4.7/classes/class_node.html)、[Timer 的停止和 timeout](https://docs.godotengine.org/en/4.7/classes/class_timer.html)、[JSON 解析和错误诊断](https://docs.godotengine.org/en/4.7/classes/class_json.html)、[AudioStreamPlayer 的 finished 与 stop](https://docs.godotengine.org/en/4.7/classes/class_audiostreamplayer.html)。Timer.stop 不发 timeout、AudioStreamPlayer.stop 不发 finished，因此取消显式清理；退出信号同步通知宿主释放锁。

新增实现同样核对 [Signal 的连接、断开和绑定参数](https://docs.godotengine.org/en/4.7/classes/class_signal.html)、[Tween 的绑定、完成与 kill](https://docs.godotengine.org/en/4.7/classes/class_tween.html)、[PackedScene 实例化](https://docs.godotengine.org/en/4.7/classes/class_packedscene.html)：kill/stop 不作为自然完成，必须显式结算取消；节点退出和句柄回调按所属事件清理。

本次使用 Godot 4.7.2 验证：新增集成测试通过（含真实物理、声音完成通知及完整开场时长），Metal Forward+ 窗口渲染和截图通过，开场实测约 24.5 秒。既有 `verify_story_director`（147）、`verify_actor_director`（165）、`verify_camera_director`（285）、`verify_audio_manager`（64）、`verify_dialogue`（75）、`verify_game_state`（120），以及 `verify_player`、`verify_milk_tea_shop`、`verify_shop_camera` 全部通过。相机回归中三处陈旧断言已改用实际公开跟随/缩放语义，未修改相机玩法实现。


## Gameplay Bridge

相邻短事件通过 [Gameplay Bridge 编排规则](../guides/story_authoring_workflow.md#自动演出与玩家操作gameplay-bridge) 连接。
`GameplayBridge` 位于 MainGame/Systems，消费既有 GameState flag（v2）或 TeaMaking 的真实完成 Signal（v1），不执行 Story steps；详见 [Gameplay Bridge](gameplay_bridge.md)。
ShopUI 制作台提供固定配方按钮；配方规则属于 `src/gameplay/milk_tea/tea_making.gd`。
输入锁继续由 MainGame 依据 busy/modal/actor 状态计算；ActorDirector 和 CameraDirector 职责保持原样。

F6：`src/debug/gameplay_bridge/gameplay_bridge_demo.tscn`。推进开场对白，WASD 到奶茶制作台，E 打开，
依次点击红茶、牛奶、珍珠，确认完成后弹窗仍开着、音乐持续；Esc 返回后自动出现后续对白。
错误投料从头制作；未完成时 Esc 可退出并再次 E 继续。结束后移动恢复、不会重复续播。
再次单独运行 Demo 使用新的运行进程；宿主不重置全局状态。

自动验证：`Godot --headless --path . --script res://tests/verify_gameplay_bridge.gd`。
涉及 UI 的截图验证可去掉 `--headless`，并追加 `-- --capture`。
Godot 4.7 依据：[Signal 同步通知与自动断连](https://docs.godotengine.org/en/4.7/classes/class_signal.html)、
[Node 的 can_process 与暂停](https://docs.godotengine.org/en/4.7/classes/class_node.html)、
[AudioStreamPlayer 播放生命周期](https://docs.godotengine.org/en/4.7/classes/class_audiostreamplayer.html)。
