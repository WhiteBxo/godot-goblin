# RPG Maker Project1 原始素材快照

来源：`D:/taptapgamejam/map/Project1`，导入日期：2026-10-18。这里保留源项目当前保存的全部媒体素材、数据库及工程标识，便于后续编辑和重新转换。原文件名称、大小写、内容和换行符均保留，不替换用户原工程。

本目录含 `.gdignore`，Godot 不扫描、导入或直接运行这里的素材；运行地图使用单独的派生图集与场景。这里也不是可独立运行的 RPG Maker 工程副本：引擎 JavaScript、网页启动文件、开发工具、旧备份和 QA 图片未复制。

## 快照范围

| 原目录 | 原文件数量 | 原文件字节数 | 内容 |
| --- | ---: | ---: | --- |
| `img` | 789 | 99,742,780 | 所有原图、图块、角色、战斗图、标题、视差图、系统图和图块说明 |
| `audio` | 451 | 44,223,845 | 全部 OGG 音频 |
| `effects` | 175 | 2,764,671 | Effekseer 特效、模型与配套图片 |
| `fonts` | 2 | 1,014,504 | 原始 WOFF 字体 |
| `icon` | 1 | 4,931 | 原项目图标 |
| `movies` | 0 | 0 | 原项目空目录 |
| `imported-assets` | 16 | 1,703,231 | AD、FBM、WL 原素材包附加图片、来源清单及许可证 |
| `data` | 18 | 1,576,313 | 当前完整数据库、地图和图块组配置 |
| `game.rmmzproject` | 1 | 12 | 原工程标识 |
| **合计** | **1,453** | **151,030,287** | **32 个原目录** |

目录统一置于 `project1/`。空的 `movies/` 增加 `.gitkeep` 供 Git 保留，此标记不计入原文件数量或字节数。其他原文件按字节复制；本目录 `.gitattributes` 禁止 Git 对 `project1/` 快照执行文本换行转换。

`manifest.json` 记录每个原文件的 `source_path`、快照相对 `target_path`、字节数和 SHA-256，以及完整目录、分类统计与合成的空目录标记。`autotile_tables.json` 仅保存原 `js/rmmz_core.js` 的三组自动图块形状坐标表，注明该源文件的 SHA-256；不包含或运行整套 RPG Maker 引擎。

## 当前地图数据

以本次快照中的 `data/MapInfos.json` 和实际地图文件为准，源工程根目录的历史说明已经与当前编辑结果不一致。

| 文件 | 当前名称 | 格数 | 图块组 |
| --- | --- | --- | --- |
| `data/Map001.json` | 哥布林洞窟 | 50 × 55 | 30 |
| `data/Map004.json` | 哥布林酒馆｜裂牙 | 19 × 17 | 28 |
| `data/Map005.json` | 哥布林赌场｜黑齿 | 25 × 21 | 28 |
| `data/Map006.json` | 长老居所 | 17 × 15 | 31 |

原图块为 48 像素，地图数据各含 4 个图块层、1 个阴影层和 1 个区域层。四图当前均无事件、视差背景或自动播放音频；`System.json` 的玩家初始地图为 0，未设置可用初始位置。旧 Map002、Map003、Map007 不在当前数据库中，不从备份恢复。


## 重新归档和核验

工具：[archive_rpg_maker_assets.py](../../../tools/map/archive_rpg_maker_assets.py)。要求 Python 3.12 或更新版本，只使用标准库；任意工作目录均可运行，输入与输出必须显式指定。

在仓库根目录运行：

```powershell
python tools/map/archive_rpg_maker_assets.py --source D:/taptapgamejam/map/Project1 --output assets/rpg_maker/source
python tools/map/archive_rpg_maker_assets.py --source D:/taptapgamejam/map/Project1 --output assets/rpg_maker/source --verify
```

第一条命令只补充不存在的相同快照文件，随后核验；第二条命令只读核验原文件、派生表、元数据和空目录。已存在文件与源文件不一致时，工具在复制前拒绝执行，不提供覆盖参数。原工程继续编辑后，请先审查差异，并显式选择一个新的输出目录保存下一版快照；不要以旧源 JSON 覆盖已经手工调整的 Godot 地图。
