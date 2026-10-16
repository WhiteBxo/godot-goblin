# Sound Library v1

首版交付 18 个基础 ID、31 个 WAV。12 项 P0 均已制作；P1 包括两条 12 秒循环环境音、两种远处滴水、岩石摩擦、三种哥布林嘀咕及交互失败提示。所有素材是可直接加载的成品 PCM，不依赖运行时合成。艺术听感仍需成员通过 Demo 验收，自动化检查不等于听感确认。

## 文件与风格

- `assets/audio/ui/`：短促木琴/软脉冲复合音；确认向上、取消向下，失败音更低；对话有 3 个变体，额外压低 5 dB。
- `assets/audio/shop/`：非整数泛音门铃、纸张摩擦订单、杯体共鸣与颗粒气泡奶茶流、压合/电机/释压封口机。奶茶有 2 个变体。
- `assets/audio/player/`：木质敲击/鞋底、石质颗粒/低频落脚，各 4 个变体。
- `assets/audio/story/`：三连敲门 2 个变体、低频冲击与失谐共鸣、共振峰合成哥布林含糊嘀咕 3 个变体。
- `assets/audio/ambience/`：室内低频机器底噪与杯声、洞穴暗风与远滴水；独立滴水 2 个变体、岩石摩擦。

逐文件 ID、路径和时长见 [完整映射表](sound_library_ids.md)。基础 ID 永远指向第一个变体；多变体另注册 `.01`、`.02` 等明确 ID。稳定单音 ID 无数字后缀。场景中的循环音用 SFX 路由播放，占用一个既有池槽，停止时使用 handle 或 owner；不依赖 BGM。

## 接入现有 AudioManager

资源表在 `src/resources/audio/sound_library.tres`，通过直接 AudioStream 引用让导出器追踪依赖。它不会自动注册，不修改 MainGame、正式场景、剧情 JSON、Bus 或播放器池。宿主取得服务后显式注册一次：

```gdscript
const SOUNDS: SoundLibrary = preload("res://src/resources/audio/sound_library.tres")
var previous_step := ""
var sound_owner := RefCounted.new()

func configure_audio(audio: AudioManager) -> void:
	var errors := SOUNDS.register_all(audio)
	for message in errors:
		push_warning(message)

func play_wood_step(audio: AudioManager) -> void:
	previous_step = SOUNDS.choose_variant("player.step_wood", previous_step)
	if not previous_step.is_empty():
		audio.play_sfx(previous_step, sound_owner)

func confirm(audio: AudioManager) -> void:
	audio.play_ui("ui.confirm", sound_owner)

func start_room_tone(audio: AudioManager) -> int:
	return audio.play_sfx("ambience.shop", sound_owner)
```

每个发声角色独立保存 previous ID，避免相邻重复。重复对话建议按字组节流（约 60–100 ms），脚步按实际落脚事件触发，避免每帧请求。结束时 `audio.stop_owned(sound_owner)`；停止单条循环可 `audio.stop_sound(handle, 0.2)`。注册缺失/null 流返回诊断列表并继续其他项；未知 ID 与丢失路径由既有 AudioManager 安全返回 0。资源表本身若被删除或破坏，属于导入/构建错误，不能用运行时跳过掩盖。

## F6 独立试听

打开 `src/debug/audio/sound_library_demo.tscn`，F6 运行。无需正式关卡或剧情。

1. 分类筛选，单击条目查看 ID、资源路径、时长和循环标志；双击或「播放」试听。列表包含全部 31 个文件。
2. 「连续试听」从当前分类第一项开始，逐条播放，间隔 0.22 秒；循环条目试听 6 秒后继续，最后自动停止。
3. 音量范围 -48～0 dB，默认 -6 dB；拖动时当前条目按新音量从头播放，并结束连续模式。只使用 AudioManager 的公开播放音量参数，不改全局 Bus。
4. 连续点击播放应重新触发且没有残留池槽；「停止」取消当前音效与待播放 Timer，再次点击无副作用。
5. 「缺失资源测试」显示安全跳过，随后正常音效仍可播放。
6. 环境音手动播放保持循环；至少听过 24 秒确认两次拼接处无明显接缝，再停止。

试听重点：门铃清楚但不尖锐，奶茶有流动与落杯层次，封口机有压下/运转/释放，木石脚步可区分，三连敲带少量空间反射，UI 与对白适合高频重复。哥布林为风格化含糊声，不含语言语义。需要更写实的机器/人声时再替换对应 ID 的资源即可。

## 来源、生成与响度

无外部音频。WAV 来源统一为 `tools/audio/generate_sound_pack.py`，许可见 [音频许可证](../assets/audio/LICENSE.md)。固定种子 `47001 + 条目序号 * 100 + 变体序号`；各素材独立随机数发生器；采样噪声、多模态衰减共鸣、滑频气泡、谐波共振峰声源、短延迟反射分层。不是纯正弦测试音集合。

处理：轻柔 tanh 饱和、短音 45–5500 Hz 带通、8 ms 首尾包络、消除不可闻长尾；常规有效区 RMS 约 -23 dBFS，对话 -28 dBFS，循环 -32 dBFS。有效区定义为超过本文件峰值 4% 的采样；这是短音一致性指标，不宣称 LUFS 等响。4 倍过采样估计 true peak 上限 -6 dBTP，实际峰值保留更多余量。叠加大量音效仍须按场景混音，单文件不削波不代表任意叠加不削波。

环境音使用周期频谱滤波噪声与整数周期调制，事件尾巴留在周期内；无起止淡入静音坑。44.1 kHz、16-bit、单声道 WAV；两个循环也使用 WAV（合计约 2.1 MB），避免编码器延迟和额外编码依赖。导入显式关闭 normalize/trim/压缩，并仅为环境音启用 forward loop；`.import` 与 WAV 一同提交。总素材约 3.7 MiB。注意 WAV 导入器 `edit/loop_mode=2` 才是 Forward，运行时 `AudioStreamWAV.LOOP_FORWARD=1`，两者枚举不同。

```powershell
python -m pip install -r tools/audio/requirements.txt
python tools/audio/generate_sound_pack.py
python tests/verify_sound_pack.py
# 把 godot 换成当地 Godot 4.7.2 可执行文件；先执行导入
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/verify_sound_library.gd
godot --headless --path . --script res://tests/verify_audio_manager.gd
```

生成工具保留既有 import UID，输出 WAV、Godot 资源表、映射文档和 SHA-256 manifest；不要手改生成文件再宣称可复现。新机器首次导入由 Godot 补齐 UID。Python 依赖已固定当前验证版本；更换数值库版本后应重新核对哈希。

验证覆盖 31 个文件哈希、PCM、有效区 RMS、DC、4 倍 true peak、高频能量、短音边界及循环接缝/静音坑；Godot 验证所有加载与 loop 配置、基础/变体注册、非相邻重复、实际服务播放状态、叠加触发、停止、自然回收、缺失文件/null 流和 Demo 分类、连续试听、音量与取消。自动化不替代人工试听。

实现依据 Godot 4.7 官方文档：[AudioStreamPlayer](https://docs.godotengine.org/en/4.7/classes/class_audiostreamplayer.html) 的 `stop()` 不发 finished，试听停止显式取消 Timer；[AudioStreamWAV](https://docs.godotengine.org/en/4.7/classes/class_audiostreamwav.html) 的 forward loop 与采样单位；[ResourceLoader](https://docs.godotengine.org/en/4.7/classes/class_resourceloader.html) 的导入前置要求及资源依赖。播放生命周期完全复用 [AudioManager](audio_manager.md)。

## 本次执行结果

Godot 4.7.2：Sound Library 912 项检查通过（含跨越完整 12 秒周期后仍播放、连续试听 6 秒自动换条目）；既有 AudioManager 64 项回归通过。31 个 WAV 的 PCM 检查及重复生成逐字节哈希检查通过。非 headless Compatibility 模式运行 Demo 验证通过，已检查 1280×720 截图：分类、列表、路径/时长和控制区显示完整。图形模式没有修改项目渲染器配置。

编辑器批量导入成功，但退出日志报告资源释放警告（495 ObjectDB、10 resources）；独立运行上述音频测试没有该警告。警告来源尚未定位，本次未修改插件。未进行人工耳听验收，主观风格和长时间舒适度按前述 F6 步骤确认。
