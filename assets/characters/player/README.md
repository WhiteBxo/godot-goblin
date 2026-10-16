# 玩家素材与跑步动画

当前玩家（洞穴、奶茶店）统一使用 `src/gameplay/player/player_run_frames.tres`，移动播放 `run_down/left/right/up`，停止播放对应 `idle_*`。旧的生成走路图、并脚补帧、生成待机图及其动画资源已删除。

## 用户素材来源（2026-10-16）

直接复制附件，源 PNG 不修改：

| 文件 | 原附件标识 | 布局 |
| --- | --- | --- |
| player_run_down.png | 8053c82b-6fb3-4fd5-9df0-b1aed067c23a | 256×256，4×4，向下跑 |
| player_run_up.png | ef4b9e85-f738-4409-844e-66ebae9b76c3 | 256×256，4×4，向上跑 |
| player_run_left.png | 1fa75a5c-c7a4-45ce-be5c-b9c64448dda6 | 256×256，4×4，向左跑 |
| player_run_right.png | f9845727-2154-4f9a-b1fc-b0efa2d78d8b | 256×256，4×4，向右跑 |
| player_idle_sheet.png | 6889b9b7-47c4-4114-b3a6-6142330c1777 | 192×192，3×3，四向待机 |

跑步每方向 16 帧，按行从左到右、从上到下，24 FPS 等时长循环；根据实际位移调整播放速度，转向保留进度。保留素材的身体起伏，不对每帧重新贴地，不插入旧动作。待机选取源图的下 `(1,2)`、左 `(0,1)`、右 `(2,1)`、上 `(1,0)` 格（从零计数）。

`player_run_atlas.png` 是可复现派生图：每格 64×64 使用 nearest 放大至 224×224，居中放入 200×300 画布，跑步顶部 y=77，待机 y=81；脚底最大 y=294。现有 Visual 比例、脚部碰撞与镜头配置继续使用。四个跑步方向各一行，待机四格放在第五行。透明源素材经现有 cutout 材质输出硬透明轮廓。

## 重新生成与检查

1. `godot --headless --path . --script tools/prepare_player_frames.gd -- --pack`
2. `godot --headless --editor --path . --import --quit`
3. `godot --headless --path . --script tools/prepare_player_frames.gd`

该工具仅在开发时切帧与排版，运行时直接加载已导入的图集。原始 `player_sheet.png` 与旧 `player_frames.tres` 为历史资源，不由玩家场景引用；旧资源中已有的本地编辑保留。

运行 `tests/verify_player.gd` 检查移动、转向、待机和锁定；带渲染运行 `tests/verify_player_visuals.gd` 检查 68 帧的切帧、透明边缘与起伏范围。F5 试玩；打开 `src/debug/player_walk_preview/player_walk_preview.tscn` 按 F6，可慢放或逐帧检查四方向跑步。

官方 API：[SpriteFrames](https://docs.godotengine.org/en/4.7/classes/class_spriteframes.html) 设置帧序列、FPS 和相对时长；[AtlasTexture](https://docs.godotengine.org/en/4.7/classes/class_atlastexture.html) 用 region 切帧并开启 filter_clip 防止邻格渗色。
