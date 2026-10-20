"""Build scene music from preserved user originals (stereo, native sample rate).

From the repository root: python tools/audio/prepare_music.py
First import: add --source-dir <folder> --ending <end.ogg>.
No time stretching, limiting or denoising; originals are never overwritten.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

import imageio_ffmpeg

import numpy as np
from scipy.signal import resample_poly
import soundfile as sf

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/audio/source/music'
OUTPUT = ROOT / 'assets/audio/music'
RECIPE = Path(__file__).with_name('music_processing.json')


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_import(path, offset):
    target = Path(str(path) + '.import')
    old = target.read_text(encoding='utf-8') if target.exists() else ''
    uid = re.search(r'^uid="[^"]+"', old, re.M)
    resource = 'res://' + path.relative_to(ROOT).as_posix()
    cache = 'res://.godot/imported/' + path.name + '-' + hashlib.md5(resource.encode()).hexdigest() + '.oggvorbisstr'
    text = '[remap]\n\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\n'
    if uid:
        text += uid[0] + '\n'
    text += f'path="{cache}"\n\n[deps]\n\nsource_file="{resource}"\ndest_files=["{cache}"]\n\n[params]\n\n'
    text += f'loop={str(bool(offset)).lower()}\nloop_offset={offset}\nbpm=0\nbeat_count=0\nbar_beats=4\n'
    target.write_text(text, encoding='utf-8', newline='\n')


def render(path, track, settings):
    audio, rate = sf.read(path, always_2d=True)
    end = round(track['end_seconds'] * rate)
    overlap = round(track['crossfade_seconds'] * rate)
    if not 0 <= overlap * 2 < end <= len(audio):
        raise ValueError(f'Invalid music selection: {track["name"]}')
    audio = audio[:end].copy()
    if overlap:
        # Preserve the opening on the first pass. Blend EOF into its beginning,
        # then let the decoder wrap to the exact next source sample (overlap).
        theta = np.linspace(0, np.pi / 2, overlap)[:, None]
        audio[-overlap:] = audio[-overlap:] * np.cos(theta) + audio[:overlap] * np.sin(theta)
    else:
        # Ending retains the entire composition and reverb tail, plays once.
        fade = min(round(.01 * rate), len(audio) // 2)
        audio[:fade] *= np.linspace(0, 1, fade)[:, None]
        audio[-fade:] *= np.linspace(1, 0, fade)[:, None]
    rms = np.sqrt(np.mean(audio ** 2))
    true_peak = np.max(np.abs(resample_poly(audio, 4, 1, axis=0)))
    gain = min(10 ** (settings['target_rms_db'] / 20) / max(rms, 1e-12),
               10 ** (settings['peak_ceiling_db'] / 20) / max(true_peak, 1e-12))
    return audio * gain, rate, float(20 * np.log10(gain))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path)
    parser.add_argument('--ending', type=Path)
    args = parser.parse_args()
    settings = json.loads(RECIPE.read_text(encoding='utf-8'))
    SOURCE.mkdir(parents=True, exist_ok=True)
    report = []
    old_manifest = OUTPUT / 'processing_manifest.json'
    expected = {row['name']: row['source_sha256'] for row in
                json.loads(old_manifest.read_text(encoding='utf-8'))} if old_manifest.exists() else {}
    for track in settings['tracks']:
        name = track['name']
        source = SOURCE / (name + '.ogg')
        supplied = args.ending if name == 'two_days_end' else (
            args.source_dir / track['source_name'] if args.source_dir else None)
        if supplied:
            if source.exists() and sha256(source) != sha256(supplied):
                raise ValueError(f'Refusing to overwrite original: {source}')
            shutil.copyfile(supplied, source)
        if name in expected and sha256(source) != expected[name]:
            raise ValueError(f'Original hash mismatch: {source}')
        audio, rate, gain = render(source, track, settings)
        target = OUTPUT / (name + '.ogg')
        # FFmpeg bitexact output fixes the Ogg serial for reproducible builds.
        subprocess.run([imageio_ffmpeg.get_ffmpeg_exe(), '-hide_banner', '-loglevel', 'error',
                        '-y', '-f', 'f32le', '-ar', str(rate), '-ac', str(audio.shape[1]),
                        '-i', 'pipe:0', '-map_metadata', '-1', '-c:a', 'libvorbis',
                        '-q:a', '6', '-fflags', '+bitexact', '-flags:a', '+bitexact', str(target)],
                       input=audio.astype('<f4').tobytes(), check=True)
        write_import(target, track['crossfade_seconds'])
        decoded, _ = sf.read(target, always_2d=True)
        report.append(dict(name=name, original_filename=track['source_name'],
                           source=source.relative_to(ROOT).as_posix(), source_sha256=sha256(source),
                           output=target.relative_to(ROOT).as_posix(), sha256=sha256(target),
                           sample_rate=rate, channels=audio.shape[1], seconds=len(audio) / rate,
                           loop=bool(track['crossfade_seconds']), loop_offset=track['crossfade_seconds'],
                           gain_db=round(gain, 6), rms_db=round(float(20 * np.log10(np.sqrt(np.mean(decoded ** 2)))), 3),
                           true_peak_db=round(float(20 * np.log10(np.max(np.abs(resample_poly(decoded, 4, 1, axis=0))))), 3)))
        print(f'{name}: {len(audio) / rate:.3f}s; loop={track["crossfade_seconds"]}; gain={gain:.2f} dB')
    old_manifest.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')


if __name__ == '__main__':
    main()
