# godot-goblin

Godot 4.7 / GDScript 项目，当前默认进入新版洞窟聚落：15 个功能区域与奶茶店共用连续平地，保留独立可编辑的建筑、外墙、碰撞和前景遮挡。

使用 Godot 打开 project.godot，按 F5 运行。WASD / 方向键移动，E 查看地点与店内设施，Esc 关闭。开发模式下 M 切换全图与跟随视角，Tab 切换两天剧情动线和补给线。地图说明、预览和验证见 [新版聚落说明](docs/settlement/README.md)。

原奶茶店 MVP 保留在 `src/core/main.tscn`，旧洞穴轮廓 demo 保留在 `src/debug/cave_demo/cave_demo.tscn`，可打开对应场景后按 F6 单独运行。

独立家具、道具与墙体库提供 208 张透明 PNG 和独立场景。打开 `src/debug/modular_assets/modular_assets_gallery.tscn` 后按 F6 检查；使用方法与素材清单见 [模块化素材说明](docs/modular_assets/README.md)。

开发约定见 [AGENTS.md](AGENTS.md)；模块结构、素材来源、资源处理及验收命令见 [洞穴 demo 接入说明](docs/cave_demo/README.md)。

剧情镜头系统的公开 API、Signal、独立 Demo 与验证方式见 [CameraDirector 说明](docs/camera_director.md)。
