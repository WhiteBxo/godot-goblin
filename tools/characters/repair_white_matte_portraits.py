"""Re-cut the philosopher and soldier portraits from the 2026-10-20 re-exports.

Usage: python tools/characters/repair_white_matte_portraits.py \
           --portrait signature_philosopher=<png> --portrait barracks_soldier=<png>

The archive entries for these two characters arrived flattened onto a rendered
transparency checkerboard. The first pass cut them by brightness and saturation
and then dropped every bright neutral hole in the silhouette, which is also what
the eyes are: both portraits lost their eye whites, and the darker checker tone
survived near the philosopher's ear.

The 2026-10-20 re-exports put the same figures on plain white, so the background
is simply the white region connected to the frame border: interior white (eyes,
teeth, paper) is unreachable and stays. A light 1px rim next to the cut is
dropped as well, otherwise the antialiased edge reads as a white halo on the
dark dialogue panel. Same 4px margin and RGBA output as the other portraits.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ALPHA_FLOOR = 8
TRIMMED_MARGIN = 4
# Transparent pixels are painted with a colour no illustration uses, so the
# filled region can be read back from the probe image.
SENTINEL = (1, 2, 3)
BACKGROUND_THRESHOLD = 48
RIM_LUMINANCE = 195
RIM_SATURATION = 30
SUPPLIED_AT = "用户附件 2026-10-20（剪贴板）"
## Plain-white gaps the border cannot reach (between the arms and the body, the
## legs, under the shield). They are indistinguishable from eyes and teeth by
## colour alone, so each one is named in the supplied image's own pixel space.
## Re-check these coordinates whenever a new export changes the framing.
INTERIOR_BACKGROUND_SEEDS: dict[str, tuple[tuple[int, int], ...]] = {
    "signature_philosopher": ((443, 1107),),
    "barracks_soldier": ((372, 886), (687, 818), (527, 1064), (336, 1186)),
}


def cut_white_background(image: Image.Image, interior_seeds: tuple[tuple[int, int], ...] = ()) -> Image.Image:
    """Keep only what the border cannot reach through near-white pixels."""
    rgba = image.convert("RGBA")
    pixels = np.array(rgba)
    rgb = pixels[:, :, :3].astype(np.int16)
    luminance = rgb.mean(axis=2)
    saturation = rgb.max(axis=2) - rgb.min(axis=2)
    probe = rgba.convert("RGB")
    for corner in [(0, 0), (probe.width - 1, 0), (0, probe.height - 1), (probe.width - 1, probe.height - 1)]:
        if probe.getpixel(corner) != SENTINEL:
            ImageDraw.floodfill(probe, corner, SENTINEL, thresh=BACKGROUND_THRESHOLD)
    for seed in interior_seeds:
        red, green, blue = probe.getpixel(seed)
        if min(red, green, blue) < 235 or max(red, green, blue) - min(red, green, blue) > 12:
            raise ValueError(f"Interior background seed {seed} is not plain white: {(red, green, blue)}")
        if probe.getpixel(seed) != SENTINEL:
            ImageDraw.floodfill(probe, seed, SENTINEL, thresh=BACKGROUND_THRESHOLD)
    outside = np.all(np.array(probe) == np.array(SENTINEL, dtype=np.uint8), axis=2)
    padded = np.pad(outside, 1, constant_values=False)
    neighbour_count = np.zeros(outside.shape, dtype=np.uint8)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            neighbour_count += padded[1 + dy:1 + dy + outside.shape[0], 1 + dx:1 + dx + outside.shape[1]]
    rim = (~outside) & (neighbour_count >= 2) & (luminance > RIM_LUMINANCE) & (saturation <= RIM_SATURATION)
    pixels[:, :, 3] = np.where(outside | rim, 0, 255).astype(np.uint8)
    return Image.fromarray(pixels, "RGBA")


def trimmed(image: Image.Image) -> tuple[Image.Image, list[int]]:
    mask = image.getchannel("A").point(lambda value: 255 if value > ALPHA_FLOOR else 0)
    box = mask.getbbox()
    if box is None:
        raise ValueError("Empty portrait after the cut")
    crop = [max(0, box[0] - TRIMMED_MARGIN), max(0, box[1] - TRIMMED_MARGIN),
            min(image.width, box[2] + TRIMMED_MARGIN), min(image.height, box[3] + TRIMMED_MARGIN)]
    portrait = image.crop(tuple(crop))
    portrait.putalpha(portrait.getchannel("A").point(lambda value: 0 if value <= ALPHA_FLOOR else value))
    return portrait, crop


def supplied_raw_name(path: Path) -> str:
    return "portrait_2026_10_20" + path.suffix.lower()


def main(pairs: list[tuple[str, Path]]) -> None:
    for slug, path in pairs:
        directory = ROOT / "assets/characters/npc" / slug
        data = path.read_bytes()
        raw = directory / "source" / supplied_raw_name(path)
        raw.parent.mkdir(parents=True, exist_ok=True)
        raw.write_bytes(data)
        seeds = INTERIOR_BACKGROUND_SEEDS.get(slug, ())
        portrait, crop = trimmed(cut_white_background(Image.open(path), seeds))
        portrait.save(directory / "portrait.png")
        sources_path = directory / "source/sources.json"
        entries = json.loads(sources_path.read_text(encoding="utf-8")) if sources_path.exists() else []
        relative = raw.relative_to(ROOT).as_posix()
        entries = [entry for entry in entries if entry.get("path") != relative]
        entries.append({
            "archive": SUPPLIED_AT,
            "entry": path.name,
            "path": relative,
            "sha256": hashlib.sha256(data).hexdigest(),
            "portrait_crop": crop,
            "derive": "white-background flood cut + 1px rim trim + 4px margin",
            "replaces": "source/portrait.png（棋盘抠图，眼睛被当背景扣掉）",
        })
        sources_path.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n",
                                encoding="utf-8", newline="\n")
        print(slug, portrait.size, crop)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--portrait", action="append", required=True, metavar="SLUG=PATH",
                        help="character slug and the supplied white-background PNG, repeatable")
    argv = parser.parse_args()
    parsed = []
    for item in argv.portrait:
        slug, _, raw_path = item.partition("=")
        if not slug or not raw_path:
            parser.error("--portrait expects SLUG=PATH")
        parsed.append((slug, Path(raw_path)))
    main(parsed)
