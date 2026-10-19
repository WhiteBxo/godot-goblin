# 安全检查点存档

存档复用唯一 GameState 的完整原生 Variant 快照，不新增 autoload 或独立经营状态。F5 新游戏建立初始检查点；标题可继续最近安全检查点。成功保存以右下角约 2.5 秒的短暂提示反馈，最近保存时间常驻在右上菜单与暂停菜单；失败提示保持可见。首版仅有单槽自动保存和一份有效备份。

## 文件层

`SaveStore` 默认使用 `user://saves/autosave.dat`，上一份有效文件为 `autosave.bak`。构造函数可注入独立目录及 `SaveCheckpoints`，测试不得读写玩家正式目录。

- `save(snapshot, checkpoint_id, saved_at = -1) -> Error`：校验完整快照及配置检查点，写临时文件并回读，备份有效旧档后替换正式档。损坏的正式档不会覆盖有效备份。
- `load_save(preflight: Callable = Callable()) -> Dictionary`：返回 `error`、`data`、`used_backup`；正式档失败后检查备份。可选预检检查目标资源与现场恢复能力，预检失败也尝试备份。失败不修改 GameState，不自动删除或修复文件。
- `validate_document(value) -> Error`、`has_files()` 和 `last_error`：用于入口预检与显示错误。
- GameState 的 `validate_snapshot(data) -> Error` 校验现有迁移及完整格式，不提交事实或通知；`can_take_snapshot() -> bool` 在同步事务/恢复通知期间返回 false。

文件包含 magic、SHA-256 和 Variant 二进制正文。正文为 `format_version`、`game_state`、`checkpoint_id`、`saved_at`；文件格式版本与 GameState schema 分别演进。读取限制为 16 MiB，使用不解码对象的 `bytes_to_var`。校验用于检测文件损坏，不是加密或防作弊。

每次写入检查创建目录、写入、flush、关闭后的回读、备份复制与重命名。失败保留原有有效档；临时文件不被当作已成功提交的存档。不承诺重命名或 flush 能抵御所有断电情况。

## 检查点配置

`src/resources/persistence/checkpoints.json` 是独立于剧情编排产物的配置。每项包含稳定 `id`、宿主 `scene`、出生入口 `entrance`、精确 `stage` / `day` / `phase`、前后事件边界 `after_event` / `before_event`、`required_flags` 和 `recovery`（opening / shop / chapter）。不存节点路径或逐帧位置。

最初六个 Day 1 白天检查点仍保留：

| ID | 恢复阶段与现场 |
| --- | --- |
| `day1.initial.shop` | 空阶段，店内开场前；完成初始化后才启动开场 |
| `day1.wait_human.shop` | `day1.wait_human`，人类顾客制作 / 交付等待 |
| `day1.wait_goblin.shop` | `day1.wait_goblin`，哥布林顾客制作 / 交付等待 |
| `day1.wait_group.shop` | `day1.wait_group`，顾客组制作 / 交付等待 |
| `day1.investigate.shop` | `day1.investigate_coins`，店内街门入口 |
| `day1.investigate.settlement` | `day1.investigate_coins`，聚落店门入口 |

未知阶段不保存，保留上一检查点。完整快照中的日期、昼夜和镜像 flag 必须一致。现已增加 S03 调查、S04 订单／地图、S05 尝试前、S06 特调，以及 Day 2 营业、酒馆、赌场、守卫和 Day 3 交接／Day 4 超时检查点。完整 schema 为 8／6／3。`verify_two_day_persistence.py` 从真实流程复制 20 个自动存档，各由独立新进程恢复。

新增阶段必须同时声明检查点、章节 `scene_setups`、目标宿主 / 出生入口，并补跨进程验收。`Day1ChapterController.preflight_recovery()` 拒绝没有现场配置的新阶段；已发布的金币调查交接允许空角色现场。检查点恢复复用前两阶段的角色、音乐与 Bridge 投影。

## 安全保存与恢复生命周期

`SaveCoordinator` 是 MainGame 创建的场景内节点。`state_changed` 只标记待保存；连续两个安全帧后生成完整快照，合并重复变化，同一快照不反复写入。只在经 GameEntry 新游戏 / 继续游戏开启的存档会话中运行；新进程直接 F6 不写正式档。

允许 Bridge 等待玩家制作 / 交付，不复用“允许出门”的守卫。事务、暂停、模态、对白、演出、标题卡、角色受演出控制、场景切换及潜入运行 / 失败 / 拦截期间不保存。顾客进店／离店尚在移动时也等待稳定边界。事件取消或失败会阻止保存，直至完成恢复投影或后续有效事件。未完成的整次潜入保留尝试前完整检查点，包含尝试前的库存。退出不强行刷新中间态。

`GameEntry.continue_game(tree)` 先校验文件、完整快照、检查点与离树目标，再调用唯一 GameState 的 `restore_state()`。MainGame 暂停自动事件和 Bridge 推进，重建角色、交互与阶段；`session_initialized(error)` 成功后才释放导航和输入锁。恢复放置使用 `prepare_scene_arrival(id, false)`，不会发布真实返店事实。启动失败回滚内存并返回标题，磁盘文件保留。

`scene_changed` 只表示 Godot 已完成场景初始化；项目自己的现场准备还需等待上述信号。启动等待不计入暂停帧。正常场景旅行在目标完成初始化、落点与转场后才保存。

标题仅在完整预检成功时显示并默认聚焦“继续游戏”；坏正式档可回退备份并显示提示。已有文件时新游戏要求确认，新快照通过临时文件校验后才替换旧档。保存失败显示提示、保留旧档并延迟重试，不阻止玩家继续操作。HUD / 暂停时间指最近成功保存；继续游戏来自备份时显示备份时间。

## 验证

所有存档测试使用独立目录，不读写玩家正式档：

- `tests/verify_save_store.gd`：原生类型、完整校验、已有版本迁移、备份与目标资源预检回退、未知版本 / 检查点、写入 / 替换失败和双档损坏。
- `tests/verify_save_game.gd`：真实标题 / 店铺 / 聚落、Bridge 操作阶段、暂停反馈、覆盖确认、恢复落点与真实抵达区分、潜入保护、坏档；另启四个引擎进程依次制作、恢复、交付、恢复，检查完整快照及奖励去重。`-- --capture` 保存界面截图至 `.godot/verification/save_system/screenshots/`。
- `tests/verify_save_boundaries.gd`：独立跨天 / 昼夜夹具，成功、失败、超时任务终态及资源整体保存，独立进程恢复、重复恢复、暂停启动与写入错误反馈。
- `tests/fixtures/save_export_probe.gd` / `.tscn`：隔离 Release 验收主场景，检查真实 release feature、开发工具禁用、导出资源、初始存档、标题继续、完整恢复与输入解锁；不随正式包发布。

2026-10-18，Godot 4.7.2：文件层 25 项、边界 18 项、OpenGL 图形集成 45 项通过，已检查继续游戏、覆盖确认与暂停截图。已有入口 66 项、GameState 126 项通过。完整相关回归初跑 61 个脚本中 52 个通过；标题音乐计时检查先排空引擎首帧加载时间后 25 项通过，其余 8 个失败均在 `05429c3` 隔离基线复现：`verify_cinematic_integration`、`verify_day1_stages_01_02`、`verify_dialogue`、`verify_disappeared_street`、`verify_floor_atlas`、`verify_gathering`、`verify_shop_equipment`、`verify_walls`。剧情编排 Python 检查也在基线复现开场路径受阻。未重跑依赖特定编辑器 / 图形宿主的 `verify_cave_editor`、`verify_player_visuals`。

已导出 PCK 并在资源根目录之外的独立工作目录验证导出检查点资源、新游戏保存、标题继续与完整恢复。另安装 Godot 4.7.2 官方 Windows Release 模板，导出正式 `pack_run/godot_goblin.exe` 并验证正常启动；隔离 Release 验收包通过 13 项存档检查，退出码为 0。Release 使用 headless 验证，界面截图来自前述 OpenGL 源工程验证。

标准 Release 模板禁用外部 `--script` 和场景路径覆盖，因此验收包从 `e515b64` 制作临时工程：保持运行时 `src/`、资源、autoload 与导出排除规则，复制上述夹具到 `probe/`，仅替换该临时工程的主场景后导出。不向正式入口加入测试开关。复现时按此方式使用待验提交，并在独立目录运行该 Release 可执行文件；应输出 `SAVE_EXPORT: PASS`。正式工程仍以标题为入口，`tests/*` 继续排除。

部分引擎退出仍有基线同样出现的 ObjectDB / Resource 泄漏诊断。日志、PCK、Release 包、截图与隔离基线保留在忽略目录 `.godot/verification/save_system/`，不提交；其中基线和验收临时工程有素材 / 导入目录的 junction，清理时避免递归进入链接目标。

试玩：F5 → 新游戏 → 完成开场并制作 → 右下角出现短暂“最近保存”提示 → 关闭进程 → 再 F5 → 继续游戏。应回到玩家操作检查点，保留库存、成品、钱包与任务事实。演出或潜入中退出应恢复最近安全检查点。

## Godot 4.7 依据

- [FileAccess](https://docs.godotengine.org/en/4.7/classes/class_fileaccess.html)：文件错误、flush 与显式关闭。
- [DirAccess](https://docs.godotengine.org/en/4.7/classes/class_diraccess.html)：复制、重命名及错误返回。
- [二进制序列化](https://docs.godotengine.org/en/4.7/tutorials/io/binary_serialization_api.html)：保留原生 Variant 数值类型。
- [SceneTree](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html)：scene_changed 发生在目标场景初始化之后。
