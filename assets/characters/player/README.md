# 玩家动画与动作接口

洞穴与聚落 / 店铺玩家统一使用 `src/gameplay/player/player_actions_frames.tres`。新素材包含站立待机、走路、奔跑、潜行、蹲下待机、投掷，共 24 组四向动画、274 帧。NPC 的既有 idle/run 资源继续由控制器兼容。

## 操作

| 按键 | 动画表现 | 当前行为 |
| --- | --- | --- |
| WASD / 方向键 | `walk_*` | 普通移动，松开后播放最后朝向的 `idle_*` |
| 按住 Shift + 移动 | `run_*` | 以普通速度的 1.6 倍奔跑 |
| 按住 Ctrl + 移动 | `sneak_*` | 以普通速度的 0.5 倍潜行 |
| 按住 Ctrl，停止移动 | `crouch_idle_*` | 蹲伏待机，松开 Ctrl 恢复站立 |
| F | `throw_*` | 面向当前方向投掷一次，期间原地播放，结束后恢复移动 |
| E | 既有交互 | 保留原有交互入口 |

输入映射为 `move_*`、`player_run`、`player_sneak`、`player_throw`。Ctrl 优先于 Shift；两种速度倍率可在 PlayerController Inspector 配置，与开发者速度倍率相乘。潜行目前只改变移动速度和动画；投掷只提供动画与信号，物品消耗、投射物、伤害、敌人感知等留待后续开发。

## 后续开发接口

公开接口位于 `src/gameplay/player/player_controller.gd`：

- `set_locomotion_mode(Locomotion.WALK / RUN / SNEAK)` 与 `locomotion_changed(mode)`：设置 / 观察移动模式。真人输入每个物理帧同步按住状态；外部持续控制应沿用既有演出 owner 契约。
- `request_action(&"throw") -> bool`：尝试播放动作。未知动作、忙碌、移动锁定或演出接管时返回 false。
- `get_active_action() -> StringName`、`cancel_action()`：查询 / 中断当前动作。
- `action_started(action, direction)`：动作开始，direction 为开始时锁定的世界朝向向量。
- `action_triggered(action, direction)`：当前投掷进入索引 3 的出手帧时发出一次。后续可在此接入物品 / 投射物逻辑，不在逐帧播放回调中重复结算。
- `action_finished(action, cancelled)`：正常完成或取消。移动锁、瞬移、剧情接管均取消动作；取消后不补发出手信号，也不会自行解除宿主移动锁。

F 通过 `_unhandled_input` 响应，遵守 GUI 对输入的消费，忽略键盘长按重复事件。`accepts_player_input = false` 的 NPC 不读取真人按键。演出移动继续通过原有公开接口驱动，普通输入不会抢占演出 owner。

## 来源与生成

用户于 2026-10-17 提供 `主角动作合集(1).zip`。包内 PNG 按下表改为可读英文名，逐字节保存到 `action_sources/`；未将 `__MACOSX` 元数据作为素材。附件仅作为图像来源。授权信息未随包提供。

| 源文件夹 | down | right | up |
| --- | --- | --- | --- |
| 站立待机 → `idle` | IMG_4347.png | 合并图片 2.png | 合并图片.png |
| 走路 → `walk` | 合并图片.png | 合并图片 2.png | 合并图片 3.png |
| 奔跑 → `run` | 合并图片.png | 合并图片 2.png | 合并图片 3.png |
| 潜行 → `sneak` | 合并图片 3.png | 合并图片 2.png | 合并图片.png |
| 蹲下待机 → `crouch_idle` | 合并图片 2.png | 合并图片.png | 合并图片 3.png |
| 投掷 → `throw` | 合并图片 2.png | 合并图片.png | 合并图片 3.png |

普通图以 64×64 格、24 像素间隔，逐行读取非空格。正面站立待机的 4096×1640 图片以 5×2 等分格缩为 64×64，保持原比例；其他素材不改变原始帧格。左向通过镜像右向生成。每帧统一 nearest 放大 3.5 倍，放入 224×300 透明画布；同一方向的整段动画共用一个脚底锚点，保留逐帧起伏，不逐帧贴地。保留玩家现有 Visual 比例、碰撞及相机配置。

`player_actions_atlas.png` 和 SpriteFrames 均由 `tools/characters/build_player_actions.py` 生成。依赖 Python + Pillow，运行时只加载已导入的资源：

```powershell
# 从仓库中保留的源 PNG 重新生成：
python tools/characters/build_player_actions.py
# 首次接收附件时可额外传入：--archive "附件完整路径.zip"
godot --headless --editor --path . --import --quit
```

FPS：待机 8、走路 12、奔跑 18、潜行 12、蹲伏待机 10、投掷 12。投掷不循环，其他动作循环。转向 / 切换步态时按完整周期的比例保留步幅进度，支持各方向不同帧数。纹理关闭 mipmaps，使用既有 cutout 材质消除半透明边缘。

旧 `player_run_*`、`player_idle_sheet.png`、`player_run_atlas.png` 与旧动画资源作为历史素材保留，新玩家场景不再引用。旧生成工具 `tools/prepare_player_frames.gd` 只重建旧资源，不影响本次资源。

## 验证与试玩

- `tests/verify_player.gd`：两套玩家场景的移动、平滑启停、转向、移动锁、洞穴通行查询。
- `tests/verify_player_actions.gd`：按键、六类四向动作、速度、Ctrl 优先级、四向单次出手、完成 / 取消、剧情接管、NPC 输入关闭、GUI 输入消费。
- 带渲染运行 `tests/verify_player_visuals.gd`：遍历 274 帧，检查透明边缘、画布、比例、落脚范围，在系统临时目录生成 `player_actions_contact_render.png`。
- F6 打开 `src/debug/player_actions_preview/player_actions_preview.tscn`：WASD、Shift、Ctrl、F 试玩；左上角显示开始、出手与结束信号；P 锁定 / 解锁移动，可检查投掷取消。该预览仅在 Debug 组装。
- `src/debug/player_walk_preview/player_walk_preview.tscn`：保留四向奔跑慢放、暂停与逐帧检查。

官方 API 参考：[AnimatedSprite2D](https://docs.godotengine.org/en/4.7/classes/class_animatedsprite2d.html) 的 `frame_changed`、非循环 `animation_finished` 与 `set_frame_and_progress`；[Node 输入传播](https://docs.godotengine.org/en/4.7/classes/class_node.html#class-node-private-method-unhandled-input)；[SpriteFrames](https://docs.godotengine.org/en/4.7/classes/class_spriteframes.html) 的动画循环和 FPS 设置。

本次实现核对的官方 4.7 文档源码：[AnimatedSprite2D.xml](https://github.com/godotengine/godot/blob/4.7/doc/classes/AnimatedSprite2D.xml)、[Node.xml](https://github.com/godotengine/godot/blob/4.7/doc/classes/Node.xml)、[SpriteFrames.xml](https://github.com/godotengine/godot/blob/4.7/doc/classes/SpriteFrames.xml)。
