# 通用对话系统（P0-1）

## 模块与接入

- `src/core/dialogue/dialogue_library.gd`：加载、校验 JSON，失败时保留上一份有效目录，提供独立数据副本。
- `src/core/dialogue/dialogue_manager.gd`：场景内的 `DialogueManager`，管理当前对话、推进、分支及结束；不读写 GameState，不管理玩家或店铺节点。
- `src/UI/dialogue/dialogue_ui.tscn` 与同目录脚本：姓名、当前说话者的可选立绘、纯文本逐字显示、选项按钮及输入请求；UI 不知道 `next` 或选项业务 ID。
- MainGame 在 `Systems` 创建 Manager，在现有 `PopupLayer`（layer 20）创建 UI，通过公开 getter 提供调用入口。未增加 Autoload、未修改订单/仓库/制作台文案及业务逻辑，未自动触发正式剧情。

后续场景或演出组件通过父场景传入的 Manager 引用调用：

```gdscript
var dialogue := game.get_dialogue_manager()
var error := dialogue.start_dialogue("demo.first_shift")
if error != OK:
	print("Dialogue did not start: ", error, " ", dialogue.last_error)
```

独立宿主只需实例化 UI 与 Manager，把 UI 加到自己的 PopupLayer，再调用 `manager.configure(ui, can_start)`。`can_start` 为可选的无参数 Callable，返回 bool，供宿主检查其他弹窗。宿主连接 `dialogue_started` / `dialogue_ended` 管理自己的输入生命周期。Manager 不依赖 MainGame 或奶茶店。

## 公开 API 与 Signal

| API | 说明 |
| --- | --- |
| `configure(ui: DialogueUI, can_start: Callable = Callable()) -> void` | 绑定显示与输入请求；宿主应在 UI 进入场景树后、启动对话前完成配置 |
| `start_dialogue(id: String, cancel_protected: bool = false) -> Error` | 首次调用自动加载 `dialogue_file`；成功返回 `OK`，已有对话或宿主拒绝返回 `ERR_BUSY`，无 UI 返回 `ERR_UNCONFIGURED`，未知 ID 返回 `ERR_DOES_NOT_EXIST`。`cancel_protected` 由剧情宿主声明本段属于事件：Esc 只跳到本段末尾，不能取消事件 |
| `load_dialogues(path: String = "") -> Error` | 空参数重新加载导出的 `dialogue_file` 配置；显式 path 加载其他 JSON。仅 idle 时允许，失败保留旧目录。已加载目录中 ID 不存在时不会静默改载默认文件 |
| `is_active() -> bool` | 当前是否有对话 |
| `get_current_line_id() -> String` | 当前行 ID，idle 时为空 |
| `set_current_portrait(portrait: Texture2D) -> Error` | 即时替换当前句立绘，传 `null` 隐藏；保留文字进度、选项、焦点及左右位置，不发 `line_changed`。下一句重新按 JSON / 默认图解析；idle 或 UI 不可用返回 `ERR_UNCONFIGURED` |
| `set_speaker_portrait(speaker: String, portrait: Texture2D) -> void` | 更新角色默认图，`null` 移除映射；当前角色同名且该句没有 `portrait` 字段时立即刷新。显式单句图或显式隐藏优先 |
| `advance() -> void` | 逐字显示时补全文本；完整显示后推进普通对白；选项行等待选择 |
| `skip_to_end() -> void` | 一次走完当前对话的线性剩余行；遇到选项停下并显示完整选项。只对落点行发一次 `line_changed`，中间行不逐句通知；用于剧情对白的 Esc 跳过，与 `end_dialogue(true)` 的取消语义分开 |
| `select_choice(index: int) -> void` | 使用从 0 开始的 UI 索引选择分支；逐字显示期间或索引无效时忽略 |
| `end_dialogue(cancelled: bool = false) -> void` | 结束当前对话；idle 时不重复通知 |
| `last_error: String` | 文件、JSON 和未知 ID 的详细诊断；按返回的 Error 判断调用结果 |

Signals：`dialogue_started(dialogue_id: String)`、`dialogue_ended(dialogue_id: String, cancelled: bool)`、`choice_selected(dialogue_id: String, line_id: String, choice_id: String)`、`line_changed(line_id: String)`。

开始 signal 先于第一行显示，方便宿主同步锁定输入。选择 signal 先于分支推进及可能的结束 signal；重复选择 dispatch 被阻止。自然结束与剧情对白的 Esc 跳过均为 `cancelled = false`；普通对白的 Esc、UI 移除和 Manager 移除为 `true`。移除时仍发结束 signal 供宿主清理。Signal 回调宜执行状态更新；串联下一段对话时建议使用 `call_deferred`，避免同步生命周期回调中递归重入。

[StoryDirector（P0-2）](story_director.md) 已订阅 `choice_selected`，通过 JSON 步骤的 `when.choice` 条件消费稳定的 choice ID；Manager 继续不解释 flags、剧情条件或事件完成状态。

## JSON 文案

示例文件为 `src/resources/dialogue/example_dialogues.json`，包含单行 `demo.greeting`、连续对白及双分支 `demo.first_shift`。

```json
{
  "version": 1,
  "dialogues": {
    "example.hello": {
      "start": "question",
      "lines": {
        "question": {
          "speaker": "店员",
          "text": "想喝点什么？",
          "choices": [
            {"id": "tea", "text": "奶茶", "next": "reply"},
            {"id": "leave", "text": "下次再来", "next": ""}
          ]
        },
        "reply": {"speaker": "店员", "text": "好的，请稍等。"}
      }
    }
  }
}
```

- `speaker` 和 `text` 为必填字符串，可为空；文本支持 Unicode、换行，不启用 BBCode。长文本可滚动阅读。
- 省略 `portrait` 时，Manager 按 `speaker` 精确匹配导出的 `speaker_portraits` 字典。默认主角、玩家、主角·内心使用用户提供的平静表情全身图 `player_neutral_portrait.png`，胖哥布林、哥布林使用微笑立绘；旁白及其他未配置角色不显示图片。宿主可在 Inspector 或启动前修改该字典，为新角色配置 Texture2D，不依赖 Actor 节点层级。
- `portrait` 非空时必须为存在的 `res://` Texture2D 路径，优先于角色默认图，可用于单句表情变化；显式 `"portrait": ""` 隐藏该句立绘。每行重新解析，缺图、结束或取消均清除上一张图片。对话使用独立的透明背景 PNG，原始白底素材保留；默认图使用 preload 建立资源依赖。
- `left_portrait_speakers` 配置主角的姓名（默认主角、主角·内心、玩家），这些角色显示在左侧；其他 NPC 显示在右侧。单句覆盖图片不改变角色所属侧。
- 普通行用 `next` 指向同一对话中的行；省略或 `""` 表示确认后结束。连续对白必须显式连接。
- 选项由 `id`、`text` 和可选 `next` 构成。ID 在当前行内唯一，文案非空；`next` 为空表示选择后直接完成。非空 choices 与行级 next 不能同时出现。
- 加载时校验整个目录及全部分支目标；不会边演出边发现悬空的 `next`。循环分支允许，每次都等待用户确认，不会自动死循环。更新 JSON 后可 idle 时显式 reload。
- `export_presets.cfg` 已用 `*.json` 导出所有对话文件，测试目录仍被排除。新增导出 preset 时需保留 JSON 包含规则，以及字体许可证规则；改为仅导出选择的场景时需显式包含头像等由 JSON 动态引用的资源。

## 主角立绘与程序切换

用户提供的两张立绘已保存原图到 `assets/characters/apron_man/source/`，运行时使用同目录上级的 `player_neutral_portrait.png`（平静）和 `player_talking_portrait.png`（说话）。两张透明 PNG 共用 390×895 画布与原图裁切范围 `(331, 30, 721, 925)`，保留原比例，切换时不改变人物大小和脚底位置。去除了外部白底、手臂/腿间白底、头发灰白残边和脚下地面；原有 `player_portrait.png` 保留供既有显式引用使用。

```gdscript
const NEUTRAL: Texture2D = preload("res://assets/characters/apron_man/player_neutral_portrait.png")
const TALKING: Texture2D = preload("res://assets/characters/apron_man/player_talking_portrait.png")

# 父场景传入 DialogueManager，或通过宿主的公开 getter 取得。
# 默认图可在启动前配置；即时切换应在对白已启动之后调用。
dialogue.set_speaker_portrait("主角", NEUTRAL)
dialogue.start_dialogue("demo.player_expressions")
dialogue.set_current_portrait(TALKING)
dialogue.set_current_portrait(null) # 只隐藏当前句，下一句重新解析。
```

如果切换由对白数据驱动，继续使用现有 v1 JSON 的 `portrait` 路径字段，例如 `"portrait": "res://assets/characters/apron_man/player_talking_portrait.png"`。无需修改 StoryDirector 或正文顺序。程序默认映射按 speaker 精确匹配；`主角·内心`、`玩家` 是独立键，按需分别配置。

重建透明素材（Python 3、Pillow、numpy）：`python tools/art/prepare_player_portraits.py`。来源和抠图规则见 [本次素材导入记录](../assets/imports/player_dialogue_portraits.md)。

## 输入与界面边界

UI 复用 InputMap 的 `interact`、`ui_accept`、`ui_up/down`、`ui_cancel`，没有硬编码 gameplay 按键。默认 E、空格、Enter：第一次补全文本，再按推进；完整显示选项后用 ↑↓ 及确认键选择，也可点击按钮。普通对白 Esc 中止；剧情宿主以 `cancel_protected` 启动的对白，Esc 只跳到本段末尾（遇选项停下），不会取消事件。长按 echo 不推进，进入新行的当前帧不接受推进键。确认键在 dispatch 前消费，结束对话的同一按键不会落入场景交互。

持续按住确认键 0.35 秒后进入连续快进，每 0.06 秒推进一次；松开即停，遇选项停止，因此不会替玩家选择分支。两段时间是 `DialogueUI` 的导出参数。`PlayerPreferences` 另提供 `dialogue_auto`（0 关闭，1.5／3／5 秒）作为自动播放间隔：全文显示后按该间隔推进普通行，选项和快进期间不生效。设置页的“对白自动播放”与对白速度、音量一起应用并写入 `user://preferences.cfg`。

逐字速度默认每秒 32 字，`DialogueUI` 的 Inspector 可调整 `comma_pause`（逗号／顿号，0.06 秒）、`sentence_pause`（句中句号／问号／叹号，0.12 秒）、`ellipsis_pause`（省略号，0.18 秒）。连续标点只采用一次最长停顿，行末及其闭引号不额外等待；设为 0 可关闭对应停顿。确认补全立即清除计时，选项在全文显示后取得焦点。

立绘首次显示、更换说话人或更换图片时按 `portrait_fade_seconds`（默认 0.14 秒）淡入，位置不变，同角色同图片连续对白不重播。确认补全同时完成淡入；关闭、取消和重新打开会清理旧动画。公开 `set_current_portrait` 仍即时切图，不重启动画或文字。实现依据：[Godot 4.7 RichTextLabel](https://docs.godotengine.org/en/4.7/classes/class_richtextlabel.html) 的 Unicode 字符计数与 [Tween](https://docs.godotengine.org/en/4.7/classes/class_tween.html) 的取消和节点生命周期。

MainGame 复用 `PlayerController.set_movement_enabled` 保存并关闭移动，并用 ShopInteraction 新增的通用 `set_input_enabled` / `is_input_enabled` 关闭交互和提示。交互点直接发 signal 也受此开关保护。MainGame 统一以“对白活跃 OR StoryDirector 忙碌”计算锁定；最后一个输入所有者结束才恢复原值，演出停顿也保持锁定，原先已禁用的控制不会被误启用。ShopUI 已打开时通过 `can_start` 拒绝启动对话，继续使用现有店铺弹窗锁定逻辑，不堆叠两个输入所有者。

UI 按 640×360 视口设计，底部面板为 560×136px，水平居中、距底边 12px，棕色、金色边框与奶茶店一致。当前说话者立绘在左侧或右侧的 240×272px 区域内等比居中，使用线性过滤。区域中心对齐面板上边缘，面板以较高的 z_index 绘制在立绘前方，遮住下半身，约上半身露出；无图时隐藏立绘。正文超出固定范围后支持鼠标滚轮和右侧滚动条阅读，不再撑大面板，新的一行从顶部开始显示。选项列表也支持滚动。对话 UI 与独立场景使用随包分发的 [Fusion Pixel](../../assets/fonts/fusion_pixel/README.md) 中文字体，避免依赖宿主系统 CJK fallback；保留完整简体字符版本、原始许可证和导入设置。

## 试玩与自动化验证

在 Godot 编辑器打开 `src/debug/dialogue/dialogue_demo.tscn`，按 F6；也可以运行：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . --scene res://src/debug/dialogue/dialogue_demo.tscn
```

1. 场景自动进入“主角表情”对白。点击右上方“平静 / 说话 / 隐藏”，观察同一句中立绘立即变化、文字继续显示。按钮在 DebugLayer，能在对话弹层打开时接收鼠标点击。继续推进时第二句使用 JSON 指定的说话表情，第三句恢复平静；结束或 Esc 后清理立绘。返回菜单选择“连续对白 · 两个选项”进行以下分支验证。
2. E 补全文本，再按推进；到达问题后出现两个选项，按 ↓ + Enter 或点击按钮选择，看到对应的不同回应。
3. 最后一行确认后返回菜单，显示稳定的选项结果 ID；菜单可重复播放普通对白、连续对白和主角表情，体验另一个分支。
4. 对话中 WASD 不移动角色；结束或 Esc 中止后 WASD 恢复移动，角色被限制在试玩区域。
5. 返回菜单点击“角色立绘 · 切换与隐藏”，依次观察左侧主角 → 右侧胖哥布林 → 旁白（隐藏）→ 左侧主角内心 → 右侧哥布林大笑（单句覆盖）→ 显式隐藏。确认立绘无白底，约上半身露在对话框上方，下半身被面板遮住，不盖住正文或选项。每句用确认键补全文本，再按推进；Esc 中止后立绘消失。F5 的现有 Day 1 主角对白也会自动显示左侧立绘。

立绘回归包含在 `tests/verify_dialogue.gd`；有渲染运行时加 `-- --capture-portraits` 可将各句截图保存至 `user://dialogue-portrait-<行 ID>.png`。立绘布局依据 [Godot 4.7 TextureRect](https://docs.godotengine.org/en/4.7/classes/class_texturerect.html) 的 `EXPAND_IGNORE_SIZE` 和 `STRETCH_KEEP_ASPECT_CENTERED`，前后遮挡依据 [CanvasItem 的 z_index](https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html#class-canvasitem-property-z-index)，资源依赖依据 [preload](https://docs.godotengine.org/en/4.7/classes/class_@gdscript.html#class-gdscript-method-preload)。

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_dialogue.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_milk_tea_shop.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_game_state.gd
```

首次 checkout 需要先让 Godot 完成项目导入。对话测试覆盖 JSON 校验、字体字符覆盖、逐字效果、跳过、键盘推进/选择、按钮 dispatch、两个分支、空文本/直接结束选项、完成与取消信号、移除清理、独立试玩宿主及真实 MainGame 输入锁。加 `-- --capture` 需使用有渲染的非 headless 运行，截图输出到 `/private/tmp/dialogue-demo-welcome.png`、`dialogue-demo-choices.png`、`dialogue-choices.png`。

实现依据 Godot 4.7 官方文档：[InputEvent 的处理顺序与消费](https://docs.godotengine.org/en/4.7/tutorials/inputs/inputevent.html)、[RichTextLabel 的 visible_characters](https://docs.godotengine.org/en/4.7/classes/class_richtextlabel.html#class-richtextlabel-property-visible-characters)、[JSON](https://docs.godotengine.org/en/4.7/classes/class_json.html)、[导出资源过滤](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_projects.html#resource-options)。

本次新增 API 与导入素材已在 Godot 4.7.2 验证。官网文档站本次访问返回 403，因此实现前直接核对同版本的官方文档源文件：[TextureRect 4.7.2](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/TextureRect.xml)（替换 `texture`、等比居中与忽略图片最小尺寸）、[ResourceLoader 4.7.2](https://github.com/godotengine/godot/blob/4.7.2-stable/doc/classes/ResourceLoader.xml)（已导入资源加载及缓存复用）。
