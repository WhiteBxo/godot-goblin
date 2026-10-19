# 前两天操作手感与反馈打磨（2026-10-19）

在已打通的两天流程上补“操作的即时回应”，不改剧情、订单、经济、存档字段或数值规则。范围分两批：A 为投掷、交互、弹窗、对白与镜头的低风险反馈；B 为被发现冲击、警戒张力、制作与钱包反馈。没有新增 autoload、输入 action、音效 ID 或外部素材。

## 改动

| 场景 | 之前 | 现在 | 主要实现 |
| --- | --- | --- | --- |
| 首夜投掷 | 只有鼠标落点，按 F 才知道是否越界 | 持投掷物时显示整像素准星、中心和射程圈；有效暖金、无效红色；弹窗/暂停/演出锁定时隐藏 | `ThrowAimIndicator`，服务每个物理 tick 用 `_valid_target` 更新 |
| 投掷命中 | 只改文字 | 0.24 秒落点效果（亮点、圆环、尘点）+ 2 像素 0.12 秒震屏 + `story.impact` | `ThrowImpactEffect`；宿主订阅 `throw_resolved` |
| 守卫警戒 | 文字百分比与单色视锥 | 视锥随曝光由黄转橙、填充加深；首次进入视线时警戒框上跳 4 像素 | `Day1GuardResponse` 的 `_alert_pop` 与颜色插值 |
| 被发现 | 左下 HUD 一行失败文字 | 守卫头顶感叹号 + 全屏暖白闪 + 4 像素震屏 + `ui.failure` + 0.18 秒聚焦发现者再回跟随 | `StealthAlertMarker`、`ThreatOverlay.pulse()`、宿主 `attempt_failed` 处理 |
| 潜入张力 | 无屏幕级提示 | 径向暗角随警戒比例升到 0.42 alpha，离开视线缓落 | `ThreatOverlay`，`get_alert_ratio()` 只读轮询 |
| 交互提示 | 瞬现、切换无声音 | 首次出现 0.08 秒淡入；焦点切换播 -20 dB 轻响；角框从 0 生长到 6 像素 | `PromptBar.appear_seconds`、`InteractionAudio.play_focus()`、`InteractionFeedback` |
| 弹窗 | 0 ms 显示 | Panel 0.10 秒 alpha + 0.985→1.0 缩放；关闭即复位 | `ModalShell` 的可见性动画，只动 Panel |
| 对白 | 每行一次字音 | 逐字发 `character_revealed`，宿主每 3 个非标点字播一次 -26 dB 字音 | `DialogueUI` 信号 + `InteractionAudio.play_blip()` |
| RPG 跟随镜头 | 始终居中 | 向移动方向前瞻 8 世界像素，停步归零；其他宿主默认 0 | `BoundedFollowCamera.follow_look_ahead`，仅 `rpg_player.tscn` 开启 |
| 钱包变化 | `+3G` 文本停留 2.8 秒 | 同一文本之外，金额浮字上移 10 像素后淡出 | `Day1BusinessHUD` 的 `BalanceFloat` |
| 制作完成 | 杯子弹跳 + 封口音 | 保留弹跳，状态文字由暖白闪回常规色 | `OrderTicket.show_result()` |

暂停中的弹窗动画使用 `TWEEN_PAUSE_STOP`；世界效果挂在 `EffectRoot`，随世界暂停。投掷、失败、制作和钱包都只读已提交结果，表现不参与扣费、入库或任务事实。

## 验证

Windows Godot 4.7.2 headless，使用真实资源与宿主；同一任务内未变化的测试只执行一次。

| 检查 | 结果 |
| --- | --- |
| `verify_feel_layer.gd`（新增） | 10 项通过：弹窗动画、镜头前瞻与停步归零、逐字信号、暗角初始与闪白回落 |
| `verify_day1_stealth.gd` | 105 项通过：准星在任务中显示、外部锁定时隐藏、每次结算恰有一个落点效果、警戒比例、发现标记 |
| 正式宿主 `verify_day1_stealth.gd -- --host-only` | 9 项通过 |
| `verify_interaction_feedback.gd` / `verify_interaction_audio.gd` | 46 / 69 项通过，含焦点音与字音音量、去重 |
| `verify_dialogue.gd` | 189 项通过（另一路已扩展的快进/自动用例一并通过） |
| `verify_order_ui.gd` / `verify_task_panel.gd` / `verify_handbook.gd` / `verify_ui_kit.gd` / `verify_ui_manager.gd` | 39 / 94 / 46 / 6 / 47 项通过 |
| `verify_camera_director.gd` / `verify_shop_camera.gd` / `verify_rpg_chapter_maps.gd` | 285 项通过 / PASS / 179 项通过 |
| `verify_day1_world_flow.gd` / `verify_two_day_flow.gd` | 48 / 282 项通过 |
| `--headless --editor --quit` | 无脚本解析错误；退出仍有既有的资源存活诊断 |

未执行：`verify_compact_menu.gd`（需要 `--fixtures=` 检查点，直接运行会退出）、带渲染的截图回归、人工试听与完整步行试玩。另有一组并行未提交改动（对白快进/自动、存档提示、任务地点引用）在同一工作树；本记录只覆盖本次文件，其行为不在本记录结论内。

## 试玩

1. F5 新游戏推进到首夜。靠近入口守卫，确认持金币时鼠标处有准星和射程圈，越界变红；按 F 后落点有亮点/圆环，画面轻震。
2. 进入视锥，观察视锥由黄转橙、守卫头顶百分比框上跳、屏幕边缘暗角加深；离开视线后暗角退去。
3. 让守卫发现，确认头顶感叹号、暖白闪、震屏与失败音，镜头短暂停在被发现者身上再回到主角；重试仍走原检查点。
4. 店内靠近柜台/仓储/制作台，确认提示淡入、切换目标有一声轻响、角框生长；按 E 打开弹窗时面板淡入。
5. 与顾客对白，确认逐字时有轻微字音但不超过音乐；把对白速度调为“立即显示”后应完全安静。
6. 完成一杯订单并交付，确认杯子弹跳、状态文字闪回与钱包 `+3G` 浮字；换日/读档不残留旧浮字。

## Godot 4.7 依据

- [Tween](https://docs.godotengine.org/en/4.7/classes/class_tween.html)：`TWEEN_PAUSE_STOP` 用于弹窗、钱包与闪白，暂停时不继续计时；节点释放自动清理绑定 Tween。
- [Camera2D](https://docs.godotengine.org/en/4.7/classes/class_camera2d.html)：保留原有位置平滑，只增加跟随目标偏移；震动仍走既有 `BoundedFollowCamera.set_shake_pixels` 的整像素钳制。
- [GradientTexture2D](https://docs.godotengine.org/en/4.7/classes/class_gradienttexture2d.html)：径向渐变替代外部暗角贴图，`FILL_RADIAL` 与 `Gradient` 在运行时生成。
- [CanvasItem.draw_arc / draw_rect](https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html)：准星、射程圈与落点效果只在 `_draw` 中绘制，关闭抗锯齿并按整像素取整。
