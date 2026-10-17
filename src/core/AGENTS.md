# 核心组装与共享状态

适用于 `src/core/`。这里负责入口、跨模块协调和场景内核心服务，具体服务另有规范；不要在 MainGame 堆放业务实现。

## 子模块与配套规范

| 修改内容 | 继续阅读 |
| --- | --- |
| 剧情调度、Gameplay Bridge、Day 1 协调、剧情音频适配 | [story/AGENTS.md](story/AGENTS.md) |
| Actor 注册、生成与动作 | [actors/AGENTS.md](actors/AGENTS.md) |
| 对话加载与运行 | [dialogue/AGENTS.md](dialogue/AGENTS.md) |
| 镜头表现 | [camera/AGENTS.md](camera/AGENTS.md) |
| 音频播放与动作 | [audio/AGENTS.md](audio/AGENTS.md) |
| 任务目录、投影与交付 | [tasks/AGENTS.md](tasks/AGENTS.md) |
| 钱包与原子交易 | [economy/AGENTS.md](economy/AGENTS.md) |
| 场景出入口与切换 | [navigation/AGENTS.md](navigation/AGENTS.md) |
| 见闻录状态 | [chronicle/AGENTS.md](chronicle/AGENTS.md) |
| 日程阶段（白天 / 夜晚）与出店门控 | [schedule/AGENTS.md](schedule/AGENTS.md) |

修改入口组装时，还要读所接入服务的规范；涉及界面层与输入锁读 [UI 规范](../UI/AGENTS.md)，涉及开发组件或 Release 边界读 [Debug 规范](../debug/AGENTS.md)。

## MainGame 场景骨架

`src/core/main.tscn` 的根节点与 script class 均为 `MainGame`，类型为 `Node`；`settlement.tscn` 复用该宿主。正式启动入口以 `project.godot` 为准，不把宿主场景误当成固定启动入口。

```text
MainGame
├─ Systems
│  ├─ DeveloperTools（Debug 运行时创建）
│  └─ CaveDemoController（洞穴专属 Debug 组件）
├─ World
│  ├─ LevelRoot
│  ├─ EntityRoot
│  └─ EffectRoot
├─ HudLayer
├─ PopupLayer
├─ PauseLayer
├─ TransitionLayer
└─ DebugLayer
   ├─ DeveloperPanel（Debug 运行时创建）
   └─ DebugOverlay（洞穴专属 Debug 显示）
```

- 此图表示职责容器，服务按需装配；新内容挂到对应容器。场景内管理与协调放 `Systems`，地图放 `LevelRoot`，动态角色放 `EntityRoot`，世界特效放 `EffectRoot`。
- MainGame 使用 `Always`；Systems、World 使用 `Pausable`。确需暂停期间运行的服务单独设 `Always`，不改变整个世界的处理模式。
- 五个屏幕容器保持 CanvasLayer 生命周期；层号、跟随视口和输入约定以 [UI 规范](../UI/AGENTS.md) 为准。既有插件 autoload 不迁入 Systems。
- MainGame 取得引用、注入依赖并初始化，通过公开 getter 提供关卡、玩家和各服务；跨模块不要查其内部节点路径。
- 地图与玩家的初始化顺序保持为：选择布局、绑定玩家移动查询、设置出生点与跟随镜头、启动调试组件。正式关卡初始化不能依赖调试节点。
- 玩家移动与模态 / 演出输入锁由共同宿主协调，不能在各子系统独立恢复移动为 true；接入服务先核对已有锁定条件。
- Release 不创建调试组件、不处理调试按键或截图 / 布局参数。MainGame 在 Release 停止 MCPRuntimeProbe 处理，保留插件源码；细则见 Debug 规范。

## GameState 与整局生命周期

- `game_state.gd` 是已有 GameState autoload，负责跨场景事实和经营会话；它不处理 UI、输入或剧情表现，不为新系统创建第二份状态。
- 状态修改经公开 API，保持快照复制、整体 reset / restore、先提交完整状态再通知的契约；不要让同步订阅者看到半提交状态或恢复时重播完成事件。详细接口见 [GameState](../../docs/systems/game_state.md)。
- 新游戏显式重置整局；普通进出场景复用会话。共享库存、制作和钱包服务沿用 GameState 的公开 getter，不因场景重建创建新副本。见 [统一经营会话](../../docs/gameplay/business_session.md)。
- `game_entry.gd` 的新游戏、返回标题与启动配置按 [启动指南](../../docs/guides/game_entry.md) 核对；进出场景的交接另读导航规范。

验证按 [分级规范](../../tests/AGENTS.md) 选择 `verify_main_game.gd`、`verify_game_state.gd`、`verify_game_entry.gd` 或直接受影响服务的检查；涉及跨模块状态或生命周期契约时升级完整回归。
