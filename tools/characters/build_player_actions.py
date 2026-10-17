"""Build player animations from preserved PNGs; optionally extract the supplied ZIP.

Usage: python tools/characters/build_player_actions.py [--archive PATH]
Requires Pillow. Outputs the runtime atlas and SpriteFrames, never edits source PNGs.
"""
from __future__ import annotations

import argparse
import zipfile
from pathlib import Path

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets/characters/player"
SOURCES = ASSETS / "action_sources"
# Each tuple is (ZIP directory, down file, right file, up file, FPS).
SPECS = {
    "idle": ("站立待机", "IMG_4347.png", "合并图片 2.png", "合并图片.png", 8),
    "walk": ("走路", "合并图片.png", "合并图片 2.png", "合并图片 3.png", 12),
    "run": ("奔跑", "合并图片.png", "合并图片 2.png", "合并图片 3.png", 18),
    "sneak": ("潜行", "合并图片 3.png", "合并图片 2.png", "合并图片.png", 12),
    "crouch_idle": ("蹲下待机", "合并图片 2.png", "合并图片.png", "合并图片 3.png", 10),
    "throw": ("投掷", "合并图片 2.png", "合并图片.png", "合并图片 3.png", 12),
}
DIRECTIONS = ("down", "right", "up")
CELL = (224, 300)


def extract(archive: Path) -> None:
    SOURCES.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as bundle:
        entries = {}
        for info in bundle.infolist():
            name = info.filename
            if not info.flag_bits & 0x800:
                name = name.encode("cp437").decode("utf-8")
            entries[name] = info
        for action, (folder, *files, _fps) in SPECS.items():
            for direction, filename in zip(DIRECTIONS, files):
                data = bundle.read(entries[f"主角动作合集/{folder}/{filename}"])
                target = SOURCES / f"{action}_{direction}.png"
                if target.exists() and target.read_bytes() != data:
                    raise ValueError(f"Refusing to overwrite different source: {target}")
                target.write_bytes(data)


def read_poses(action: str, direction: str) -> list[Image.Image]:
    image = Image.open(SOURCES / f"{action}_{direction}.png").convert("RGBA")
    if (action, direction) == ("idle", "down"):
        # The large front-idle export has five columns and two rows, no gutters.
        assert image.size == (4096, 1640)
        return [image.crop((round(x * image.width / 5), y * 820,
                            round((x + 1) * image.width / 5), (y + 1) * 820))
                .resize((64, 64), Image.Resampling.NEAREST)
                for y in range(2) for x in range(5)]
    assert image.width == 504 and image.height in (64, 152, 240)
    poses = []
    for y in range(0, image.height, 88):
        for x in range(0, image.width, 88):
            pose = image.crop((x, y, x + 64, y + 64))
            if pose.getchannel("A").getbbox():
                poses.append(pose)
    return poses


def build() -> None:
    atlas = Image.new("RGBA", (16 * CELL[0], 24 * CELL[1]))
    textures, animations = [], []
    texture_id = 0
    for action, spec in SPECS.items():
        poses_by_direction = {d: read_poses(action, d) for d in DIRECTIONS}
        poses_by_direction["left"] = [ImageOps.mirror(p) for p in poses_by_direction["right"]]
        for direction in ("down", "left", "right", "up"):
            row = len(animations)
            refs = []
            poses = poses_by_direction[direction]
            assert 1 < len(poses) <= 16, (action, direction, len(poses))
            # One ground anchor for the whole cycle, never normalize each frame.
            ground = max(p.getchannel("A").point(lambda a: 255 if a >= 230 else 0)
                         .getbbox()[3] for p in poses)
            top = 294 - round(ground * 3.5)
            for index, pose in enumerate(poses):
                texture_id += 1
                x, y = index * CELL[0], row * CELL[1]
                # Uniform 3.5x scale retains the artist's body bounce.
                scaled = pose.resize((224, 224), Image.Resampling.NEAREST)
                tile = Image.new("RGBA", CELL)
                tile.alpha_composite(scaled, (0, top))
                atlas.paste(tile, (x, y))
                textures.append(f'[sub_resource type="AtlasTexture" id="Pose_{texture_id}"]\n'
                                f'atlas = ExtResource("1_atlas")\n'
                                f'region = Rect2({x}, {y}, {CELL[0]}, {CELL[1]})\n'
                                'filter_clip = true\n')
                refs.append('{"duration": 1.0, "texture": SubResource("Pose_%d")}' % texture_id)
            animations.append('{"frames": [%s], "loop": %s, "name": &"%s_%s", "speed": %.1f}'
                              % (", ".join(refs), "false" if action == "throw" else "true",
                                 action, direction, spec[-1]))
            print(f"{action}_{direction}: {len(poses)} frames")
    atlas.save(ASSETS / "player_actions_atlas.png")
    resource = ('[gd_resource type="SpriteFrames" load_steps=%d format=3]\n\n' % (texture_id + 2)
                + '[ext_resource type="Texture2D" path="res://assets/characters/player/player_actions_atlas.png" id="1_atlas"]\n\n'
                + "\n".join(textures) + "\n[resource]\nanimations = [\n"
                + ",\n".join(animations) + "\n]\n")
    (ROOT / "src/gameplay/player/player_actions_frames.tres").write_text(resource, encoding="utf-8", newline="\n")
    print(f"PLAYER_ACTIONS: {texture_id} frames, 24 animations")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path)
    args = parser.parse_args()
    if args.archive:
        extract(args.archive)
    build()
