# 场景音乐与循环处理

2026-10-20 用户提供七首 Ogg。完整原文件保存于 `../source/music/`（由 `source/.gdignore` 与导出排除规则隔离），成品在本目录；原始名称、源/成品 SHA-256、采样率、时长和增益见 [处理记录](processing_manifest.json)。许可边界见 [LICENSE](../LICENSE.md)。标题曲 `start.ogg` 未修改。旧 `two_days_end.wav` 保留供作者对照，已从注册与全部导出预设排除。

| 逻辑 ID | 使用位置 | 首次长度 | 后续循环起点 |
| --- | --- | --- | --- |
| `music.daily_milk_tea` | 奶茶店；替换旧曲 | 64 秒 | 1.5 秒 |
| `music.cave` | 洞穴聚落外景，集市以外 | 177 秒 | 3 秒 |
| `music.market` | 洞穴地图已配置的集市观察区域 | 50 秒 | 1 秒 |
| `music.casino` | 赌场室内 | 29.5 秒 | 1 秒 |
| `music.tavern` | 酒馆室内 | 29 秒 | 1 秒 |
| `music.elder_house` | 长老居所室内 | 182.5 秒 | 2 秒 |
| `music.two_days_end` | 两天版结尾卡；替换旧 WAV | 90 秒 | 不循环 |

原文件不含可直接使用的循环设计。场景曲依据音量包络裁去结束淡出/静音，以 1–3 秒等功率交叉淡化，将尾段混入原曲开头；文件末尾接到交叉淡化长度处，首次保留完整开头，后续循环跳过已混入的开头。接缝连续性并不保证乐句、和声或鼓点完全对齐；仍需作者人工耳听后按配方调整。结尾曲保留完整 90 秒及混响尾音，仅加 10 ms 边缘保护，不循环。

各曲保持原速、原采样率（结尾 48 kHz，其余 44.1 kHz）与立体声；以整曲 RMS -22 dBFS 对齐平均电平，4 倍过采样峰值上限 -3 dBTP，不使用动态压缩或限幅。RMS 对齐不是 LUFS 感知响度母带处理。Vorbis 二次编码为 FFmpeg `libvorbis -q:a 6`；成品解码后再核对 RMS、峰值、接缝跳变和接缝两侧短时电平。

依据：[Audacity 淡化与等功率交叉淡化](https://manual.audacityteam.org/man/fade_and_crossfade.html)、[Godot 4.7 AudioStreamOggVorbis](https://docs.godotengine.org/en/4.7/classes/class_audiostreamoggvorbis.html)。使用 `loop_offset` 指定回接秒数、`beat_count=0` 保证实际 EOF 为循环终点；不通过 `finished` 信号手动重播。

在仓库根运行：

```powershell
python -m pip install -r tools/audio/requirements.txt
# 已保存原文件，普通重建不依赖上传临时目录
python tools/audio/prepare_music.py
python tools/audio/generate_sound_pack.py
python tests/verify_music.py
godot --headless --path . --editor --import --quit
godot --headless --path . --script res://tests/verify_sound_library.gd
godot --headless --path . --script res://tests/verify_scene_music.gd
```

处理配方为 `tools/audio/music_processing.json`；工具拒绝覆盖内容不同的原文件，重建先校验已记录的源哈希。初次导入可加 `--source-dir <上传目录> --ending <end.ogg>`。输出采用 bitexact 编码，避免随机 Ogg serial 破坏可复现性；Godot 已有导入 UID 保留。

F6 运行 `src/debug/audio/sound_library_demo.tscn`，选 music 分类可逐曲试听；六首场景曲从末尾回接，结尾曲播完停止。正式入口为 `src/core/main.tscn`、`settlement.tscn`、`casino.tscn`、`tavern.tscn`、`elder_house.tscn`。在聚落集市与公共火塘之间往返，停留超过 0.75 秒应淡变切歌；短暂穿过边界不切换，剧情专用音乐优先。结尾卡沿用原剧情触发。

本次验证：`verify_music.py` 七首全部通过；七首成品逐字节重建一致；Godot 4.7.2 的 `verify_sound_library.gd` 1774 项、`verify_bgm_loop.gd` 42 项、`verify_scene_music.gd` 15 项均为 0 failures。导入退出仍有既有的 495 ObjectDB / 10 resources 释放诊断，场景检查退出另有 1 ObjectDB 释放诊断；不影响以上断言结果。未执行全项目回归、发布导出或人工耳听，自动验证不替代听感验收。
