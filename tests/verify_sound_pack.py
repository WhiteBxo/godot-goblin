"""Verify raw archive provenance, sampled PCM, reproducibility and loop boundaries."""
import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import sys
import wave
import numpy as np
from scipy.signal import resample_poly

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'assets/audio/manifest.json').read_text(encoding='utf-8'))
failures = []


def check(condition, message):
    if not condition:
        failures.append(message)


spec = importlib.util.spec_from_file_location('sound_builder', ROOT / 'tools/audio/generate_sound_pack.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
source_manifest = json.loads((ROOT / 'assets/audio/source/manifest.json').read_text(encoding='utf-8'))
sources = {entry['path']: entry['sha256'] for pack in source_manifest for entry in pack['files']}
check(len(sources) == 335, 'Expected every original file from all three archives')
check((ROOT / 'assets/audio/source/.gdignore').exists(), 'Raw recordings excluded from Godot imports')
for path, expected in sources.items():
    check(hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == expected, f'{path}: changed raw source')
ids = set()
for entry in manifest:
    path = ROOT / entry['path']
    check(entry['id'] not in ids, f'{path}: duplicate sound ID')
    ids.add(entry['id'])
    check(hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256'], f'{path}: stale hash')
    check(entry['sources'] and all(s in sources for s in entry['sources']), f'{path}: missing source provenance')
    check(set(entry['sources']) == {'assets/audio/source/' + part['source'] for part in entry['recipe']['parts']}, f'{path}: recipe provenance differs')
    with wave.open(str(path)) as wav:
        check((wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) == (1, 2, 44100), f'{path}: format')
        pcm = wav.readframes(wav.getnframes())
        x = np.frombuffer(pcm, dtype='<i2').astype(float) / 32768
    target = -32 if entry['loop'] else (-28 if entry['id'].startswith('ui.dialogue') else -23)
    check(builder.render(entry['recipe'], entry['loop'], target).tobytes() == pcm, f'{path}: not reproducible from recordings')
    peak = np.max(np.abs(resample_poly(x, 4, 1)))
    check(peak < .503, f'{path}: true peak exceeds -6 dBTP tolerance')
    check(abs(x.mean()) < .002, f'{path}: DC offset')
    check(abs(len(x) / 44100 - entry['seconds']) < .00001, f'{path}: duration')
    active = abs(x) > max(abs(x)) * .04
    rms = 20 * np.log10(np.sqrt(np.mean(x[active] ** 2)))
    # Preserve recorded transients; peak protection may reduce the RMS by up to 4 dB.
    check(target - 4 < rms < target + .5, f'{path}: active RMS {rms:.2f} vs {target}')
    if entry['loop']:
        check(abs(x[0] - x[-1]) < max(.0005, np.std(np.diff(x)) * 5), f'{path}: loop seam')
        blocks = np.sqrt(np.mean(x[:len(x)//4410*4410].reshape(-1, 4410) ** 2, axis=1))
        check(min(blocks) > max(blocks) * .35, f'{path}: loop contains a fade gap')
    else:
        check(x[0] == 0 and x[-1] == 0, f'{path}: nonzero edge')
        audible = np.flatnonzero(abs(x) > .0005)
        check(audible[0] / 44100 < .035, f'{path}: leading silence')
        check((len(x) - audible[-1]) / 44100 < .15, f'{path}: excessive silent tail')
    spectrum = abs(np.fft.rfft(x)) ** 2
    freq = np.fft.rfftfreq(len(x), 1 / 44100)
    check(sum(spectrum[freq > 8000]) / sum(spectrum) < .002, f'{path}: excess high-frequency energy')
check(len(manifest) == 43, 'Expected 43 curated files')
check(len({e['path'] for e in manifest}) == len(manifest), 'Every variant has its own asset')
# The old embedded Story Demo must contain the same recorded knock, not a stale tone.
legacy = (ROOT / 'src/debug/story/strange_knock.tres').read_text(encoding='utf-8')
encoded = re.search(r'data = PackedByteArray\("([^"]+)"\)', legacy)[1]
with wave.open(str(ROOT / 'assets/audio/story/knock_01.wav')) as wav:
    check(base64.b64decode(encoded) == wav.readframes(wav.getnframes()), 'Legacy Story Demo still uses a placeholder')
if failures:
    raise SystemExit('\n'.join(failures))
print('PASS: 335 raw source files; 43 reproducible recorded WAVs; PCM, peaks, RMS, DC, edges, loops and legacy knock')
