# 统一手册

手册是任务、见闻录、饮品图鉴与人物记录的统一正式入口：HUD 图标打开 `handbook`，`tasks` / `chronicle` / `drinks` / `characters` 作为别名复用同一模态。饮品业务见[自由调配](../../../docs/gameplay/free_tea_recipes.md)。业务规则见 [任务规范](../../core/tasks/AGENTS.md)、[见闻录规范](../../core/chronicle/AGENTS.md) 与 [人物记录规范](../../core/characters/AGENTS.md)。

- `handbook_panel.tscn` 只组合 `ModalShell` 与 `HandbookBody`；`HandbookBody` 持有 `TabContainer` 与 `Tasks` / `Chronicle` / `Drinks` / `Characters`。
- 内容页只负责列表、详情与焦点，不复制遮罩、Panel、关闭按钮或页脚；关闭与 Esc 由 `ModalShell` 和 `UIManager` 处理。
- 未解锁页签隐藏；全部未解锁时 HUD 入口隐藏。`select_page()` 先校验可用性，再切页；失败不改变 `_has_opened`。
- 不新增第二个任务 / 见闻录弹窗；需要独立预览时使用 `TaskPopup` 或调试宿主，不接入正式入口。
- 修改页签或共享壳后验证 `verify_handbook`、`verify_task_panel`、`verify_chronicle`；画面与焦点问题补 640×360 / 1280×720 截图。
