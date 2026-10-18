"""Build recorded CC0 SFX. First use --archive-dir D:/download, then rebuild without it.
Every edit is declared in sound_selection.json; requires requirements.txt.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import re
import wave
import zipfile
import numpy as np
import soundfile as sf
from scipy.signal import butter, resample_poly, sosfiltfilt

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/audio/source'
RATE = 44100
PACKS = {'rpg_sfx': '80-CC0-RPG-SFX.zip', 'tinysized': 'tinysized.zip', 'accessory': 'accessory.zip'}


def write_text(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding='utf-8', newline='\n')


def digest(data):
    return hashlib.sha256(data).hexdigest()


def import_archives(directory):
    packs = []
    for pack, filename in PACKS.items():
        archive = directory / filename
        files = []
        with zipfile.ZipFile(archive) as zipped:
            for entry in zipped.infolist():
                if entry.is_dir():
                    continue
                output = (SOURCE / pack / entry.filename).resolve()
                if not output.is_relative_to((SOURCE / pack).resolve()):
                    raise ValueError(f'Unsafe archive path: {entry.filename}')
                data = zipped.read(entry)
                output.parent.mkdir(parents=True, exist_ok=True)
                if output.exists() and output.read_bytes() != data:
                    raise ValueError(f'Refusing to overwrite modified source: {output}')
                output.write_bytes(data)
                files.append(dict(path=output.relative_to(ROOT).as_posix(), sha256=digest(data)))
        packs.append(dict(pack=pack, archive=filename, archive_sha256=digest(archive.read_bytes()), files=files))
    write_text(SOURCE / 'manifest.json', json.dumps(packs, ensure_ascii=False, indent=2) + '\n')
    write_text(SOURCE / '.gdignore', '')
    write_text(SOURCE / '.gitattributes', '* -text\n')


def read_sample(part):
    audio, rate = sf.read(SOURCE / part['source'], always_2d=True)
    audio = audio.mean(axis=1)
    divisor = math.gcd(rate, RATE)
    if rate != RATE:
        audio = resample_poly(audio, RATE // divisor, rate // divisor)
    start = round(part.get('start', 0) * RATE)
    end = start + round(part['duration'] * RATE) if 'duration' in part else len(audio)
    audio = audio[start:end]
    if not len(audio):
        raise ValueError(f'Empty selection: {part}')
    if not part.get('bed', False):
        active = np.flatnonzero(abs(audio) > max(abs(audio)) * .025)
        if len(active):
            audio = audio[max(0, active[0] - 220):min(len(audio), active[-1] + 882)]
    speed = part.get('speed', 1)
    if speed != 1:
        audio = np.interp(np.arange(0, len(audio), speed), np.arange(len(audio)), audio)
    audio -= audio.mean()
    audio = sosfiltfilt(butter(6, [55, 5500], btype='bandpass', fs=RATE, output='sos'), audio)
    fade = min(220, len(audio) // 4)
    audio[:fade] *= np.linspace(0, 1, fade)
    audio[-fade:] *= np.linspace(1, 0, fade)
    return audio / max(.000001, max(abs(audio))) * part.get('gain', 1)


def render(recipe, looping, target):
    parts = [(part, read_sample(part)) for part in recipe['parts']]
    length = round(recipe.get('seconds', max(part.get('at', 0) + len(x) / RATE for part, x in parts)) * RATE)
    mixed = np.zeros(length)
    for part, audio in parts:
        if part.get('bed', False):
            hop = max(1, len(audio) // 2)
            audio = audio * np.sin(np.linspace(0, np.pi, len(audio))) ** 2
            positions = range(0, length, hop)
        else:
            positions = [round(t * RATE) for t in part.get('times', [part.get('at', 0)])]
        for position in positions:
            if looping:
                np.add.at(mixed, (np.arange(len(audio)) + position) % length, audio)
            elif position < length:
                size = min(len(audio), length - position)
                mixed[position:position + size] += audio[:size]
    if recipe.get('echo', False):
        for delay, gain in [(.071, .2), (.139, .1)]:
            shift = round(delay * RATE)
            mixed += np.roll(mixed, shift) * gain if looping else np.pad(mixed[:-shift], (shift, 0)) * gain
    mixed -= mixed.mean()
    if not looping:
        audible = np.flatnonzero(abs(mixed) > max(abs(mixed)) * .003)
        mixed = mixed[:min(len(mixed), audible[-1] + 1764)]
    if looping:
        fade = 2205
        mixed[-fade:] = mixed[-fade:] * np.linspace(1, 0, fade) + mixed[:fade] * np.linspace(0, 1, fade)
        mixed[-1] = mixed[0]
    else:
        fade = min(353, len(mixed) // 4)
        mixed[:fade] *= np.linspace(0, 1, fade)
        mixed[-fade:] *= np.linspace(1, 0, fade)
    active = abs(mixed) > max(abs(mixed)) * .04
    rms = np.sqrt(np.mean(mixed[active] ** 2))
    mixed *= min(10 ** (target / 20) / max(rms, 1e-9), .44 / max(abs(mixed)))
    return np.round(mixed * 32767).astype('<i2')


def write_import(path, looping):
    import_path = path.with_suffix('.wav.import')
    previous = import_path.read_text(encoding='utf-8') if import_path.exists() else ''
    uid = re.search(r'^uid="[^"]+"', previous, re.M)
    source = 'res://' + path.relative_to(ROOT).as_posix()
    cache = 'res://.godot/imported/' + path.name + '-' + hashlib.md5(source.encode()).hexdigest() + '.sample'
    settings = '[remap]\n\nimporter="wav"\ntype="AudioStreamWAV"\n'
    if uid:
        settings += uid[0] + '\n'
    settings += f'path="{cache}"\n\n[deps]\n\nsource_file="{source}"\ndest_files=["{cache}"]\n\n[params]\n\n'
    settings += 'force/8_bit=false\nforce/mono=false\nforce/max_rate=false\nforce/max_rate_hz=44100\nedit/trim=false\nedit/normalize=false\n'
    settings += f'edit/loop_mode={2 if looping else 1}\nedit/loop_begin=0\nedit/loop_end=-1\ncompress/mode=0\n'
    write_text(import_path, settings)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive-dir', type=Path)
    args = parser.parse_args()
    if args.archive_dir:
        import_archives(args.archive_dir)
    specs = json.loads(Path(__file__).with_name('sound_selection.json').read_text(encoding='utf-8'))
    for pack in json.loads((SOURCE / 'manifest.json').read_text(encoding='utf-8')):
        for entry in pack['files']:
            if digest((ROOT / entry['path']).read_bytes()) != entry['sha256']:
                raise ValueError(f"Source hash mismatch: {entry['path']}")
    report, entries, ext = [], [], []
    mapping = ['# 音效 ID 与资源映射（生成文件）', '', '由 `tools/audio/generate_sound_pack.py` 和 `sound_selection.json` 生成。基础 ID 指向首变体；原始路径相对 `assets/audio/source/`。', '', '| 基础 ID | 用途与适配说明 | 变体 ID / 成品路径 / 秒 / 原始素材 |', '| --- | --- | --- |']
    for spec in specs:
        sound_id, label = spec['id'], spec['label']
        category, name = sound_id.split('.')
        looping = spec.get('loop', False)
        variants = spec['variants']
        refs, descriptions = [], []
        for index, recipe in enumerate(variants):
            filename = name + (f'_{index + 1:02}' if len(variants) > 1 else '') + '.wav'
            path = ROOT / 'assets/audio' / category / filename
            path.parent.mkdir(parents=True, exist_ok=True)
            target = -32 if looping else (-28 if sound_id == 'ui.dialogue' else -23)
            pcm = render(recipe, looping, target)
            with wave.open(str(path), 'wb') as wav:
                wav.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
                wav.writeframes(pcm.tobytes())
            write_import(path, looping)
            relative = path.relative_to(ROOT).as_posix()
            resource_id = f's{len(ext) + 1}'
            ext.append(f'[ext_resource type="AudioStream" path="res://{relative}" id="{resource_id}"]')
            refs.append(f'ExtResource("{resource_id}")')
            variant_id = sound_id if len(variants) == 1 else f'{sound_id}.{index + 1:02}'
            sources = sorted({'assets/audio/source/' + part['source'] for part in recipe['parts']})
            report.append(dict(id=variant_id, path=relative, loop=looping, seconds=round(len(pcm) / RATE, 6), sha256=digest(path.read_bytes()), sources=sources, recipe=recipe))
            descriptions.append(f'`{variant_id}` → `res://{relative}` ({len(pcm) / RATE:.3f})；' + ', '.join('`' + s.removeprefix('assets/audio/source/') + '`' for s in sources))
        entries.append('{"id": "%s", "label": "%s", "loop": %s, "streams": [%s]}' % (sound_id, label, str(looping).lower(), ', '.join(refs)))
        mapping.append(f'| `{sound_id}` | {label}；{spec["note"]} | ' + '<br>'.join(descriptions) + ' |')
    ext.append('[ext_resource type="AudioStream" path="res://assets/audio/music/daily_milk_tea.ogg" id="music"]')
    entries.append('{"id": "music.daily_milk_tea", "label": "奶茶店日常 BGM", "loop": true, "loop_offset": 68.279, "streams": [ExtResource("music")]}')
    mapping.append('| `music.daily_milk_tea` | 用户提供原音乐 | `res://assets/audio/music/daily_milk_tea.ogg`；末尾回到 68.279 秒 |')
    resource = '[gd_resource type="Resource" script_class="SoundLibrary" load_steps=%d format=3]\n\n' % (len(ext) + 2)
    resource += '[ext_resource type="Script" path="res://src/resources/audio/sound_library.gd" id="1"]\n' + '\n'.join(ext)
    resource += '\n\n[resource]\nscript = ExtResource("1")\nentries = Array[Dictionary]([\n' + ',\n'.join(entries) + '\n])\n'
    write_text(ROOT / 'src/resources/audio/sound_library.tres', resource)
    write_text(ROOT / 'assets/audio/manifest.json', json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    write_text(ROOT / 'docs/assets/sound_library_ids.md', '\n'.join(mapping) + '\n')
    import runpy
    runpy.run_path(str(ROOT / 'tools/story/generate_demo_knock.py'), run_name='__main__')
    print(f'Built {len(report)} sampled WAVs / {len(specs)} base IDs; preserved music.daily_milk_tea.')


if __name__ == '__main__':
    main()
