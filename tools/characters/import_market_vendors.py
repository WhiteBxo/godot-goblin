"""Import the three market vendor NPCs from the supplied NPC archive.

Usage: python tools/characters/import_market_vendors.py --archive <zip>

Raw PNG bytes stay under each vendor's `source/`; derived sheets use the same
64px frame / 88px stride / baseline y=62 convention as the other NPCs, fitting the
actual artwork with nearest-neighbour sampling. Vendors have a single supplied
pose, so every direction reuses that frame and they never walk in the market.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import zipfile
from pathlib import Path

from PIL import Image

from build_character_frames import build

ROOT = Path(__file__).resolve().parents[2]
ARCHIVE_PREFIX = "哥布林npc：有特定对话，不能重复利用的npc/其他可对话npc/小贩/"
DEFINITIONS = [
    ("market_vendor_1", "吆喝的摊主", "集市上吆喝着卖食材的摊主。", "小贩1",
     "job_5aec32b66fe2407696340c48399b2c91_00.png", "微信图片_20261020032733_2381_2110.png"),
    ("market_vendor_2", "懂行的摊主", "集市上熟悉食材的摊主。", "小贩2",
     "job_9dc7ae9bd2804d12b8001e32084aa120_00.png", "微信图片_20261020032733_2380_2110.png"),
    ("market_vendor_3", "老练的摊主", "集市上老练的摊主。", "小贩3",
     "job_f5bba401c3f6462b84fc3af50dd678c5_01.png", "微信图片_20261020032733_2379_2110.png"),
]
FRAME = 64
BASELINE = 62
ART_HEIGHT = 58
ALPHA_FLOOR = 8


def save_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8", newline="\n")


def source_entries(path: Path) -> dict[str, bytes]:
    with zipfile.ZipFile(path) as archive:
        result = {}
        for entry in archive.infolist():
            name = entry.filename
            if not entry.flag_bits & 0x800:
                try:
                    name = name.encode("cp437").decode("gbk")
                except (UnicodeEncodeError, UnicodeDecodeError):
                    name = entry.filename
            if name.startswith("__MACOSX/") or not name.lower().endswith(".png"):
                continue
            result[name] = archive.read(entry)
        return result


def strip_ground_shadow(art: Image.Image, box: tuple[int, int, int, int]) -> Image.Image:
    """Drop a baked neutral-grey ground shadow; the scene draws its own."""
    pixels = art.load()
    width, height = art.size
    seen: set[tuple[int, int]] = set()
    queue: list[tuple[int, int]] = []
    # The shadow sits on the artwork's own bottom rows, inside the canvas margin.
    for y in range(max(box[1], box[3] - 4), box[3]):
        for x in range(box[0], box[2]):
            queue.append((x, y))

    def neutral(x: int, y: int) -> bool:
        red, green, blue, alpha = pixels[x, y]
        if alpha == 0:
            return False
        return max(red, green, blue) - min(red, green, blue) <= 6 and 40 <= (red + green + blue) / 3 <= 235

    while queue:
        x, y = queue.pop()
        if (x, y) in seen or not (0 <= x < width and 0 <= y < height) or not neutral(x, y):
            continue
        seen.add((x, y))
        queue.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
    if not seen:
        return art
    for x, y in seen:
        red, green, blue, _ = pixels[x, y]
        pixels[x, y] = (red, green, blue, 0)
    return art


def single_frame(data: bytes) -> Image.Image:
    """Fit the one supplied pose into the shared 64px canvas, feet on y=62."""
    art = Image.open(io.BytesIO(data)).convert("RGBA")
    box = art.getchannel("A").getbbox()
    if box is None:
        raise ValueError("Empty vendor sprite")
    art = strip_ground_shadow(art, box)
    box = art.getchannel("A").getbbox()
    if box is None:
        raise ValueError("Empty vendor sprite")
    art = art.crop(box)
    factor = min((FRAME - 4) / art.width, ART_HEIGHT / art.height)
    target = (max(1, round(art.width * factor)), max(1, round(art.height * factor)))
    art = art.resize(target, Image.Resampling.NEAREST)
    sheet = Image.new("RGBA", (FRAME, FRAME))
    sheet.paste(art, ((FRAME - target[0]) // 2, BASELINE - target[1]))
    return sheet


def trimmed_portrait(data: bytes) -> tuple[Image.Image, list[int]]:
    image = Image.open(io.BytesIO(data)).convert("RGBA")
    # Faint border noise (alpha 1-2) would keep the full canvas; trim the artwork.
    mask = image.getchannel("A").point(lambda value: 255 if value > ALPHA_FLOOR else 0)
    box = mask.getbbox()
    if box is None:
        raise ValueError("Empty vendor portrait")
    crop = [max(0, box[0] - 4), max(0, box[1] - 4), min(image.width, box[2] + 4), min(image.height, box[3] + 4)]
    portrait = image.crop(tuple(crop))
    alpha = portrait.getchannel("A").point(lambda value: 0 if value <= ALPHA_FLOOR else value)
    portrait.putalpha(alpha)
    return portrait, crop


def main(archive: Path) -> None:
    images = source_entries(archive)
    catalog = []
    for slug, name, role, folder, sprite_entry, portrait_entry in DEFINITIONS:
        directory = ROOT / "assets/characters/npc" / slug
        sprite_path = ARCHIVE_PREFIX + folder + "/" + sprite_entry
        portrait_path = ARCHIVE_PREFIX + folder + "/" + portrait_entry
        sprite = images[sprite_path]
        portrait = images[portrait_path]
        raw_sprite = directory / "source/idle_sheet.png"
        raw_portrait = directory / "source/portrait.png"
        for target, data in [(raw_sprite, sprite), (raw_portrait, portrait)]:
            target.parent.mkdir(parents=True, exist_ok=True)
            if target.exists() and target.read_bytes() != data:
                raise ValueError(f"Refusing to overwrite {target}")
            target.write_bytes(data)
        sheet = single_frame(sprite)
        sheet.save(directory / "idle_sheet.png")
        cropped, crop = trimmed_portrait(portrait)
        cropped.save(directory / "portrait.png")
        sources = [
            {"archive": archive.name, "entry": sprite_path,
             "path": raw_sprite.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(sprite).hexdigest()},
            {"archive": archive.name, "entry": portrait_path,
             "path": raw_portrait.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(portrait).hexdigest(),
             "portrait_crop": crop},
        ]
        save_text(directory / "source/sources.json", json.dumps(sources, ensure_ascii=False, indent=2))
        animations = {}
        for direction in ["down", "up", "left", "right"]:
            for kind in ["idle", "run"]:
                animations[f"{kind}_{direction}"] = {
                    "source": "idle_sheet", "fps": 6 if kind == "idle" else 8,
                    "first_only": True, "frame_count": 1}
        catalog.append({"id": slug, "display_name": name, "role": role,
                        "active_archive": archive.name, "side_faces_left": False,
                        "animations": animations,
                        "source_entry": sprite_path})
    path = ROOT / "src/gameplay/characters/market_vendor_catalog.json"
    save_text(path, json.dumps(catalog, ensure_ascii=False, indent=2))
    build(path)
    for entry in catalog:
        slug, name, role = entry["id"], entry["display_name"], entry["role"]
        scene = (ROOT / "src/gameplay/characters/common_goblin.tscn").read_text(encoding="utf-8")
        scene = (scene.replace("CommonGoblin", "".join(part.title() for part in slug.split("_")) + "")
                 .replace("common_goblin.gd", "settlement_character.gd")
                 .replace("common_goblin_frames.tres", slug + "_frames.tres")
                 .replace("&\"common_goblin\"", f"&\"{slug}\"")
                 .replace("普通哥布林", name)
                 .replace("聚落居民与奶茶店背景顾客。", role)
                 .replace("side_faces_left = true", "side_faces_left = false"))
        save_text(ROOT / f"src/gameplay/characters/{slug}.tscn", scene)
        rpg = (ROOT / "src/gameplay/characters/rpg_common_goblin.tscn").read_text(encoding="utf-8")
        rpg = (rpg.replace("CommonGoblin", "".join(part.title() for part in slug.split("_")))
               .replace("common_goblin.tscn", slug + ".tscn"))
        save_text(ROOT / f"src/gameplay/characters/rpg_{slug}.tscn", rpg)
        print(slug, name, sheet.size)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    main(parser.parse_args().archive)
