"""Preserve the legacy Story Demo resource path using the curated wooden knocks.

Called by generate_sound_pack.py; can also run after building the WAV pack.
No generated oscillator, noise, or independent placeholder recording.
"""
import base64
from pathlib import Path
import wave


def main():
    root = Path(__file__).resolve().parents[2]
    with wave.open(str(root / 'assets/audio/story/knock_01.wav')) as wav:
        rate = wav.getframerate()
        encoded = base64.b64encode(wav.readframes(wav.getnframes())).decode('ascii')
    (root / 'src/debug/story/strange_knock.tres').write_text(
        '[gd_resource type="AudioStreamWAV" format=3]\n\n[resource]\n'
        f'format = 1\nmix_rate = {rate}\nstereo = false\n'
        f'data = PackedByteArray("{encoded}")\n', encoding='utf-8', newline='\n')


if __name__ == '__main__':
    main()
