# Day 1 世界门控、调查与血液特调

本页描述当前业务接入，剧情来源仍按 [对接约定](../design/day_01_integration_contract.md) 和 [待定清单](../story_authoring/day_01_integration_pending.md)。后四阶段的正式对白、探索结束、守卫支付、潜行、撤离及异常演出尚待编排；这里提供可独立验证的业务能力，不将切阶段视为剧情完成。

## 阶段与场景

- Day1Access 读取 GameState.story_stage，章节阶段允许点号分隔的操作子阶段。正式 Day 1 的 S01/S02 不能出店；已发布前两阶段末尾的 day1.investigate_coins 和 day1.s03 允许探索；day1.s05 还要求委托接受和夜间。S04、S06 以及未知阶段不开放出店。教学配置沿用原通行规则。
- 聚落沿用一张地图。白天显示普通哥布林、守卫队长、长老、厨师；夜晚显示酒馆和赌场角色。胖哥布林及入口守卫保留常驻配置。隐藏角色同时退出 NPC 物理层，关联交互点停用。
- 长老宅门洞在地图保存 StoryGate 碰撞，Day 1 仅 S05、委托接受和夜间同时满足时放行。该门只表达章节准入；醉酒守卫的调查点不伪造贿赂、支付或潜行成功。
- 正式委托已接受并进入 S05 时，由 Day1WorldController 经 DayPhase 建立一次夜间边界。DayPhase 原子写 world.phase 和 world.phase.night；夜转昼同时将 current_day 加一，重复调用不重复推进。调试预览使用同一接口。
- 只有实际进入奶茶店 street_door 入口，且处于 S05/S06 并已有真实取血事实，才写 day1.s05.returned_shop。该事实不代表尚未实现的 escape_completed。重建店铺不再把后续阶段投影回 S02 检查点。

## 调查与拾取

StoryInteractionPoint 保存 entry_id、interaction_id、类型、阶段、前置 flag、物品数量和 success_flags。MainGame 注册真实点位 ID，并经唯一 ShopInteraction 分发；组件不抢先消费 interacted 信号。

| 点位 | 提交时点 | 业务结果 |
| --- | --- | --- |
| day1_elder_document | 实际展示内容并关闭面板 | day1.s05.document_read，可重读但只首次发 resolved |
| day1_blood_storage | 取物成功 | day1_griffin_blood × 1 与 day1.s05.blood_acquired |
| drunken_guard | 查看并关闭面板 | 只记调查回执，不扣款、不开放额外权限 |

三个点均要求 S05、world.phase.night 和 day1.s04.commission_accepted。文书与拾血互相独立，不额外规定先读文书才能取血。

GameState.commit_story_interaction 在同一事务内提交真实库存、success_flags 和 story.<entry_id>.resolved。无效物品、容量不足或会话锁定不写成功事实；重试、同步回调重入、场景重建和快照恢复均不会重复发物。点位是否消失从持久回执读取，不保留一份不可恢复的本地完成状态。

教学与 Day 1 共用包含血液的完整物品目录；配方是否可用由会话事实与阶段决定。钱包、库存和制作服务继续复用原对象，跨配置快照恢复时整体替换数据后才通知。

## S06 制作与交付

血液配方沿用已提交的四种材料：day1_griffin_blood、black_tea、creamer、syrup。配方资源同时要求：

1. day1.s05.blood_acquired 为真；
2. day1.s05.returned_shop 为真；
3. 当前为 day1.s06 或其操作子阶段。

未解锁时，配方及专属材料不进入制作菜单；直接调用制作同样拒绝。解锁并不等于库存充足，制作仍校验并实际消耗材料，成品为 day1_blood_milk_tea。

Day1WorldController 投影 day1.s06.blood_drink_available，激活专用任务 day1.s06.blood_drink 和订单 day1_s06_blood_drink。玩家接单后向实际胖哥布林交付一杯特调，TaskDelivery 消耗成品并原子写 day1.s06.blood_drink_delivered 与交付回执。错人、缺成品、重复交付均不完成；不增加未经确认的报酬或饮用异常效果。

## 验证与试玩

Godot 4.7.2 的 tests/verify_day1_world_flow.gd 使用真实聚落与店铺宿主，覆盖阶段与门洞、昼夜显隐碰撞、文书关闭、取血、实际切场景返店、S06 制作及指定对象交付。组件原子性与重入另见 verify_story_interaction.gd，配方门禁见 verify_tea_recipes.gd，日程见 verify_day_phase.gd。

人工观察可 F6 运行 src/debug/story/day1_world_flow_demo.tscn。该专用 Debug 入口重置会话并准备已接受委托的 S05，随后由正式宿主建立夜晚，可观察夜景及长老宅准入；到 elder_document / elder_blood_storage 锚点交互，取血后走奶茶店入口返店。该 Debug 入口在真实返店后自动设置 day1.s06.wait_blood_drink，打开订单板接取特调订单、在制作台制作、交给胖哥布林。这里只用于独立业务验收，正式 S03–S06 自动剧情尚未发布。

本次没有修改源稿对白或生成新的剧情 Beat。原待定清单中的内容与表现决策继续保留。

## 本次验证记录（2026-10-17）

使用 Godot 4.7.2。43 项检查通过，包括真实宿主 world flow、调查原子性、配方门禁、DayPhase、GameState、共享经营会话、SceneTravel、TaskDelivery、WalletTransactions、角色、聚落及既有 S01–S02。

- 历史失败：verify_cinematic_integration.gd 的 6 项断言，以及 verify_story_authoring.py 的 cinematic.opening/steps[9] 移动受阻；在 fbf6f72 隔离基线并叠加接手前的工作区配置后复现。
- 历史失败：verify_floor_atlas.gd、verify_walls.gd 把当前店铺地图强转 CaveMap，报相同类型错误；隔离基线复现。
- 不适用 headless 命令行：verify_cave_editor.gd 继承 EditorScript；verify_player_visuals.gd 依赖实际渲染的 frame_post_draw，此运行方式下超时。未将这两项计为通过。
- 导入无脚本解析错误；编辑器退出仍报告 10 个资源在用，基线也有相同诊断。未执行人工画面验收，提供上述 F6 入口供观察。

本次核对 [Godot 4.7 Object 信号连接](https://docs.godotengine.org/en/4.7/classes/class_object.html) 的同步/延迟通知约定，以及 [CollisionObject2D](https://docs.godotengine.org/en/4.7/classes/class_collisionobject2d.html) 的物理层开关接口。库存与回执在同步通知前整体提交；门洞及隐藏角色通过物理层控制实际碰撞。
