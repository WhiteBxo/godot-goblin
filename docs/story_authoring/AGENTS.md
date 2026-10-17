# 剧情编排映射与验证清单

本目录保存开发期产物，不供游戏运行时加载。先读 [源稿与编排规范](../design/AGENTS.md) 和 [编排工作流](../guides/story_authoring_workflow.md)。

- Beat 映射、验证 case 和 pending 跟随对应 Markdown 与事件维护；保留已有资源 / 事件 ID 对应的文件名，不为文档命名整洁改运行时 ID。
- `source` 指向真实源稿，`source_sha256` 对应实际编排过的源稿。仅移动路径、整理文档或继承旧产物时，不把未重新核对的哈希改成“已验证”。
- Beat 区间采用工作流规定的零起始 `[start, start + count)`；局部修改同步受影响的 Dialogue ID、区间和后续偏移，未受影响的数据保持语义一致。
- 验证 case 覆盖本次涉及的事件、选择分支、正反条件和真实触发路由；不因有清单就声称已在宿主注册或执行。
- pending 记录具体缺失的素材、空间、宿主绑定或系统能力及影响的 Beat；不以猜测清除待定项。Day 1 同步维护 [对接待定清单](day_01_integration_pending.md)。
- 生成或验证工具见 [tools/AGENTS.md](../../tools/AGENTS.md)；校验 `tools/story/validate_story.gd` 时只选择本次对应清单，扩大范围遵循 [tests/AGENTS.md](../../tests/AGENTS.md)。
