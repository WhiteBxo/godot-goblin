"""Import supplied sheets unchanged and build Godot SpriteFrames (Python stdlib only)."""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import zipfile

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / 'assets/characters/goblin_actions'
FRAMES = ROOT / 'src/gameplay/goblin_actions'
# Source filenames are provenance, not instructions. Side poses face right.
SHEETS = [
    ('goblin', 'walk_down', '普通哥布林走路（无背包/合并图片.png', 64, 9),
    ('goblin', 'walk_side', '普通哥布林走路（无背包/合并图片 4.png', 64, 15),
    ('goblin', 'walk_up', '普通哥布林走路（无背包/合并图片 5.png', 64, 15),
    ('captain', 'attack_side', '攻击动画/守卫长/合并图片.png', 256, 13),
    ('captain', 'attack_down', '攻击动画/守卫长/合并图片 2.png', 256, 10),
    ('captain', 'attack_up', '攻击动画/守卫长/合并图片 3.png', 256, 9),
    ('guard', 'attack_side', '攻击动画/守卫/合并图片.png', 64, 10),
    ('guard', 'attack_down', '攻击动画/守卫/合并图片 2.png', 64, 9),
    ('guard', 'attack_up', '攻击动画/守卫/合并图片 3.png', 64, 10),
    ('chef', 'attack_up', '攻击动画/厨师/合并图片.png', 64, 9),
    ('chef', 'attack_down', '攻击动画/厨师/合并图片 2.png', 64, 12),
    ('chef', 'attack_side', '攻击动画/厨师/合并图片 3.png', 64, 9),
    ('goblin', 'attack_side', '攻击动画/普通哥布林/合并图片.png', 64, 12),
    ('goblin', 'attack_up', '攻击动画/普通哥布林/合并图片 2.png', 64, 8),
    ('goblin', 'attack_down', '攻击动画/普通哥布林/合并图片 3.png', 64, 9),
]


def build(archive=None):
    ASSETS.mkdir(parents=True, exist_ok=True)
    FRAMES.mkdir(parents=True, exist_ok=True)
    sources = {}
    if archive:
        with zipfile.ZipFile(archive) as bundle:
            for entry in bundle.infolist():
                name = entry.filename
                if not entry.flag_bits & 0x800:
                    name = name.encode('cp437').decode('utf-8')
                if name.endswith('.png') and not name.startswith('__MACOSX/'):
                    sources[name.removeprefix('攻击动画合集/')] = bundle.read(entry)
    manifest = []
    for actor, action, original, cell, count in SHEETS:
        filename = f'{actor}_{action}.png'
        target = ASSETS / filename
        if archive:
            target.write_bytes(sources[original])
        data = target.read_bytes()
        stride = cell + 24
        size = struct.unpack('>II', data[16:24])
        assert size == (6 * stride - 24, ((count + 5) // 6) * stride - 24), filename
        manifest.append(dict(actor=actor, animation=action, source='攻击动画合集/' + original,
                             file=filename, cell=cell, stride=stride, columns=6, count=count,
                             fps=12, loop=action.startswith('walk_'), sha256=hashlib.sha256(data).hexdigest()))
    (ASSETS / 'manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    for actor in dict.fromkeys(row['actor'] for row in manifest):
        rows = [row for row in manifest if row['actor'] == actor]
        lines = ['[gd_resource type="SpriteFrames" format=3]', '']
        for row in rows:
            lines += [f'[ext_resource type="Texture2D" path="res://assets/characters/goblin_actions/{row["file"]}" id="{row["animation"]}"]', '']
        animations = []
        for row in rows:
            action, cell, stride = row['animation'], row['cell'], row['stride']
            entries = []
            for index in range(row['count']):
                resource_id = f'{action}_{index:02d}'
                lines += [f'[sub_resource type="AtlasTexture" id="{resource_id}"]',
                          f'atlas = ExtResource("{action}")',
                          f'region = Rect2({index % 6 * stride}, {index // 6 * stride}, {cell}, {cell})',
                          'filter_clip = true', '']
                entries.append('{"duration": 1.0, "texture": SubResource("' + resource_id + '")}')
            animations.append('{\n"frames": [' + ',\n'.join(entries) + '],\n"loop": ' + str(row['loop']).lower() + ',\n"name": &"' + action + '",\n"speed": 12.0\n}')
        lines += ['[resource]', 'animations = [' + ',\n'.join(animations) + ']', '']
        (FRAMES / f'{actor}_frames.tres').write_text('\n'.join(lines))
    print(f'Imported {len(manifest)} animations, {sum(row["count"] for row in manifest)} frames.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', nargs='?', type=Path, help='Omit to rebuild from imported PNGs')
    build(parser.parse_args().archive)
