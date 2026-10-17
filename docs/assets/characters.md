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

这些是可编辑的聚落常驻展示位置，保存在 `src/core/settlement.tscn` 的 `World/EntityRoot`，不是第一天各阶段的出场排程。正式剧情应按剧情数据决定何时显隐、生成和移动，例如长老夜间外出时由剧情隐藏/移动。NPC 无玩家输入、不阻挡玩家，移动时仍与地图墙体/家具碰撞；未实现巡逻、寻路、订单或任务 AI。

## 动画与源图

`character_catalog.json` 保存人物身份、源图、有效帧数、FPS 与动画映射；`*_frames.tres` 为可在编辑器查看的 SpriteFrames，使用 AtlasTexture 引用原图，不重编码图片。脚底为角色原点，碰撞只覆盖脚部；普通图集 64 像素帧等比放大 2 倍，守卫长 128 像素帧保持 1 倍，画布统一为 128 世界像素，可见人物约 110 像素高。守卫长待机图与走路图存在原素材的造型差异，保留原图。

- 普通图集为 64×64 帧、88 像素间隔；守卫长走路为 128×128 帧、152 像素间隔。6 列，逐行播放。尾部空格排除，每张有效帧数为 9～16。
- 播放接口沿用 PlayerController 的 `idle_down/left/right/up` 与 `run_down/left/right/up`。走路 8 FPS，待机 6 FPS。原包未给出 FPS，当前为可调的接入值。
- 只有一侧的素材采用左右镜像；普通哥布林和长老的侧面源图朝左，其他侧面源图按右侧使用。守卫长为接近侧面的斜向图，尚缺真正侧面行走图。
- 守卫没有独立待机图，各方向取对应行走首帧。其他人物缺失的方向待机同样取行走首帧。
- 胖哥布林只有待机素材：正面/侧面待机已接入，移动采用对应静帧；背面使用正面 fallback，尚缺四向行走及背面素材。`emote_laugh` 收录第三张表情动画，未自动插入剧情。
- 长老两张待机分别用于正面、侧面；守卫长原待机额外保留 `idle_variant`。所有原图均被引用。

重新生成帧资源（Python 3 标准库）：

```sh
python3 tools/characters/build_character_frames.py
```

生成器只重建 SpriteFrames，不覆盖场景身份、聚落位置或图片。调整源图/帧数先修改 catalog，然后重建资源。

## 场景与演出

主场景组装时将 EntityRoot 中的 SettlementCharacter 按 `actor_id` 注册给现有 ActorDirector。各 NPC 场景根继承 PlayerController，`accepts_player_input = false`，可直接用 `actor_spawn` 实例化到其他宿主。复用同一场景生成多个居民时，为各个实例提供不同注册 ID；聚落预置实例的 actor_id 必须唯一。

Godot F6 打开 `src/debug/characters/character_gallery.tscn`：同时查看 8 类人物，自动循环四向移动、停止待机，观察镜像、脚底和人物比例。F6 打开 `src/core/settlement.tscn`：出生点向右可看到胖哥布林，出门继续向右下可看到普通哥布林；其余人物在表中对应区域外。NPC 不跟随 WASD，不遮挡出入口。

## 验证

```sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --fixed-fps 60 --script res://tests/verify_characters.gd
# 带图形环境保存 /tmp/godot_character_gallery.png
/Applications/Godot.app/Contents/MacOS/Godot --path . --fixed-fps 60 --script res://tests/verify_characters.gd -- --capture
```

测试实际加载各场景，核对全部动画帧非空/不越界、31 张源图覆盖、NPC 输入隔离、四向朝向、真实 ActorDirector 移动、聚落注册及出生点地图碰撞。测试不会把缺失方向的 fallback 误报为已有完整美术。

实现核对的 Godot 4.7 官方文档：[SpriteFrames](https://docs.godotengine.org/en/4.7/classes/class_spriteframes.html)（帧序列和 FPS）、[AtlasTexture](https://docs.godotengine.org/en/4.7/classes/class_atlastexture.html)（region 裁取及 filter_clip 防止邻格渗色）、[AnimatedSprite2D](https://docs.godotengine.org/en/4.7/classes/class_animatedsprite2d.html)（flip_h、offset 与动画播放）。

本次在 Godot 4.7.2 验证：人物 headless 1295 项通过；Metal Forward+ 实际渲染 1296 项通过（含截图），中文字体与八类人物画面已检查；ActorDirector 165 项、StoryDirector 163 项回归通过；聚落回归通过，验证 16 个区域、剧情锚点、桥梁、真实移动和墙体（48623 个可达采样点）。headless editor 资源导入成功；退出时存在沙盒外 editor_settings 无法保存和编辑器资源清理提示，未出现本次人物资源解析错误。
