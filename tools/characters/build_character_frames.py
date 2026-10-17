"""Build editable SpriteFrames from original sheets, without modifying image pixels.
Run from any directory with Python 3 (standard library only).
"""
import argparse
import json
import zipfile
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'src/gameplay/characters'


def build(catalog_path=DEST / 'character_catalog.json', archive=None):
    catalog = json.loads(catalog_path.read_text(encoding='utf-8'))
    if archive is not None:
        with zipfile.ZipFile(archive) as bundle:
            entries = {}
            for entry in bundle.infolist():
                name = entry.filename
                if not entry.flag_bits & 0x800:
                    name = name.encode('cp437').decode('utf-8')
                entries[name] = entry
            for character in catalog:
                for animation in character['animations'].values():
                    data = bundle.read(entries[animation['source_entry']])
                    target = ROOT / 'assets/characters/npc' / character['id'] / (animation['source'] + '.png')
                    target.parent.mkdir(parents=True, exist_ok=True)
                    if target.exists() and target.read_bytes() != data:
                        raise ValueError(f'Refusing to overwrite different source: {target}')
                    target.write_bytes(data)
    for character in catalog:
        slug = character['id']
        sources = sorted({a['source'] for a in character['animations'].values()})
        lines = ['[gd_resource type="SpriteFrames" format=3]', '']
        frames = {}
        resources = []
        for index, source in enumerate(sources):
            path = f'assets/characters/npc/{slug}/{source}.png'
            width, height = struct.unpack('>II', (ROOT / path).read_bytes()[16:24])
            size, stride = (128, 152) if width == 888 else (64, 88)
            columns = (width - size) // stride + 1
            rows = (height - size) // stride + 1
            # Count is visually checked: trailing cells are frequently empty.
            count = next(a["frame_count"] for a in character["animations"].values() if a["source"] == source)
            frames[source] = []
            resources += [f'[ext_resource type="Texture2D" path="res://{path}" id="{index}"]', '']
            for frame in range(count):
                ident = f'{index}_{frame}'
                frames[source].append(ident)
                lines += [f'[sub_resource type="AtlasTexture" id="{ident}"]',
                          f'atlas = ExtResource("{index}")',
                          f'region = Rect2({frame % columns * stride}, {frame // columns * stride}, {size}, {size})',
                          'filter_clip = true', '']
        lines[2:2] = resources
        lines += ['[resource]', 'animations = [']
        for name, animation in character['animations'].items():
            ids = frames[animation['source']]
            if animation['first_only']:
                ids = ids[:1]
            entries = ', '.join('{"duration": 1.0, "texture": SubResource("%s")}' % i for i in ids)
            lines += ['{', f'"frames": [{entries}],', '"loop": true,',
                      f'"name": &"{name}",', f'"speed": {float(animation["fps"])}', '},']
        lines += [']', '']
        (DEST / f'{slug}_frames.tres').write_text('\n'.join(lines), encoding='utf-8', newline='\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--catalog', type=Path, default=DEST / 'character_catalog.json')
    parser.add_argument('--archive', type=Path, help='Import byte-identical PNG sources named by source_entry')
    args = parser.parse_args()
    build(args.catalog, args.archive)
