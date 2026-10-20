# 第一天第二次来客改成三只哥布林（2026-10-20）

## 问题

第一天共五波哥布林顾客，第二次（赌徒哥布林点草莓奶绿）的对白写的是四个哥布林在聊天
（赌徒、说教的、爱收集的、胆小的），但场景里只 `actor_show` 了 `goblin_a` 一只。
台词照念，画面只有一个人，明显对不上。

## 原因

编排只给了单客模板：`door → aisle → counter` 一个人走完就说话。
场景里其实早就摆好了三个并列站位锚点 `day1_group_a/b/c`（760/850/940, y=550），
第二天节日客组也在用它们，但第一天这条 beat 没接。

## 改法

真实源稿 `docs/story_authoring/day1_stages_01_02_project.json` 里改两个 beat，再用
`tools/story/edit_story_project.gd -- --save` 重新生成运行时产物。改源稿的脚本是
`tools/story/apply_group_customers.py`（幂等，可重跑）。

### 1. `goblin_group_customers`（事件 `day1.group_arrival`）

三只同时 `actor_show`，各自直线走到站位后转身朝柜台：

| 演员 | 身份 | 站位 |
| --- | --- | --- |
| `goblin_a` | 赌徒哥布林（点单者） | `day1_group_b`（柜台正中 850） |
| `goblin_b` | 说教的哥布林 | `day1_group_c`（右 940） |
| `goblin_c` | 爱收集的哥布林 | `day1_group_a`（左 760） |

- 三条路线大致平行（左/中/右），可以同时起步而不互相挤。`actor_move` 的 `wait` 只给最靠里的那只，
  用它的到达当同步点，不写死秒数。
- **不要**让它们先挤到 `day1_aisle` 再分岔：三只同时走同一条窄过道会互相阻挡，
  实测报 `Move blocked or timed out`。

### 2. `customer_c_arrives`（事件 `day1.customer_c`）

交付完赌徒的单之后：赌徒、说教的**先后**沿 `door ↔ aisle` 那条已验证可走的路离开，
爱收集的留在原地走上前一步（`day1_group_a → day1_counter`，84px），接着说出他那一单的台词。
原来这里是「上一只走光、新一只再从门口走进来」，现在改成群客里的第三位直接留下来点单，
不用再演一遍进门。

离开动画只有这一条路线是安全的：给 `goblin_b` 另编坐标（如 `[1160, 600]`）会被判阻挡。

### 3. 对白

`day1.goblin_group_customers` 的 `line_5`（「老板，这个草莓奶绿是什么？给我来一杯！」）
说话人从「胆小的哥布林」改成「赌徒哥布林」：订单 `day1.order_group_a` 的交付目标是
`goblin_a`，点单者必须和交付对象是同一只。胆小的哥布林是第一位顾客，已在上一场离开。

### 4. 场景与存档

- `src/core/main.tscn`：`GoblinA/B/C` 的初始位置从同一个门口点改成门口并排三点
  （x 分别为 1403.75 / 1459.75 / 1347.75，间距 56px，大于 54px 的角色宽度），
  `actor_show` 之后不会先叠成一只再裂开。
- `src/resources/story/day1_stages_01_02_setup.json`：`day1.wait_group` 检查点的 actors
  改为 `{goblin_a: day1_group_b, goblin_b: day1_group_c, goblin_c: day1_group_a}`。
  读档恢复靠这份表决定谁可见、站在哪，漏改会导致读档后只剩一个人。

## 立绘

五个哥布林顾客说话人（赌徒 / 说教的 / 爱收集的 / 领工钱的 / 倒霉的）、跑腿的哥布林，
以及第一场里的泛称「哥布林」，在 `DialogueManager.speaker_portraits` 里补上了绑定，
统一指向 `common_goblin_portrait.png`——现有素材只有这一张普通哥布林立绘。
等作者补画独立立绘后改对应键即可，剧情数据不用动。

## 验证

| 测试 | 结果 |
| --- | --- |
| `verify_two_day_flow` | 379 项 0 失败（改动前 379 项 0 失败） |
| `verify_day1_stages_01_02` | 16 项失败，与改动前逐条一致（基线对照跑过 stash 前后各一次） |
| `verify_two_day_persistence` | 33 个检查点 0 失败 |
| 画面 | `.godot/day1_group_wait.png`：三只并排站在柜台前，任务提示仍是「草莓奶绿 → 赌徒哥布林」 |

`tests/verify_two_day_flow.gd` 里「Only the current customer occupies the shop」
改为按阶段给期望值（第二次来客 3 位，其余 1 位）：这条断言写的是旧的逐位接待，
和本需求冲突。

## 已知取舍

- `day1.order_group_b`（说教的哥布林的订单）仍未发布，他在这段里只是陪聊。要给他单子
  得同时改营业计划与交付流程，属于新需求，不在本次范围。
- `verify_day1_stages_01_02` 的既有失败里有 `Actual reach and focus select goblin_b`：
  该测试按「三只各交付一杯」的旧设计写（`shop.orders_completed == 5`），
  与当前五位逐位接待的产物不一致，仍待判定。
