"""Generate the original, procedural demo placeholder (two wooden knocks).

Run from any directory with Python 3; no third-party packages or source audio.
"""

import base64
import math
from pathlib import Path
import struct

rate = 22050
samples = []
for index in range(int(rate * 0.35)):
    time = index / rate
    value = 0.0
    for start in (0.0, 0.17):
        delta = time - start
        if 0 <= delta < 0.12:
            value += math.sin(2 * math.pi * 190 * delta) * math.exp(-delta * 65) * 0.55
    samples.append(struct.pack("<h", int(value * 32767)))

encoded = base64.b64encode(b"".join(samples)).decode("ascii")
output = Path(__file__).resolve().parents[2] / "src/debug/story/strange_knock.tres"
output.write_text(
    '[gd_resource type="AudioStreamWAV" format=3]\n\n[resource]\n'
    'format = 1\nmix_rate = 22050\nstereo = false\n'
    f'data = PackedByteArray("{encoded}")\n',
    encoding="utf-8",
)
