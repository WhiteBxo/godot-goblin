# 昼夜、日期与章节准入

核对日期：2026-10-18。`src/core/schedule/day_phase.gd` 是无节点的昼夜迁移工具，GameState 保存事实；Day1Access 读取章节与业务条件；Day1WorldController 把结果投影到出口、角色和地图。不自动流逝时间，也没有期限或任务超时结算。

## 昼夜接口

| API | 行为 |
| --- | --- |
| `DayPhase.get_phase(state)` | 返回 day / night；变量缺省时由夜晚 flag 推断，未知非空值拒绝迁移 |
| `DayPhase.is_night(state)` | 统一夜晚查询 |
| `DayPhase.enter_night(state)` | 仅 day → night 成功，重复返回 false |
| `DayPhase.enter_day(state)` | 仅 night → day 成功，并将 current_day 加一；重复不推进 |

持久真相为变量 `world.phase`，镜像 flag 为 `world.phase.night`；经 `GameState.commit_day_phase()` 同次提交，通知后观察者读到一致结果。正式写入使用 DayPhase，Story 的 `set_phase` 也走此接口，不单独写镜像键。状态在现有完整快照内保存，不另设日程存档。

## Day 1 准入

`Day1Access.at_stage()` 接受章节本身及其点号子阶段。tutorial 不受正式出店限制；day1 使用以下规则：

| 场景 / 能力 | 准入 |
| --- | --- |
| 出店探索 | day1.investigate_coins 或 day1.s03 及其子阶段 |
| S05 出店 / 长老宅门洞 | day1.s05、委托接受事实和夜间同时成立 |
| S01 / S02、S04、S06、未知阶段及 day2.* 出店 | 拒绝 |
| S06 血液特调 | day1.s06 及子阶段，并已取得血液、真实返店；制作还需实际库存 |

这些条件只表达已实现的业务门禁。后四阶段正式事件数据为空，不能靠改阶段认定已经完成探索、支付、撤离或章末。夜间 S05 已接受委托时，Day1WorldController 经 DayPhase 建立夜晚；章节结束能力中的 `set_phase day` 可推进次日，但当前没有正式章末事件调用它。

聚落夜景与 NPC `active_phase` 使用同一日程事实。采集点沿用 `world.phase.night` gate，daily 刷新读取 current_day。Debug F4 经 DayPhase 切换，Release 不提供该按键。见[世界流程](../gameplay/day_01_world_flow.md)与[采集](../gameplay/gathering.md)。

## 检查入口

候选模块检查为 `tests/verify_day_phase.gd`、`verify_day1_world_flow.gd` 与 `verify_day1_chapter_systems.gd`；按[验证分级](../../tests/AGENTS.md)选受影响项。F6 `src/debug/story/day1_world_flow_demo.tscn` 可观察夜景、门洞与返店业务；它准备的是隔离验收进度。本轮文档更新未运行这些检查。
