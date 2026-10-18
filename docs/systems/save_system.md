# 安全检查点存档

存档复用唯一 GameState 的完整原生 Variant 快照，不新增 autoload 或独立经营状态。文件层已提供单槽位、有效备份、版本与校验；入口及安全边界的接入见后续章节。

## 文件层

`SaveStore` 默认使用 `user://saves/autosave.dat`，上一份有效文件为 `autosave.bak`。构造函数可注入独立目录及 `SaveCheckpoints`，测试不得读写玩家正式目录。

- `save(snapshot, checkpoint_id, saved_at = -1) -> Error`：校验完整快照及配置检查点，写临时文件并回读，备份有效旧档后替换正式档。损坏的正式档不会覆盖有效备份。
- `load_save() -> Dictionary`：返回 `error`、`data`、`used_backup`；正式档失败后检查备份。失败不修改 GameState，不自动删除或修复文件。
- `validate_document(value) -> Error`、`has_files()` 和 `last_error`：用于入口预检与显示错误。
- GameState 的 `validate_snapshot(data) -> Error` 校验现有迁移及完整格式，不提交事实或通知；`can_take_snapshot() -> bool` 在同步事务/恢复通知期间返回 false。

文件包含 magic、SHA-256 和 Variant 二进制正文。正文为 `format_version`、`game_state`、`checkpoint_id`、`saved_at`；文件格式版本与 GameState schema 分别演进。读取限制为 16 MiB，使用不解码对象的 `bytes_to_var`。校验用于检测文件损坏，不是加密或防作弊。

每次写入检查创建目录、写入、flush、关闭后的回读、备份复制与重命名。失败保留原有有效档；临时文件不被当作已成功提交的存档。不承诺重命名或 flush 能抵御所有断电情况。

## 检查点配置

`src/resources/persistence/checkpoints.json` 是独立于剧情编排产物的配置。每项包含稳定 `id`、宿主 `scene`、出生入口 `entrance`、精确 `stage`、前后事件边界 `after_event` / `before_event`、`required_flags` 和 `recovery`（opening / shop / chapter）。不存节点路径或逐帧位置。

首批声明 Day 1 开场、三段经营操作，以及金币调查阶段的店铺/聚落落点。未知阶段不保存。完整快照中的日期、昼夜和镜像 flag 必须一致。后续阶段必须连同恢复现场与跨进程验收一起发布，不能只增加一个 stage 字符串。

## 验证

`tests/verify_save_store.gd` 使用独立目录，覆盖原生类型、完整校验、已有快照迁移、备份回退、未知版本/检查点、写入失败、替换失败及双档损坏。实际测试记录与入口恢复验证随集成完成更新。

## Godot 4.7 依据

- [FileAccess](https://docs.godotengine.org/en/4.7/classes/class_fileaccess.html)：文件错误、flush 与显式关闭。
- [DirAccess](https://docs.godotengine.org/en/4.7/classes/class_diraccess.html)：复制、重命名及错误返回。
- [二进制序列化](https://docs.godotengine.org/en/4.7/tutorials/io/binary_serialization_api.html)：保留原生 Variant 数值类型。
- [SceneTree](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html)：scene_changed 发生在目标场景初始化之后。
