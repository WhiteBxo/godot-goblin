# AudioManager（剧情演出第一阶段）

`src/core/audio/audio_manager.tscn` 是可独立实例化的轻量音频服务，正式场景位于 `MainGame/Systems/AudioManager`，通过 `MainGame.get_audio_manager()` 取得。生命周期跟随 MainGame；当前没有跨 MainGame 切换保持播放的需求，因此不增加 autoload。正式入口不注册 Demo 音色、不自动播放音乐。

根目录 `default_bus_layout.tres` 使用 Godot 默认加载位置，保存 Music、SFX、UI 三个 Bus，均发送到 Master；无需改动 `project.godot`。不添加 Bus effect、空间声或混音编辑器。淡入淡出只调整对应播放器的音量，不改变整个 Bus。

## 资源与 API

在场景 Inspector 的 `sounds` 字典配置 `逻辑 ID -> AudioStream`，或使用 `register_sound` 注入。集中资源表位于 `src/resources/audio/sound_library.tres`，新增剧情 ID 时由宿主注册对应资源。场景中的直接资源引用可由导出器跟踪；同一个目录可供音乐、SFX 和 UI 使用，路由由调用的 API 决定。运行时注册的文件和旧 JSON 中动态路径仍须显式纳入导出资源。

```gdscript
var audio := game.get_audio_manager()
audio.register_sound("shop.ambience", preload("res://assets/audio/shop_loop.ogg"))
audio.register_sound("story.knock", preload("res://assets/audio/knock.wav"))
audio.play_bgm("shop.ambience", 0.6)
var handle := audio.play_sfx("story.knock")
audio.stop_sound(handle, 0.3)
```

示例路径需要替换为实际素材。未传循环配置时保留 AudioStream 导入设置；配置 BGM 循环时仅修改独立资源副本。未开启循环的曲目自然结束后停止。

| API | 行为 |
| --- | --- |
| `register_sound(id, stream, bgm_config = {}) -> Error` | 注册或替换逻辑 ID；空 ID/null 拒绝；可选 BGM 原生循环配置见下；已播放声音继续使用原流 |
| `play_bgm(id, fade_seconds = 0.5, volume_db = 0, restart = false) -> Error` | 无音乐时淡入；不同曲目先淡出旧曲再淡入新曲，每段各耗时 fade_seconds；0 立即切换；restart 显式从 Intro 重播 |
| `fade_bgm(volume_db, seconds) -> Error` | 调整当前音乐音量；可压低、恢复或淡至静音；不停止播放 |
| `stop_bgm(fade_seconds = 0)` | 淡出后停止并释放当前流；0 立即停止 |
| `play_sfx(id, owner = null, volume_db = 0) -> int` | SFX Bus，返回正数播放 handle，失败返回 0 |
| `play_ui(id, owner = null, volume_db = 0) -> int` | 同一播放器池，UI Bus，暂停时继续播放 |
| `play_sfx_path(path, owner = null) -> int` | 旧剧情兼容入口，检查 `res://` 和 AudioStream 类型 |
| `stop_sound(handle, fade_seconds = 0)` | 停止单个 handle；旧 handle/重复停止静默；可淡出 |
| `stop_owned(owner, fade_seconds = 0)` | 只停止这个 RefCounted token 所属的短音效；null 静默；从不操作 BGM |
| `get_active_sound_count(owner = null)` | 返回在用池槽数（包括暂停/淡出），指定 token 时只计所属声音 |
| `get_bgm_state()` | 返回 `id`、`playing`、`volume_db`，供状态显示和调试 |
| `last_error` | 资源、参数、服务不可用或池满诊断 |

淡出时长要求有限且 ≥ 0；音量要求有限并限制在 -80～6 dB，-80 dB 为淡出静音底线。BGM 新请求会 kill 旧 Tween，取消未执行的换曲/停止回调；最新有效请求生效。缺失曲目不会打断当前 BGM 或已有过渡。同 ID 且同资源的 BGM 请求保持播放位置，只更新目标音量。切换过程 `get_bgm_state().id` 在新曲真正开始时才更新。

播放器池预建 8 个 AudioStreamPlayer，Inspector 可配置为 1～32。一个 handle 对应一个播放器，可重叠播放同一音效。池满跳过新请求，保留已播放声音；不扩张、不抢占。自然结束、显式停止和演出收尾均归还池槽；停止会清除流和旧淡出 Tween，复用时重置路由、音量和 process mode。handle 单调增长，旧 handle 不会停止后来复用同一播放器的声音。

AudioManager 使用 Always：BGM、BGM Tween 和 UI 在暂停时继续；SFX 播放器使用 Pausable，其淡出 Tween 绑定播放器，一起暂停/恢复。演出取消即时停止所属 SFX，即使世界已暂停。服务退出清理播放和 Tween。

## BGM Intro + Loop

集中配置仍使用 `src/resources/audio/sound_library.tres` 的 `entries`，在宿主调用 `register_all(audio)` 时注册。支持直接资源引用（推荐，可自动跟踪导出）或下面的路径字典；字典也可来自 JSON 解析后赋给 `entries`，无需修改剧情 JSON：

```json
{
  "id": "shop_bgm",
  "path": "res://assets/audio/bgm/shop.ogg",
  "loop": true,
  "loop_offset": 12.345
}
```

该示例素材需自行提供，`path` 资源需显式纳入导出。直接资源引用的条目写为 `{"id": "shop_bgm", "streams": [ExtResource("shop_music")], "loop": true, "loop_offset": 12.345}`，并按现有资源表声明对应 `ext_resource`。`path` 和 `streams` 不能同时提供。

也可由现有代码注入配置：

```gdscript
audio.register_sound("shop_bgm", shop_stream, {"loop": true, "loop_offset": 12.345})
audio.play_bgm("shop_bgm", 0.5) # 首次从 0 开始；重复请求只调整音量
audio.play_bgm("shop_bgm", 0.5, 0.0, true) # 显式从 Intro 重播
```

- `loop=true`、`loop_offset=0.0`（默认）为整首循环；正偏移为一次 Intro 后循环后半段；`loop=false` 播放一次后自然结束。新配置省略 `loop` 时默认为 true。
- 偏移单位为秒，必须是有限数且 `0 <= loop_offset < stream.get_length()`，包括 `loop=false` 时也检查。非法配置返回错误和诊断，保留同 ID 原先注册内容及正在播放的音乐。
- 配置仅用于 `play_bgm`：复制 `AudioStreamOggVorbis` 的顶层 Resource，设置 `loop` / `loop_offset`，清零 `beat_count`，确保文件结尾就是 Loop End。音频线程原生跳转，不用 Timer、`_process()` 或 `finished` 重启。现有 `finished` 回调只清理自然结束的非循环曲目状态。
- 同 ID 且同资源的普通请求保留播放位置；停止后重播、切换曲目或切回都会从 Intro 开始。`restart=true` 也使用原有淡出/淡入流程。
- 显式循环配置仅支持 Ogg Vorbis；其他格式返回错误并 `push_warning`，不静默忽略偏移。未配置的旧资源保留原导入行为，SFX/UI/环境音仍使用原始资源。旧 WAV 条目中的 `loop` 标签仍是素材元数据；增加 `loop_offset` 才会尝试新的 BGM 配置。Ogg 条目的 `loop` 或 `loop_offset` 均可启用配置。
- 缺失路径、非音频资源、加载失败由 `register_all` 返回错误列表，调用方应检查；非法 BGM 配置同时写入 `last_error` 并发出警告。

剧情继续使用原 `play_bgm` / `fade_bgm` / `stop_bgm` 指令和 ID。剧情需要显式重播同一首时可先 `stop_bgm` 再 `play_bgm`，无需扩展 JSON 参数。场景生命周期、总线、音量与淡变逻辑均保持原接口。

依据 [Godot 4.7 AudioStreamOggVorbis](https://docs.godotengine.org/en/4.7/classes/class_audiostreamoggvorbis.html) 的 `loop`、秒制 `loop_offset` 和 `beat_count` 规则，以及 [Resource.duplicate](https://docs.godotengine.org/en/4.7/classes/class_resource.html#class-resource-method-duplicate) 的资源复制语义实现。代码不修复素材接缝，无缝听感仍取决于 REAPER 中的裁剪质量。

### 验证与试听

```sh
godot --headless --path . --script res://tests/verify_bgm_loop.gd
```

测试使用本项目合成的 `tests/fixtures/bgm_intro_loop.ogg`（1.2 秒；0～0.4 秒 220 Hz Intro，后续 440 Hz Loop），观察真实解码播放位置跨文件结尾回跳，覆盖整首循环、两次后半段循环、不循环、重播/切回、淡变、非法输入、资源隔离和原剧情适配接口。素材生成方式见同目录 `bgm_intro_loop.md`。

人工试听：在现有宿主注册该路径、`loop=true`、`loop_offset=0.4`，调用 `play_bgm`。应先听一次低音，再持续高音；重复调用保持高音，切回或显式重播再次出现低音。也可将示例配置放进自己的 `SoundLibrary` 后 F6 运行宿主。现有 `src/debug/audio/audio_demo.tscn` 的 F6 可继续验收淡变、总线和音效交互，其合成 WAV Demo 不用于验收 Ogg 接缝。

## StoryDirector 适配

MainGame 注入 `StoryAudioAdapter.new(audio)`，Director 只调用适配层，不操作 AudioStreamPlayer 或 AudioServer。

```json
{"command": "play_sfx", "id": "story.knock"}
{"command": "play_sfx", "path": "res://src/debug/story/strange_knock.tres"}
```

每步必须提供非空 `id` 或旧 `res:// path` 之一，二者不能同时提供。保持 `version: 1` 和原 `play_sfx` 的非阻塞语义。适配层有独立 RefCounted ownership token，Director 的成功、失败、取消、重新配置和退出均通过 `stop_owned` 清理声音，独立 BGM、独立场景音效、其他适配层的声音不受影响。替换适配层前先取消旧演出。

未知 ID、缺失文件、非 AudioStream、无适配层、已删除服务或池满均通过 `step_skipped` 报告，然后继续下一步；没有等待声音的 coroutine，因此不会因缺失资源卡住。无效 JSON 引用类型仍在加载阶段报错。

## 独立试听与验证

编辑器打开 `src/debug/audio/audio_demo.tscn`，F6 运行；无需加载 MainGame、对白或剧情目录。所有音色在 `audio_demo_tones.gd` 中确定性合成，为本项目原创占位资源，没有外部素材依赖。

1. 点「BGM A」，听到淡入；再点「切换 BGM B」，旧曲用 0.6 秒淡出，新曲用 0.6 秒淡入。快速交替点击应以最后一次请求为准。
2. 点「压低 BGM」「恢复 BGM」「淡出停止」，听到渐变音量，最后状态显示停止。
3. 点「叠加低音 + 高音」，应同时听见两种音高；重复点击观察池槽上限和自然回收。
4. BGM 播放时点「演出长音效」，随即点「取消所属音效」：长音立即停止，BGM 持续。
5. 点「独立音效淡出」：长音在 1.5 秒内衰减；点「UI 提示音」验证独立 UI 路由。
6. 点「缺失 ID」：状态显示诊断，其他按钮仍可操作。

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . res://src/debug/audio/audio_demo.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_audio_manager.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_story_director.gd
```

音频测试覆盖实际播放状态、淡入淡出中间值/终点、连续换曲、取消延迟停止、自然结束、池满、复用和旧 handle、owner 隔离、暂停语义、真实 Director 取消/退出/服务移除、缺失资源及独立 Demo。非 headless 运行测试时加 `-- --capture` 可保存 `/private/tmp/audio-demo.png`。自动化检查能确认播放调度与状态，最终听感按上述步骤人工验收。

依据 Godot 4.7 官方文档：[AudioStreamPlayer](https://docs.godotengine.org/en/4.7/classes/class_audiostreamplayer.html) 的 `stop()` 不发 `finished`，因此显式回收；[Tween](https://docs.godotengine.org/en/4.7/classes/class_tween.html) 同一属性避免多个 Tween，替换时 kill、退出时随绑定节点清理；[Audio Bus](https://docs.godotengine.org/en/4.7/tutorials/audio/audio_buses.html) 默认布局和 Bus 路由；[Node process mode](https://docs.godotengine.org/en/4.7/classes/class_node.html) 与 [AudioStreamWAV](https://docs.godotengine.org/en/4.7/classes/class_audiostreamwav.html) 暂停和循环设置。

## StoryDirector Cinematic 接入

旧 play_bgm / fade_bgm / stop_bgm 返回类型不变，新增 `get_music_action() -> AudioAction` 返回最近一次有效音乐操作的独立结果。`completed / succeeded / reason` 可检查状态，`finished(action)` deferred 发布且只结算一次；自然淡变完成成功，替换、取消、服务退出失败。零时长同样返回可连接的结果；等待的是音乐过渡，不是循环曲目结束。

新增 `sound_finished(handle, cancelled)` 在声音归还池后发出；自然结束 cancelled=false，stop/owner 清理为 true。适配层把声音 handle 转为 AudioAction，并在事件结束断开通知。JSON 新增 play_bgm / stop_bgm / fade_bgm 和可选 wait；原 play_sfx id/path 均兼容。声音缺失继续 skipped，默认 SFX 非阻塞、新 BGM 指令阻塞。场景 BGM 与新外部请求通过最近 action 身份和所属音效 owner 区分，详见 [演出调度与所有权](story_director.md#并行冲突与取消)。
