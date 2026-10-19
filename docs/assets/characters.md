# 游戏人物与美术接入

主角保留 `src/gameplay/player/shop_player.tscn`、现有四向动画与对白立绘。新增 8 个独立 NPC 场景位于 `src/gameplay/characters/`，使用全部 31 张已入库 NPC 图集；原始插画、表情整图和同人物不同表情不另造人物。围裙男子对应主角，哥布林插画对应胖哥布林；现有对白立绘接入保持不变。

身份依据 `docs/design/day_01_story_flow.md` 的第一天人物关系和聚落现有功能区域；不新增对白、任务、剧情顺序或角色真名。

| Actor ID / 场景文件名 | 人物 | 聚落预置位置（世界像素） | 剧情 / 用途 |
| --- | --- | --- | --- |
| `fat_goblin` | 胖哥布林 | (5400, 8620)，奶茶店外 | 提供地图、委托取得格里芬之血的关键人物 |
| `common_goblin` | 普通哥布林 | (5500, 8910)，店外街道 | 居民、背景顾客 |
| `guard` | 守卫 | (4410, 6250)，居所方向道路 | 可复用于夜间醉酒守卫演出；未自动触发剧情 |
| `guard_captain` | 守卫长 | (7130, 3120)，训练区外 | 武装人员，专属剧情尚待设计 |
| `elder` | 长老 | (6410, 1730)，长老居所外 | 格里芬信仰的权威代表 |
| `chef` | 厨师 | (7290, 6650)，厨房外 | 厨房备料人物，专属剧情尚待设计 |
| `tavern` | 酒馆人物 | (3680, 4910)，酒馆外 | 第二天酒水线索的候选人物；未擅自确定姓名和身份 |
| `casino` | 赌场人物 | (6690, 4920)，赌场外 | 第二天食材线索的候选人物；未擅自确定姓名和身份 |

这些是可编辑的聚落常驻展示位置，保存在 `src/core/settlement.tscn` 的 `World/EntityRoot`，不是第一天各阶段的出场排程。正式剧情应按剧情数据决定何时显隐、生成和移动，例如长老夜间外出时由剧情隐藏/移动。NPC 无玩家输入；可见角色脚底占层 3 并阻挡玩家，隐藏时退出该层，自身只与地图墙体 / 家具碰撞。普通来客 AI、巡逻和寻路未实现；专用潜入感知与投掷组件已有，正式配置仍待绑定。

## 动画与源图

`character_catalog.json` 保存人物身份、源图、有效帧数、FPS 与动画映射；`*_frames.tres` 为可在编辑器查看的 SpriteFrames，使用 AtlasTexture 引用原图，不重编码图片。脚底为角色原点，碰撞只覆盖脚部；普通图集 64 像素帧等比放大 2 倍，守卫长 128 像素帧保持 1 倍，默认画布为 128 世界像素，可见人物约 110 像素高；这套基础场景继续供独立奶茶店与角色预览使用。RPG Maker 地图当前使用 `rpg_common_goblin.tscn`、`rpg_guard.tscn`、`rpg_tavern.tscn`、`rpg_casino.tscn` 四个继承场景，将 Visual、阴影、脚部碰撞减半，最终画布为 64 世界像素，脚底锚点与根节点缩放不变。RPG 正式宿主的玩家镜头从 0.5 拉近为 1.0，补偿人物减半后的屏幕尺寸。NPC 演出仍使用既有指令中的世界速度、位置与计时，不把剧情移动距离或时长按美术倍率机械缩放。守卫长待机图与走路图存在原素材的造型差异，保留原图。

- 普通图集为 64×64 帧、88 像素间隔；守卫长走路为 128×128 帧、152 像素间隔。6 列，逐行播放。尾部空格排除，每张有效帧数为 9～16。
- 播放接口沿用 PlayerController 的 `idle_down/left/right/up` 与 `run_down/left/right/up`。走路 8 FPS，待机 6 FPS。原包未给出 FPS，当前为可调的接入值。
- 只有一侧的素材采用左右镜像；普通哥布林和长老的侧面源图朝左，其他侧面源图按右侧使用。守卫长为接近侧面的斜向图，尚缺真正侧面行走图。
- 守卫没有独立待机图，各方向取对应行走首帧。其他人物缺失的方向待机同样取行走首帧。
- 胖哥布林只有待机素材：正面/侧面待机已接入，移动采用对应静帧；背面使用正面 fallback，尚缺四向行走及背面素材。`emote_laugh` 收录第三张表情动画，未自动插入剧情。
- 普通哥布林在生成时独立以 50% 概率选择背包版或无背包版，实例的行走、转向、待机与显隐保持该外观。`common_goblin.tscn` 及其 RPG 继承场景都适用；`appearance` 默认 `RANDOM`，也可在编辑器固定外观。背包版沿用原图集；无背包版复用 `goblin_actions/goblin_frames.tres` 的走路帧，映射为四向 `run_*`（8 FPS）和对应首帧 `idle_*`，侧面源图朝右，向左镜像。无背包版没有独立待机动画。
- 长老两张待机分别用于正面、侧面；守卫长原待机额外保留 `idle_variant`。所有原图均被引用。

重新生成帧资源（Python 3 标准库）：

```sh
python3 tools/characters/build_character_frames.py
```

生成器只重建 SpriteFrames，不覆盖场景身份、聚落位置或图片。调整源图/帧数先修改 catalog，然后重建资源。

## 场景与演出

主场景组装时将 EntityRoot 中的 SettlementCharacter 按 `actor_id` 注册给现有 ActorDirector。各 NPC 场景根继承 PlayerController，`accepts_player_input = false`，可直接用 `actor_spawn` 实例化到其他宿主。复用同一场景生成多个居民时，为各个实例提供不同注册 ID；聚落预置实例的 actor_id 必须唯一。

Godot F6 打开 `src/debug/characters/character_gallery.tscn`：同时查看 8 类人物，自动循环四向移动、停止待机，观察镜像、脚底和人物比例。F6 打开 `src/core/settlement.tscn`：出生点向右可看到胖哥布林，出门继续向右下可看到普通哥布林；其余人物在表中对应区域外。NPC 不跟随 WASD；行走时应观察脚底碰撞与门口通行，不把动画身体范围当碰撞范围。

## 验证

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 --script res://tests/verify_characters.gd
# 带图形环境保存 /tmp/godot_character_gallery.png
/Applications/Godot.app/Contents/MacOS/Godot --path . --fixed-fps 60 --script res://tests/verify_characters.gd -- --capture
```

测试实际加载各场景，核对全部动画帧非空/不越界、31 张源图覆盖、NPC 输入隔离、四向朝向、真实 ActorDirector 移动、聚落注册及出生点地图碰撞。测试不会把缺失方向的 fallback 误报为已有完整美术。

实现核对的 Godot 4.7 官方文档：[SpriteFrames](https://docs.godotengine.org/en/4.7/classes/class_spriteframes.html)（帧序列和 FPS）、[AtlasTexture](https://docs.godotengine.org/en/4.7/classes/class_atlastexture.html)（region 裁取及 filter_clip 防止邻格渗色）、[AnimatedSprite2D](https://docs.godotengine.org/en/4.7/classes/class_animatedsprite2d.html)（flip_h、offset 与动画播放）。

本次在 Godot 4.7.2 验证：人物 headless 1295 项通过；Metal Forward+ 实际渲染 1296 项通过（含截图），中文字体与八类人物画面已检查；ActorDirector 165 项、StoryDirector 163 项回归通过；聚落回归通过，验证 16 个区域、剧情锚点、桥梁、真实移动和墙体（48623 个可达采样点）。headless editor 资源导入成功；退出时存在沙盒外 editor_settings 无法保存和编辑器资源清理提示，未出现本次人物资源解析错误。

## 普通男、女顾客（2026-10-17）

用户附件 `普通顾客走路和待机(1).zip` 中的 12 张 PNG 已逐字节导入
`assets/characters/npc/human_customer/` 和 `human_customer_female/`；忽略
`__MACOSX` 元数据。附件由用户提供供本项目使用，未附独立许可证文件，授权范围未另行声明。
源图不裁剪、不重编码，原附件路径记录在
`src/gameplay/characters/customer_catalog.json` 的 `source_entry` 中。

`human_customer.tscn` 使用红衣男顾客替换原主角动画及蓝色染色，正式店铺已有的
`human_customer` 自动使用新图。`human_customer_female.tscn` 提供黄裙女顾客，
可独立复用，尚未加入剧情出场排程。普通哥布林仍使用自己的素材。

两套资源均提供 `run_*`（8 FPS，现有 NPC 行走接口）和 `idle_*`（6 FPS）四向循环，
左右共用侧面图，由 `SettlementCharacter` 镜像左向。每格 64×64、步长 88，
逐行取有效帧，排除末尾透明格；保持原有 2 倍等比显示及脚底锚点。

| 角色 | 走路 下 / 右 / 上 | 待机 下 / 右 / 上 |
| --- | --- | --- |
| 男顾客 | 8 / 11 / 12 | 7 / 7 / 9 |
| 女顾客 | 16 / 16 / 8 | 13 / 9 / 11 |

从原 ZIP 重新导入并生成（Python 3 标准库；将附件路径替换为实际路径）：

```sh
python tools/characters/build_character_frames.py --catalog src/gameplay/characters/customer_catalog.json --archive "普通顾客走路和待机(1).zip"
```

只重建两套帧资源时省略 `--archive`。默认不加参数仍只重建原 NPC catalog。
已有源文件内容与 ZIP 不同会拒绝覆盖。

F6 打开 `src/debug/characters/character_gallery.tscn`，右下角两位顾客自动循环
右、上、左、下行走与停止待机；观察朝向、左右镜像、完整循环与脚底位置。
`tests/verify_characters.gd` 同时检查这两位顾客的帧边界、非空帧、输入隔离、
四向朝向与镜像、ActorDirector 真实移动。

此次切帧依据官方 4.7 [AtlasTexture](https://docs.godotengine.org/en/4.7/classes/class_atlastexture.html)
的 `region`、`filter_clip`，循环与帧率沿用
[SpriteFrames](https://docs.godotengine.org/en/4.7/classes/class_spriteframes.html)，
侧向镜像沿用 [AnimatedSprite2D](https://docs.godotengine.org/en/4.7/classes/class_animatedsprite2d.html) 的 `flip_h`。

## 赌场侍卫（2026-10-19）

用户附件 `侍卫2(1).zip` 已接入独立 `casino_sentry`，按[最新聚落补充稿](../design/settlement_dialogue_supplement_revised.md)的“赌场：侍卫”确定身份，正文别名为“护卫”。基础场景 `src/gameplay/characters/casino_sentry.tscn`、RPG 场景 `rpg_casino_sentry.tscn`、独立 `sentry_catalog.json` 和 SpriteFrames 均已配置；不改变 `guard`、`guard_captain` 或四个潜入守卫的身份和素材。

正式赌场继承场景在已有 `casino_guard_a` 锚点 `(120, 552)` 放置一名侍卫，随宿主注册到 ActorDirector，使用 RPG 人物比例。三向行走图分别为下 13、右 15、上 10 帧，左向镜像，待机使用对应首帧；保留原始插画并生成仅裁透明边的显示立绘。“侍卫”“护卫”均绑定这张立绘；原守卫两种说话人仍绑定原立绘。

素材来源、SHA-256、裁切矩形与重建命令见[侍卫素材说明](../../assets/characters/npc/casino_sentry/README.md)。补充稿的分支对话尚未编排到运行时，本次接入 NPC 与素材；普通交互沿用忙碌反馈。

试玩：F6 打开 `src/core/casino.tscn`，从入口向左上走到地毯左端，应看到独立侍卫，角色不受 WASD 控制，脚部可阻挡玩家且不与墙或家具重叠。F6 打开 `src/debug/characters/character_gallery.tscn`，第二排最右侧的侍卫自动循环四向行走、镜像和停止待机。

![赌场侍卫正式宿主截图](captures/casino_sentry_2026_10_19.png)

实际验证（Godot 4.7.2）：`verify_casino_sentry.gd` headless 263 项通过，OpenGL 图形 264 项通过（含正式赌场截图）；覆盖逐帧非空与边界、镜像、输入隔离、真实 ActorDirector 移动、隐藏退出碰撞层、原守卫素材隔离、正式注册、锚点和站位碰撞。未运行全项目回归，本次没有更改通用逻辑或剧情状态契约。首次导入新 PNG 时已有 autoload 提前解析产生预导入报错，完成导入后运行时验证通过；再次 editor 导入无脚本解析错误，退出时仍报告 495 个 ObjectDB 实例与 10 个资源未清理。

实现沿用 Godot 4.7 [AtlasTexture](https://docs.godotengine.org/en/4.7/classes/class_atlastexture.html) 的 `region` / `filter_clip` 与 [SpriteFrames](https://docs.godotengine.org/en/4.7/classes/class_spriteframes.html) 的动画序列，不重编码行走图。

## 角色素材使用盘点（2026-10-19）

这里以正式店铺、外景、酒馆、赌场和长老宅的场景引用、实际角色组装为准；角色预览或帧资源引用不等于正式出场。原图、派生图和同角色不同表情不按新角色计数。上文早期“所有源图均被引用”是资源接入覆盖记录，不代表当前主线使用了所有角色。

| 角色 / 素材 | 当前状态 | 路径与说明 |
| --- | --- | --- |
| 守卫长 | 有基础场景、动画和画廊预览，未进入正式流程 | `assets/characters/npc/guard_captain/`，4 张；不把它自动认定为补充稿中的侍卫 |
| 厨师 | 有基础场景、动画和画廊预览，未进入正式流程 | `assets/characters/npc/chef/`，4 张 |
| 长老本人 | 有基础场景、动画和画廊预览，正式长老宅尚未实例化本人 | `assets/characters/npc/elder/`，5 张；地图中的长老宅不等于长老本人已出场 |
| 普通女顾客 | 有基础场景、四向动画和画廊预览，未进入正式营业出场排程 | `assets/characters/npc/human_customer_female/`，6 张 |
| 守卫长、厨师、守卫的攻击动画 | 有动作资源与独立预览，尚未接入正式战斗 / 行为 | `assets/characters/goblin_actions/` 的 `captain_attack_*`、`chef_attack_*`、`guard_attack_*`，各 3 张；不代表守卫整个角色没用 |
| 普通哥布林攻击动画 | 资源被无背包哥布林读取，但正式外观只提取行走 / 待机，未触发攻击 | 同目录 `goblin_attack_*`，3 张；`goblin_walk_*` 已实际用于无背包哥布林 |

已在正式场景使用的角色包括：主角、胖哥布林、普通哥布林（有 / 无背包）、原守卫、男顾客、酒馆老板、赌场老板，以及本次新增赌场侍卫。侍卫立绘已绑定，等待其补充稿对白的运行时编排。各类原始插画、旧像素头像和待机候选图属于来源或备选版本，不额外统计为未使用角色。

未使用角色的原因：当前前两天主线未安排守卫长、厨师的独立出场；长老已在故事中被提及，但首夜潜入明确利用他外出的时机，当前没有本人出场演出；人类顾客已使用男顾客外观，女顾客属于尚未安排出场的备选外观。攻击动画未触发属于行为尚未接入，不意味着对应人物没有出场。

用户于 2026-10-19 确认，原按附件名误称“猫鸡”的 19 张图片属于**格里芬剧情物品素材**，已移到 `assets/story/griffin/`，候选图改用 `griffin_<hash>.png`，不再计入未使用人物。前两天剧情已经涉及格里芬与格里芬之血，但这批图片尚未绑定具体物品或场景；“没有使用这批图”不能解释成“前两天没有格里芬相关内容”。来源和当前路径见[格里芬素材说明](../../assets/story/griffin/README.md)。
