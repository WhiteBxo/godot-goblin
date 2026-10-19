# 玩家起停的身体反馈 L1（2026-10-20）

精灵本身没有改。这一轮只补“速度变化时身体有没有回应”，也就是手感里最底层的一档。

## 原来的状态

- 玩家是 `CharacterBody2D → Visual(Node2D) → AnimatedSprite2D`，128×160 帧、24 组四向动画（idle/walk/run/sneak/crouch_idle/throw），加减速 1800/2400 已经存在。
- 切走路 / 奔跑 / 潜行时，`_update_animation()` 按 `frame_progress` 续帧，相位不会跳。
- 缺的是：起步与刹车时身体完全不变形，走路也没有“迈步”的纵向节拍。

## 新增 `PlayerBodyFeel`

`src/gameplay/player/player_body_feel.gd`，挂在 `shop_player.tscn` 的 `Visual` 节点上。`rpg_player.tscn` 继承自 `shop_player.tscn`，所以聚落、酒馆、赌场、长老居所里的玩家自动也有，不需要逐个场景接线。

它只做三件事，全部只动 `Visual.scale` 与 `Visual.position.y`：

| 动作 | 表现 | 时长 |
| --- | --- | --- |
| 起步 | 纵向拉伸 4% / 横向收 2%，`TRANS_QUAD` 落回原尺寸 | 0.10s |
| 刹车 | 横向压扁 5% / 纵向缩 4%，同时整体落下 1px，`TRANS_BACK` 回弹 | 0.09s |
| 走路 | 按动画帧奇偶，身体整 1px 抬起；影子同步收 4% | 跟随步伐 |

支撑细节：

- **刹车在“速度骤降的那一帧”触发**（`SPEED_STEP = 8`），不是等减速结束。原来靠 `moving` 边沿判断，要等速度掉到 2 以下才回缩，实际要等 0.1–0.2 秒，看起来像延迟；现在松手当帧就有反应。
- **只用整像素**：位移经 `roundf` 取整，缩放幅度压到 5% 以内，`texture_filter` 又是 nearest，所以像素边缘不会抖动。
- **相对原尺寸**：`rpg_player` 把 `Visual` 缩到 0.5，脚本启动时记住 `_base_scale`，所有反应都乘在它上面，结束回到它而不是写死的 1。
- **不抢演出**：剧情接管（`is_performance_controlled()`）或移动锁（`movement_enabled == false`）时不播，直接回原尺寸，避免过场里人物莫名其妙被压扁。
- 不碰碰撞体、不碰动画状态机、不碰 `_update_animation()`，也不写 `velocity`。

## 验证

- 新增 `tests/verify_player_body_feel.gd`：32 项，跑**满尺寸与半尺寸两遍**——静止等于原尺寸、起步纵向变高、刹车横向变宽且整体下落、走路位移只在 `0` 与 `-1` 之间、剧情接管与移动锁后复位。
- `verify_player_visuals`：274 帧渲染通过，其中 `animated_sprite.global_scale == Vector2.ONE` 的断言仍在（静止必须严格回到原尺寸）。
- `verify_player`、`verify_player_actions`、`verify_player_preferences`、`verify_day1_playability`（108）、`verify_gameplay_bridge`（249）全部通过。
- 逐帧截图在 `.godot/captures/feel/`：`crop_idle` / `crop_start` / `crop_walk` / `crop_stop` / `crop_rest`，4 倍放大。实测起步时 `Visual.scale = (0.983, 1.034)`，刹车时 `= (1.0485, 0.9612)` 且 `position.y = 1`，0.09 秒后精确回到 `(1, 1)`。

## 还没做

- **L2**：脚步扬尘、转向瞬间的 1px 侧移。仍是纯代码，不需要美术。
- **L3**：转向帧、刹车姿势、抬脚帧。需要美术按现有 128×160 像素风格出帧，外加素材授权；用生成的图硬凑会和现有 24 组动画不一致，不做。

## 试玩

进店后按住方向键起步、松开刹车，注意身体在起停的第一帧就变高 / 变扁，脚落下 1px；走动时身体随步伐有 1px 起伏。半尺寸的聚落场景（`settlement.tscn`）表现一致。
