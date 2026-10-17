# 见闻录基础模块

`ChronicleJournal` 负责解锁、追加和已读状态，`ChroniclePanel` 负责列表与详情，`ChronicleHUD` 显示入口和未读条目数。MainGame 在 Systems 组装服务，将两个 UI 注册到现有 UIManager；无需新 autoload。正式入口不会加载测试内容。

## 接口与数据

```gdscript
var journal := game.get_chronicle_journal()
journal.unlock_entry("example.place", "条目标题")
journal.append_record("example.place", "example.place_first", "第一条记录正文")
journal.append_record("example.place", "example.place_follow_up", "后续记录正文")
game.open_chronicle()
```

| API | 约定 |
| --- | --- |
| `configure(state) -> Error` | 注入现有 GameState；可在入树前配置；重新配置断开旧订阅 |
| `unlock_entry(entry_id, title) -> Error` | 首次解锁设为未读；重复返回 OK，不改标题、记录或已读状态 |
| `append_record(entry_id, record_id, content) -> Error` | 条目必须已解锁；按追加顺序保留多条正文并重新标未读 |
| `mark_read(entry_id) -> Error` | 标为已读；重复调用无副作用 |
| `get_entry(entry_id) -> Dictionary` | 未解锁返回 `{}`；已解锁返回含 `entry_id/title/records/unlocked/is_read` 的独立副本 |
| `get_entries() -> Array[Dictionary]` | 仅已解锁条目，按首次解锁顺序排列，返回独立副本 |
| `get_unread_count() -> int` | 未读条目数（不是记录数） |
| `changed()` | 见闻录内容变化、GameState reset/restore 导致投影变化时发出；无关状态不触发 |

条目 ID 和记录 ID 均为项目命名空间标识符，例如 `day1.market`；标题和正文不可为空白。记录 ID 全局唯一，同条目内重复追加返回 OK，保留第一次正文及当前已读状态；另一条目复用该记录 ID 返回 ERR_ALREADY_EXISTS。未知条目的追加/已读返回 ERR_DOES_NOT_EXIST；未配置返回 ERR_UNCONFIGURED；非法参数返回 ERR_INVALID_PARAMETER。

进度存入 GameState 保留变量 `chronicle.entries`：`entry_id -> {title, records: [{record_id, content}], is_read}`。存在即已解锁，无需另存 `unlocked`。业务通过服务读写此保留变量，不直接修改字典。服务拒绝覆盖结构损坏的变量（ERR_INVALID_DATA），显示为空；开发者修正/恢复变量后自动刷新。

现有项目没有磁盘存档系统。进度已进入 `GameState.to_dict()` / `restore_state()` 边界，跨场景和已有快照恢复都保留解锁、正文和已读状态，不建立第二套存档。未来存档层保存完整原生 Variant 快照即可；遵循 [GameState 的类型约定](../systems/game_state.md)，不要直接将 JSON 数字解析结果作为原生快照。测试使用临时文件 store_var/get_var 验证真实磁盘往返。

## 正式剧情接入

在现有 Story v1 事件的 steps 中使用以下同步指令；支持现有 `when` 条件，不接受 `wait`：

```json
[
  {"command": "chronicle_unlock", "entry_id": "example.place", "title": "条目标题"},
  {"command": "chronicle_append", "entry_id": "example.place", "record_id": "example.place_first", "content": "记录正文"}
]
```

后续 Beat 只需追加另一个稳定 record_id；重播或失败重试不会重复内容。MainGame 已注入服务；自定义宿主将配置好的 journal 传入 `director.set_chronicle_journal(journal)`。缺少服务、未解锁追加或 ID 冲突会让事件失败并报告所在步骤，先前已成功步骤保持原样，沿用原 Director 的非事务语义。

正式编排继续遵循 [剧情编排工作流](../guides/story_authoring_workflow.md)，只从 Markdown 取标题与正文，不把剧情顺序硬编码到 GDScript。当前没有正式条目库，也不预加载未解锁正文；未来内容直接由各剧情 JSON 提供。测试事件集中在 `src/debug/chronicle/demo_story.json`，可独立替换，不引用正式剧情。

## UI 行为与 F6 验收

HUD 右下角“见闻录”按钮显示 `● 未读数`；打开后列表只显示已解锁内容，未读项前显示 `●`。打开列表本身不标已读，点击/方向键选择条目后显示详情并标已读。关闭清除选择，不会在再次打开时自动消费未读。向当前查看的条目追加内容会刷新正文但仍设为未读，重新选择后才标已读；隐藏或被暂停覆盖时不会自动消除提示。正文保持纯文本，自动换行并可滚动；长标题在列表截断并提供 tooltip，详情显示完整标题。

`MainGame.open_chronicle()` 返回 UIManager 错误码；剧情、对白、其他弹窗、Actor 控制和暂停期间拒绝新打开；重复打开已有界面返回 OK。弹窗复用主场景操作锁，最后一个锁退出后恢复玩家原本的移动状态。Esc 关闭，P 暂停覆盖并保留内容；方向键选择，Enter 确认，Tab 切换焦点，也支持鼠标。

打开 `src/debug/chronicle/chronicle_demo.tscn`，F6：

1. 点击右下角见闻录，列表为空；Esc 关闭。
2. 点击“解锁首条”，入口出现未读数；打开后选择条目，看到正文并清除未读。
3. 关闭后点击“追加记录”，重新打开可查看两段正文并消除未读；重复触发不会增加第三段。
4. 点击“解锁第二条”，列表出现第二条；读取它不会清除第一条的未读。
5. 在任意混合已读状态点击“快照”，改变进度后点击“恢复”，确认记录和已读状态回到快照。
6. 在回顾界面按 P，再 Esc，确认返回原界面；再次 Esc 关闭，玩家恢复操作。

Demo 开始时临时重置 GameState，离树恢复原快照。测试按钮只在 Debug 创建，模态打开时隐藏。正式主场景不会注入测试条目。

## 验证

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --log-file /private/tmp/goblin-chronicle-test.log --script res://tests/verify_chronicle.gd
/Applications/Godot.app/Contents/MacOS/Godot --path . --log-file /private/tmp/goblin-chronicle-visual.log --script res://tests/verify_chronicle.gd -- --capture
```

专用测试覆盖数据幂等、非法参数/损坏数据、只读副本、跨场景与磁盘快照恢复、真实 Story Loader/Director 调用、HUD/列表刷新、原生键盘已读、隐藏与暂停、弹窗/对白互斥和原有移动锁。窗口版在 640×360、1280×720、1440×720 检查长正文边界、实际窗口尺寸和滚动，并输出 `/private/tmp/goblin-chronicle-<width>x<height>.png`。

Godot 4.7.2 执行结果：专用测试 65 项通过；窗口版附加尺寸/边界/滚动断言 9 项通过并检查截图；UIManager 47 项、StoryDirector 163 项、GameState 120 项、MainGame 73 项、Debug 边界 97 项通过。仅包含本次改动的临时项目副本再次通过专用 65 项和 MainGame 73 项，确认不依赖同工作区的其他未提交功能。

## Godot 4.7 官方依据

- [Control](https://docs.godotengine.org/en/4.7/classes/class_control.html)：Theme 继承、容器布局、GUI 焦点与事件消费。
- [ItemList](https://docs.godotengine.org/en/4.7/classes/class_itemlist.html)：原生选择与滚动；`allow_reselect` 允许重复读取，程序调用 `select()` 不发选择信号，因此刷新不会误标已读。
- [RichTextLabel](https://docs.godotengine.org/en/4.7/classes/class_richtextlabel.html)：关闭 BBCode 以保留原文，使用内部滚动显示多条记录。
