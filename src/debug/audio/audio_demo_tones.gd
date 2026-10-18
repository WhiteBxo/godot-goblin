class_name AudioDemoTones
extends RefCounted
## Legacy demo IDs backed by the curated recordings. No runtime synthesis.

static func sample_clip(source: AudioStreamWAV, seconds: float, loop: bool = false) -> AudioStreamWAV:
	var stream := source.duplicate() as AudioStreamWAV
	var frame_bytes := 4 if source.stereo else 2
	var bytes := maxi(frame_bytes, int(seconds * source.mix_rate) * frame_bytes)
	var data := PackedByteArray()
	while data.size() < bytes:
		data.append_array(source.data.slice(0, mini(source.data.size(), bytes - data.size())))
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if loop else AudioStreamWAV.LOOP_DISABLED
	stream.loop_begin = 0
	stream.loop_end = bytes / frame_bytes
	return stream


static func populate(audio: AudioManager) -> void:
	audio.register_sound("demo.music_a", preload("res://assets/audio/ambience/shop.wav"))
	audio.register_sound("demo.music_b", preload("res://assets/audio/ambience/cave.wav"))
	audio.register_sound("demo.low", sample_clip(preload("res://assets/audio/story/impact.wav"), 0.45))
	audio.register_sound("demo.high", sample_clip(preload("res://assets/audio/shop/door_bell.wav"), 0.45))
	audio.register_sound("demo.ui", sample_clip(preload("res://assets/audio/ui/hover.wav"), 0.15))
	audio.register_sound("demo.story", sample_clip(preload("res://assets/audio/story/knock_01.wav"), 4.0))
