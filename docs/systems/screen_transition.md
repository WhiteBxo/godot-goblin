# ScreenTransition

独立屏幕视觉模块：`src/UI/screen_transition/screen_transition.tscn`，根节点/class 为 `ScreenTransition`（Control）。仅显示视觉，不切换场景、不锁输入、不修改暂停状态或剧情数据，无 autoload。

## 挂载与 API

由宿主将模块实例挂到自己的 `TransitionLayer`：`CanvasLayer.layer = 40`、`follow_viewport_enabled = false`、`process_mode = Always`，并显式 `show()`（MainGame 的层默认隐藏）。店铺与聚落 MainGame 已通过 [SceneTravel](scene_travel.md) 接入门口进出，待机及完成后隐藏层。

```gdscript
var visual: ScreenTransition = preload("res://src/UI/screen_transition/screen_transition.tscn").instantiate()
transition_layer.add_child(visual)
transition_layer.show()
var action := visual.fade_out(0.5)
if not action.is_finished():
	await action.finished
if action.result == TransitionAction.Result.COMPLETED:
	# 宿主可在黑场中自行更新内容；不销毁承载模块的宿主。
	visual.fade_in(0.5)
```

| API | 行为 |
| --- | --- |
| `fade_out(duration = 0.5)` | 当前黑色透明度 → 1，完成后保留黑场 |
| `fade_in(duration = 0.5)` | 当前黑色透明度 → 0，显露画面；初始黑场可先 `fade_out(0)` |
| `flash_white(duration = 0.25)` | 白色立即达到不透明，再淡到透明；不清除黑场和遮幕 |
| `letterbox(show_bars, duration = 0.4, ratio = 0.12)` | 开关上下黑色遮幕；ratio 是**每条**遮幕占视口高度比例，范围 0～0.5 |
| `cancel(action, reason = "Cancelled")` | 仅取消仍属于此实例的活动 handle，清除对应通道；过期/其他实例的 handle 无影响 |
| `cancel_all(reason = "Cancelled")` | 取消全部活动请求，清除所有视觉（包括已完成保留的黑场/遮幕）；可重复调用 |
| `is_busy()` | 任一通道仍有待完成请求时为 true；保留黑场不算 busy |

所有视觉 API 返回 `TransitionAction`，包含递增 `id`、`effect`、`result`、`reason`。终态是 `COMPLETED / CANCELLED / FAILED`；handle 的 `finished(action)` **延迟且只发一次**，取消、无效参数和模块释放也会结算。保留 handle 即可检查结果，不要等待内部 Tween.finished（kill 不代表完成）。

模块提供 `completed(action)`、`cancelled(action)` 信号，在状态结算后同步发送；无效请求只在 handle 上返回 FAILED，不影响原请求。取消/替换正在发送同步信号期间重入视觉 API 会返回 FAILED，重入取消会忽略，避免信号创建的请求被外层清理。需要接续时使用 handle 的延迟 `finished` 或 `call_deferred`。完成回调可直接发起下一请求。

## 行为边界

- 三个独立通道：黑场、白闪、遮幕。同通道新请求先 kill 旧 Tween、以 `Replaced` 取消旧 handle；黑场/遮幕从当前值平滑接续，白闪重新从白色开始。跨通道可同时播放。绘制顺序为遮幕 → 黑场 → 白闪。
- 时长单位为真实秒，必须有限且非负；遮幕 ratio 必须有限且在范围内（关闭时也校验）。0 秒立即应用视觉，延迟结算，让调用方有机会连接信号；同帧替换/取消不会发出旧完成信号。
- 模块使用 Always，绑定自身的 Tween 设置 `TWEEN_PAUSE_PROCESS` 与 `set_ignore_time_scale(true)`，暂停及 `Engine.time_scale = 0` 时继续完成，不改变游戏暂停状态。
- 全屏 anchors 覆盖宿主视口；遮幕按高度比例布局，窗口尺寸变化自动适配。不跟随世界相机。所有视觉 Control 均忽略鼠标且不取得焦点；输入锁由宿主管理。
- `_exit_tree` 主动 kill 所有 Tween、同步取消活动请求、清除保留视觉；离树/等待删除期间拒绝新请求。handle 的延迟结束通知独立于视觉节点。重入树后可复用；不承诺跨宿主销毁保留黑场。

## F6 与验证

打开 `src/debug/screen_transition/screen_transition_demo.tscn`，按 F6。Demo 使用自身背景及 layer 40 转场层，Debug 面板位于 layer 50；Release 不创建测试界面。

1. 点“黑场 1s”，背景渐黑且保持，面板仍可用；点“揭幕 1s”渐显。黑场中途反向点击，透明度从当前值接续。
2. 点“闪白”，背景立即变白再恢复；打开遮幕后闪白，结束后遮幕仍保留。拖动窗口，两条遮幕始终等高，全屏覆盖无缺口。
3. 点“替换请求”，旧 fade_out 显示 CANCELLED，新 fade_in 完成；“零时长黑场”立即变黑。
4. 暂停后执行任一效果，应仍可完成，paused 保持 true；“取消 / 清屏”即时清除所有效果；执行长转场时“退出 / 重建模块”不会遗留 Tween。

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --log-file /private/tmp/screen-transition.log --script res://tests/verify_screen_transition.gd
# 窗口版同时检查实际渲染像素，输出三张截图到 /private/tmp/screen-transition-{black,bars,white}.png
/Applications/Godot.app/Contents/MacOS/Godot --path . --log-file /private/tmp/screen-transition-visual.log --script res://tests/verify_screen_transition.gd -- --capture
```

测试覆盖插值/终点、跨通道独立及各自替换、零时长结算、陈旧回调、取消幂等、非法输入、视口变化、暂停与零时间缩放、退出/重入/释放、取消回调触发退出、真实 Demo 重建。窗口版额外验证黑场/白闪覆盖及上下遮幕的渲染结果。

实现核对 Godot 4.7 官方说明：[Tween 创建/绑定、kill、暂停与忽略时间缩放](https://docs.godotengine.org/en/4.7/classes/class_tween.html)、[Node 的 Always 与退出顺序](https://docs.godotengine.org/en/4.7/classes/class_node.html)、[Control anchors 与 MOUSE_FILTER_IGNORE](https://docs.godotengine.org/en/4.7/classes/class_control.html)、[CanvasLayer 层级与 follow_viewport_enabled](https://docs.godotengine.org/en/4.7/classes/class_canvaslayer.html)。验证引擎：Godot 4.7.2。
