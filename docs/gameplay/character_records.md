# 人物记录

人物记录是独立于异闻录的最小情报模块：剧情显式解锁人物，按获得顺序追加主角已知的信息，玩家在统一手册的「人物记录」页查看。人物列表不会提前显示未解锁姓名或正文；不包含雇佣、队伍或长期关系数值。

## 接入与存储

MainGame 在 Systems 创建 `CharacterJournal`，注入现有 GameState、StoryDirector 与手册。服务不新增 autoload，不写文件；人物进度位于 GameState 保留变量 `characters.entries`，随完整快照和现有检查点存档保存。旧快照缺少该变量时视为尚未解锁。

```gdscript
var journal := game.get_character_journal()
journal.unlock_character("characters.drunken_guard", "醉酒守卫")
journal.append_record("characters.drunken_guard", "guard.identity", "身份——哥布林守卫")
game.open_characters()
```

| 接口 | 行为 |
| --- | --- |
| `configure(state) -> Error` | 可在入树前配置；重绑断开旧状态订阅；无效配置保留原绑定 |
| `unlock_character(character_id, title) -> Error` | 首次出现设为未读；重复不覆盖姓名、正文或已读状态 |
| `append_record(character_id, record_id, content) -> Error` | 必须先解锁；新增信息设为未读；同人物同记录 ID 重试无副作用 |
| `mark_read(character_id) -> Error` | 显式标已读；重复读取无副作用 |
| `get_character(character_id) -> Dictionary` | 锁定返回 `{}`；解锁后返回含 `character_id/title/records/is_read/unlocked` 的副本 |
| `get_characters() -> Array[Dictionary]` | 仅已解锁人物，按首次解锁顺序返回副本 |
| `get_unread_count() -> int` | 未读人物数 |
| `changed()` | 内容、已读状态或 reset/restore 改变投影后通知；不因无关事实通知 |

保留变量格式为 `人物ID -> {title, records: [{record_id, content}], is_read}`。ID 使用命名空间；姓名和正文不可为空白。记录 ID 在人物记录模块中全局唯一，跨人物复用返回 `ERR_ALREADY_EXISTS`。未解锁的追加/读取返回 `ERR_DOES_NOT_EXIST`，无绑定返回 `ERR_UNCONFIGURED`，非法参数返回 `ERR_INVALID_PARAMETER`。损坏的保留变量显示为空并拒绝写入，返回 `ERR_INVALID_DATA`；GameState 正在替换状态而拒绝提交时返回 `ERR_BUSY`。

## 剧情指令

StoryLibrary 严格校验以下同步指令；保留现有 `when` 条件，不接受 `wait`。MainGame 自动注入服务，其他宿主调用 `StoryDirector.set_character_journal(journal)`。缺少服务或追加到未解锁人物时，事件明确失败，已执行步骤保持现有不回滚语义。

```json
[
  {"command": "character_unlock", "character_id": "characters.drunken_guard", "name": "醉酒守卫"},
  {"command": "character_append", "character_id": "characters.drunken_guard", "record_id": "guard.identity", "content": "身份——哥布林守卫"}
]
```

标题、身份、特征、已知交集及主角判断均由剧情提供纯文本，不根据 Actor 注册、地图出生或未来剧情自动推断。后续更新使用新的稳定记录 ID，保留先前认识。结构化剧情工程沿用现有 StoryLibrary 校验，无需第二种编排格式。

Day 2 正式运行时事件目前仍为空，`s05_useful_guard` 的正式发布受原有剧情接线约束。本模块已提供可用指令与独立预览；后续在正式结构化工程中把人物解锁和情报追加放在对应「人物记录更新」提示附近，再生成运行时产物。本次未修改其他工作中的剧情工程或替它发布 pending 内容。

## 查看与试玩

统一手册新增第四页「人物记录」，`ScreenIds.CHARACTERS` / `MainGame.open_characters()` 复用同一模态。首位人物解锁后显示页签和 HUD；没有任何已解锁页面时入口隐藏。HUD 未读点合并异闻录与人物记录，tooltip 分别显示数量。打开列表不标已读；点击或方向键/Enter 选择人物才读取。切换页签、隐藏窗口或暂停覆盖不会自动消费未读。追加当前查看人物的信息会刷新详情并保持未读，需再次选择。Esc 关闭并由 UIManager 恢复焦点及原有输入锁。

F6 打开 [人物记录预览](../../src/debug/characters/character_records_demo.tscn)：

1. 点击「解锁守卫」，右上角手册出现未读提示；点击「查看」或手册的「人物记录」。
2. 选择醉酒守卫，查看原稿中的身份、特征和已知交集；未读提示消除。
3. Esc 关闭后点击「追加判断」，再次查看可见「此人或许具有利用价值，未来可以尝试拉拢。」；重复追加不重复记录。
4. 用「快照」「重置」「恢复」检查人物、正文和已读状态恢复。
5. 页面内按 P 暂停，Esc 返回原页面，再 Esc 关闭；观察角色操作恢复。

预览临时重置整局，离树恢复原快照。预览事件仅供显式运行调试场景，正式入口不加载它们。

## 验证与官方依据

```sh
godot --headless --path . --script res://tests/verify_character_records.gd
godot --path . --script res://tests/verify_character_records.gd -- --capture
```

测试覆盖幂等、只读副本、非法数据、真实 Story dispatch、独立状态、磁盘快照、宿主重建、手册解锁、键盘已读、暂停覆盖、页签切换、输入锁和预览隔离；窗口模式另检查 640×360 / 1280×720 的长正文边界与滚动，截图位于 `.godot/character-records/`。

实现核对 Godot 4.7 的 [ItemList](https://docs.godotengine.org/en/4.7/classes/class_itemlist.html)（程序 `select()` 不发选择信号）、[TabContainer](https://docs.godotengine.org/en/4.7/classes/class_tabcontainer.html)（隐藏未解锁页签）和 [RichTextLabel](https://docs.godotengine.org/en/4.7/classes/class_richtextlabel.html)（纯文本、内部滚动）。

2026-10-18，Godot 4.7.2 实际验证：人物记录无窗口 59 项、窗口模式 65 项通过；手册 44、任务页 92、异闻录 64、UIManager 47、StoryDirector 163、GameState 126、MainGame 74、SaveStore 25、存档集成 45、存档边界 18、剧情编辑器 44、主题 219 项通过。窗口截图已检查。

在 `7af642e` 的临时源码副本中仅应用本次运行时代码与测试，人物记录 59 项及 MainGame 74 项再次通过，确认不依赖同工作区的其他并行修改。

`verify_story_authoring.py --godot <引擎路径>` 在 `cinematic.opening/steps[9]` 因顾客移动到 `(1470, 560)` 受阻失败；未含本次改动的 `7af642e` 基线复现相同失败。UIManager 退出的 7 个 ObjectDB / 3 个资源诊断也在基线复现。未执行发行导出及无关玩法专项检查，本次未改变发布配置或其业务规则。
