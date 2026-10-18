# 项目长期记忆

## 协作约定（用户偏好）

- **表现类反馈先修后验**：用户报告"动画反了 / 位置错了 / 手感不对"这类他直接看得见的问题时，按描述直接改、重跑测试、给渲染图或试玩入口，由用户确认。不要先去逆向校验"用户说得对不对"；仅在按描述改完仍不对、或改动会波及相邻功能时才深挖根因。
- 用户是画面与手感的最终判据，像素分析、几何偏移之类的佐证只能用于定位，不能用来否定用户的观察。
- 报告要短：说清根因、改动文件、验证结果、试玩入口即可，不铺陈排查过程。

## 本机环境

- Godot 4.7.2 控制台版：`D:\download\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe`（目录名带 .exe）。headless 测试用它；新增 `class_name` 前先跑 `--headless --editor --quit` 生成 .uid 与类缓存，跑完检查 `git status` 有没有无关 .tres 重存。
- Godot 编辑器开着时监听 9080 的 `godot_mcp` native 服务，可直接 `curl -X POST http://127.0.0.1:9080/mcp` 做 JSON-RPC（`tools/list`、`tools/call`）。改 `.tscn`/加节点优先走它而不是手写场景文件。

## 场景切换与房间

- 跨场景切换只有一条真实连边：奶茶店室内 ↔ 聚落店门口。聚落 16 个功能区是同一张 8192×9216 图上的剖面，`PaintedInterior` + `Walls` + y-sort `Foreground` 裁片，直接走入、不切场景。
- 新增可进入场景不需要改 `main.gd`：地图实现 `HOST_MAP_CONTRACT` 四个方法（`get_scene_entrance` / `get_scene_exits` / `get_spawn_position` / `get_camera_bounds`），宿主场景骨架照抄 `settlement.tscn`，就会走 `_initialize_room_map` 精简装配。
- 房间装配不建经营、章节、任务、地图面板和存档服务。房间内的剧情/任务/存档接线是已知未做项，别把它当成 bug。
- 测试里造 `SceneExit` 不能用 `.new()`（缺 `Label` 子节点会在 `InteractionPoint._ready` 报错），要用 `interaction_point.tscn` 实例化后 `set_script(scene_exit.gd)`。

## 玩家与角色

- **真正进游戏的是 `src/gameplay/player/shop_player.tscn`**（`main.tscn`、`settlement.tscn`、各 debug demo 与测试都用它）。`player.tscn` 是 CavePlayer 的大图版本（Visual scale 0.13），当前 `src/` 内已无引用。改玩家表现前先确认目标是哪一个。
- shop_player 像素基准：帧 128×160、内容 bbox 54×114、脚在 y=0、头顶 y=-114、双手在 y≈-52、手部 x≈±24。
- 角色朝向靠四套独立动画（`idle_left` / `walk_right` …），**没有任何 `scale.x` 镜像**，所以依赖朝向的挂点必须按朝向分别配置，不能靠翻转自动推导。
