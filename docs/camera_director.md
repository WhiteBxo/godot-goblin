# CameraDirector：2D 剧情镜头

`MainGame.get_camera_director()` 返回 `Systems` 中的场景级服务。它复用 ShopPlayer 的唯一 `BoundedFollowCamera`，不创建 Camera2D，不接管玩家输入、碰撞或 DialogueUI。洞穴旧调试相机不是 BoundedFollowCamera，该场景 getter 返回 null。

## 公开 API

所有指令返回独立 `CameraAction`；duration 单位为秒，位置为全局世界坐标，震动强度为 **640×360 逻辑视口像素**，不随窗口放大而提高逻辑强度。

| 调用 | 行为 |
| --- | --- |
| `camera_follow(duration = 0.6, transition = Tween.TRANS_SINE, ease = Tween.EASE_IN_OUT)` | 平滑回到玩家原来的 `(0, -48)` 跟随位置，然后恢复原有内置平滑；保留当前缩放和震动 |
| `camera_focus(target, duration = 0.8, transition, ease)` | target 为存活且在场景树中的 Node2D（角色、Marker2D 等）或 Vector2；到位后保持 Cinematic，节点目标继续实时跟踪 |
| `camera_move(world_position, duration = 0.8, transition, ease)` | 移动到指定世界位置并保持 Cinematic；支持 Godot Tween 的 transition / ease 枚举 |
| `camera_shake(intensity = 2.0, duration = 0.3, decay = 1.5)` | 单个随机震动包络；强度最大默认 6 像素，到期归零 |
| `camera_zoom(value, duration = 0.5, transition, ease)` | 均匀缩放；正数、越大越近；实际值受背景和视口尺寸约束 |
| `camera_reset()` | 立即停止全部动作，恢复默认跟随、preferred_zoom 和零 offset；返回已完成的 reset 动作 |
| `cancel_all(reason = "Camera sequence cancelled")` | 全部活动动作标记 CANCELLED，并恢复默认镜头；暂停期间也可调用 |
| `cancel_shake(reason = "Shake cancelled")` | 仅取消并清除震动，保留构图和缩放 |
| `configure(camera)` / `get_camera()` | 宿主注入 / 查询已有的 BoundedFollowCamera；重新注入先取消旧动作并复位 |

duration 为 0 时立即应用。负数、非有限值、非正缩放、无效目标或缓动枚举返回 FAILED，不打断正在执行的有效动作。震动 decay 必须非负；0 表示不衰减，正数表示 `strength * (1 - progress)^decay`，数值越大越快减弱；结束均归零。

`shake_enabled = false` 会取消活动震动并立刻归零；关闭时新震动请求成功完成但无位移。`maximum_shake_pixels` 可配置强度上限；新震动始终替换旧震动，不累加。

## Signal 与等待

`CameraAction` 包含 `id`、`command`、`result`、`reason` 和 `is_finished()`。result 为 `PENDING / COMPLETED / CANCELLED / FAILED`；每个动作只进入一次终态。`action.finished(action)` 和 `CameraDirector.action_finished(action)` 在 deferred 回调中发出，包括 duration=0、失败和取消；调用方可以先保存返回值再连接 signal。场景退出后仍可通过持有的 CameraAction 收到终态，不能等待已释放的 Director signal。

```gdscript
var cameras := game.get_camera_director()
var action := cameras.camera_focus(shop_entrance, 0.8)
action.finished.connect(_on_camera_finished)

func _on_camera_finished(action: CameraAction) -> void:
	match action.result:
		CameraAction.Result.COMPLETED:
			# 这里只向已有调度器安排下一步，避免递归 dispatch。
			print("镜头到位：", action.command)
		CameraAction.Result.CANCELLED, CameraAction.Result.FAILED:
			print("停止演出：", action.reason)
```

独立 Node 的简单 coroutine 示例（宿主必须在退出时取消，调度器建议采用上面的 signal 方式）：

```gdscript
var action := cameras.camera_move(Vector2(1500, 240), 1.2, Tween.TRANS_CUBIC, Tween.EASE_IN_OUT)
if not action.is_finished():
	await action.finished
if action.result != CameraAction.Result.COMPLETED:
	return
await get_tree().create_timer(0.5, false).timeout
var back := cameras.camera_follow(1.0)
if not back.is_finished():
	await back.finished
if back.result == CameraAction.Result.COMPLETED:
	cameras.camera_shake(2.0, 0.3, 1.5)
```

位置（focus/move/follow）、缩放、震动为三个独立通道，可以并行。同通道新动作将旧动作标记 CANCELLED。reset/cancel_all 终止所有通道。需要按顺序演出时，请按返回的 action 等待；并行时按各自 action.id 区分，不能假定 Director 的下一个完成 signal 就是自己等待的动作。

MainGame 已通过 `configure_cinematic` 把 CameraDirector 接入 StoryDirector；JSON 支持 focus/move/shake/zoom/reset，默认等待对应 CameraAction。事件结束、失败、取消和退出都恢复默认镜头。位置 ID 通过 ActorDirector 的共享 Marker 表解析，无 NodePath。完整语法与同通道替换策略见 [Cinematic Integration](story_director.md#演出-json-指令)。

## 相机职责与边界

- Follow 使用现有 BoundedFollowCamera 的世界坐标跟随实现：top_level 保持 true，在物理 tick 更新目标，保留 Camera2D 内置位置平滑与 preferred_zoom（当前默认为 0.5）。测试通过 get_follow_position 和 get_directed_zoom 验证，避免依赖旧局部坐标实现。
- Cinematic 将同一个相机设为 top_level，关闭内置位置平滑。Director 只 tween 进度并调用相机公开方法，相机计算最终位置；跟随和 Tween 不会竞争同一个 transform。回到 Follow 后恢复原有世界坐标跟随和内置平滑。
- Cinematic 的像素对齐在 zoom 后的视口空间执行；边界优先，极限位置允许不足一个像素的修正。平滑缩放仍会产生连续采样，不能保证任意分数 zoom 都呈现整数倍像素；沿用项目 nearest filter 和像素 snap 配置，不改动默认跟随手感。
- 相机根据视口 / 整数背景边界动态计算最小缩放，再按当前可见世界半尺寸限制中心。窗口变化保留演出请求的 zoom，并重新约束实际 zoom 和位置；不会重新使用 preferred_zoom 覆盖正在执行的缩放。
- Camera2D.offset 会绕过引擎 limits；震动因此同时约束当前平滑中心和跟随终点的可用偏移，并向零取整到视口像素。紧贴地图边缘时向外震动被裁掉；地图刚好填满视口时该方向没有震动空间。
- 震动仅改变世界相机 offset。HUD、对白等 CanvasLayer 保持 `follow_viewport_enabled = false`，不会随世界晃动。
- 节点聚焦期间目标离树或被删除：活动动作 FAILED，镜头恢复默认。已经完成并保持目标的 focus 不改变历史结果，通过 `camera_recovered(reason)` 通知恢复；其他仍在执行的动作 FAILED。
- Tween 绑定 Director，继承 Systems 的暂停模式；退出时主动 kill 并结算动作。相机移除同样取消全部活动请求；不存在等待已被 kill 的 Tween.finished 的挂起流程。

## Demo 与验收

编辑器 F6 运行 [camera_demo.tscn](../src/debug/camera/camera_demo.tscn)，或：

```sh
/Applications/Godot.app/Contents/MacOS/Godot --path . res://src/debug/camera/camera_demo.tscn
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tests/verify_camera_director.gd
```

1. WASD 正常移动，观察原有跟随。点击“播放 / 重播”，镜头聚焦右上奶茶店入口，停留 0.5 秒，回到玩家，轻震一次，恢复跟随；可反复播放。
2. 在聚焦、停留、返回或震动中点击“取消 / 重置”，应立刻回到默认跟随 / 缩放 / 零偏移；继续移动。
3. 在聚焦途中或停留时点击“删除聚焦目标”，应停止演出并安全恢复；再次播放自动新建 Marker2D。
4. 演出期间点击“退出 / 重建场景”，旧 MainGame 从场景树移除，新 MainGame 正常跟随；没有遗留 Tween 或失效目标访问。
5. 切换“开关震动”，关闭时轻震步骤无位移且能正常完成。震动时上方测试面板、HUD、对白保持固定；拖动窗口尺寸时地图边缘不露白。

Demo 是独立 Debug 场景，仅在 debug build 创建测试控制；不会加入正式入口。自动测试覆盖完整 Demo 流程、重播、取消、目标消失、重建，以及三通道替换、无效输入、暂停、实际 StoryDirector 取消、场景退出、四角边界、缩放、窗口变化和偏移地图。非 headless 运行同一测试并添加 `-- --capture` 可生成 `/private/tmp/camera-demo-follow.png` 和 `/private/tmp/camera-demo-entrance.png`。

实现依据 Godot 4.7 官方文档：[Camera2D 的真实屏幕中心、平滑、offset 与 limits](https://docs.godotengine.org/en/4.7/classes/class_camera2d.html)、[Tween 的绑定、替换、kill 与处理时序](https://docs.godotengine.org/en/4.7/classes/class_tween.html)、[CanvasLayer 的 follow_viewport_enabled](https://docs.godotengine.org/en/4.7/classes/class_canvaslayer.html)、[Node 的暂停和退出生命周期](https://docs.godotengine.org/en/4.7/classes/class_node.html)。实际验证引擎为 Godot 4.7.2。
