# 剧情调度与 Gameplay Bridge

本模块包含 StoryLibrary、StoryDirector、GameplayBridge、Day1ShopController、Day1ChapterController、Day1WorldController 与剧情音频适配。内容编排必须先读 [剧情源稿规范](../../../docs/design/AGENTS.md)；修改配套 JSON 另读 [共享资源规范](../../resources/AGENTS.md)。

- [StoryDirector](../../../docs/systems/story_director.md) 描述接入；Schema 以 `story_library.gd` 的 Loader 和 `story_director.gd` 的实际 dispatch 为准。Library 负责加载与校验，Director 负责步骤调度，不能把玩法规则写进调度器。
- Director 使用宿主注入的 DialogueManager、ActorDirector、CameraDirector、AudioManager 等服务与已有 GameState，不自行查其他模块内部层级或创建第二份状态。
- 业务步骤（`unlock_map`／`tavern_purchase`／`casino_settle`／`business`）只经 `StoryBusinessAdapter` 调用宿主注入的已配置服务并投影真实回执；调度器不持有价格、奖励、库存或关店规则。服务未绑定时步骤失败，不用默认值代替。
- 演出顺序与内容留在现有 v1 Story / Dialogue JSON。宿主只做依赖注入、注册、加载、触发和必要的清理，不以 GDScript 硬编码 Beat 顺序。
- `conditions` 不会自动启动事件；交互 `trigger` 必须接入真实 `request_interaction` 路由。改路由、优先级、once 或 flag 时检查直接消费者与遮蔽关系。
- Blocking / 非阻塞动作、同角色动作互斥、失败后已执行状态不回滚等语义按工作流与当前实现核对；不要用额外等待掩盖缺失能力或路径受阻。
- [Gameplay Bridge](../../../docs/systems/gameplay_bridge.md) 只负责短演出与玩家操作阶段的交接。phase 配置声明解锁范围与完成条件，真实制作、采集、交付等规则留在各玩法服务。
- 不在 Director busy 中解锁玩家，不在 Bridge 或宿主硬编码剧情顺序；移动锁由 MainGame 统一协调。结束、取消、重置及宿主退出时，保持现有动作、订阅和阶段的清理契约。
- 修改 Actor、镜头、音频适配时，分别读 [角色](../actors/AGENTS.md)、[镜头](../camera/AGENTS.md)、[音频](../audio/AGENTS.md) 规范；对白解析读 [对话规范](../dialogue/AGENTS.md)。
- Day1WorldController 只投影昼夜、准入及真实抵达事实，不执行对白或硬编码 Beat 顺序。后续阶段返店时 Day1ShopController 不回写前两阶段检查点。业务接入见 [世界门控与调查](../../../docs/gameplay/day_01_world_flow.md)。
- Day 1 接入按 [对接约定](../../../docs/design/day_01_integration_contract.md) 与 [pending](../../../docs/story_authoring/day_01_integration_pending.md) 维护，不把设计目标当成既有能力。

验证按 [分级规范](../../../tests/AGENTS.md)：内容与单 Beat 参数只校验对应清单并 F6；调度 / Loader 用 `verify_story_director.gd`，Bridge 用 `verify_gameplay_bridge.gd`，再加直接调用方的最小检查。汇报相关宿主与 pending。
