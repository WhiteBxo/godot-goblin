# 玩家精灵图

`player_sheet.png` 为用户于 2026-10-16 提供的原始透明 PNG（1086 × 1448），直接保存附件，未重绘、缩放或修改像素。旧的 `goblin.png` 已移除，洞穴素材工具不再生成旧玩家。

当前角色使用 `src/gameplay/player/player_walk_frames.tres`。旧的三帧动画资源 `player_frames.tres` 保留为原素材版本，不再作为玩家场景的显示资源。

- `player_walk_sheet.png`：使用内置 imagegen 根据用户原图修整的 1536 × 1024 精灵图，每个方向 8 个迈步阶段，方向依次为下、左、右、上。
- `player_idle_source.png`：imagegen 生成的四向中立站姿源图；`player_idle_atlas.png` 是使用 nearest 缩小并排版后的 800 × 300 派生图。
- `player_passing_source.png`：imagegen 单独修整的四向并脚姿势源图，采用 2 × 2 排列；`player_passing_atlas.png` 是同样规范到 208 像素高、躯干中心与脚底对齐的 800 × 300 派生图。
- `idle_*` 使用独立中立站姿，双脚自然落地；不再使用迈步过渡帧作为待机。
- `walk_*` 顺序播放 8 个帧，基准 12 FPS。第 3、7 帧明确使用独立并脚姿势，双腿回到躯干下方、两只鞋底同高；两个半周期复用该收拢姿势。相对时长为 `[1, 1, 1.25, 0.75, 1, 1, 1.25, 0.75]`，并脚比普通帧停留稍长，总周期保持 8 个时长单位。根据实际移动速度调整节奏，转向时保留迈步进度，不做帧混合。
- 行走通过 AtlasTexture 裁切，以棕色围裙的躯干中心对齐，统一到 200 × 300 的虚拟画布，脚底基线 y=294。待机缩放至 208 像素高并使用同一画布与基线。
- `player_sprite_material.tres` 使用 `player_cutout.gdshader` 丢弃 alpha 小于 0.9 的杂色并输出不透明轮廓；使用 nearest 采样，避免半透明边缘形成重影。
- `Visual` 节点缩放显示；脚部碰撞体独立配置，不随精灵缩放。
- 动画状态只取决于四向朝向和实际位移，停下或被墙挡住时切换到对应待机。

在 Godot 的 SpriteFrames 面板可直接修改动画。Inspector 暴露 `speed`（像素/秒）、`acceleration`、`deceleration`（像素/秒²）、`animation_speed` 和 `initial_facing`。斜向保持上一朝向轴；停止保留最后朝向。

可复现处理：先导入源图，再分别运行 `godot --headless --path . --script tools/prepare_player_frames.gd -- --prepare-idle` 和 `godot --headless --path . --script tools/prepare_player_frames.gd -- --prepare-passing` 生成待机、并脚图集；执行 `godot --headless --editor --path . --import --quit` 导入派生图；最后运行 `godot --headless --path . --script tools/prepare_player_frames.gd` 保存动画资源。处理代码只负责确定性切帧、锚点与 nearest 缩放，原始生成图保留不变。

验证：运行 `tests/verify_player.gd` 和 `tests/verify_milk_tea_shop.gd`；使用带渲染的 Godot 运行 `tests/verify_player_visuals.gd`，检查 36 个实际渲染姿势的透明度、基线与格子隔离。试玩主场景，用 WASD / 方向键八方向移动，观察加减速、四向步态、转向与中立待机；贴墙沿边移动、尝试穿过柜台/货架，并在交互弹窗打开时按移动键，确认角色停止。

内置 imagegen 的最终提示词及参考关系记录在 [生成记录](walk_generation.md)。

步态专项检查：打开 `src/debug/player_walk_preview/player_walk_preview.tscn` 按 F6，默认以 0.5 倍速并排播放四个方向。暂停后用「上一帧 / 下一帧」检查第 3、7 帧，两处必须显示双脚并拢。也可选择 0.25 或 1.0 倍速检查整个循环。此场景独立于主游戏入口，不修改角色物理、相机或输入配置。
