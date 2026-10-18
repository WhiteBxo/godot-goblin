# 游戏内剧情编排

F5 新游戏进入奶茶店，等开场结束后按 F3 →「编排」→「打开工程」。默认打开前两阶段的 `res://docs/story_authoring/day1_stages_01_02_project.json`。编排页展开为全宽，左侧选 Beat 与步骤，右侧编辑表单、步骤 JSON、对白或完整工程 JSON。

## 修改和保存

1. 选择 Beat，再选择步骤。表单可修改现有参数，角色、Marker、对白与音频提供工程绑定清单中的下拉选项。选择另一条指令会用该指令模板替换当前步骤的参数；应用前可用「撤销」放弃输入。复杂条件、坐标数组、选项、事件准入及新 Beat 用 JSON 视图编辑。
2. 点击「应用修改」将输入写入内存草稿。未应用的输入会阻止切换步骤、Beat、对白行和编辑视图，避免把内容写到错误对象。「添加停顿」「复制」「删除」「上移」「下移」操作当前 Beat 的步骤，稳定步骤 ID 随步骤保留。可在工程 JSON 中创建、删除和调整 Beat。
3. 对白页按 Dialogue ID 和行 ID 编辑说话人、文本、立绘；不会改写该行的 next / choices。更复杂的分支在工程 JSON 中修改。共享 Dialogue ID 的改动影响全部引用者。
4. 「撤销 / 重做」保留最近 50 次已应用修改；有未应用输入时，「撤销」先放弃输入。关闭 F3 面板保留草稿，退出宿主会丢失未保存修改。
5. 「校验」使用原 StoryLibrary / DialogueLibrary，检查步骤、对白、声明的绑定、Bridge v2 phase 和映射；不证明移动路线可达或节奏合适。
6. 「保存工程和产物」保存工程并生成原格式 Story、Dialogue、Bridge phase 和 Beat 清单。步骤区间与源散列自动维护；不回写 MD。现有游戏的演出和对白可在 F3 → 剧情 → 事件重新加载；phase 改动需要重启宿主。

保存只在带 editor 特性的 Godot Debug 开发环境开放。写入前取得工程保存锁，检查工程与每份输出的磁盘散列，外部有改动时拒绝保存并保留草稿。此时先复制「工程 JSON」保留修改，点击「放弃并重读」并再次点击确认，打开最新工程后合并。所有输出先写临时文件，再备份和替换；失败尝试恢复原文件。发现 `.story_editor_backup` 或遗留的 `.story_editor_lock` 目录时停止保存，需先确认无保存进程，再恢复备份、移走遗留文件；进程被强行结束不等同于多文件原子事务。

## 独立预览

「预览整段」使用已应用的草稿，不要求先保存。选择的 Beat 所属短事件在独立 Godot 进程中运行，原游戏的 GameState 与进度不变。窗口内正常推进对白，按 R 或「重演」从事件起点重建宿主；Esc 按现有对白逻辑取消。「停止预览」或原编排面板退出时结束该预览进程。

前两阶段已配置 opening、first_goblin、group_arrival、ending 四个预览现场。预览配置使用既有检查点的角色与 Marker，设置事件要求的 day / stage / 前置事件 / flags，停用自动开场和 Bridge 自动续播，然后执行真实 StoryDirector。预置事实只服务于演出预览，不代表真的完成订单或通过经济验收。预览成功、取消和错误都会显示在窗口顶部。

预览单位是整个短事件，不支持任意步骤跳转；不具备现场配置的事件明确拒绝预览。玩家操作 Beat 仍通过正式宿主测试。自定义宿主当前需要 MainGame 与已注册的 Actor、Marker、音频；独立窗口从磁盘加载场景，所以编辑器中尚未保存的场景修改不会进入预览。

## 正式内容来源

迁移后的项目以工程 JSON 为内容来源。前两阶段的 MD 保留为初稿和来源说明；清单的 source / source_sha256 记录最初导入的原稿，authoring_project / authoring_sha256 指向当前正式来源。不要直接修改派生的运行时 JSON 后再从旧工程保存，也不要用旧 MD 整篇生成覆盖手调结果。尚未迁移的剧情继续沿用原 Markdown 工作流。

工程字段：

| 字段 | 内容 |
| --- | --- |
| version / format | 1 / goblin_story_project |
| manifest | 原绑定信息、宿主、输出路径；manifest_path 是派生 Beat 清单路径 |
| events | 事件 ID → 原事件元数据，不包含 steps |
| beats | 顺序 Beat；演出 Beat 含 event 和 steps，每个步骤为稳定 id 与原命令 data；玩家 Beat 含 Bridge v2 phase |
| dialogues | 原 Dialogue v1 的 dialogues 字典 |
| next_step_id | 自动插入步骤的 ID 序列，不手工减小 |
| previews | 事件 ID → 预览现场；actors 配置角色 ID → marker / visible，可选 business_profile、bgm、flags |

JSON 视图与表单共用 `StoryProject` 模型。Codex 可以直接修改同一份工程，再使用下面的 CLI 校验或生成。运行时 Loader 与 StoryDirector 不加载工程文件；元数据不会进入严格的 Story v1 Schema。Bridge 编辑当前支持 v2，实际制作、任务、交付、奖励规则继续由原业务模块负责。

## 命令行

在仓库根目录执行，将 godot 替换为本机 Godot 4.7 可执行文件：

```sh
# 快速检查工程结构及产物一致性
godot --headless --path . --script res://tools/story/edit_story_project.gd -- res://docs/story_authoring/day1_stages_01_02_project.json
# 工程已修改时生成全部派生产物
godot --headless --path . --script res://tools/story/edit_story_project.gd -- res://docs/story_authoring/day1_stages_01_02_project.json --save
# 只执行目标事件的预览，自动推进对白，不替代玩法与画面验收
godot --headless --path . --script res://src/debug/developer_tools/story_preview_runner.gd -- res://docs/story_authoring/day1_stages_01_02_project.json day1.first_goblin --auto
# 不带 --headless 和 --auto 时可手动观察、选择和重演
# 一次性导入旧清单；目前玩家 Beat 需 Bridge v2，预览现场另行配置
godot --headless --path . --script res://tools/story/edit_story_project.gd -- --import res://docs/story_authoring/example.json res://docs/story_authoring/example_project.json
```

自动预览不代选 choices，含选择的事件应手动预览；超时或取消都返回失败。结构 / 编辑 / 保存与冲突保护由 `tests/verify_story_editor.gd` 检查；现有 Console 与 Debug 边界分别沿用其模块测试，真实五单结算仍由 `tests/verify_day1_stages_01_02.gd` 验证。根据改动风险选择检查，不默认运行全项目测试。

实现依据：[Godot 4.7 OptionButton](https://docs.godotengine.org/en/4.7/classes/class_optionbutton.html)、[ItemList](https://docs.godotengine.org/en/4.7/classes/class_itemlist.html)、[DirAccess](https://docs.godotengine.org/en/4.7/classes/class_diraccess.html)。OptionButton 的程序 select 不会发出用户 item_selected，视图刷新与用户编辑显式分开；文件替换检查 rename 的返回值。

## 验证记录

2026-10-18，Godot 4.7.2：编辑器 44 项、Console 152 项、Debug 边界 97 项、正式 Day 1 五单流程 225 项均通过；工程及派生产物一致性检查通过。四个独立演出预览均成功，开场另做图形窗口和连续两次重建重演检查；D3D12 图形窗口截图检查了编排页与实景预览。Console 测试中的 engine / warning probe 是预期日志夹具。未做人工听音、全部分支试玩或真实 Release 导出。
