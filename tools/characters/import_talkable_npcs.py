"""Import the named talkable NPCs that still had no art (poet, philosopher, soldier).

Usage: python tools/characters/import_talkable_npcs.py --archive <zip>

Single supplied pose per character, so every direction reuses that frame. Two of
the portraits came back flattened onto a rendered transparency checkerboard; those
are cut with a noise/neutral-bright matte before trimming. Raw bytes stay in each
character's `source/` next to the archive entry and SHA-256.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage
from build_character_frames import build
from import_market_vendors import ROOT, save_text, single_frame, source_entries

ARCHIVE_PREFIX = "哥布林npc：有特定对话，不能重复利用的npc/其他可对话npc/"
ALPHA_FLOOR = 8
DEFINITIONS = [
    ("casino_poet", "哥布林诗人", "赌场里为黄金与格里芬吟诗、听不进人话的诗人。", "诗人",
     "job_d1b53dba84ef481abb7dc696cc746272_01.png", "微信图片_20261020035711_2405_2110.png", False),
    ("signature_philosopher", "酒馆外的哥布林哲人", "S08：与醉鬼争论格里芬、感官认知与幻觉。", "哲人",
     "job_3b0a6075a1c949b2b6e1b6cbbbf0d085_02.png",
     "e5d01d0c-4d1b-4592-83fe-8f37128379e1_0_0.png", True),
    ("barracks_soldier", "哥布林军人", "军营前高喊「犯我格里芬者，虽远必诛」的军人。", "军人",
     "job_c6ebed9cb1e64d66a6751f6aab722b3d_02.png",
     "870bf4a6-40f5-426e-9a83-42f147a3a0a2_0_2.png", True),
]


def cut_checkerboard(data: bytes) -> Image.Image:
    """Remove a rendered transparency checker flattened into an opaque portrait.

    The checker is bright, neutral and noisy; the character's armour and helmet are
    also grey but either darker or slightly saturated, so brightness plus saturation
    separates them. Enclosed leftovers (gaps between limbs) are dropped by looking at
    the holes of the remaining silhouette and keeping only bright neutral ones, which
    leaves teeth and eye highlights intact.
    """
    image = Image.open(io.BytesIO(data)).convert("RGBA")
    pixels = np.array(image)
    rgb = pixels[:, :, :3].astype(np.float32)
    luminance = rgb.mean(axis=2)
    saturation = rgb.max(axis=2) - rgb.min(axis=2)
    background = (saturation < 10) & (luminance > 140)
    background = ndimage.binary_opening(background, np.ones((3, 3)))
    for _ in range(3):
        holes = ndimage.binary_fill_holes(~background) & background
        labels, count = ndimage.label(holes)
        added = False
        for index in range(1, count + 1):
            area = labels == index
            if luminance[area].mean() > 190 and saturation[area].mean() < 4:
                background |= area
                added = True
        if not added:
            break
    pixels[background, 3] = 0
    return Image.fromarray(pixels, "RGBA")


def trimmed_portrait(image: Image.Image) -> tuple[Image.Image, list[int]]:
    mask = image.getchannel("A").point(lambda value: 255 if value > ALPHA_FLOOR else 0)
    box = mask.getbbox()
    if box is None:
        raise ValueError("Empty talkable NPC portrait")
    crop = [max(0, box[0] - 4), max(0, box[1] - 4), min(image.width, box[2] + 4), min(image.height, box[3] + 4)]
    portrait = image.crop(tuple(crop))
    portrait.putalpha(portrait.getchannel("A").point(lambda value: 0 if value <= ALPHA_FLOOR else value))
    return portrait, crop


def main(archive: Path) -> None:
    images = source_entries(archive)
    catalog = []
    for slug, name, role, folder, sprite_entry, portrait_entry, needs_cut in DEFINITIONS:
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
        source_portrait = cut_checkerboard(portrait) if needs_cut else Image.open(io.BytesIO(portrait)).convert("RGBA")
        portrait_image, crop = trimmed_portrait(source_portrait)
        portrait_image.save(directory / "portrait.png")
        sources = [
            {"archive": archive.name, "entry": sprite_path,
             "path": raw_sprite.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(sprite).hexdigest()},
            {"archive": archive.name, "entry": portrait_path,
             "path": raw_portrait.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(portrait).hexdigest(),
             "portrait_crop": crop,
             "derive": "checkerboard matte + 4px trim" if needs_cut else "alpha trim + 4px margin"},
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
                        "animations": animations, "source_entry": sprite_path})
    path = ROOT / "src/gameplay/characters/talkable_npc_catalog.json"
    save_text(path, json.dumps(catalog, ensure_ascii=False, indent=2))
    build(path)
    for entry in catalog:
        slug, name, role = entry["id"], entry["display_name"], entry["role"]
        scene = (ROOT / "src/gameplay/characters/common_goblin.tscn").read_text(encoding="utf-8")
        scene = (scene.replace("CommonGoblin", "".join(part.title() for part in slug.split("_")))
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
        print(slug, name, sheet.size, portrait_image.size)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    main(parser.parse_args().archive)
