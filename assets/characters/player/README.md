# 玩家精灵图

`player_sheet.png` 为用户于 2026-10-16 提供的原始透明 PNG（1086 × 1448），直接保存附件，未重绘、缩放或修改像素。旧的 `goblin.png` 已移除，洞穴素材工具不再生成旧玩家。

`src/gameplay/player/player_frames.tres` 通过 `AtlasTexture` 切帧，无需额外生成图片。四行依次为下、左、右、上，每行三帧；列起点为 166、443、720，行起点为 60、404、744、1084，每帧 200 × 300 像素。裁切范围保留透明边距，以躯干中心和脚底对齐。

- `idle_*` 使用中间帧；附件没有独立的呼吸待机帧。
- `walk_*` 按中间、左、中间、右循环，8 FPS，覆盖两次交替迈步。
- `Visual` 节点缩放显示；脚部碰撞体独立配置，不随精灵缩放。
- 动画状态只取决于四向朝向和实际位移，停下或被墙挡住时切换到对应待机。

在 Godot 的 SpriteFrames 面板可直接修改动画。Inspector 暴露 `speed`（像素/秒）、`acceleration`、`deceleration`（像素/秒²）、`animation_speed` 和 `initial_facing`。斜向保持上一朝向轴；停止保留最后朝向。

验证：运行 `tests/verify_player.gd` 和 `tests/verify_milk_tea_shop.gd`。试玩主场景，用 WASD / 方向键八方向移动，观察加减速、四向行走与停下待机；贴墙沿边移动、尝试穿过柜台/货架，并在交互弹窗打开时按移动键，确认角色停止。
