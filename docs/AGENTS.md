# 文档维护规范

适用于 `docs/`。分类与完整命名规则见 [文档中心](README.md#分类与命名规范)，新增或移动文档时同步维护其中的索引。

- `guides/` 放使用工作流，`systems/` 放系统接口，`gameplay/` 放玩法说明，`levels/` 放关卡说明，`assets/` 放素材接入，`development/` 放开发记录。
- 剧情源稿与策划放 `design/`；编排前读 [design/AGENTS.md](design/AGENTS.md)。Beat 映射、验证清单与 pending 放 `story_authoring/`，另读其 [AGENTS.md](story_authoring/AGENTS.md)。
- 文件名使用英文小写 `snake_case`，正文与标题可用中文；`README.md`、各级 `AGENTS.md` 和许可证沿用约定名称。剧情天数、场次与阶段用两位数。
- 保留 `_draft`、`_revised`、`_development_spec`、`_pending` 等来源关系；一次性记录与历史快照以 `YYYY_MM_DD` 结尾，持续维护的接口说明不加日期后缀。
- 图片放对应主题的 `captures/`，原始 PDF / Excel 等附件放 `design/source/`。素材来源、许可证与测试夹具说明仍跟随素材或夹具，第三方说明仍留在插件内。
- Markdown 链接相对当前文档；命令中的路径相对仓库根，Godot 资源路径用 `res://`。移动文档要同步链接、明文路径、生成目标、清单源路径和截图输出路径。
- 设计说明目标，模块文档描述实际接口，历史记录只证明当时的状态。全局状态见[2026-10-18 现状](development/development_status_2026_10_18.md)，后续变化同步持续维护的模块说明与优先级，旧快照只补指向新记录的时效说明。入口与配置以源码为准；Day 1 稿件冲突按 [对接约定](design/day_01_integration_contract.md) 和 [pending 清单](story_authoring/day_01_integration_pending.md) 核对。
- 修改模块说明时读取对应代码模块的 `AGENTS.md`；新增规范更新直接上级索引，跨目录必读关系使用显式链接。不要把 API 全文或候选测试命令复制进每份规范。
- 纯文档只检查内容、链接、格式与 diff，不运行 Godot 和项目测试。不要把历史结果或未执行的命令写成本次验证通过。
