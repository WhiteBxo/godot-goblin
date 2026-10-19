# UI 视觉层级与手感打磨（2026-10-19）

提交 `78628945`。本轮只改 UI 展示层、共享主题与标题画面，不动业务数据、存档和剧情事实。

## 目标与取舍

原主题给每个面板都描 2px 金边，任务卡、钱包、对白、弹窗的视觉权重相同，HUD 在明亮的像素地板上也缺少分隔；按钮只有静态的 normal / hover / pressed 三个色块，点击没有动作反馈。本轮按“表面分工”重排层级：

| 表面 | 用途 | 处理 |
| --- | --- | --- |
| `Panel` | HUD、对白、暂停 | 1px 暗边 + 3px 投影，不再抢金边 |
| `InsetPanel` | 弹窗 | 保留 1px 金线，投影加深，作为唯一“主角”表面 |
| `HudPanel` | 当前任务卡 | 左侧 3px 铜色导轨 + 1px 金线，目标一眼可见 |
| `CoinPanel` | 金币 | 圆角药丸，和任务卡同高但不抢标题 |
| `ChipButton` | 右上角“菜单” | 实心小片，替代原先几乎隐形的 Ghost 描边 |

正文 Label 统一加 1px 暗色投影；纸色订单笺的墨色文字显式关闭投影，避免发糊。金色主按钮改用深色 2px 焦点环，解决“金色焦点框压在金色底上”不可见的问题。

## 动效

- `src/UI/components/ui_button_motion.gd`：与 `UIAudioFeedback` 一样由宿主注入 UI 层根节点，统一处理悬停微放大、按下回缩、松开回弹和键盘焦点轻抬。只改 `scale` / `pivot_offset`，不改变布局、焦点和信号；覆盖整张任务卡的透明热区用 `metadata/ui_motion = false` 退出，防止悬停底框溢出卡片。
- 弹窗打开：面板 0.94 → 1（`TRANS_BACK`）+ 遮罩淡入，替代原来的 0.985 微缩。
- 交互提示：面板 0.9 → 1 弹入；提示内容切换时键帽单独弹一下。
- 任务栏：目标或余额变化时横向轻推一次；从隐藏恢复时 0.12s 淡入。
- 标题画面：任务面板 0.96 → 1 入场，背景以 16s 为周期缓慢呼吸；默认动作按“有存档＝继续、无存档＝新游戏”设为唯一金色主按钮。

## 标题画面

背景改用项目内的奶茶店剖面图 `assets/map/milkTea/shop_interior_open.png`，放大 12% 裁掉原图米色边框，叠暗色 tint 与径向暗角；面板宽 328、留白 20/8，避免在 640×360 下顶满屏幕。标题用 36px `HeroTitle`，副标题一行说明场景，底部补键盘提示。

## 验证

真实窗口渲染截图（都在 `.godot/`，不提交）：

- `.godot/captures/title/`：1280×720 标题画面，确认底图裁切、唯一金色主按钮、Tab 提示。
- `.godot/order_hud_640.png`、`.godot/order_active_640.png`：`verify_order_ui.gd -- --capture`，640×360 下的真实 HUD（任务卡 + 金币 + 提示条）与订单弹窗。
- `.godot/captures/ui/`：`shop_modal_640`、`pause_640`、`hud_640`，检查 1px 金线弹窗、暗角与暂停面板层级。

自动检查：`python tests/run_all.py --filter "(ui_|task_|handbook|chronicle|character_records|dialogue|main_game|milk_tea_shop|order_ui|interaction_feedback|screen_transition|game_entry|title_music|settings|inventory|hud)"` 共 19 项，12 项通过；7 项失败全部在本轮改动前的 HEAD 隔离检出中逐条复现（`ui_theme` 的 4 个 raw Color / 缺主题项、`game_entry` 的 Tab 循环断言、`chronicle`、`character_records`、`inventory_screen`、`milk_tea_shop`、`warehouse_inventory`），本轮没有新增失败。

`verify_order_ui.gd -- --capture` 45 项全部通过。

## 边界

- 没有跑完整回归（99 项），也没有做完整真人试玩；按钮手感依赖 F5 / F6 实际操作确认。
- 同一工作区另有并行进行中的存档槽位改动，改动 `title_menu`、`main.gd`、`pause` 与 `src/UI/saves/`。本提交只包含 UI 打磨所需的行；该功能自己的场景、脚本和测试仍未提交，未计入本轮结果。
- 主题改动覆盖全部界面，F6 主题画廊只人工检查了文字与徽标区；列表、页签、输入框仍由既有 `verify_ui_kit.gd` 冒烟覆盖。
