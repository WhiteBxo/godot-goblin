# Day 1 世界门控、调查与血液特调

本页描述当前业务接入，剧情来源仍按 [对接约定](../design/day_01_integration_contract.md) 和 [待定清单](../story_authoring/day_01_integration_pending.md)。后四阶段的正式对白、探索结束、守卫支付、潜行、撤离及异常演出尚待编排；这里提供可独立验证的业务能力，不将切阶段视为剧情完成。

2026-10-18 补充：[投掷与守卫反应组件](day_01_stealth.md)已实现，聚落宿主已装配服务及缺口提示；火把、四名守卫绑定、支付与正式撤离配置未齐，S05 潜入仍未启用。原有调查/返店能力不代表潜入通关。

## S03–S06 剧情宿主与收尾能力（2026-10-18）

本节只提供接入能力，没有编写任何 S03–S06 对白或 Beat。地图完成后，地图侧摆放 Marker、触发区、调查点并配置守卫，剧情侧填写下列数据文件，两边都不需要再改代码。

**数据入口**：`src/resources/story/day1_stages_03_06_setup.json`，当前是空骨架。

| 字段 | 内容 |
| --- | --- |
| `story` / `dialogue` / `phases` | S03–S06 的 Story v1、Dialogue v1、Bridge v2 文件，当前均为空骨架 |
| `auto_events` | 按顺序列出的事件 ID。宿主空闲时（无切场景、暂停、弹窗、演出或对白），请求第一个条件满足且未完成的事件；准入被拒绝时等下一次状态变化再试；执行失败或取消后停止自动重试，须显式请求该事件或重建会话 |
| `derived_facts` | `{flag, stage, all_flags}`：处于 `stage`（含子阶段）且 `all_flags` 全部为真时写一次 `flag`。用于 S03 观察点看完后写 `day1.s03.exploration_completed`，再由 Bridge v2 续播 |
| `scene_setups` | `{host: shop/settlement, stage, actors: {actor_id: Marker 名或 null}}`：进入该 stage 或重建场景时，把角色传送到 Marker 并显示，`null` 表示隐藏。列出的角色不再受昼夜和 S06 默认可见规则影响 |

**任务**：Day 1 任务目录由 `day1_stages_01_02.json` 与 `day1_stages_03_06.json` 合并加载（`TaskCatalog.load_files`），两份文件中的任务与订单 ID 必须全局唯一。S04 胖哥布林订单沿用 S06 的写法：任务带 `delivery`，用 flag 揭示和激活。同一 NPC 同时有多个订单时，交付优先针对当前 active 订单。

**宿主分工**：
- `Day1ChapterController` 在聚落中总是接管；在奶茶店中从 `day1.investigate_coins`（S02 结尾）起接管，或阶段以 `day2.` 开头时接管。S01–S02 仍由 `Day1ShopController` 负责，交接后不再按检查点回拉阶段。前段演出仍 busy 时等待 `event_finished` 后加载，不在同一帧反复延迟调用。
- 聚落宿主额外注册完整的 `sound_library.tres`。

**走进即触发**：在关卡任意位置放置 `src/gameplay/story_interaction/story_trigger_zone.tscn`，填 `trigger_id`，可选填 `required_stages`（任一满足）和 `required_flags`（全部满足）。玩家进入区域后，按与 E 交互相同的路由请求 `"trigger": "<trigger_id>"` 的事件。被拒绝时，只要玩家仍在区域内就会重试；离开后重新进入可再次触发。是否只播一次由事件的 `once` 决定。

**新增剧情指令**：`pay_items`、条件 `items`、`set_phase`、`title_card`、`actor_animate`，详见 [指令表](../guides/story_authoring_commands.md)。守卫贿赂可写成 `pay_items` 加 `receipt: "day1.s05.guard_payment_completed"`，同时用 `set_flags` 写守卫的 `clearance_flag`；`Day1StealthService` 读取这两个事实后放行。金额在剧情 JSON 中填写，系统没有写死任何数值。

**章节结束**：在 S06 结尾按顺序写 `set_flag day1.s06.completed` → `title_card "第一天结束"` → `set_phase day`（`current_day` 变为 2）→ `set_stage day2.placeholder` → `title_card "第二天"`。阶段以 `day2.` 开头时，玩家不能出店，HUD 显示"第二天的内容尚未开放"，重建奶茶店也不会把阶段拉回 Day 1 的检查点。

**验证**：`tests/verify_day1_chapter_systems.gd`。

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

调查 / 制作的独立业务验证不产生正式后四阶段 Beat。当前待定状态见[P 编号清单](../story_authoring/day_01_integration_pending.md)，前段已解决项与后段开放项分开维护。

## 历史验证记录（2026-10-17）

使用 Godot 4.7.2。43 项检查通过，包括真实宿主 world flow、调查原子性、配方门禁、DayPhase、GameState、共享经营会话、SceneTravel、TaskDelivery、WalletTransactions、角色、聚落及既有 S01–S02。

- 历史失败：verify_cinematic_integration.gd 的 6 项断言，以及 verify_story_authoring.py 的 cinematic.opening/steps[9] 移动受阻；在 fbf6f72 隔离基线并叠加接手前的工作区配置后复现。
- 历史失败：verify_floor_atlas.gd、verify_walls.gd 把当前店铺地图强转 CaveMap，报相同类型错误；隔离基线复现。
- 不适用 headless 命令行：verify_cave_editor.gd 继承 EditorScript；verify_player_visuals.gd 依赖实际渲染的 frame_post_draw，此运行方式下超时。未将这两项计为通过。
- 导入无脚本解析错误；编辑器退出仍报告 10 个资源在用，基线也有相同诊断。未执行人工画面验收，提供上述 F6 入口供观察。

本次核对 [Godot 4.7 Object 信号连接](https://docs.godotengine.org/en/4.7/classes/class_object.html) 的同步/延迟通知约定，以及 [CollisionObject2D](https://docs.godotengine.org/en/4.7/classes/class_collisionobject2d.html) 的物理层开关接口。库存与回执在同步通知前整体提交；门洞及隐藏角色通过物理层控制实际碰撞。

## 工作区收尾核验（2026-10-18）

使用 Windows 上的 Godot 4.7.2。S03–S06 的四份剧情 / 对话 / Phase / Setup 数据与后续任务文件仍为空骨架；本次完成接入能力，不发布受 P06–P10、P13–P16 阻塞的剧情，也不自动进入 Day 2。Day 2 初稿与 D 编号清单只作为策划来源保留。

- 修复 `day1.investigate_coins` 的章节接管，等待前段事件结束后才加载；避免同一 idle 帧反复 `call_deferred`。自动事件执行失败或取消后不再自行重播，后续阶段也不显示前两阶段的继续按钮。
- 标题卡复用 TransitionLayer，并由宿主协调标题卡与切场景的显示状态；取消后隐藏，不遗留黑屏。店铺玩家恢复世界 / NPC 碰撞，重存丢失的店门隐藏 Marker / Label 设置恢复。
- 九份角色动作资源逐动画比较名称、循环、速度、帧顺序和贴图引用，内容一致；配方重存去除了重复的 `Recipe_h01`–`Recipe_h06` 定义，配方数组保持原有十条。
- `verify_day1_chapter_systems.gd`：95 项通过，覆盖支付、同步通知重入、恢复后幂等、交接、失败不重播、区域实际触发、角色摆位、标题卡显隐与 Day 2 占位恢复。
- 执行 55 个适用的 `verify_*.gd`（含新增章节检查），最终 49 个通过。直接检查包括 MainGame 74 项、正式五单流程 225 项、Bridge 248 项、GameState 124 项、ActorDirector 165 项、角色 1923 项、DeveloperTools 152 项、Debug 边界 97 项及 UI 主题 172 项；世界流程、任务、交付、制作、库存、钱包与地图检查通过。
- 六个历史失败均在未改动的 `0c31c75` 隔离 checkout 复现：`verify_cinematic_integration.gd` 的 6 项演出 / 移动断言；`verify_disappeared_street.gd` 的 7 项街景比例；`verify_scene_travel.gd`、`verify_shop_equipment.gd` 仍按 Label 读取现有 PromptBar 的 `.text`；`verify_floor_atlas.gd`、`verify_walls.gd` 把奶茶店强转为 CaveMap。后三个会挂起的脚本按超时终止，未记为通过。
- 场景切换另以临时副本改用 PromptBar 公开 `get_text()` 核对当前提示，真实 E 键往返、落点、输入恢复和会话保留共 163 项通过；仓库中的旧测试保留原状。
- 结构化前两阶段工程及产物一致性通过，保留用户新增的 2 秒 / 1.5 秒停顿。`verify_story_authoring.py` 新增的 4 项物品与动画引用负例通过；随后仍被既有 `cinematic.opening/steps[9]` 移动失败阻塞。临时内存跳过该已确认历史用例后，其余 14 项通过，不把原始完整脚本报告为通过。Python 工具补齐 Windows UTF-8 与正斜杠资源路径处理。
- OpenGL 图形窗口实际渲染并检查了标题卡及取消后的店铺画面。未做完整剧情人工试玩、听音或真实 Release 导出；`verify_cave_editor.gd` 需要编辑器，`verify_player_visuals.gd` 依赖实际渲染，未列入 headless 批次。引擎退出仍有少量资源 / ObjectDB 在用诊断。

复现时在仓库根目录用本机 Godot 执行 `--headless --path . --script res://tests/verify_day1_chapter_systems.gd`；普通试玩 F5 从标题菜单新游戏，S01–S02 完成后停在古怪硬币调查边界。独立世界业务可 F6 运行 `src/debug/story/day1_world_flow_demo.tscn`，按上节路线调查、取血、返店、制作并交付；不代表空骨架中的后四阶段剧情已发布。

本轮尝试访问 [Object.call_deferred](https://docs.godotengine.org/en/4.7/classes/class_object.html#class-object-method-call-deferred)、[AnimatedSprite2D.animation_finished](https://docs.godotengine.org/en/4.7/classes/class_animatedsprite2d.html#class-animatedsprite2d-signal-animation-finished) 和 [Area2D.body_entered](https://docs.godotengine.org/en/4.7/classes/class_area2d.html#class-area2d-signal-body-entered) 的 4.7 官方在线文档均返回 HTTP 403；改用本机引擎导出的 API 元数据核对方法 / 信号，并用上述实际运行检查其生命周期行为，未声称在线正文核验通过。
