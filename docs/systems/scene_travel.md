# 店铺与聚落进出

奶茶店 `src/core/main.tscn` 与洞窟聚落 `src/core/settlement.tscn` 已通过门口 E 交互双向连接。普通进出沿用同一 GameState 经营会话，不调用新游戏，不写剧情阶段或探索完成事实，不提供跨进程存档。

## 试玩

F6 运行 `src/core/main.tscn`（或 F5 新游戏），走到店内右下门口，看到「[E] 走出奶茶店」后按 E。黑场后出现在聚落奶茶店门外，朝下；回到门前看到「[E] 进入奶茶店」后按 E，回到店内门口，朝上。按住 E 不会立即反向切换，松开后再按可以返回。

制作一杯后出店再进店，仓库中的原料/成品和制作队列保持原值；接单、交付回执、奖励、钱包和剧情事实也保留。重载仍使用原默认出生点；直接 F6 聚落仍使用原聚落出生点，进门请求不会残留到下一次重载或新游戏。

## 配置和职责

| 组件 | 位置与职责 |
| --- | --- |
| `SceneExit` | `src/core/navigation/scene_exit.gd`，继承原 InteractionPoint；配置目标宿主 `.tscn` 和目标入口 ID，沿用 InputMap `interact` 和 ShopInteraction 的唯一目标派发 |
| `SceneEntrance` | `scene_entrance.gd`，Marker2D；位置为关卡本地世界像素中的玩家脚底位置，`facing` 配置到达朝向 |
| `SceneTravel` | `scene_travel.gd`，MainGame 创建到 Systems；预检目标、淡出、请求切换、目标淡入、失败清理；无 autoload 或全局待处理入口 |
| MainGame | 取得地图公开的出口/入口，装配转场，把 travel busy 纳入原输入锁；拒绝对白/演出、模态、暂停、玩家控制占用和 Bridge 不允许开始事件期间的进出 |
| GameEntry | `travel_to_scene(tree, destination)` 接受已预检且未入树的目标；与新游戏/回标题共用切换锁，由 `scene_changed` 释放；不重置状态、不解除暂停 |
| ScreenTransition | 挂在 TransitionLayer 40，仅负责黑场；待机及完成后层隐藏 |

地图的 `SceneExits`、`SceneEntrances` 保存在 `.tscn`，可在编辑器调整。`get_scene_exits()`、`get_scene_entrance(id)` 是公开接口；常规地点列表 `get_interaction_points()` 保持原用途，宿主合并出口参与同一交互选择。

| 方向 | 源出口 ID / 交互位置 | 目标入口 ID / 脚底落点 | 朝向 |
| --- | --- | --- | --- |
| 店内 → 聚落 | `shop_exit`，`(1123, 700)` | `shop_door`，`(5189, 8800)` | 下 |
| 聚落 → 店内 | `shop_enter`，`(5189, 8750)` | `street_door`，`(1123, 650)` | 上 |

聚落复用现有 `00_shop_entrance` 的门前位置；原 `00_shop` 信息交互设为不可用，避免与进店出口抢目标。地图画面、剖面室内、原有碰撞和店内三个设施点保留；本轮不重做两幅店铺素材的内部陈设，也不新增门洞阻挡。

## 切换和错误边界

请求首先检查资格并占用场景本地 busy，MainGame 同步锁住移动和交互；延迟调用加载并实例化目标。目标 MainGame 在入树前通过 `prepare_scene_arrival(id)` 校验宿主结构、玩家类型和命名入口，成功才淡出并调用 Godot 4.7 `change_scene_to_node`。目标 `_ready` 先落点和设朝向，再配置镜头；首次画面前盖黑，淡入后释放输入。

缺失资源直接拒绝；缺少入口、不支持的目标宿主、导航忙碌或黑场中被暂停/模态打断时，释放未入树目标、清除黑场、保留原场景和全部会话状态。可显示错误时复用地点弹窗提供重试提示，暂停中的错误不抢占暂停界面。关闭提示/继续游戏后可重试。busy 期间重复请求及暂停返回标题返回 Busy，完成或中断后可正常返回标题。

源宿主在淡出期间被重载/销毁，会释放它持有的未入树目标；交给 SceneTree 前解除本地所有权，避免离树清理误删目标。入口信息只保存在这一目标实例中，不写 GameState、不新增快照字段。

## 验证

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script tests/verify_scene_travel.gd
/Applications/Godot.app/Contents/MacOS/Godot --path . --script tests/verify_scene_travel.gd -- --capture
```

截图写 `/tmp/goblin_scene_travel_street.png`、`/tmp/goblin_scene_travel_shop.png`，不提交缓存。自动验证覆盖真实 E 键、重复/长按、命名落点/朝向/镜头、真实脚底碰撞和移动、往返状态完整相等、一次性交付、无订阅累积、错误目标、暂停/导航占用和源重载清理。店铺旧移动测试也将出口加入实体通路验证。

2026-10-17，Godot 4.7.2：进出 headless 开启/关闭开发工具各 163 项、Metal Forward+ 图形模式 165 项均为 0 失败，已查看两侧落点截图。回归通过：经营会话 48、标题导航 65、MainGame 73、转场 54、Gameplay Bridge 248、Debug 边界 97 项，以及原玩家、店铺和聚落测试（48,623 个可达物理采样点）。Bridge 初次沙箱运行无法写 `user://` 临时 JSON，允许测试临时文件写入后完整通过；headless 的系统证书读取诊断不影响断言。未执行 Release 导出。

第三阶段的首次出门揭示、阶段准入、观察点、有限探索、返回收束及 S04 续播留给后续剧情接线；进出本身不代表 S03 完成。

## Godot 4.7 依据

- [SceneTree.change_scene_to_node](https://docs.godotengine.org/en/4.7/classes/class_scenetree.html#class-scenetree-method-change-scene-to-node)：先配置实例；源立即离树，帧末释放后加入目标；`scene_changed` 在目标初始化后发出。
- [PackedScene.instantiate](https://docs.godotengine.org/en/4.7/classes/class_packedscene.html#class-packedscene-method-instantiate)：先创建离树节点层级供预检，不提前运行目标 `_ready`。
- [Node 生命周期](https://docs.godotengine.org/en/4.7/classes/class_node.html#class-node-private-method-ready)：子节点先 ready，宿主随后配置落点、镜头和本地服务。
