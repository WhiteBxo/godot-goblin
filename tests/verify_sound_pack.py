"""Checks delivered PCM, reproducibility hashes, loudness, tails and loop boundaries."""
import hashlib
import json
from pathlib import Path
import wave

import numpy as np
from scipy.signal import resample_poly

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'assets/audio/manifest.json').read_text(encoding='utf-8'))
failures = []
metrics = []


def check(condition, message):
    if not condition:
        failures.append(message)


for entry in manifest:
    path = ROOT / entry['path']
    check(hashlib.sha256(path.read_bytes()).hexdigest() == entry['sha256'], f'{path}: stale hash')
    with wave.open(str(path)) as wav:
        check((wav.getnchannels(), wav.getsampwidth(), wav.getframerate()) == (1, 2, 44100), f'{path}: format')
        x = np.frombuffer(wav.readframes(wav.getnframes()), dtype='<i2').astype(float) / 32768
    peak = np.max(np.abs(resample_poly(x, 4, 1)))
    check(peak < .503, f'{path}: true peak exceeds -6 dBTP tolerance')
    check(abs(x.mean()) < .002, f'{path}: DC offset')
    check(abs(len(x)/44100 - entry['seconds']) < .00001, f'{path}: duration')
    active = abs(x) > max(abs(x)) * .04
    rms = 20*np.log10(np.sqrt(np.mean(x[active]**2)))
    target = -32 if entry['loop'] else (-28 if entry['id'].startswith('ui.dialogue') else -23)
    check(abs(rms - target) < 1.0, f'{path}: active RMS {rms:.2f} vs {target}')
    if entry['loop']:
        # Boundary jump must be comparable to ordinary sample-to-sample motion.
        check(abs(x[0]-x[-1]) < max(.0005, np.std(np.diff(x))*5), f'{path}: loop seam')
        blocks = np.sqrt(np.mean(x[:len(x)//4410*4410].reshape(-1,4410)**2, axis=1))
        check(min(blocks) > max(blocks)*.35, f'{path}: loop contains a fade gap')
    else:
        check(x[0] == 0 and x[-1] == 0, f'{path}: nonzero edge')
        audible = np.flatnonzero(abs(x) > .0005)
        check(audible[0]/44100 < .035, f'{path}: leading silence')
        check((len(x)-audible[-1])/44100 < .15, f'{path}: excessive silent tail')
    spectrum = abs(np.fft.rfft(x))**2
    freq = np.fft.rfftfreq(len(x), 1/44100)
    high_ratio = sum(spectrum[freq > 8000]) / sum(spectrum)
    check(high_ratio < .002, f'{path}: excess high-frequency energy')
    metrics.append(dict(id=entry['id'], active_rms_db=round(rms,2), true_peak_db=round(20*np.log10(peak),2)))

check(len(manifest) == 31, 'Expected 31 delivered files')
print(json.dumps(metrics, ensure_ascii=False, indent=2))
if failures:
    raise SystemExit('\n'.join(failures))
print('PASS: 31 WAVs; hashes, PCM, true peaks, active RMS, DC, high band, edges and loop seams')
