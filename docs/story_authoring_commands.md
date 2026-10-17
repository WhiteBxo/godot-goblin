# 剧情编排指令速查（v1）

以 `src/core/story/story_library.gd`、`story_director.gd` 及 `src/core/dialogue/dialogue_library.gd` 的实际校验和 dispatch 为准。共 19 条 Story 指令；Director 的公开 GDScript API 不一定能在 JSON 中使用，例如 `camera_follow` 不是 Story command。

## Story JSON

顶层仅 `{"version": 1, "events": {"namespace.event": {...}}}`；事件仅 `once`（bool，默认 true）、`trigger`（string，默认空）、`conditions`（默认 `{}`）、`steps`（非空数组）。未知字段拒绝。每步必有 `command`，可有 `when`；下表列出其余全部参数，未注明默认值即必填。

`target` = 注册 Marker2D 的非空 ID 或有限世界坐标 `[x, y]`，不是 NodePath；`actor` = 非空 Actor ID。所有数字必须有限；时间单位秒，位置/速度为世界像素及世界像素/秒。

| command | 参数、默认值与限制 | 默认 Blocking |
| --- | --- | --- |
| `dialogue` | `id` 非空，对应已加载 Dialogue ID；等待自然结束 | 是，不接受 wait |
| `wait` | `seconds >= 0`；0 到下一 process tick | 是，不接受 wait |
| `set_flag` | `key` 命名空间 ID；`value` bool，默认 true | 同步，不接受 wait |
| `set_stage` | `value` string | 同步，不接受 wait |
| `play_sfx` | `id` 非空或 `path` 为 res://，严格二选一；`wait` bool | 否 |
| `actor_spawn` | `actor` 尚未占用；`scene` 为 res://*.tscn，根继承 PlayerController；`target`；`wait` bool | 是 |
| `actor_move` | `actor`、`target`；`speed = 120`、`timeout = 15`，均 > 0；`wait` bool | 是 |
| `actor_face` | `actor`、`direction` 为 up/down/left/right；`wait` bool | 是 |
| `actor_emote` | `actor`；`symbol = "!"` 非空文字；`duration = 0.8`，> 0；`wait` bool | 是 |
| `actor_show` | `actor`；`wait` bool；只显现，不改变碰撞 | 是 |
| `actor_hide` | `actor`；`wait` bool；只隐藏，不注销/移除碰撞 | 是 |
| `camera_focus` | `actor` 或 `target` 二选一；`duration = 0.8 >= 0`；`wait` bool；到位后持续跟踪节点 | 是 |
| `camera_move` | `target`；`duration = 0.8 >= 0`；`wait` bool；位置快照 | 是 |
| `camera_shake` | `intensity = 2`、`duration = 0.3`、`decay = 1.5`，均 >= 0；`wait` bool；强度为逻辑视口像素且受相机上限限制 | 是 |
| `camera_zoom` | `value > 0`；`duration = 0.5 >= 0`；`wait` bool；实际缩放受地图约束 | 是 |
| `camera_reset` | `wait` bool；立即恢复默认 Follow/zoom/offset | 是 |
| `play_bgm` | 注册的 `id`；`fade = 0.5 >= 0`、`volume_db = 0`；`wait` bool；换曲可能含淡出+淡入两段 | 是，只等过渡 |
| `stop_bgm` | `fade = 0 >= 0`；`wait` bool | 是 |
| `fade_bgm` | `volume_db`；`fade = 0.5 >= 0`；`wait` bool；改变当前 BGM 音量 | 是 |

`conditions` / `when` 允许以下字段（均可省略，各项 AND）：`day` 正整数、`stage` string、`flags` 命名空间 key→bool（缺失 flag 为 false）、`completed_events` / `not_completed_events` 命名空间 ID 数组。仅 `when` 额外接受 `choice: {"dialogue": "ID", "line": "行ID", "id": "选项ID"}`，三个字符串非空。本次尚未作出的选择不匹配。

命名空间 ID 至少两个由 `.` 分隔的合法 identifier，例如 `day1.intro_finished`。Actor、Marker、音频和 Dialogue ID 没有该强制命名空间约束，但应保持现有稳定名称。

## Dialogue JSON

```json
{
  "version": 1,
  "dialogues": {
    "example.greeting": {
      "start": "hello",
      "lines": {
        "hello": {"speaker": "店员", "text": "你好。", "next": "question"},
        "question": {
          "speaker": "店员", "text": "需要什么？",
          "choices": [{"id": "leave", "text": "下次再来", "next": ""}]
        }
      }
    }
  }
}
```

Dialogue ID、行 ID 非空，`start` 必须指向当前对话的行；`speaker`、`text` 为必填 string，可空，纯文本不启用 BBCode。`portrait` 默认空，非空须是存在的 res:// Texture2D；`next` 默认空，非空须指向同一对话的行。`choices` 默认空数组；非空时不能同时带行级 `next`；每项 `id` 在行内唯一且非空、`text` 非空、`next` 规则同上。普通连续对白显式连接 `next`，否则结束。Loader 允许循环，需人工确认是否为原稿意图，并为自动验证提供有限路径。DialogueLibrary 未严格拒绝额外字段，但编排产物只写上述字段。

## 当前绑定基线

| 宿主/作用域 | 可复用项与来源 |
| --- | --- |
| MainGame | 默认 `player`；`res://src/core/main.tscn` 当前组装奶茶店、ShopPlayer 和各 Director。没有默认演出 Marker 或剧情音频注册 |
| Cinematic Demo | `door` (1500, 270)、`aisle` (1470, 560)、`counter` (1100, 610)，保存在 cinematic_demo.tscn 的 Positions；宿主注册后才可用 |
| Cinematic 动态角色 | `customer` 由 Story spawn，资源 `res://src/debug/cinematic/customer.tscn`；复用 PlayerController 的暖色占位形象 |
| Cinematic 音频 | `cinematic.bell` = AudioDemoTones.tone(880, 0.45)；`cinematic.room` = tone(164.81, 2, true) 循环；`cinematic.rumble` = `res://src/debug/story/strange_knock.tres`；仅 Demo 宿主注册 |
| 其他演示与测试 | 如 `demo.*` 音频、`test_position` 不属于正式注册表；只有目标宿主实际配置后才能引用 |

此表是检索起点；每次编排重新核对目标场景实际注册和资源存在性，不把基线当全局常量。更多冲突/取消规则见 [StoryDirector](story_director.md#并行冲突与取消)，工作流见 [编排规范](story_authoring_workflow.md)。


## Gameplay 模式字段

Markdown Beat 可声明 `执行模式：自动演出 / 玩家操作`，玩家 Beat 必须声明 `玩法完成条件`。
它们是编排字段，不是 Story command，不传给 StoryLibrary。Codex 在玩家边界结束当前短事件，
生成六字段 phase 条目，并为下段事件生成 stage + completed_events + completion flag 准入条件。
详见 [拆分、映射和验证规则](story_authoring_workflow.md#自动演出与玩家操作gameplay-bridge)。
v1 保留 `pearl_milk_tea` 一杯（红茶→牛奶→珍珠）。v2 支持 `completion: {"flag": "shop.order_001_delivered", "allow_existing": true}`，消费真实业务事实；其他尚无 Signal/状态实现的目标列 pending。
成功事件收尾保留场景 BGM，SFX 仍清理；取消/失败仅停止仍属本事件的音乐。
