# 委托列表与详情

活动任务窗口补充原有的当前主线 HUD。正式店铺、聚落与洞穴 MainGame 共用相同装配；窗口只显示活动主线和委托，任务完成后立即退出列表。

## 操作与显示

- 点击 HUD 右下角、见闻录上方的“委托 [J]”，或按 J 打开。无任务时也能打开，显示“暂无活动任务”。
- 鼠标或方向键选择任务，Tab 切换列表、正文和关闭按钮，正文支持独立滚动。Esc 或关闭按钮退出。
- 任务按目录顺序排列，区分主线与委托。首次选择第一项；刷新和重新打开保留仍活动的所选任务，所选任务完成后选择剩余第一项。
- 详情包含描述、全部目标、完成状态、可选标记、已揭示的计数、交付对象、成品或物资数量和奖励说明。目标全部达成仍等待原任务完成条件。
- 未揭示内容显示 `???`；隐藏任务不返回交付 ID。缺少交付名称时显示待确认，缺少奖励说明时显示“暂无奖励说明”。
- 默认 640×360 为左右布局；逻辑宽度不足 480 时改为上下布局，列表高度 88。长标题省略并保留完整提示，正文自动换行。
- 打开窗口锁定移动和场景交互。P 暂停覆盖窗口，Esc 先退出暂停，再次 Esc 关闭窗口。其他弹窗、对白、演出及玩家表演控制期间不能打开委托窗口。

查看和选择不改变当前主线 HUD，也不接单、交付或结算奖励。既有业务仍负责进度和物品。没有增加已完成记录、追踪切换、导航或存档状态。

## 接口与数据边界

- `MainGame.open_tasks() -> Error`：按钮和 InputMap `open_tasks`（物理 J）共用入口；重复打开幂等，输入忙碌时返回 `ERR_BUSY`。
- `TaskPanel.bind_journal(journal)`：从 `get_active_tasks()` 读取只读投影，订阅 `projection_changed`；支持解绑、重绑和离树/重入树。
- `TaskPanel.set_delivery_names(target_names, product_names)`：复制宿主注入的名称字典。MainGame 使用现有 NPC 点位和物品定义解析，投影变化时同步新揭示的名称。
- `TaskPanel.close_requested`：交由 UIManager 关闭 `tasks` 模态屏幕，节点归 PopupLayer；独立 `TaskButton` 归 HudLayer。
- TaskJournal 的 Task view 新增 `delivery`：已揭示的成品任务返回 `{target_object_id, product_id}`，物资任务返回 `{target_object_id, items}`，其他情况返回 `{}`。不暴露订单 ID、条件或结算数据，不改变 TaskCatalog JSON v1。

## F6 试玩

打开 `src/debug/tasks/task_panel_demo.tscn` 后按 F6，自动展示四个隔离任务，含交付、长标题/正文、计数与隐藏内容。关闭窗口后可用顶部测试按钮推进目标、计数、揭示或清空任务，再按 J 查看。退出试玩恢复进入前的 GameState。

该入口仅 Debug 生效，测试目录不会被正式入口加载。原 `task_demo.tscn` 仍用于真实制作/交付流程。本窗口不向正式任务目录添加虚构委托。

实际首单：F6 `src/debug/story/legacy_shop.tscn` 或 `src/core/settlement.tscn`，订单板接单后按 J，确认显示胖哥布林、珍珠奶茶和糖浆奖励；制作入库后任务仍活动，实际交付后退出列表。

## 验证记录

Godot 4.7.2.stable.official.ed1daf0bf，2026-10-17。

| 检查 | 结果 |
| --- | --- |
| `verify_task_panel.gd`，headless | 85 项，0 失败 |
| 同一测试，Metal Forward+ 图形窗口 | 85 项，0 失败 |
| `verify_task_system.gd` | 196 项，0 失败 |
| `verify_task_delivery.gd` | 69 项，0 失败 |
| `verify_ui_manager.gd` | 47 项，0 失败 |
| `verify_main_game.gd` | 73 项，0 失败 |
| `verify_chronicle.gd` | 65 项，0 失败 |
| `verify_debug_build.gd` | Debug 模式 97 项，0 失败；未执行真正 Release 导出 |

新增检查覆盖多任务、隐藏信息和名称解析、窗口打开期间揭示、计数与滚动保留、完成移出、只读性、reset/restore、生命周期、实际按键、输入锁与各类互斥。图形截图位于 `.godot/task_panel/`，已检查宽窄屏、长文本、HUD 入口和独立试玩窗口，不提交缓存。

命令示例：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/verify_task_panel.gd
/Applications/Godot.app/Contents/MacOS/Godot --path . --script tests/verify_task_panel.gd -- --capture
```

沙箱中的图形进程启动失败；放行后使用 Metal 完成图形验收。见闻录第一次受限试跑无法写入 `user://` 快照，放行后完整重跑通过。headless 的 macOS 系统证书提示不影响上述断言；检查结果同时确认无 `SCRIPT ERROR`。导入扫描结束时另有编辑器设置目录不可写和编辑器资源释放提示，未将其计作运行验证通过。

## Godot 4.7 官方依据

- [ItemList](https://docs.godotengine.org/en/4.7/classes/class_itemlist.html)：原生选择、完整标题提示和溢出省略；程序调用 `select()` 不发选择信号，刷新需显式更新详情。
- [Control](https://docs.godotengine.org/en/4.7/classes/class_control.html)：焦点、输入传播与尺寸标志，沿用 UIManager 的原生 GUI 输入通道。
- [InputMap](https://docs.godotengine.org/en/4.7/classes/class_inputmap.html)：统一通过项目 action 绑定快捷键。
- [BoxContainer](https://docs.godotengine.org/en/4.7/classes/class_boxcontainer.html)：通过 `vertical` 切换宽窄布局。
- [RichTextLabel](https://docs.godotengine.org/en/4.7/classes/class_richtextlabel.html)：使用独立滚动条，禁用 BBCode，按任务切换或内容刷新管理滚动位置。

合并回归覆盖醒神菇委托的物资数量、中文名称、目标和深拷贝投影，兼容原成品详情。任务窗口示例显式使用无剧情 legacy_shop，避免启动正式 Day 1；正式演出及活动 Bridge phase 的原有窗口准入不变。
