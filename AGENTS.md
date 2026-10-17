# Godot Goblin 通用开发规范

本文件适用于整个仓库。用户当前任务的明确要求优先于默认约定；模块细则见下方索引。

## 按任务读取规范

- 开始前检查 Git 状态，先读本文件，再沿目标文件的目录层级读取适用的各级 `AGENTS.md`；子目录规范在父目录通用规则之上补充模块约束。
- 根据下表定位模块，进入模块后继续按其索引阅读。跨模块修改要读取双方规范；只读本次涉及的文档、代码、场景与配置，不预读所有模块。
- 索引中的“还需阅读”同样适用于目录之外的调用方和配套资源。例如编排 Markdown、调整剧情 JSON 或修改宿主绑定，都先读剧情编排规范。
- 新增模块时，只有存在独立职责或关键契约才增加模块 `AGENTS.md`，并更新直接上级索引；不复制整份通用规则，也不把模块细节堆回根目录。

| 修改范围 / 任务 | 规范入口 |
| --- | --- |
| 游戏入口、MainGame、GameState、场景内服务与核心系统 | [src/core/AGENTS.md](src/core/AGENTS.md)，内含剧情、对话、角色、镜头、音频、任务、交易、导航和见闻录索引 |
| 玩家、NPC、交互、采集、制作、库存与房间表现 | [src/gameplay/AGENTS.md](src/gameplay/AGENTS.md)，继续按功能进入子模块 |
| 关卡、地图布局、出生点、TileMap 与通行规则 | [src/levels/AGENTS.md](src/levels/AGENTS.md)，内含店铺、聚落和洞穴索引 |
| HUD、菜单、弹窗、暂停、UI 管理与屏幕转场 | [src/UI/AGENTS.md](src/UI/AGENTS.md) |
| 共享 Resource、运行时 JSON、TileSet 与导出资源 | [src/resources/AGENTS.md](src/resources/AGENTS.md) |
| Shader、遮挡与材质参数 | [src/shaders/AGENTS.md](src/shaders/AGENTS.md) |
| 独立试玩、截图、开发者面板与 Debug / Release 边界 | [src/debug/AGENTS.md](src/debug/AGENTS.md) |
| 图片、角色、地图、音频、字体及导入设置 | [assets/AGENTS.md](assets/AGENTS.md)，地图另读 [assets/map/AGENTS.md](assets/map/AGENTS.md) |
| 文档分类、维护与链接 | [docs/AGENTS.md](docs/AGENTS.md) |
| 自然语言剧情编排、局部 Beat、剧情源稿与编排产物 | [docs/design/AGENTS.md](docs/design/AGENTS.md) 与 [src/core/story/AGENTS.md](src/core/story/AGENTS.md) |
| 命令行工具、素材处理与剧情校验工具 | [tools/AGENTS.md](tools/AGENTS.md) |
| 选择验证级别、运行或修改测试 | [tests/AGENTS.md](tests/AGENTS.md)；纯文档按下方规则局部检查 |
| 第三方插件、插件配置与运行时边界 | [addons/AGENTS.md](addons/AGENTS.md) |

## 项目与模块边界

- 项目使用 Godot 4.7 系列和 GDScript；引擎、入口、渲染器、autoload、插件及输入配置以 `project.godot` 为准，历史文档不覆盖实际配置。
- 开发 Godot 功能前，查阅与项目引擎版本匹配的 [Godot 官方文档](https://docs.godotengine.org/en/stable/)，只核对本次节点、API、生命周期及配置的用法、限制和版本差异；汇报影响实现的关键文档链接。
- 入口负责组装，地图负责地图，角色负责自身行为，UI 负责显示与界面交互。功能场景应能独立配置与验证，避免一个脚本同时承担多个模块职责。
- 模块内部可以引用自己的子节点；跨模块通过公开方法、signal、Callable 或共同父场景传入依赖，不依赖对方内部节点层级。
- 普通玩法逻辑留在对应场景；确有跨场景生命周期需求的共享状态才使用 autoload。调试、截图和素材处理放在专用模块或工具中。
- 同一功能的场景和脚本就近放置；关卡专属数据跟随关卡，共享定义放 `src/resources/`；工具、文档和测试分别放 `tools/`、`docs/`、`tests/`。按需创建目录，保留仍需追踪的 `.gitkeep`。

## 命名、文件与配置

- 新文件、目录、变量与 function 使用 `snake_case`；节点和类使用 `PascalCase`，常量使用 `UPPER_SNAKE_CASE`。`AGENTS.md`、`README.md` 等约定文件名保留；现有 `src/UI/`、`src/levels/milkTea/` 等路径大小写不随任务重命名，引用必须一致。
- GDScript 使用 Tab 缩进，优先明确类型注解或类型推断，按 Godot 生命周期组织回调。
- 文本使用 UTF-8、LF、一个末尾换行符，不留行尾空格。格式调整仅限本次相关内容。
- 移动或重命名脚本时保留对应 `.uid`，同步检查场景、资源及脚本中的路径引用。
- `.godot/` 缓存不提交，也不作为源资源依赖。素材、共享数据与文档的额外规则分别见对应模块规范。
- 修改 `project.godot` 只调整任务必要的配置，核对 autoload、插件和 InputMap 的依赖。

## 执行、验证与交付

- 默认小步自主完成：完成任务、执行必要验证、创建对应 commit 后汇报。用户要求只分析、不写代码、不运行或分步确认时，按其范围和节奏执行。
- 保留用户已有改动；不夹带目录重排、全项目格式化、插件升级或无关玩法调整。
- 开始验证前，用一两句说明“本次风险点 → 要执行的检查”。代码、场景和数据按 [tests/AGENTS.md](tests/AGENTS.md) 选择最低必要级别，有明确风险才升级。
- 纯文档只检查内容、Markdown 链接、格式与 Git diff，不运行引擎或项目测试。文档中的命令是候选清单，不能直接当成本次必跑清单。
- 如实报告改动、相关文件、实际检查结果、未执行项及原因、无关历史失败和 commit。涉及画面、手感或交互时，给出试玩入口、步骤和可观察结果。
- 每次改动完成后必须创建一个完整、可回滚的 commit。提交前检查 diff 和暂存范围，只暂存本次文件，不混入用户已有改动。
- 提交信息使用清楚的 `feat`、`fix`、`refactor`、`docs` 或 `chore` 前缀；是否 push 由用户任务决定，不因本地提交自动推送。
