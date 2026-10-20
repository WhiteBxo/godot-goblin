# 第二天反馈修正（2026-10-19）

## 实现

- 左上任务卡显示主线标题和当前目标，点击整块卡片直接打开任务日志。主线优先于追踪订单的缺料提示；旁侧金币卡持续读取真实钱包，模态关闭后恢复。
- 胖哥布林在第二天各店铺阶段和第三天交接时使用卧室 `day2_bedroom_rest`，休养期间关闭互动。返店和继续存档按同一阶段数据恢复；第一天事件不在第二天重播。截图中的“格里芬使者”对白本来属于第二天普通顾客，保留台词并修正角色立绘。
- 守卫、酒馆老板、赌场老板、普通顾客使用用户压缩包中的独立透明插画。地图像素小人、头像与对话立绘分别使用。胖哥布林第二天对白使用不适表情；正式工程先修改后生成 Dialogue 与 Beat 清单。
- 守卫高头盔立绘上移 40 逻辑像素，避免脸被对话框挡住。守卫的两种说话人名称都映射到对应插画，覆盖交付前后。
- 守卫交付目标文案改为“将奶茶提交给守卫”，交谈和实际交付的业务边界保持原有流程。

资源、原包文件映射和可复现裁边过程见 [对话立绘来源](../../assets/characters/dialogue/README.md)。

## 验证

Godot 4.7.2，Windows，D3D12 Forward+ 实际图形窗口：

- `verify_task_system.gd`、`verify_task_panel.gd` 通过，覆盖投影、窄屏、任务日志与宿主输入恢复。
- `verify_dialogue.gd` 243 项通过；核对真实第二天对白中的各角色插画、守卫交付前后、不适表情以及高头盔偏移。截图输出路径改为跨平台的 `user://`。
- `verify_order_ui.gd` 通过，确认任务栏调整没有改变实际订单交付和钱包反馈。
- `verify_compact_menu.gd -- --fixtures=res://.godot/flow_fixtures --capture` 48 项通过。读取既有真实营业、返店和守卫交付检查点；实际鼠标点击任务卡，核对日志页、关闭后的移动恢复、真实钱包收支及浮字消退后的常驻余额、卧室位置与交互禁用、返店恢复和守卫交付文案。
- 第二天工程 CLI `edit_story_project.gd ... --save` 通过，29 个 Beat；生成结果只增加胖哥布林的表情引用并更新工程散列。
- `verify_ui_theme.gd` 报出四项历史问题：`threat_overlay.tscn`、`inventory_body.tscn` 缺显式主题，`order_ticket.gd`、`threat_overlay.gd` 含 raw Color。四个文件与检查时的 HEAD 一致，本次任务卡和立绘没有新增主题审计失败。
- `git diff --check` 通过。未运行全项目回归或 Release 导出；本次没有变更共享数据格式或业务结算契约。

首次导入时脚本早于新插画完成导入，出现 preload 加载提示；资源导入完成后，正式工程生成、模块测试和图形检查均可正常加载。headless 宿主测试退出时存在既有资源清理提示，图形窗口运行正常。

## 画面与试玩

F5 开始游戏，推进到第二天白天营业：点击左上任务卡应进入任务日志，关闭后恢复移动；金币卡在无交易时仍然可见。前厅没有胖哥布林；进入卧室可见其休养位置，不能触发旧对白。之后前往酒馆、赌场，查看对应老板立绘；制作守卫特调并交谈后，目标显示“将奶茶提交给守卫”，交付后的守卫对白继续显示同一角色插画。

| 实际画面 | 截图 |
| --- | --- |
| 营业时任务与金币 | [任务栏](../gameplay/captures/day2_feedback_2026_10_19/task_wallet.png) |
| 返店后前厅与目标 | [返店](../gameplay/captures/day2_feedback_2026_10_19/returned_shop.png) |
| 守卫交付目标 | [目标文案](../gameplay/captures/day2_feedback_2026_10_19/guard_delivery.png) |
| 对话 UI 独立渲染：守卫 | [守卫插画](../gameplay/captures/day2_feedback_2026_10_19/guard.png) |
| 对话 UI 独立渲染：酒馆老板 | [酒馆老板](../gameplay/captures/day2_feedback_2026_10_19/tavern.png) |
| 对话 UI 独立渲染：赌场老板 | [赌场老板](../gameplay/captures/day2_feedback_2026_10_19/casino.png) |
| 对话 UI 独立渲染：普通顾客 | [普通顾客](../gameplay/captures/day2_feedback_2026_10_19/common_goblin.png) |
| 对话 UI 独立渲染：不适表情 | [胖哥布林](../gameplay/captures/day2_feedback_2026_10_19/fat_goblin_sick.png) |

## API 依据

核对 Godot 官方 4.7 版本的 [BaseButton](https://github.com/godotengine/godot/blob/4.7/doc/classes/BaseButton.xml)：按钮以 `pressed` 发出导航请求，实际日志打开及输入锁仍由 MainGame / UIManager 处理。立绘在既有 TextureRect 中保持比例；图片导入与透明裁边见资源说明。通用 UI 的 `portrait_vertical_offsets` 按纹理配置显示偏移，切换人物或隐藏时重新恢复默认位置。
