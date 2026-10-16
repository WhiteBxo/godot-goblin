# 2D 交互反馈

## 现有调用链与接入

`InteractionPoint` 仍用原 Area2D 的 player body 进出记录判定范围，`ShopInteraction` 是唯一目标选择与 dispatch 入口；没有增加检测 Area、全局交互管理器或新的玩法。订单板、仓库、制作台仍走原 StoryDirector 路由，未匹配的路由打开原 ShopUI，Esc 关闭并恢复移动。

MainGame 在 `World/EffectRoot` 创建场景内 `InteractionFeedback`，注入已有 ShopInteraction 和 AudioManager。没有修改 main.tscn、关卡场景、正式剧情 JSON 或 project.godot。玩家增加公开 `get_facing_vector()`，反馈组件不依赖玩家子节点。

新增对象沿用 `interaction_point.tscn`，将其交给宿主已有的 `ShopInteraction.configure(player, shop_ui, points, handler)`。设置：

- `display_name`：提示显示为 `[E] 对象名称`。
- `feedback_rect`：对象本地坐标的美术范围；默认围住既有菱形标记。家具美术位于地图背景时，可把该矩形调整到对应家具范围，不改变 Area2D 半径、碰撞或通行规则。
- `interaction_enabled`：对象级禁用；在范围内重新启用也会恢复目标。
- `success_sound`：可选 AudioManager catalogue ID，默认空；空值、缺失 ID 或未注入音频时静默跳过。
- `sound_bus`：`UI` 或 `SFX`，调用现有 `play_ui` / `play_sfx`，不建立新音频池。

自定义反馈只需订阅 `target_changed(point)` 和 `interaction_succeeded(point)`；前者传 null 表示清除。世界反馈组件通过 `configure(interaction, audio)` 接入任意世界特效容器，移除组件不影响交互。提示通过 `target_changed` 接到现有 `ShopUI.show_prompt`，视觉组件不监听输入、不调用 interact。

## 选择、触发与锁定

目标分数为距离减去面向投影乘 `facing_weight`（默认 24 世界像素）。挑战者必须比当前目标至少好 `switch_margin`（默认 12 世界像素）才切换；同分保持当前目标，初次同分按配置顺序。离开范围或禁用的目标立即失去保留资格。参数以世界像素为单位，按场景比例调整。

`_unhandled_input` 继续使用 InputMap 的 `interact`，让 GUI 先处理输入。触发前刷新目标并重新检查锁；拒绝键盘 echo、按住跨越解锁/关闭的重复事件、同步重入和同帧重复 dispatch。释放后才允许下一次按下。公开 `InteractionPoint.interact()` 仍供已有代码调用，接受相同的可用性、剧情锁、暂停、重入与同帧保护。

路由 Callable 兼容原 bool：false 打开原弹窗，true 表示已处理且成功。建议新宿主返回 Error：`OK` 才发成功 signal，`ERR_DOES_NOT_EXIST` 才 fallback，其他错误消耗请求但不播放成功反馈。MainGame 已使用 Error，避免忙碌或无效剧情被显示为成功。

MainGame 继续持有剧情/对白/ActorDirector 的锁定和原状态恢复逻辑；反馈不另造锁。额外检查玩家演出控制权、移动禁用、UI 是否打开、SceneTree 暂停、实例有效性和待删除状态。`set_input_enabled(false)` 同步清空目标；暂停通过 `NOTIFICATION_PAUSED` 清空 Always HUD，不需要把交互节点设为 Always。关闭弹窗不会覆盖仍有效的宿主禁用。

世界角框采用不抗锯齿的硬边线，成功时用 0.18 秒、两级整数外扩反馈；不改对象 material、modulate、像素边缘或碰撞。暂停会取消残留 pulse。ShopUI 提示复用已有 Fusion Pixel 12px 字体、1px 阴影、底部 24px 高度与左右 16px 留白，长名称省略；保留 640×360 与 integer scaling。对白/剧情/弹窗期间提示隐藏，非交互提示使用 MOUSE_FILTER_IGNORE。

## F6 试玩

打开 `src/debug/interaction/interaction_feedback_demo.tscn`，按 F6：

1. WASD 移动，接近三个对象，检查底部名称与单一角框；离开即消失。
2. 在订单板和仓库之间左右微移，目标不应频繁跳动；明确转身后切换。
3. E 打开既有弹窗，可听短音并看到角框轻闪；持续按 E 不重复触发。Esc 返回。
4. 顶部按钮切换暂停/禁用，启动实际对白或三秒 StoryDirector wait，再取消；提示和输入随锁恢复。
5. 删除当前目标，随后重置；不应留下角框、失效提示或报错。

Demo 独立组装真实组件，测试音来自已有 `AudioDemoTones`，演出 JSON 仅在该调试目录。按钮不抢键盘焦点；暂停后仍可点击“暂停”恢复。没有添加项目输入配置。

## 自动化验证

```sh
godot --headless --path . --script tests/verify_interaction_feedback.gd
godot --headless --path . --script tests/verify_milk_tea_shop.gd
godot --headless --path . --script tests/verify_dialogue.gd
godot --headless --path . --script tests/verify_story_director.gd
godot --headless --path . --script tests/verify_cinematic_integration.gd
```

新测试使用真实物理进出和实际输入事件，覆盖面向、边界抖动、反复进出、对象/全局禁用、释放重按、暂停、对白/演出取消、演出控制权、重入、Error fallback、缺失音效、UI/SFX、已排队删除/已删除目标、玩家删除和 controller 删除。既有回归验证三种原弹窗行为及 MainGame 的剧情控制权恢复。

## Godot 4.7 依据

已使用本地 Godot 4.7.2 验证。实现核对了以下版本文档：

- [Node：生命周期、process_mode、NOTIFICATION_PAUSED 与 unhandled input](https://docs.godotengine.org/en/4.7/classes/class_node.html)：暂停回调清除 Always HUD；世界与 controller 保持 Pausable。
- [InputEvent.is_action_pressed / is_echo](https://docs.godotengine.org/en/4.7/classes/class_inputevent.html)：使用 action 输入、拒绝按键重复，不依赖原始 E 键码做玩法逻辑。
- [CanvasItem.draw_line / queue_redraw](https://docs.godotengine.org/en/4.7/classes/class_canvasitem.html)：只在 `_draw` 绘制，关闭 antialiased，变换后取整端点。
