class_name AudioDemoTones
extends RefCounted
## Original deterministic placeholder tones; no external assets or imports.

static func tone(frequency: float, seconds: float = 0.45, loop: bool = false) -> AudioStreamWAV:
	var rate := 22050
	var samples := int(seconds * rate)
	var data := PackedByteArray()
	data.resize(samples * 2)
	for index in range(samples):
		var time := float(index) / rate
		var envelope := minf(1.0, minf(time, seconds - time) * 35.0)
		var note := frequency * (1.25 if loop and time > seconds * 0.5 else 1.0)
		var value := int(sin(TAU * note * time) * envelope * 4500.0)
		data[index * 2] = value & 255
		data[index * 2 + 1] = (value >> 8) & 255
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = samples
	return stream


static func populate(audio: AudioManager) -> void:
	audio.register_sound("demo.music_a", tone(220.0, 2.0, true))
	audio.register_sound("demo.music_b", tone(330.0, 2.0, true))
	audio.register_sound("demo.low", tone(440.0))
	audio.register_sound("demo.high", tone(660.0))
	audio.register_sound("demo.ui", tone(880.0, 0.15))
	audio.register_sound("demo.story", tone(180.0, 4.0))
