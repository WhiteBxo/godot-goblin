# 调试宿主、预览与 Release 边界

本目录保存独立试玩、调试展示、截图及开发工具，不混入正式业务入口。

## 开发与发布边界

- 使用 `OS.has_feature("debug")` 区分开发与 Release。Release 不创建调试节点，不响应调试按键、截图请求或布局参数。
- Debug 时可在内存把 `debug/developer_tools/enabled` 设为 false 关闭工具；该设置不能在 Release 启用工具。正式关卡初始化不能依赖调试组件。
- 调试控制组件挂 Systems，显示挂 DebugLayer；非交互 Control 使用 MOUSE_FILTER_IGNORE，空层不能截获输入。需要模态交互时接入已有 UIManager。
- 通用工具通过 Callable 或公开接口注入目标，不访问 MainGame、玩家或业务服务的私有字段 / 内部路径；洞穴布局对比、墙体切换和截图保留在洞穴专属组件。
- MainGame 启动 Release 时由项目侧停止 MCPRuntimeProbe 处理，避免无 debugger 时逐帧轮询，不改插件源码；组装处另读 [核心规范](../core/AGENTS.md)。

## 按调试目标继续阅读

| 目标 | 规范入口 |
| --- | --- |
| 通用 Console、角色工具与日志 | [developer_tools/AGENTS.md](developer_tools/AGENTS.md) |
| `cave_demo/`、`settlement/` 的地图预览 | [关卡规范](../levels/AGENTS.md) 及对应子关卡 |
| `story/`、`cinematic/`、`gameplay_bridge/` | [剧情规范](../core/story/AGENTS.md)；编排内容另读 [源稿规范](../../docs/design/AGENTS.md) |
| 角色、镜头、音频、对话、任务、见闻录等模块预览 | [核心模块索引](../core/AGENTS.md) 中对应服务；遵守正式模块公开契约 |
| 玩家、交互、房间、动作资源预览 | [玩法模块索引](../gameplay/AGENTS.md) 中对应功能 |
| UI、屏幕转场 | [UI 规范](../UI/AGENTS.md) |
| 模块化地图素材展示 | [地图素材规范](../../assets/map/AGENTS.md) |

- 可独立 F6 的宿主只做注册、依赖注入、演示触发与重播清理，不复制正式业务实现；需要注入的组件场景不能标成独立游戏入口。
- 测试 / Demo 音色、剧情和占位数据只由目标调试宿主加载，不在正式入口自动播放或装载；截图按所属说明放对应 `captures/`。
- 按 [验证分级](../../tests/AGENTS.md) 选择目标预览和模块检查。关闭开发工具不等于真实 Release 验证，未导出运行的构建不能声称 Release 通过；边界改动按风险选择 `verify_debug_build.gd`。
