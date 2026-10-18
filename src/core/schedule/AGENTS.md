# 日程与阶段

白天 / 夜晚阶段的最小状态机。GameState 只存事实，本模块只负责读取与合法迁移，不含对白、演出和任务判定。

## 状态键

阶段全部落在 GameState 的 variables / flags，不新增字段，不升快照 schema。

| 键 | 类型 | 语义 |
| --- | --- | --- |
| `world.phase` | variable，`"day"` / `"night"` | 阶段真相，随会话与快照持久化 |
| `world.phase.night` | flag，bool | 同一事实的镜像，供采集点 `required_flag`、剧情判定与 Debug 读取 |

- 变量缺失时以 `world.phase.night` 推断，兼容只写 flag 的调试会话与既有剧情数据。
- 变量存在未知值时 `get_phase` 返回空字符串，所有迁移一律拒绝，由数据侧修正，不做猜测。
- 两个键始终由 DayPhase 经 `GameState.commit_day_phase` 原子写，读取方不要各取一个再自行比较。

## 唯一写入者

正式流程通过 `DayPhase.advance_to(state, day, phase)` 或兼容的 `DayPhase.enter_night()` / `DayPhase.enter_day()` 写这两个键。剧情、UI、Debug 需要切换阶段时调用它们，不要直接 `set_variable("world.phase")` 或 `set_flag("world.phase.night")`。

允许读取方：`SceneExit.are_conditions_met`（经 GameState 读 flag）、`GatherPoint` 的 `required_flag`、地图夜景覆盖层、任务截止判定。

## 迁移表

| 当前阶段 | 调用 | 结果 |
| --- | --- | --- |
| day | `enter_night` | 写入 night 与 flag=true，返回 true |
| night | `enter_day` | 写入 day 与 flag=false，返回 true |
| day | `enter_day` | 拒绝，状态不变，返回 false |
| night | `enter_night` | 拒绝，状态不变，返回 false |
| 未知值 | 任意 | 拒绝，状态不变，返回 false |

## 表现与门控

- 聚落夜景由 `SettlementMap` 在 `_ready` 实例化 `src/levels/settlement/night_overlay.tscn`（CanvasLayer，layer 5，低于 HudLayer 的 10），绑定 `DayPhase.is_night` 并监听 `state_changed`；地图场景不保存该节点。
- 出店等条件门控用 `SceneExit.required_flags`：数组为空即无门控，缺任一 flag 时 `SceneTravel.request_exit` 返回 `ERR_UNAVAILABLE` 并发出 `travel_failed`，不进入切换流程。

夜转昼会在同一次提交中将 `current_day` 加一；重复切换不推进日期。按天数与昼夜的截止比较、绝对目标推进和任务结果的接入契约见 [日程与任务结果](../../../docs/systems/schedule_and_task_results.md)；期限必须显式指定 at/after，不由本模块决定关店条件。正式 S05 接受委托后的夜间边界由 Day1WorldController 调用 DayPhase 建立。

`Day1Access` 读取章节/操作阶段与真实业务事实，提供出店、长老宅和 S06 配方准入；地图物理门洞与昼夜 NPC 投影由宿主注入后协调。完整接入与待定内容边界见 [Day 1 世界流程](../../../docs/gameplay/day_01_world_flow.md)。

候选验证：`tests/verify_day_phase.gd`；改动门控或夜景后补对应宿主的最小观察。
