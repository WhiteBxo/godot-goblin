# 设计源稿与自然语言剧情编排

适用于本目录的设计稿；用户要求“编排这段剧情”或修改局部 Beat 时，无论改动位于源稿、运行时 JSON 还是宿主，都必须先读本文件。

## 必需上下文与产物

- 必须执行 [剧情编排工作流](../guides/story_authoring_workflow.md)，按需核对 [全部指令及参数](../guides/story_authoring_commands.md)、[StoryDirector](../systems/story_director.md) 和目标 Loader / dispatch；运行时边界见 [剧情模块规范](../../src/core/story/AGENTS.md)。
- Markdown 是剧情唯一内容来源。先保留或更新原稿，再生成现有 v1 Dialogue / Story JSON，以及 `docs/story_authoring/` 中的 Beat 映射和验证清单；产物规范见 [story_authoring/AGENTS.md](../story_authoring/AGENTS.md)。
- 逐字保留对白、标点、换行、选项、内心与台词区分；不得扩写对白、改变节奏、把叙述变成新台词或将演出顺序硬编码进 GDScript。
- 先核对目标宿主实际注册的 Actor、Marker、音频与场景资源。明确的位置或资源可自主配置；无法确认的空间、关键素材、角色身份或表现能力列入 pending，不编造坐标与占位身份，不为编排扩展通用系统。

## 执行与局部修改

- 混合演出与玩法的 Beat 必须声明“执行模式：自动演出 / 玩家操作”和“玩法完成条件”。按工作流拆成 StoryDirector 短事件与 Gameplay Bridge phase 数据；禁止在 busy 中解锁、在 Director 写玩法规则或在宿主硬编码顺序。
- 参数采用已有默认值时在摘要注明；决定关键节奏或空间含义、但原稿未明确的内容先列 pending。剧情状态与触发点同样不得猜测。
- 用清单的 Beat 区间与 Dialogue ID 定位局部修改，只调整对应区间、关联对白和必要依赖；保留稳定 ID，更新后续索引偏移，不对整个 JSON 重排或把 Beat 元数据放进运行时 Schema。
- 已有 JSON 与源稿不一致时记录冲突，以源稿控制内容，不能把手工改过的对白反向吞并到原稿；pending 事件按工作流保留上一份有效产物，不发布伪造的可播放版本。

## 验证与汇报

- 按 [验证分级](../../tests/AGENTS.md) 选范围。逐字对白、立绘、音效引用或单个 Beat 参数只校验对应清单并 F6 观察目标宿主；Loader、路由或 flag 契约变化才升级。
- 缺失引用、关键音效 skipped、移动受阻或超时、执行失败都不能写成验收通过；明确区分通过、未执行与 pending。
- 汇报 Beat 变更、匹配或新增的绑定、验证结果、pending、Godot F6 入口和 commit。
