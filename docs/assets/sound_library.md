# 项目音效库

当前可用库包含 **23 个音效基础 ID、43 个 WAV 变体**，另保留用户提供的 `music.daily_milk_tea`。原有 18 个基础 ID、31 个 WAV 路径与导入 UID 全部保留，内容替换为本次三个素材包的采样与组合；现有调用方无需迁移 ID。新增登记钱币、锁盒解锁、开瓶、碗勺搅拌、翻页 5 类声音。

## 原始素材与许可

`assets/audio/source/` 按包完整保存压缩包中的 335 个文件：331 条音效、2 个预览、2 个原始 readme。源文件逐字节保留，原始文件名也保留；目录内 `.gitattributes` 禁止 Git 转换源文件换行符；不会被派生 WAV 覆盖。`source/manifest.json` 记录压缩包与每个成员的 SHA-256。

| 目录 | 来源 / 作者 | 原始音效数 | 许可 |
| --- | --- | --- | --- |
| `rpg_sfx/` | [80 CC0 RPG SFX / rubberduck](https://opengameart.org/node/86018) | 80 Ogg | CC0 |
| `tinysized/` | [Tinysized SFX / Vehicle (Jan Schupke)](https://opengameart.org/content/fantasy-sound-effects-tinysized-sfx) | 96 WAV | CC0 |
| `accessory/` | [Accessory SFX / Vehicle (Jan Schupke)](https://opengameart.org/content/fantasy-accessory-sfx-library) | 155 WAV | CC0 |

两个 Vehicle 包原始 readme 保存在各自目录。许可与独立音乐边界见 [LICENSE](../../assets/audio/LICENSE.md)。原始目录有 `.gdignore`，导出配置也显式排除 `assets/audio/source/*`：完整原始库用于后续挑选，游戏只导入成品目录。

## 选用与适配

逐项 ID、路径、时长、原始文件和适配说明见 [完整映射表](sound_library_ids.md)；`tools/audio/sound_selection.json` 是唯一选用与处理配方，包含裁剪、相对增益、播放速度、触发位置、回声与环境底层参数。`assets/audio/manifest.json` 记录每个成品的配方、源文件、时长和 SHA-256。

- UI 使用短木器触声、宝石拾取与锁扣声；对白保留三种低响度变体。
- 门铃改为素材中的木风铃片段；订单使用真实翻页，奶茶使用倒水与小瓶注水。
- 封口机以抽屉压合和压缩空气组合；木地脚步以皮靴与木器轻触组合，石地以土壤落脚与轻石声组合。这些是用途适配，不宣称是对应设备或地面的实录。
- 神秘三连敲来自木勺敲木碗，冲击与摩擦来自石块，哥布林声来自生物短叫并降低音高。
- 两条 12 秒循环环境音使用气流采样底层，分别加入器物或远水滴；它们是场景环境设计，并非完整现场环境录音。
- 新增 `shop.coins`、`story.unlock`、`shop.bottle_open`、`shop.stir`、`story.page_turn`，可由现有宿主显式播放；登记不会自动在玩法中新增触发。

成品统一为 44.1 kHz、16-bit、单声道 PCM。处理包含 55–5500 Hz 带通、首尾包络、移除静音尾部；有效区 RMS 目标为普通音效 -23 dBFS、对白 -28 dBFS、环境 -32 dBFS。峰值保护优先保留动态，允许 RMS 比目标低 4 dB；4 倍过采样估计 true peak 不超过 -6 dBTP。短音显式关闭循环，环境显式使用 Forward；关闭 Godot 二次 normalize、trim 与压缩。

## 注册与播放

集中资源表位于 `src/resources/audio/sound_library.tres`，使用直接 AudioStream 引用供导出器跟踪。宿主通过已有公开接口注册：

```gdscript
const SOUNDS: SoundLibrary = preload("res://src/resources/audio/sound_library.tres")
var previous_step := ""
var sound_owner := RefCounted.new()

func configure_audio(audio: AudioManager) -> void:
	for message in SOUNDS.register_all(audio):
		push_warning(message)

func play_wood_step(audio: AudioManager) -> void:
	previous_step = SOUNDS.choose_variant("player.step_wood", previous_step)
	if not previous_step.is_empty():
		audio.play_sfx(previous_step, sound_owner)
```

基础 ID 指向首变体，多变体注册 `.01`、`.02` 等 ID。各角色独立保存 previous ID 避免连续重复；结束时调用 `audio.stop_owned(sound_owner)`。循环环境走既有 SFX 池，需使用 handle 或 owner 停止。未知 ID 或缺失资源继续由现有 AudioManager 安全处理。服务契约见 [AudioManager](../systems/audio_manager.md)。

## Demo 与试听

F6 运行 `src/debug/audio/sound_library_demo.tscn`：列表包含 43 个音效及 1 首日常音乐；选择分类，双击条目或点「播放」，也可「连续试听」。短音自然结束，循环音连续模式播放 6 秒后换条目；手动循环持续到「停止」。音量默认 -6 dB，可调 -48～0 dB。

至少听过两次环境循环，确认边界与气流音色；再检查门铃、三连敲、木石脚步区分、封口机的用途适配，以及对白高频重复的舒适度。自动化只验证资源和播放行为，不代替人工耳听。

`src/debug/audio/audio_demo.tscn` 保留淡变、叠加、暂停与取消试听。历史类名 `AudioDemoTones` 和 `demo.*` ID 为兼容现有 Demo/测试继续保留，绑定已改为本次成品；有限时长通过采样裁剪/重复生成内存片段，没有正弦音合成。`cinematic.bell` / `cinematic.room` 分别绑定新门铃/室内环境；旧 `strange_knock.tres` 嵌入与 `story/knock_01.wav` 相同的 PCM，由生成链同步更新。

`tests/fixtures/bgm_intro_loop.ogg` 是专门验证解码器 Intro/Loop 位置的测试音乐夹具，保留固定频率段用于断言；不进入游戏音效登记或 Demo 播放。

## 重建与验证

在仓库根运行：

```powershell
python -m pip install -r tools/audio/requirements.txt
# 首次导入本地压缩包；已存在且内容不同的源文件会拒绝覆盖
python tools/audio/generate_sound_pack.py --archive-dir D:/download
# 已提交完整原始库，其他机器不需要原下载目录
python tools/audio/generate_sound_pack.py
python tests/verify_sound_pack.py
# 使用当地 Godot 4.7.2 可执行文件
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/verify_sound_library.gd
```

重建会校验全部原始文件哈希，输出 WAV、保留 UID 的导入配置、集中资源表、逐项文档、成品 manifest 及兼容的 Story Demo 敲击资源，并保留用户日常音乐的资源引用及 68.279 秒循环起点。生成文件与配方一起提交。

本次验证包括 335 个原文件哈希、43 个 PCM 成品逐采样重建、响度/峰值/边缘/循环接缝、兼容敲击内容，以及 Godot 的资源注册、变体选择、实际播放、回收与 Demo 列表。实际命令结果以任务交付为准；未进行人工耳听，不声称主观听感通过。

实现依据：[Godot 4.7 音频导入](https://docs.godotengine.org/en/4.7/tutorials/assets_pipeline/importing_audio_samples.html)。WAV 导入器 `edit/loop_mode=2` 表示 Forward，运行时 `AudioStreamWAV.LOOP_FORWARD=1`；二者枚举不同。循环音不会自然发出 finished，沿用既有试听超时和显式停止逻辑。

## 用户提供的音乐

`music/daily_milk_tea.ogg` 与 `music/start.ogg` 均保持原内容，不在三个 CC0 音效包的许可声明内。日常音乐资源表和导入配置保留 `loop=true`、`loop_offset=68.279`、`beat_count=0`：首次从头播放，文件末尾回到 1:08.279。标题音乐继续由标题界面单独引用。

## 2026-10-18 验证记录

- `python tests/verify_sound_pack.py`：335 个原文件与 43 个成品通过来源哈希、逐采样重建、PCM、峰值、响度、边缘、循环及旧敲击兼容检查。完整生成链重跑后所有输出逐字节一致；原有 31 个成品内容均已改变且 UID 保留，43 个导入 UID 无重复。
- Godot 4.7.2 导入成功。`verify_sound_library.gd` 1223 项、`verify_audio_manager.gd` 64 项、`verify_bgm_loop.gd` 42 项、`verify_gameplay_bridge.gd` 249 项均为 0 failures。
- `verify_cinematic_integration.gd` 为 286 项、6 failures；`validate_story.gd -- res://docs/story_authoring/cinematic_opening.json` 为 1 case、2 failures，包含顾客朝 (1470, 560) 移动受阻。未改动 HEAD 的独立副本复现相同断言失败，未扩大本次音效任务修理移动问题。
- Bridge 清单使用其声明的 `verify_gameplay_bridge.gd` 验证。曾直接传给 `validate_story.gd`，因该清单采用 `verification` 而非 `cases` 被拒绝；这不是适用的验证入口。
- 编辑器导入退出仍有 495 ObjectDB / 10 resources 释放诊断，未改动 HEAD 同样复现。独立音频测试无该诊断。未执行全项目回归或导出发布；本次未改变玩法契约。未进行人工耳听，试听步骤见上文。
