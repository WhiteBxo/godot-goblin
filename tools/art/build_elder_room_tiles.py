"""Build the elder-room 48 px tile pack from its own generated source art.

Run from any directory:
    python tools/art/build_elder_room_tiles.py

Requires Pillow. No API requests, engine invocation, or source-image changes.
Missing sources are skipped by default, with stable atlas space reserved for
them. Use --require-all for the final build. Width/height are pixels; atlas
coordinates, sizes, and placement anchors in layout.json are 48 px cells.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = REPO_ROOT / "assets/map/elder_room_tiles/manifest.json"
DEFAULT_TILESETS = REPO_ROOT / "src/resources/tilesets/elder_room"
MAGENTA = (255, 0, 255)


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8", newline="\n")


def relative_path(path: Path, root: Path) -> str:
    try:
        return path.resolve().relative_to(root.resolve()).as_posix()
    except ValueError:
        return path.as_posix()


def image_pixels(image: Image.Image):
    """Use Pillow's current pixel API while remaining compatible with older versions."""
    reader = getattr(image, "get_flattened_data", None)
    return reader() if reader is not None else image.getdata()


def validate_manifest(manifest: dict) -> list[dict]:
    if manifest.get("tile_size", 48) != 48:
        raise ValueError("This pack requires tile_size = 48.")
    if (manifest.get("atlas_columns", 16), manifest.get("atlas_rows", 16)) != (16, 16):
        raise ValueError("This pack requires a 16 x 16 atlas (768 x 768 px).")
    assets = manifest["assets"]
    identifiers: set[str] = set()
    for asset in assets:
        identifier = asset["id"]
        if not re.fullmatch(r"[a-z0-9_]+", identifier) or identifier in identifiers:
            raise ValueError(f"Invalid or duplicate asset id: {identifier!r}")
        identifiers.add(identifier)
        for dimension in ("width", "height"):
            value = asset[dimension]
            if not isinstance(value, int) or value <= 0 or value % 48:
                raise ValueError(f"{identifier}: {dimension} must be a positive 48 px multiple.")
        padding = asset.get("padding", 2)
        if not isinstance(padding, int) or not 0 <= padding <= 2:
            raise ValueError(f"{identifier}: padding must be 0, 1, or 2 pixels.")
        if asset.get("anchor", "bottom_center") not in ("bottom_center", "center"):
            raise ValueError(f"{identifier}: anchor must be bottom_center or center.")
        if "atlas_cell" in asset:
            cell = asset["atlas_cell"]
            if (not isinstance(cell, list) or len(cell) != 2
                    or any(type(value) is not int or value < 0 for value in cell)):
                raise ValueError(f"{identifier}: atlas_cell must contain two non-negative integers.")
    return assets


def allocate_rectangles(assets: list[dict]) -> dict[str, tuple[int, int]]:
    """Reserve explicit rectangles, then first-fit others; (0, 0) stays empty."""
    occupied = {(0, 0)}
    positions = {}
    for asset in assets:
        if "atlas_cell" not in asset:
            continue
        x, y = asset["atlas_cell"]
        width, height = asset["width"] // 48, asset["height"] // 48
        if x < 0 or y < 0 or x + width > 16 or y + height > 16:
            raise ValueError(f"{asset['id']}: explicit atlas rectangle exceeds the 16 x 16 grid.")
        cells = {(x + dx, y + dy) for dy in range(height) for dx in range(width)}
        if cells.intersection(occupied):
            raise ValueError(f"{asset['id']}: explicit atlas rectangle overlaps another tile or empty cell (0, 0).")
        occupied.update(cells)
        positions[asset["id"]] = (x, y)
    for asset in assets:
        if asset["id"] in positions:
            continue
        width, height = asset["width"] // 48, asset["height"] // 48
        found = None
        for y in range(17 - height):
            for x in range(17 - width):
                cells = {(x + dx, y + dy) for dy in range(height) for dx in range(width)}
                if not cells.intersection(occupied):
                    found = (x, y)
                    occupied.update(cells)
                    break
            if found is not None:
                break
        if found is None:
            raise ValueError(f"No continuous {width} x {height} region for {asset['id']}.")
        positions[asset["id"]] = found
    return positions


def remove_chroma(source: Image.Image) -> tuple[Image.Image, dict]:
    """Remove only the saturated key; repair mixed pixels at its narrow edge.

    Dark red/purple pixels never qualify as key. Edge cleanup only visits a
    two-source-pixel band beside the strict key and requires a good linear
    blend match against nearby non-key artwork, rather than a broad hue cut.
    """
    rgba = source.convert("RGBA")
    red, green, blue, alpha = rgba.split()
    # Generated flat backgrounds can contain sparse 200..234 channel noise.
    # Requiring both bright R/B and low G keeps the actual dark-purple art.
    key = ImageChops.multiply(red.point(lambda v: 255 if v >= 200 else 0),
                              blue.point(lambda v: 255 if v >= 200 else 0))
    key = ImageChops.multiply(key, green.point(lambda v: 255 if v <= 80 else 0))
    key = ImageChops.multiply(key, ImageChops.difference(red, blue).point(
        lambda v: 255 if v <= 65 else 0))
    opaque = ImageChops.multiply(alpha.point(lambda v: 255 if v >= 128 else 0),
                                 ImageChops.invert(key))
    edge = ImageChops.subtract(key.filter(ImageFilter.MaxFilter(5)), key)
    pixel = rgba.load()
    mask = opaque.load()
    edge_pixel = edge.load()
    width, height = rgba.size
    repaired = removed = 0
    # Only near the key can a saturated pink pixel be an antialias fringe.
    candidates = []
    for y in range(height):
        for x in range(width):
            if not edge_pixel[x, y] or not mask[x, y]:
                continue
            r, g, b, _ = pixel[x, y]
            if min(r, b) >= 150 and min(r, b) - g >= 80 and abs(r - b) <= 95:
                candidates.append((x, y))
    candidate_set = set(candidates)
    for x, y in candidates:
        color = pixel[x, y][:3]
        best = None
        for radius in range(1, 5):
            for dy in range(-radius, radius + 1):
                for dx in range(-radius, radius + 1):
                    if max(abs(dx), abs(dy)) != radius:
                        continue
                    nx, ny = x + dx, y + dy
                    if not (0 <= nx < width and 0 <= ny < height):
                        continue
                    if not mask[nx, ny] or (nx, ny) in candidate_set:
                        continue
                    foreground = pixel[nx, ny][:3]
                    direction = [MAGENTA[c] - foreground[c] for c in range(3)]
                    denominator = sum(v * v for v in direction)
                    if denominator == 0:
                        continue
                    fraction = sum((color[c] - foreground[c]) * direction[c]
                                   for c in range(3)) / denominator
                    residual = max(abs(color[c] - foreground[c] - fraction * direction[c])
                                   for c in range(3))
                    if 0.12 <= fraction <= 1.02 and residual <= 18:
                        score = (residual, dx * dx + dy * dy)
                        if best is None or score < best[0]:
                            best = (score, fraction, foreground)
            if best is not None:
                break
        if best is not None:
            if best[1] >= 0.5:
                mask[x, y] = 0
                removed += 1
            else:
                pixel[x, y] = (*best[2], 255)
                repaired += 1
    rgba.putalpha(opaque)
    # Transparent RGB must be zero too, so scaling/import never reveals pink.
    clean = Image.new("RGBA", rgba.size)
    clean.paste(rgba, (0, 0), opaque)
    return clean, {
        "key": "#ff00ff",
        "keyed_pixels": key.histogram()[255],
        "fringe_pixels_recolored": repaired,
        "fringe_pixels_removed": removed,
        "hard_alpha": True,
    }


def quantize_opaque(image: Image.Image, color_limit: int) -> Image.Image:
    """Keep transparency separate so invisible RGB cannot bias the palette."""
    alpha = image.getchannel("A")
    colors = [rgb for rgb, a in zip(image_pixels(image.convert("RGB")), image_pixels(alpha)) if a]
    if not colors:
        raise ValueError("No opaque pixels remain after normalization.")
    strip = Image.new("RGB", (len(colors), 1))
    strip.putdata(colors)
    palette = strip.quantize(colors=color_limit, method=Image.Quantize.MEDIANCUT,
                             dither=Image.Dither.NONE)
    result = image.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE).convert("RGBA")
    result.putalpha(alpha)
    clean = Image.new("RGBA", image.size)
    clean.paste(result, (0, 0), alpha)
    return clean


def process_asset(asset: dict, source_path: Path, color_limit: int) -> tuple[Image.Image, dict]:
    with Image.open(source_path) as source:
        source.load()
        image, chroma = remove_chroma(source)
        source_size = list(source.size)
    bbox = image.getchannel("A").getbbox()
    if bbox is None:
        raise ValueError(f"{asset['id']}: source contains no non-key artwork.")
    crop = image.crop(bbox)
    width, height = asset["width"], asset["height"]
    padding = asset.get("padding", 2)
    scale = min((width - 2 * padding) / crop.width, (height - 2 * padding) / crop.height)
    resized_size = (max(1, min(width - 2 * padding, round(crop.width * scale))),
                    max(1, min(height - 2 * padding, round(crop.height * scale))))
    # A single scale controls both axes; only integer-pixel rounding differs.
    resized = crop.resize(resized_size, Image.Resampling.NEAREST)
    resized = quantize_opaque(resized, color_limit)
    x = (width - resized.width) // 2
    y = ((height - resized.height) // 2 if asset.get("anchor", "bottom_center") == "center"
         else height - padding - resized.height)
    canvas = Image.new("RGBA", (width, height))
    canvas.paste(resized, (x, y))
    opaque_colors = {pixel[:3] for pixel in image_pixels(canvas) if pixel[3]}
    return canvas, {
        "source_size_px": source_size,
        "source_bbox_px": list(bbox),
        "source_bbox_convention": "left, top, right-exclusive, bottom-exclusive",
        "uniform_scale": scale,
        "resampled_size_px": list(resized_size),
        "resampling": "nearest; one aspect-preserving scale with integer size rounding",
        "placement_px": [x, y],
        "canvas_size_px": [width, height],
        "padding_px": padding,
        "image_anchor": asset.get("anchor", "bottom_center"),
        "opaque_bbox_px": list(canvas.getchannel("A").getbbox()),
        "opaque_palette_colors": len(opaque_colors),
        "source_sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
        "chroma": chroma,
    }


def save_tilesets(entries: list[dict], atlas_path: Path, output: Path) -> None:
    atlas_resource = "res://" + atlas_path.resolve().relative_to(REPO_ROOT).as_posix()
    common = [
        '[gd_resource type="TileSet" load_steps=3 format=3]', "",
        f'[ext_resource type="Texture2D" path="{atlas_resource}" id="1_atlas"]', "",
        '[sub_resource type="TileSetAtlasSource" id="TileSetAtlasSource_elder"]',
        'texture = ExtResource("1_atlas")',
        'texture_region_size = Vector2i(48, 48)',
        '0:0/0 = 0',
    ]
    individual, whole = common.copy(), common.copy()
    for entry in entries:
        if entry["status"] != "ready":
            continue
        x, y = entry["atlas_cell"]
        width, height = entry["size_in_cells"]
        for dy in range(height):
            for dx in range(width):
                individual.append(f"{x + dx}:{y + dy}/0 = 0")
        whole.extend([
            f"{x}:{y}/size_in_atlas = Vector2i({width}, {height})",
            f"{x}:{y}/0 = 0",
            f"{x}:{y}/0/texture_origin = Vector2i({-(width - 1) * 24}, {(height - 1) * 24})",
        ])
    for name, lines, label in [
        ("elder_room_tiles.tres", individual, "长老房间 · 48像素单格"),
        ("elder_room_objects.tres", whole, "长老房间 · 完整物件（左下格落点）"),
    ]:
        lines.extend(["", "[resource]", f"resource_name = {json.dumps(label, ensure_ascii=False)}",
                      "tile_size = Vector2i(48, 48)",
                      'sources/0 = SubResource("TileSetAtlasSource_elder")'])
        write_text(output / name, "\n".join(lines))


def font(size: int) -> ImageFont.ImageFont:
    for path in ("C:/Windows/Fonts/msyh.ttc", "C:/Windows/Fonts/simhei.ttf",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"):
        if Path(path).exists():
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def checkerboard(size: tuple[int, int], cell: int = 12) -> Image.Image:
    image = Image.new("RGBA", size, (98, 101, 110, 255))
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], cell):
        for x in range(0, size[0], cell):
            if (x // cell + y // cell) % 2:
                draw.rectangle((x, y, x + cell - 1, y + cell - 1), fill=(116, 119, 128, 255))
    return image


def save_previews(assets: list[dict], images: dict[str, Image.Image], entries: list[dict],
                  atlas: Image.Image, output: Path) -> None:
    output.mkdir(parents=True, exist_ok=True)
    scale, columns, gap, title_height = 2, 3, 20, 86
    title_font, label_font, small_font = font(24), font(17), font(14)
    label_width = max(label_font.getlength(f"{asset['id'].split('_', 1)[0]}  {asset['name']}")
                      for asset in assets)
    cell_width = max(max(asset["width"] for asset in assets) * scale, int(label_width) + 1) + 2 * gap
    row_heights = [max(asset["height"] for asset in assets[start:start + columns]) * scale + 74
                   for start in range(0, len(assets), columns)]
    sheet = Image.new("RGB", (columns * cell_width, title_height + sum(row_heights)), "#20232c")
    draw = ImageDraw.Draw(sheet)
    draw.text((20, 12), "长老房间素材 · 48 × 48 网格", font=title_font, fill="#f6ead8")
    draw.text((20, 48), "所有物件均为 2× 最近邻预览；透明棋盘仅用于检查，不写入素材。",
              font=label_font, fill="#c5c8d0")
    y = title_height
    for row, row_height in enumerate(row_heights):
        for column, asset in enumerate(assets[row * columns:(row + 1) * columns]):
            x = column * cell_width + gap
            label = f"{asset['id'].split('_', 1)[0]}  {asset['name']}"
            draw.text((x, y + 2), label, font=label_font, fill="#f6ead8")
            draw.text((x, y + 27), f"{asset['width']} × {asset['height']} px  |  "
                      f"{asset['width'] // 48} × {asset['height'] // 48} tiles",
                      font=small_font, fill="#c5c8d0")
            preview_size = (asset["width"] * scale, asset["height"] * scale)
            preview = checkerboard(preview_size)
            if asset["id"] in images:
                preview.alpha_composite(images[asset["id"]].resize(preview_size, Image.Resampling.NEAREST))
            else:
                ImageDraw.Draw(preview).text((8, 8), "待生成", font=label_font, fill="white")
            sheet.paste(preview.convert("RGB"), (x, y + 51))
        y += row_height
    sheet.save(output / "contact_sheet.png")

    used_rows = max(entry["atlas_cell"][1] + entry["size_in_cells"][1] for entry in entries)
    grid = checkerboard((1536, used_rows * 96), 24)
    atlas_preview = atlas.crop((0, 0, 768, used_rows * 48))
    grid.alpha_composite(atlas_preview.resize(grid.size, Image.Resampling.NEAREST))
    grid_draw = ImageDraw.Draw(grid)
    for i in range(17):
        grid_draw.line((i * 96, 0, i * 96, grid.height - 1), fill=(170, 175, 192, 140), width=1)
    for i in range(used_rows + 1):
        grid_draw.line((0, i * 96, 1535, i * 96), fill=(170, 175, 192, 140), width=1)
    for entry in entries:
        x, y = entry["atlas_cell"]
        width, height = entry["size_in_cells"]
        color = "#e8c88c" if entry["status"] == "ready" else "#e07f83"
        grid_draw.rectangle((x * 96, y * 96, (x + width) * 96 - 1, (y + height) * 96 - 1),
                            outline=color, width=2)
        grid_draw.text((x * 96 + 4, y * 96 + 3), entry["id"].split("_", 1)[0],
                       font=label_font, fill="white", stroke_width=1, stroke_fill="#20232c")
    grid_draw.text((5, 5), "EMPTY", font=label_font, fill="white")
    grid.convert("RGB").save(output / "atlas_grid.png")


def build(manifest_path: Path, tileset_output: Path, require_all: bool) -> dict:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8-sig"))
    assets = validate_manifest(manifest)
    if not assets:
        raise ValueError("Manifest contains no assets.")
    color_limit = int(manifest.get("palette_colors", 48))
    if not 2 <= color_limit <= 256:
        raise ValueError("palette_colors must be between 2 and 256.")
    root = manifest_path.parent
    sources = {asset["id"]: root / asset.get("source_image", f"source/{asset['id']}.png")
               for asset in assets}
    missing = [identifier for identifier, path in sources.items() if not path.is_file()]
    if require_all and missing:
        raise ValueError("Missing sources: " + ", ".join(missing))
    positions = allocate_rectangles(assets)
    images: dict[str, Image.Image] = {}
    entries = []
    atlas = Image.new("RGBA", (768, 768))
    for folder in ("objects", "tiles", "preview"):
        (root / folder).mkdir(parents=True, exist_ok=True)
    for asset in assets:
        identifier = asset["id"]
        x, y = positions[identifier]
        width, height = asset["width"] // 48, asset["height"] // 48
        entry = {
            "id": identifier,
            "name": asset["name"],
            "status": "missing_source" if identifier in missing else "ready",
            "source_image": relative_path(sources[identifier], root),
            "atlas_cell": [x, y],
            "size_in_cells": [width, height],
            "atlas_rect_px": [x * 48, y * 48, width * 48, height * 48],
            "object_placement_anchor_cell": [0, height - 1],
            "object_texture_origin_px": [-(width - 1) * 24, (height - 1) * 24],
        }
        entries.append(entry)
        if identifier in missing:
            continue
        image, processing = process_asset(asset, sources[identifier], color_limit)
        images[identifier] = image
        object_path = root / "objects" / f"{identifier}.png"
        image.save(object_path)
        entry["object_image"] = relative_path(object_path, root)
        entry["processing"] = processing
        entry["tiles"] = []
        for ty in range(height):
            for tx in range(width):
                tile_path = root / "tiles" / f"{identifier}_x{tx}_y{ty}.png"
                image.crop((tx * 48, ty * 48, (tx + 1) * 48, (ty + 1) * 48)).save(tile_path)
                entry["tiles"].append(relative_path(tile_path, root))
        atlas.paste(image, (x * 48, y * 48))
    atlas_path = root / "atlas.png"
    atlas.save(atlas_path)
    save_tilesets(entries, atlas_path, tileset_output)
    save_previews(assets, images, entries, atlas, root / "preview")
    layout = {
        "schema_version": 1,
        "tile_size_px": 48,
        "atlas_size_px": [768, 768],
        "atlas_size_in_cells": [16, 16],
        "atlas_image": "atlas.png",
        "empty_tile_cell": [0, 0],
        "object_brush_anchor": "leftmost cell of bottom row; texture_origin aligns canvas to that cell",
        "collision": "none; configured separately by the destination map",
        "palette_limit_per_object": color_limit,
        "complete": not missing,
        "ready_count": len(images),
        "asset_count": len(assets),
        "tilesets": {
            "individual_cells": relative_path(tileset_output / "elder_room_tiles.tres", REPO_ROOT),
            "whole_objects": relative_path(tileset_output / "elder_room_objects.tres", REPO_ROOT),
        },
        "assets": entries,
    }
    write_text(root / "layout.json", json.dumps(layout, ensure_ascii=False, indent=2))
    return {"ready": len(images), "total": len(assets), "missing": missing,
            "atlas": str(atlas_path), "layout": str(root / "layout.json")}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--tileset-output", type=Path, default=DEFAULT_TILESETS)
    parser.add_argument("--require-all", action="store_true", help="Fail before writing if any source is missing.")
    args = parser.parse_args()
    result = build(args.manifest.resolve(), args.tileset_output.resolve(), args.require_all)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
