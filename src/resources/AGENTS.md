# 共享资源与运行时数据

本目录保存跨关卡复用的 Resource、TileSet 与运行时 JSON；关卡专属布局跟随对应关卡。

| 数据目录 | 必须阅读的消费者规范 |
| --- | --- |
| `story/`：事件与 Bridge phase | [剧情模块](../core/story/AGENTS.md) 和 [源稿编排](../../docs/design/AGENTS.md) |
| `dialogue/`：台词与选项 | [对话模块](../core/dialogue/AGENTS.md)；剧情内容另读源稿编排规范 |
| `tasks/`：任务与交付定义 | [任务模块](../core/tasks/AGENTS.md) |
| `milk_tea/`：食材、菜单、配方 | [制作与库存](../gameplay/milk_tea/AGENTS.md) |
| `audio/`：音频映射与资源表 | [音频模块](../core/audio/AGENTS.md) |
| `tilesets/`：共享 TileSet | [关卡规范](../levels/AGENTS.md) |
| `ui/`：Theme 与共享 UI 数据 | [UI 规范](../UI/AGENTS.md)；tokens 由 [build_theme.gd](../../tools/ui/build_theme.gd) 生成 |

- 数据结构、合法字段和默认值以实际 Resource 定义与 Loader 为准；修改前查看直接消费者，不依据历史示例猜测 Schema，不往严格 JSON 插入 Beat 注释等开发元数据。
- 保持稳定资源 / 事件 / 物品 ID 和路径大小写；变更 ID 或类型时同步引用方与必要验证，避免只改显示名称就改业务键。
- 可复用 TileSet 存为外部 Resource；素材与必要的 `.import` 设置一同管理，不引用 `.godot/` 中的派生缓存。
- JSON 及运行时动态加载的数据必须纳入 `export_presets.cfg` 的现有导出规则；检查正式资源引用与 source / prompts、docs、tools、tests 等开发文件的排除范围，只改本次必要配置。
- 菜单、配方和物品描述是数据，UI 与剧情不另维护一份目录；设计中的战斗属性或效果描述不自动意味着具备执行系统。
- 剧情内容先改 Markdown 再生成现有 v1 数据及 Beat 清单；只改文案、立绘或音效引用时按 [验证分级](../../tests/AGENTS.md) 做局部校验，Schema 或共享契约变更才升级。
