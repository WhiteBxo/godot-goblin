# BGM native loop fixture

`bgm_intro_loop.ogg` is an original synthesized test tone, not a production BGM.
Mono, 44100 Hz, 1.2 seconds: 220 Hz before 0.4 seconds, then 440 Hz.
Imported without looping so tests can detect unintended shared-resource changes.

Recreate from the repository root with Python, NumPy and SoundFile (test asset generation only; no game dependency):

```python
import numpy as np
import soundfile as sf

rate = 44100
t = np.arange(rate * 12 // 10) / rate
y = 0.15 * np.sin(2 * np.pi * np.where(t < 0.4, 220.0, 440.0) * t)
sf.write("tests/fixtures/bgm_intro_loop.ogg", y, rate, format="OGG", subtype="VORBIS")
```

The fixture verifies decoder loop behavior and distinguishable Intro playback;
final production music still requires listening for clean edit boundaries.
