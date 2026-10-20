"""Check the shipped music, source provenance and actual decoded loop seams."""
import hashlib
import json
from pathlib import Path

import numpy as np
from scipy.signal import resample_poly
import soundfile as sf

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / 'assets/audio/music/processing_manifest.json').read_text(encoding='utf-8'))
assert len(manifest) == 7
for track in manifest:
    for key, hash_key in [('source', 'source_sha256'), ('output', 'sha256')]:
        assert hashlib.sha256((ROOT / track[key]).read_bytes()).hexdigest() == track[hash_key], track[key]
    audio, rate = sf.read(ROOT / track['output'], always_2d=True)
    assert audio.shape[1] == 2 and rate == track['sample_rate'], track['name']
    assert abs(len(audio) / rate - track['seconds']) < 1 / rate, track['name']
    rms_db = 20 * np.log10(np.sqrt(np.mean(audio ** 2)))
    peak_db = 20 * np.log10(np.max(np.abs(resample_poly(audio, 4, 1, axis=0))))
    assert abs(rms_db + 22) < .3 and peak_db <= -3, (track['name'], rms_db, peak_db)
    if track['loop']:
        offset = round(track['loop_offset'] * rate)
        assert 0 < offset < len(audio)
        # Inspect the seam the engine actually decodes, not the pre-encode PCM.
        seam = np.concatenate([audio[-rate // 10:], audio[offset:offset + rate // 10]])
        jump = np.max(np.abs(audio[-1] - audio[offset]))
        typical = np.quantile(np.abs(np.diff(seam, axis=0)), .999)
        assert jump < typical * 2 + .002, (track['name'], 'seam discontinuity', jump, typical)
        before = np.sqrt(np.mean(audio[-rate // 10:] ** 2))
        after = np.sqrt(np.mean(audio[offset:offset + rate // 10] ** 2))
        assert abs(20 * np.log10(before / after)) < 6, (track['name'], 'seam level gap')
        assert min(before, after) > .002, (track['name'], 'silent loop seam')
    else:
        assert track['name'] == 'two_days_end' and track['seconds'] == 90
        assert np.max(np.abs(audio[-rate // 10:])) < .002, 'Ending must retain its quiet tail'
    print(f'PASS {track["name"]}: {rms_db:.2f} dBFS RMS, {peak_db:.2f} dBTP; stereo and seam/tail verified')
