"""Sample casino source art at explicit integer factors and package sprites.

Run from any working directory with Pillow installed::

    python tools/art/prepare_casino_refresh.py

The generator did not honor the requested 8x pixel-grid contract. Sources are
therefore sampled with an explicit, individually reviewed integer factor, equal
on both axes. No object is fitted, stretched, recolored, or painted. Source art
and its actual dimensions remain intact, and all deviations are in the manifest.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "assets/map/rpg_maker/casino_refresh"
REQUESTED_MASTER_SCALE = 8
TILE_SIZE = 48
MARGIN = 2
ALPHA_THRESHOLD = 128
MODEL = "gpt-image-2.5-sunburst"
REFERENCE = "reference/map_005_native.png"
FONT_PATH = Path("C:/Windows/Fonts/msyh.ttc")


@dataclass(frozen=True)
class SpriteSpec:
    asset_id: str
    label: str
    size: tuple[int, int]


@dataclass(frozen=True)
class SourceSpec:
    source_id: str
    requested_master_size: tuple[int, int]
    sample_factor: int | None
    sprites: tuple[SpriteSpec, ...]


SOURCES = (
    SourceSpec("gambling_table", (1024, 1536), 10, (
        SpriteSpec("gambling_table", "破旧赌桌", (96, 144)),
    )),
    SourceSpec("round_stool", (1024, 1024), 12, (
        SpriteSpec("round_stool", "圆木凳", (48, 48)),
    )),
    SourceSpec("dice_cup", (1024, 1024), 16, (
        SpriteSpec("dice_cup", "骰盅", (48, 48)),
    )),
    SourceSpec("dice_set", (1024, 1024), 20, (
        SpriteSpec("die_d4", "骨质四面骰", (48, 48)),
        SpriteSpec("die_d6", "金属六面骰", (48, 48)),
        SpriteSpec("die_d12", "矿石十二面骰", (48, 48)),
    )),
    SourceSpec("chips", (1024, 1024), 20, (
        SpriteSpec("chips", "磨损筹码", (48, 48)),
    )),
    SourceSpec("clay_cups", (1024, 1024), 20, (
        SpriteSpec("clay_cup_upright", "陶杯·直立", (48, 48)),
        SpriteSpec("clay_cup_tilt_a", "陶杯·左倾", (48, 48)),
        SpriteSpec("clay_cup_tilt_b", "陶杯·右倾", (48, 48)),
    )),
    SourceSpec("wall_oil_lamp", (1024, 1536), 20, (
        SpriteSpec("wall_oil_lamp", "墙挂油灯", (48, 96)),
    )),
    SourceSpec("boss_desk", (1536, 1024), 10, (
        SpriteSpec("boss_desk", "老板书桌", (144, 144)),
    )),
    SourceSpec("ledger", (1024, 1024), 22, (
        SpriteSpec("ledger", "账本", (48, 48)),
    )),
)


def harden_alpha(image: Image.Image) -> Image.Image:
    """Keep the supplied alpha mask, harden its edge, and clear invisible RGB."""
    rgba = image.convert("RGBA")
    alpha = rgba.getchannel("A").point(
        lambda value: 255 if value >= ALPHA_THRESHOLD else 0
    )
    clean = Image.new("RGBA", rgba.size, (0, 0, 0, 0))
    clean.paste(rgba, (0, 0), alpha)
    clean.putalpha(alpha)
    return clean


def load_source(spec: SourceSpec) -> tuple[Image.Image, dict]:
    path = ART / "source" / f"{spec.source_id}.png"
    with Image.open(path) as source:
        rgba = source.convert("RGBA")
    alpha = rgba.getchannel("A")
    minimum, maximum = alpha.getextrema()
    if minimum == 255 or maximum < ALPHA_THRESHOLD:
        raise ValueError(f"{path.name}: a visible asset on real alpha is required.")
    rgba = harden_alpha(rgba)
    master_box = rgba.getchannel("A").getbbox()
    if master_box is None:
        raise ValueError(f"{path.name}: the source is empty.")
    if (master_box[0] == 0 or master_box[1] == 0
            or master_box[2] == rgba.width or master_box[3] == rgba.height):
        raise ValueError(f"{path.name}: alpha touches a master edge; silhouette may be cut.")
    return rgba, {
        "path": f"source/{spec.source_id}.png",
        "actual_source_dimensions_px": list(rgba.size),
        "requested_source_dimensions_px": list(spec.requested_master_size),
        "source_size_matches_request": rgba.size == spec.requested_master_size,
        "requested_pixel_grid_scale": REQUESTED_MASTER_SCALE,
        "requested_pixel_grid_contract_honored": False,
        "sample_factor": spec.sample_factor,
        "source_alpha_bbox": list(master_box),
        "prompt": f"prompts/{spec.source_id}.txt",
    }


def components(alpha: Image.Image) -> list[dict]:
    """Find 8-connected components with run lengths, retaining their exact masks."""
    width, height = alpha.size
    pixels = alpha.tobytes()
    parents, runs, previous = [], [], []

    def find(label: int) -> int:
        while parents[label] != label:
            parents[label] = parents[parents[label]]
            label = parents[label]
        return label

    for y in range(height):
        row = pixels[y * width:(y + 1) * width]
        current, cursor, previous_cursor = [], 0, 0
        while cursor < width:
            start = row.find(b"\xff", cursor)
            if start == -1:
                break
            end = row.find(b"\x00", start)
            if end == -1:
                end = width
            label = len(parents)
            parents.append(label)
            while previous_cursor < len(previous) and previous[previous_cursor][1] < start:
                previous_cursor += 1
            for a, b, other in previous[previous_cursor:]:
                if a > end:
                    break
                one, two = find(label), find(other)
                if one != two:
                    parents[one] = two
            current.append((start, end, label))
            runs.append((y, start, end, label))
            cursor = end
        previous = current
    groups = {}
    for y, start, end, label in runs:
        group = groups.setdefault(find(label), {
            "bbox": [start, y, end, y + 1], "area": 0, "runs": [],
        })
        group["runs"].append((y, start, end))
        group["area"] += end - start
        box = group["bbox"]
        box[:] = [min(box[0], start), min(box[1], y), max(box[2], end), max(box[3], y + 1)]
    return list(groups.values())


def source_regions(spec: SourceSpec, rgba: Image.Image) -> tuple[list[tuple[Image.Image, list[int]]], dict]:
    alpha = rgba.getchannel("A")
    if len(spec.sprites) == 1:
        bbox = list(alpha.getbbox())
        return [(rgba.crop(bbox), bbox)], {"object_count": 1}
    groups = components(alpha)
    minimum_area = max(group["area"] for group in groups) * 0.001
    main_groups = [group for group in groups if group["area"] >= minimum_area]
    if len(main_groups) != 3:
        raise ValueError(
            f"{spec.source_id}: found {len(main_groups)} main alpha silhouettes "
            f"after ignoring components below {minimum_area:g}px, expected exactly 3."
        )
    main_groups.sort(key=lambda group: group["bbox"][0])
    if any(left["bbox"][2] >= right["bbox"][0]
           for left, right in zip(main_groups, main_groups[1:])):
        raise ValueError(f"{spec.source_id}: the three objects must have horizontal transparent gaps.")
    regions = []
    for group in main_groups:
        bbox = group["bbox"]
        mask = Image.new("L", (bbox[2] - bbox[0], bbox[3] - bbox[1]), 0)
        draw = ImageDraw.Draw(mask)
        for y, start, end in group["runs"]:
            draw.line((start - bbox[0], y - bbox[1], end - 1 - bbox[0], y - bbox[1]), fill=255)
        crop = Image.new("RGBA", mask.size, (0, 0, 0, 0))
        crop.paste(rgba.crop(bbox), (0, 0), mask)
        regions.append((crop, bbox))
    return regions, {
        "object_count": 3,
        "component_noise_area_fraction_of_largest": 0.001,
        "ignored_component_count": len(groups) - len(main_groups),
        "ignored_alpha_area_px": sum(group["area"] for group in groups if group["area"] < minimum_area),
    }


def pack_sprite(
    source_crop: Image.Image, source_bbox: list[int],
    source: SourceSpec, spec: SpriteSpec,
) -> tuple[Image.Image, dict]:
    factor = source.sample_factor
    if factor is None or factor < 1:
        raise ValueError(f"{source.source_id}: explicit reviewed integer sample factor is missing.")
    # Transparent padding makes both axis scales exactly 1/factor, even if the
    # full source alpha bbox width/height are not multiples of that factor.
    padded_size = tuple((value + factor - 1) // factor * factor for value in source_crop.size)
    padded = Image.new("RGBA", padded_size, (0, 0, 0, 0))
    padded.paste(source_crop, (0, 0))
    sampled = padded.resize(tuple(value // factor for value in padded_size), Image.Resampling.NEAREST)
    bbox = sampled.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError(f"{spec.asset_id}: no pixels remain after integer sampling.")
    crop = sampled.crop(bbox)
    width, height = spec.size
    if crop.width > width - MARGIN * 2 or crop.height > height - MARGIN * 2:
        raise ValueError(
            f"{spec.asset_id}: native alpha bbox is {crop.size}, exceeds "
            f"{(width - MARGIN * 2, height - MARGIN * 2)}; regenerate, never fit/stretch."
        )
    position = ((width - crop.width) // 2, height - MARGIN - crop.height)
    sprite = Image.new("RGBA", spec.size, (0, 0, 0, 0))
    sprite.paste(crop, position)
    return sprite, {
        "id": spec.asset_id,
        "label": spec.label,
        "path": f"sprites/{spec.asset_id}.png",
        "dimensions_px": list(spec.size),
        "tile_dimensions": [width // TILE_SIZE, height // TILE_SIZE],
        "alpha_bbox": list(sprite.getchannel("A").getbbox()),
        "ground_anchor": [width // 2, height - MARGIN],
        "source": f"source/{source.source_id}.png",
        "source_crop_px": source_bbox,
        "source_crop_dimensions_px": list(source_crop.size),
        "sample_factor": factor,
        "sampling_padded_dimensions_px": list(padded_size),
        "sampled_alpha_bbox_before_placement": list(bbox),
        "native_object_dimensions_px": list(crop.size),
        "prompt": f"prompts/{source.source_id}.txt",
    }


def checker(size: tuple[int, int]) -> Image.Image:
    background = Image.new("RGB", size, "#e1e2df")
    draw = ImageDraw.Draw(background)
    for y in range(0, size[1], 16):
        for x in range(0, size[0], 16):
            if (x // 16 + y // 16) % 2:
                draw.rectangle((x, y, x + 15, y + 15), fill="#c7ccc9")
    return background


def catalog(items: list[tuple[Image.Image, dict]]) -> Image.Image:
    """Use the same 2x nearest-neighbor zoom for every sprite and tile canvas."""
    if not FONT_PATH.is_file():
        raise FileNotFoundError(f"Chinese catalog font is missing: {FONT_PATH}")
    font = ImageFont.truetype(str(FONT_PATH), 19)
    small_font = ImageFont.truetype(str(FONT_PATH), 15)
    title_font = ImageFont.truetype(str(FONT_PATH), 25)
    columns, cell_width, cell_height, header_height = 4, 332, 376, 76
    rows = (len(items) + columns - 1) // columns
    canvas = Image.new("RGB", (columns * cell_width, rows * cell_height + header_height), "#22272b")
    draw = ImageDraw.Draw(canvas)
    draw.text((20, 12), "赌场美术素材 · 48×48 tile · 全部按原生像素 2×展示", font=title_font, fill="#f3e8cb")
    draw.text((20, 46), "仅参考 RPG Maker 移植赌场 Map005；棋盘格表示透明区域。", font=small_font, fill="#cbd1d2")
    for index, (sprite, item) in enumerate(items):
        left = index % columns * cell_width
        top = header_height + index // columns * cell_height
        draw.rectangle((left + 6, top + 6, left + cell_width - 7, top + cell_height - 7), fill="#323a40")
        draw.text((left + 18, top + 14), item["label"], font=font, fill="#f3e8cb")
        draw.text((left + 18, top + 42), f'{item["id"]} · {sprite.width}×{sprite.height} px', font=small_font, fill="#cbd1d2")
        zoomed = sprite.resize((sprite.width * 2, sprite.height * 2), Image.Resampling.NEAREST)
        backdrop = checker(zoomed.size)
        backdrop.paste(zoomed, (0, 0), zoomed)
        x = left + (cell_width - zoomed.width) // 2
        y = top + 72 + (cell_height - 84 - zoomed.height) // 2
        canvas.paste(backdrop, (x, y))
        draw.rectangle((x - 1, y - 1, x + zoomed.width, y + zoomed.height), outline="#748088")
    return canvas


def map_preview(items: list[tuple[Image.Image, dict]]) -> Image.Image:
    """Place art on Map005 only, without writing scene or collision data."""
    data = json.loads((ART.parent / "catalog.json").read_text(encoding="utf-8"))
    level = next(value for value in data["maps"] if value["id"] == 5)
    tileset = next(value for value in data["tilesets"] if value["id"] == level["tileset_id"])
    tiles = {tile["id"]: tile for tile in tileset["tiles"]}
    pages = {
        page["source_id"]: Image.open(ROOT / page["texture"].removeprefix("res://")).convert("RGBA")
        for page in tileset["pages"]
    }
    image = Image.new("RGBA", (level["width"] * TILE_SIZE, level["height"] * TILE_SIZE))
    shadow = Image.open(ART.parent / "shadow_tiles.png").convert("RGBA")
    table_ids = {3570, 3572, 3576, 3574, 13576, 13574}

    def blit(cell: list[int]) -> None:
        x, y, tile_id = cell
        if tile_id == 8 or tile_id in table_ids:
            return
        if 19 <= x <= 21 and 4 <= y <= 6 and (tile_id >= 10000 or y < 6 and tile_id != 2836):
            return
        tile = tiles[tile_id]
        sx, sy = tile["x"] * TILE_SIZE, tile["y"] * TILE_SIZE
        image.alpha_composite(pages[tile["source_id"]].crop((sx, sy, sx + TILE_SIZE, sy + TILE_SIZE)),
                              (x * TILE_SIZE, y * TILE_SIZE))

    for z, layer in enumerate(level["layers"]):
        for cell in layer:
            if not tiles[cell[2]]["star"]:
                blit(cell)
        if z == 1:
            for x, y, mask in level["shadows"]:
                image.alpha_composite(shadow.crop((mask * TILE_SIZE, 0, (mask + 1) * TILE_SIZE, TILE_SIZE)),
                                      (x * TILE_SIZE, y * TILE_SIZE))
            for cell in level["table_edges"]:
                blit(cell)
    for layer in level["layers"]:
        for cell in layer:
            if tiles[cell[2]]["star"]:
                blit(cell)
    sprites = {item["id"]: sprite.crop(sprite.getchannel("A").getbbox()) for sprite, item in items}

    def place(asset_id: str, x: int, y: int) -> None:
        image.alpha_composite(sprites[asset_id], (x, y))

    for layer in level["layers"]:
        for x, y, tile_id in layer:
            if tile_id == 8:
                place("round_stool", x * TILE_SIZE + 9, y * TILE_SIZE + 8)
    for x, y in ((5, 6), (5, 14), (11, 14), (17, 14)):
        place("gambling_table", x * TILE_SIZE + 5, y * TILE_SIZE + 4)
    place("dice_cup", 5 * TILE_SIZE + 13, 6 * TILE_SIZE + 11)
    place("die_d4", 5 * TILE_SIZE + 62, 6 * TILE_SIZE + 13)
    place("chips", 5 * TILE_SIZE + 48, 14 * TILE_SIZE + 9)
    place("die_d6", 11 * TILE_SIZE + 13, 14 * TILE_SIZE + 12)
    place("die_d12", 11 * TILE_SIZE + 62, 14 * TILE_SIZE + 12)
    place("clay_cup_upright", 17 * TILE_SIZE + 12, 14 * TILE_SIZE + 10)
    place("clay_cup_tilt_a", 17 * TILE_SIZE + 64, 14 * TILE_SIZE + 11)
    place("clay_cup_tilt_b", 10 * TILE_SIZE + 3, 5 * TILE_SIZE + 11)
    place("boss_desk", 19 * TILE_SIZE + 9, 4 * TILE_SIZE + 4)
    place("ledger", 20 * TILE_SIZE + 12, 4 * TILE_SIZE + 12)
    for x in (2, 8):
        place("wall_oil_lamp", x * TILE_SIZE + 7, TILE_SIZE + 4)
    canvas = Image.new("RGB", (image.width, image.height + 96), "#22272b")
    canvas.paste(image, (0, 96), image)
    draw = ImageDraw.Draw(canvas)
    draw.text((22, 12), "Map005 赌场 · 新素材静态试摆", font=ImageFont.truetype(str(FONT_PATH), 30), fill="#f3e8cb")
    draw.text((22, 58), "48×48 tile · 原生 1:1 · 仅用于风格与比例审阅，未写入游戏场景", font=ImageFont.truetype(str(FONT_PATH), 20), fill="#cbd1d2")
    return canvas


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-available", action="store_true", help="Check existing sources without writing outputs.")
    args = parser.parse_args()
    required = [ART / "reference/map_005_native.png"]
    for spec in SOURCES:
        required.extend((ART / "source" / f"{spec.source_id}.png",
                         ART / "prompts" / f"{spec.source_id}.txt"))
    missing = [path.relative_to(ROOT).as_posix() for path in required if not path.is_file()]
    if missing and not args.check_available:
        raise FileNotFoundError("Missing inputs:\n" + "\n".join(missing))
    # Validate every input before replacing any existing derived asset.
    items: list[tuple[Image.Image, dict]] = []
    source_records = []
    for source in SOURCES:
        if args.check_available and not (ART / "source" / f"{source.source_id}.png").is_file():
            continue
        rgba, source_record = load_source(source)
        regions, region_record = source_regions(source, rgba)
        source_record.update(region_record)
        source_records.append(source_record)
        for spec, (crop, bbox) in zip(source.sprites, regions, strict=True):
            items.append(pack_sprite(crop, bbox, source, spec))
    if args.check_available:
        for _, item in items:
            print(f'{item["id"]}: source bbox {item["source_crop_px"]}, factor {item["sample_factor"]}, '
                  f'object {item["native_object_dimensions_px"]}, canvas {item["dimensions_px"]}')
        print(f"Checked {len(items)} sprites without writing outputs.")
        return
    preview = catalog(items)
    manifest = {
        "schema_version": 1,
        "generation": {
            "model": MODEL,
            "style_reference": REFERENCE,
            "requested_pixel_grid_scale": REQUESTED_MASTER_SCALE,
            "requested_pixel_grid_contract_honored": False,
            "source_deviation": "The service did not honor the requested 8x pixel grid; some returned canvas sizes also differ from requests.",
        },
        "tile_size_px": [TILE_SIZE, TILE_SIZE],
        "processing": {
            "sampling": "explicit per-source integer nearest-neighbor factor, identical on both axes",
            "sampling_padding": "transparent right/bottom padding to a whole factor multiple before sampling",
            "alpha_threshold": ALPHA_THRESHOLD,
            "transparent_rgb": [0, 0, 0],
            "placement": "bottom center, with at least 2px transparent margin",
            "bbox_coordinates": "[left, top, right, bottom], right/bottom exclusive",
            "ground_anchor_coordinates": "pixel boundary at bottom center of alpha",
            "reproduce": "python tools/art/prepare_casino_refresh.py",
        },
        "sources": source_records,
        "assets": [item for _, item in items],
        "previews": ["previews/catalog.png", "previews/map_005_art_preview.png"],
    }
    (ART / "sprites").mkdir(parents=True, exist_ok=True)
    (ART / "previews").mkdir(parents=True, exist_ok=True)
    for sprite, item in items:
        sprite.save(ART / item["path"])
    preview.save(ART / "previews/catalog.png")
    map_preview(items).save(ART / "previews/map_005_art_preview.png")
    (ART / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8", newline="\n",
    )
    print(f"Prepared {len(items)} sprites from {len(SOURCES)} masters: {ART}")


if __name__ == "__main__":
    main()
