# 独立家具、道具与墙体素材库

本轮把已有聚落场景中的物品、建筑墙体整理为 **208 张独立透明 PNG + 208 个独立 Godot 场景**，共 26 组。原整图保留；本轮交付素材库，没有将原地图的底图去底并重新搭建。

![独立素材总览](captures/catalog.png)

## 包含内容

| 分类 | 数量 | 内容 |
| --- | --- | --- |
| 区域家具与小道具 | 136 | 酒馆、赌场、聚餐区、厨房、军营、长老房、祭坛、宿舍、仓库、奶茶店、种植、工坊、火塘、庭院，以及独立桌面物品和厨具 |
| 墙体与附属组件 | 48 | 灰石木梁、赌场深灰石、奶茶店粉刷墙三种材质，各含四向墙段、转角、门框、支柱、窗框、墙灯与横梁 |
| 原有通用道具 | 24 | 石块、石柱、箱桶、长凳、蘑菇、草药、灯杆、板车等，从已有透明图集中原尺寸提取 |

桌子、凳子、柜台和墙体已分开；杯子、瓶子、烛台、书卷、骰子、卡牌、金币、菜刀和砧板等另有独立小道具。轮盘桌保留家具本身的轮盘机构，储物架保留其库存陈设，火盆保留火焰；这些属于完整道具组合，而不是可逐零件拆开的模型。

原图是平面合成图，无法恢复原本不存在的图层。家具轮廓与背景粘连、被遮挡的位置，采用 imagegen 按原场景造型与新版奶茶店线条进行提取、补画，再透明化；这些图片不保证与原图逐像素相同。常用道具的 24 张则直接来自原有透明图集。

## 使用位置

- 透明图片：`assets/map/settlement/modular/<组名>/<物品名>.png`
- 可拖入场景的对象：`src/levels/settlement/modules/<组名>/<物品名>.tscn`
- 全部文件、真实尺寸与来源索引：`assets/map/settlement/modular/catalog.json`
- 每组带棋盘背景的检查图：`assets/map/settlement/modular/previews/`
- 原始图集与选用提示词：`assets/map/settlement/modular/source/`、`prompts/`

例如酒馆：

```text
modules/tavern/round_table.tscn
modules/tavern/wood_stool.tscn
modules/tavern/bar_straight.tscn
modules/tavern/bar_corner.tscn
modules/tavern/bottle_rack.tscn
modules/tavern/fireplace.tscn
modules/tavern/ale_barrel.tscn
modules/tavern/skull_banner.tscn
```

这些场景直接引用各自独立 PNG，不使用旧房间底图的 region 裁片。可分别移动、复制、删除和组合。每个对象以底部中心为落点，包含 `GroundAnchor`；桌台提供 `SurfaceAnchor`，墙直段提供端点参考。端点与桌面标记可在具体搭建时编辑。

图片主体像素经过透明化与完整轮廓裁切，不做拉伸或重采样；PNG 带 2 像素透明边距。所有对象的根节点和 Sprite2D 默认均为 scale=(1,1)，真实像素尺寸在索引中记录。预览海报的缩略显示不影响运行素材。

这批 PackedScene 是视觉组件，尚未配置每件物品的碰撞、交互、门动画或灯火动画。墙体是独立构件，尚未配置自动拼接 TileSet；摆放时使用位置与定位点对齐，不通过拉伸弥合接缝。正式替换地图时仍需结合主角校准布局、脚底碰撞和遮挡。

## Godot 检查场景

打开 `src/debug/modular_assets/modular_assets_gallery.tscn`，按 F6：

- Tab：下一组。
- WASD：平移视野。
- PageUp / PageDown：统一缩放查看。
- M：当前组居中。

画廊实际实例化独立对象，右侧放置现有主角作尺度参考。图库的相机缩放不改变 PNG 或对象比例。项目 F5 进入标题菜单，新游戏进入奶茶店；画廊独立 F6，不替换正式地图。

## 生成、透明化与复现

采用用户已授权的 CLI/API 模式，模型显式为 `gpt-image-2.5-sunburst`。图片请求由系统 imagegen 技能原 CLI 完成；`tools/art/imagegen_guarded_cli.py` 仅在当前进程接入本地配置及共享请求门禁，不修改系统脚本文件。

适配器每次读取 CODEX_HOME 下的 config.toml，按 model_provider 取得服务和凭据；当前进程注入 OPENAI_BASE_URL / OPENAI_API_KEY，SDK 自动重试设为 0。每个同步图片请求通过 CODEX_HOME/tools/api_concurrency.py 的 guarded_call，共用同一状态库；不吞掉 RequestUncertainError、不自动回收占用、不自动重试不明请求。该门禁仅覆盖通过此适配器发出的本机同步请求，不代表直接运行原 CLI、其他语言、远端设备或 Codex 客户端聊天已被限流。

`prepare_modular_briefs.py` 生成按原场景分类的图集提示词和布局参考。`extract_modular_assets.py` 根据真实透明轮廓进行连通域分组，完整保留跨过图集分格的物品，避免矩形裁切混入邻件或切断桌腿。原生透明度清理为硬边，裁出独立 PNG，同时写出对应场景和索引。

已保存选用源图集，重新提取无需再次请求图片 API：

```powershell
python tools/art/extract_modular_assets.py
```

如需选用外部生成目录，可显式传 `--raw-dir`。`guides/` 只用于生图布局参考，`previews/` 只用于检查；它们和原始图集、提示词已从游戏导出中排除。

## 验证

```powershell
godot --headless --path . --script res://tests/verify_modular_assets.gd
godot --path . --script res://tests/verify_modular_assets.gd -- --capture
```

上述测试已在 Godot 4.7.2 / Windows 上通过：208 个 PNG / PackedScene 对、26 组目录，0 failures。验证索引数量、每个独立场景的加载、每张独立贴图的实际尺寸、透明边角、原生比例、落点和画廊分组切换。另经像素检查，全部 PNG 的 alpha 仅为 0 或 255，四周留有透明边距；人工检查每组预览，没有相邻家具残片或切断的轮廓。检查图的棋盘背景不属于物品 PNG。

已保存酒馆、赌场与灰石墙体的实际 Godot 画廊截图。原聚落的 48,623 个可达采样点、入口、路线、桥梁、碰撞与交互回归检查亦通过。

实现参照 [Godot 4.7 Sprite2D 官方说明](https://github.com/godotengine/godot/blob/4.7-stable/doc/classes/Sprite2D.xml)：使用独立 Texture2D、centered=false 和整数锚点偏移，保持素材定位明确；[Node2D 官方说明](https://github.com/godotengine/godot/blob/4.7-stable/doc/classes/Node2D.xml) 定义实例的局部位置与变换。未执行游戏整包导出。
