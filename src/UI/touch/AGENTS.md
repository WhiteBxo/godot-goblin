# 触摸操作层

适用于 `src/UI/touch/`。让手机玩家用拇指玩同一套玩法，不新增第二条业务代码路径。

## 边界

- 触摸层只做"把手指变成输入"：摇杆写 `move_*`，动作按钮回放 `InputMap` 里该 action 的原始按键事件。它不调用角色、交互或剧情接口，也不判断玩法状态。
- 输入锁、模态与暂停仍由 `MainGame` / `UIManager` 统一管理。宿主通过 `set_blocked()`（模态、转场）和 `set_movement_available()`（对话、演出、移动锁）驱动显示，触摸层不自行恢复移动。
- 按钮集合是固定 HUD 控件，不做通用虚拟手柄；新增动作先确认 `project.godot` 里已有对应 action，再在 `ACTION_PADS` 里登记位置。
- 触控判定只处理 `InputEventScreenTouch` / `InputEventScreenDrag`。宿主坐标必须经 `get_global_transform_with_canvas()` 反变换，拉伸缩放后点击位置才不会偏移。
- 桌面不加载本层：是否显示由 `MobileSupport.should_show_touch_controls()` 决定，可用 `--touch-controls` 强制打开用于试玩。

## 负责的内容

| 内容 | 位置 |
| --- | --- |
| 摇杆、动作按钮、暂停键与绘制 | `touch_controls.gd` / `touch_controls.tscn` |
| 触屏判定与键位文案降级 | `mobile_support.gd` |
| 列表触摸拖动滚动 | `../components/touch_scroll.gd`（由宿主对各 UI 层注入） |

## 布局

- 布局按 640×360 设计分辨率写成常量，运行时贴到最近的物理边（`_place()`），因此超宽屏上摇杆仍在左下、动作键仍在右下。
- 顶部暂停键属于「居中」而不是「贴右」：走 `_place_centered()`，保持相对视口中心 +32px 的偏移。`expand` 与动态基准都会让逻辑视口变宽，用贴边规则会把它推到右边。
- 左下留给摇杆、右下留给动作键。会占这两块区域的 HUD 必须在 `MobileSupport.is_touch_ui()` 时让位（潜行卡片移到右侧、交互提示去掉键帽），不要靠遮挡蒙混过关。
- 颜色只取 `src/resources/ui/ui_tokens.gd` 的 `TOUCH_PAD_*`；控件自绘，不新增主题类型。

候选验证：`tests/verify_touch_controls.gd`（摇杆、按钮注入、模态屏蔽、移动锁）；改布局或视觉时另做一次强制触摸层试玩（`--touch-controls`）。
