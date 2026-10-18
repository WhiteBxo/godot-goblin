# 剧情编排映射与验证清单

本目录保存开发期产物，不供游戏运行时加载。先读 [源稿与编排规范](../design/AGENTS.md) 和 [编排工作流](../guides/story_authoring_workflow.md)。

- Beat 映射、验证 case 和 pending 跟随对应 Markdown 与事件维护；保留已有资源 / 事件 ID 对应的文件名，不为文档命名整洁改运行时 ID。
- 未迁移清单的 `source` / `source_sha256` 指向实际编排过的 MD。已迁移清单的 `authoring_project` / `authoring_sha256` 指向当前结构化工程及其散列，source 字段保留最初导入来源，生成时不伪造更新原稿散列。仅移动路径、整理文档或继承旧产物时，不把未重新核对的哈希改成“已验证”。
- `*_project.json` 是可编辑的正式来源，表单与 Codex 共用；以稳定步骤 ID 维护内容，由 `StoryProject` 生成运行时 JSON 和 Beat 区间。不要直接改派生文件，保存前检查外部修改。使用见[游戏内编排](../guides/story_editor.md)。
- Beat 区间采用工作流规定的零起始 `[start, start + count)`；局部修改同步受影响的 Dialogue ID、区间和后续偏移，未受影响的数据保持语义一致。
- 验证 case 覆盖本次涉及的事件、选择分支、正反条件和真实触发路由；不因有清单就声称已在宿主注册或执行。
- pending 记录具体缺失的素材、空间、宿主绑定或系统能力及影响的 Beat；不以猜测清除待定项。Day 1 同步维护 [对接待定清单](day_01_integration_pending.md)。
- 生成或验证工具见 [tools/AGENTS.md](../../tools/AGENTS.md)；校验 `tools/story/validate_story.gd` 时只选择本次对应清单，扩大范围遵循 [tests/AGENTS.md](../../tests/AGENTS.md)。
