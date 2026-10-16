# 自然语言剧情编排工作流

入口：提供 `docs/design/<name>.md`，说「编排这段剧情」；局部修改可说「将 Beat arrival 的走路速度改为每秒 80 像素」。Codex 按本流程完成源稿、JSON、必要场景配置、验证和 commit。自然语言理解和生成由 Codex 执行，无需独立编译器、插件或新的 runtime。

## 创作源与产物

| 文件 | 职责 |
| --- | --- |
| `docs/design/<name>.md` | 唯一剧情内容来源：对白、演出顺序、并行关系、时长、触发与状态意图 |
| `src/resources/dialogue/<name>.json` | DialogueLibrary v1 执行产物 |
| `src/resources/story/<name>.json` | StoryLibrary v1 执行产物 |
| `docs/story_authoring/<name>.json` | 生成的追踪/验证清单：源稿 SHA-256、场景、Beat 到步骤/对白映射、测试 cases；不供游戏加载 |
| `<name>.pending.md`（确有阻塞时，放在清单旁） | 原文位置、缺失信息/能力、受影响 Beat；解决后删除 |

源稿无需预先写 JSON 或掌握 ID。推荐 `## Beat <稳定的 snake_case ID>` 标题；普通 Markdown 也可编排，Codex 先按原有段落添加稳定标题，不改内容。可在开头说明宿主场景、何时触发、是否只播一次；已明确的绑定和实施参数写回源稿的「编排约定」，不得把剧情内容只保留在清单或脚本。设计背景和开发者秘密不会自动转换为玩家对白。

参见完整基准稿 [cinematic_opening.md](design/cinematic_opening.md) 与 [指令表](story_authoring_commands.md)。已有 `day_01_story_flow.md` 是包含玩法与未定地图的长篇设计，不是可直接无损执行的定稿；未获指示时不要将它整篇改写成 Demo 或补写人物对白。

## Codex 执行流程

1. 检查 Git，读本规范、目标源稿、[StoryDirector](story_director.md)，按需读实际 Loader / dispatch、宿主和关联资源；以代码为 Schema 真相。核对当前 Godot 4.7 官方相关 API。
2. 从原文提取 Beat、逐字对白/说话人/选项、动作依赖、显式停顿、并行、触发条件、成功状态。保持标点、换行、内心/台词区分；不把叙述改成新台词，不添加原文没有的门铃、表情或反应。
3. 在目标宿主及其注册代码中解析绑定。先精确 ID，再按名称/用途匹配唯一现有项。多个候选、身份不符的占位角色、未确认空间位置或关键声音必须列入 pending。跨场景同名不代表已注册，`speaker` 也不等于 Actor ID。
4. 位置/资源明确时完成必要配置：Marker2D 保存到所属场景，由共同宿主调用 `register_position`；现有角色用 `actor_register`，动态角色用 `actor_spawn`；音频用 AudioManager 的 `sounds` 或 `register_sound`。不得虚构坐标、复用人类占位角色冒充正式哥布林、生成临时音调冒充指定关键音效。确认过的占位资源可以复用并注明。
5. 依照指令表生成原有 v1 JSON。只在宿主做服务注入、注册、加载、启动和必要重播清理；所有剧情顺序在 Story JSON。正式启动事件必须接入真实触发调用；仅配置 `conditions` 不会自动开播。新增 debug 宿主与正式关卡分开，保持 Release 边界。
6. 更新清单和源稿 SHA-256，运行下方验证；每个事件、选项分支、正反条件和触发路由安排 case。缺失引用、音效 skipped、移动受阻/超时或执行失败均不能宣称验收通过。pending 涉及的事件保留上一份有效产物；新事件不要发布伪造的可播放版本，可先完成独立且已确认的其他事件。
7. 检查差异、仅提交本次文件，给出 Beat 变更、自动匹配/新增绑定、检查结果、待确认事项、F6 入口和 commit。不自动 push。

未指定动作参数时可用现有默认值，并在摘要注明；若会决定关键节奏或空间含义（如“沉默很久”“去门外”且没有对应 Marker），先列 pending。原稿不明确的触发点和剧情状态不能编造成既定设定。

## 顺序、并行与状态规则

- “然后/到达后”使用默认 Blocking；“同时”将先启动的动作设为 `wait: false`，再执行另一动作。每步按 process tick dispatch，并行不表示同一帧精确同步。对白始终 Blocking，不能添加 `wait: false`。
- 一个角色共用动作互斥槽。先移动完成再 face/emote/show/hide；不支持同角色边走边表情。镜头位置、缩放、震动可并行；同通道后发替换先发。无法表达的精确同步、join 或定时动作不得用猜测的 `wait.seconds` 伪装。
- 末尾收束未完角色/镜头动作；非阻塞音频不延长事件，收尾会停止本段声音。需要听完的有限 SFX 用 `wait: true`；循环 SFX 不能阻塞。BGM Blocking 只等淡变，不等循环音乐结束。
- `actor_move` 直线移动且有碰撞，不寻路。只使用已确认且可通行的 Marker 路线，需要拐弯时分段；不要只增大 timeout 掩盖受阻。
- `conditions` 在请求时检查，`when` 在步骤执行时检查；全部字段为 AND。没有 OR、else、goto、循环或命令式场景切换。`trigger` 是交互路由 ID，需宿主实际调用 `request_interaction`，JSON 顺序优先第一个合格事件；订单/仓库/制作台为 `orders`/`storage`/`tea_station`。
- `once` 默认 true，整段成功才记完成。重复演出显式 false；不同条件的路由要检查遮蔽和优先顺序。flag 和事件 ID 用命名空间；`set_stage` 字符串按原稿约定。成功标记置末尾；失败不回滚已执行状态和角色位置/生成/显隐，重试须核对现场。
- `when.choice` 只能消费本次演出已完成选择的稳定 ID；跨事件先写 flag。对白分支由 `next`/`choices` 表达，不按选项显示文本匹配。
- MainGame 统一锁输入；不得在新脚本重复锁定或强制恢复 true。超出已有指令的动画、场景切换、给予物品、任务/手札等真实业务能力列为缺口；不能用 `set_flag` 冒充已实现这些系统。

## 局部 Beat 修改

先更新用户指定源稿段落，再用清单 `beats` 找到事件的 `[start, start + count)`（零起始、右端不含）及 Dialogue ID。只替换该区间和被影响对白/必要绑定；后续 Beat 索引随长度偏移，ID 不变，不对整个 JSON 重排键/格式。共享对白被其他 Beat 引用时同时检查影响，必要时拆为新稳定 ID；事件依赖、状态或路由被改变时验证相邻 Beat 和消费者，但不改写其内容。不得把 Beat ID、注释、源路径塞进严格拒绝未知字段的 Story JSON。

已有 JSON 与源稿不一致时，先报告冲突，源稿控制内容，不能反向吞并手工改过的对白。重新生成须保证未受影响数据语义相同；首次接管旧剧情可像基准稿一样逐字转录，后续仅修改源稿。

## 验证与试玩

首次 checkout 先让 Godot 导入：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --editor --path . --quit
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/story/validate_story.gd -- res://docs/story_authoring/cinematic_opening.json
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_story_director.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_cinematic_integration.gd
python3 tests/verify_story_authoring.py
```

`validate_story.gd` 是离线验证工具：通过原 StoryLibrary/DialogueLibrary 校验，实例化真实宿主（关闭 autoplay），检查源稿散列/Beat 覆盖、所有步骤的引用和 `when.choice`，然后由原 StoryDirector 执行清单 cases，自动推进对白。不会解释演出命令或修改项目数据。音频引用在此严格检查，避免 runtime 的可选音频 fallback 隐藏遗漏。

宿主暴露 `autoplay`、`dialogue_file`、`story_file` 和 `get_story_authoring_game() -> MainGame`（公开组装接口，不访问 MainGame 内部路径）。清单文件格式见已提交示例：

- `version: 1`、`source`、`source_sha256`、`scene`、`story`、`dialogue`；均使用 `res://` 项目路径。
- `beats` 按源稿顺序：`id`、`event`、`start`、`count`、`dialogues`。每个事件的 steps 连续覆盖且不重叠；对白也必须有归属。
- `cases` 非空：`event` 或 `trigger`（二选一，trigger case 额外 `expected_event`）、可选 `state`（GameState snapshot 的覆盖项）、`choices`（`dialogue_id/line_id: choice_id`，有选项时必须显式指定）、`expected_skips`（默认空，下标须与实际一致）、`expect_flags`、`expect_stage`、`timeout`（默认 60 秒）、`reading_seconds`（默认 0.05）。`request_error` 默认 `OK`；反向准入 case 可用 `ERR_UNAUTHORIZED`、`ERR_ALREADY_EXISTS`、`ERR_DOES_NOT_EXIST` 或 `ERR_BUSY`，验证拒绝且没有启动。每个 case 使用新宿主与干净 GameState；跨事件存活角色等前置现场由宿主 fixture 明确配置，不能只填 flag 冒充。条件/选项路径不能以跑过一个 case 冒充完整覆盖，Codex 负责补齐场景相关 cases/已有测试。

自动推进只用于结构与执行检查，不证明阅读节奏和画面。F6 运行 `src/debug/cinematic/cinematic_demo.tscn`：手动读两段对白、观察顾客按门口→过道→柜台移动，听门铃与敲击、看震动、结束后确认 WASD/E 恢复；另测 Esc/取消与重播。新增剧情每次汇报对应的 F6 场景和原稿要求的可观察结果。

实现核对 Godot 4.7 官方文档：[JSON.parse 的错误诊断](https://docs.godotengine.org/en/4.7/classes/class_json.html)、[SceneTree 的帧信号与退出码](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html)、[Marker2D 位置标记](https://docs.godotengine.org/en/4.7/classes/class_marker2d.html)、[CharacterBody2D 碰撞移动](https://docs.godotengine.org/en/4.7/classes/class_characterbody2d.html)。Marker 的局部 position 不能当全局 target；注册后由原 Director 使用 global_position，移动仍由原角色物理逻辑处理。
