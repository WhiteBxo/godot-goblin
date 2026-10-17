"""Build editable SpriteFrames from original sheets, without modifying image pixels.
Run from any directory with Python 3 (standard library only).
"""
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'src/gameplay/characters'


def build():
    catalog = json.loads((DEST / 'character_catalog.json').read_text())
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
        (DEST / f'{slug}_frames.tres').write_text('\n'.join(lines))


if __name__ == '__main__':
    build()
