"""Extract the supplied eagle heraldry sheet into 48px RPG Maker map assets."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw


CELL = 48

# Coordinates are measured on the 1536x1024 user-supplied reference sheet.
OBJECT_CROPS = {
    "lantern": (150, 10, 335, 445),
    "round_medallion": (1090, 50, 1440, 390),
    "shield_sign": (80, 545, 440, 910),
    "eagle_pillar": (610, 445, 835, 965),
    "grand_eagle_monument": (990, 445, 1490, 965),
}

# The center panel is a 3x3 stone-block sample. The middle cell contains the
# eagle crest and is kept separately from the eight plain stone variants.
PANEL_CELLS = {
    "top_left": (562, 34, 683, 161),
    "top_middle": (684, 34, 803, 161),
    "top_right": (804, 34, 923, 161),
    "middle_left": (562, 162, 683, 290),
    "center_crest": (684, 162, 803, 290),
    "middle_right": (804, 162, 923, 290),
    "bottom_left": (562, 291, 683, 380),
    "bottom_middle": (684, 291, 803, 380),
    "bottom_right": (804, 291, 923, 380),
}

SPRITE_FOOTPRINTS = {
    "lantern": (1, 3),
    "round_medallion": (2, 2),
    "shield_sign": (2, 2),
    "eagle_pillar": (1, 3),
    "grand_eagle_monument": (3, 3),
}


def make_transparent(image: Image.Image) -> Image.Image:
    """Remove the black matte while retaining dark pixels inside the objects."""
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    for y in range(rgba.height):
        for x in range(rgba.width):
            red, green, blue, _ = pixels[x, y]
            if max(red, green, blue) <= 6:
                pixels[x, y] = (red, green, blue, 0)
            else:
                pixels[x, y] = (red, green, blue, 255)
    return rgba


def fit_on_grid(image: Image.Image, footprint: tuple[int, int]) -> Image.Image:
    width, height = footprint[0] * CELL, footprint[1] * CELL
    source = image.crop(image.getbbox())
    scale = min(width / source.width, height / source.height)
    resized = source.resize(
        (max(1, round(source.width * scale)), max(1, round(source.height * scale))),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    canvas.alpha_composite(
        resized,
        ((width - resized.width) // 2, (height - resized.height) // 2),
    )
    return canvas


def build_floor_tile(reference: Image.Image, box: tuple[int, int, int, int]) -> Image.Image:
    """Create one opaque 48px floor cell from a source stone block."""
    source = reference.crop(box).convert("RGB")
    return source.resize((CELL, CELL), Image.Resampling.LANCZOS).convert("RGBA")


def make_preview(sprites: dict[str, Image.Image], floor_atlas: Image.Image, output: Path) -> None:
    preview = Image.new("RGB", (720, 520), (28, 28, 31))
    draw = ImageDraw.Draw(preview)
    draw.text((24, 18), "Eagle Crest RPG Maker 48px Assets", fill=(235, 226, 198))

    preview.paste(floor_atlas.convert("RGB"), (24, 54))
    draw.text((24, 108), "stone floor variants", fill=(192, 188, 176))

    positions = {
        "lantern": (24, 150),
        "round_medallion": (126, 150),
        "shield_sign": (246, 150),
        "eagle_pillar": (366, 150),
        "grand_eagle_monument": (480, 150),
    }
    labels = {
        "lantern": "lantern",
        "round_medallion": "medallion",
        "shield_sign": "shield",
        "eagle_pillar": "pillar",
        "grand_eagle_monument": "monument",
    }
    for name, position in positions.items():
        image = sprites[name]
        checker = Image.new("RGB", image.size, (64, 64, 68))
        checker.paste(image, mask=image.getchannel("A"))
        checker.thumbnail((190, 280), Image.Resampling.NEAREST)
        preview.paste(checker, position)
        draw.text((position[0], position[1] + 292), labels[name], fill=(192, 188, 176))

    output.parent.mkdir(parents=True, exist_ok=True)
    preview.save(output)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()

    with Image.open(args.source) as opened:
        reference = opened.convert("RGB")
    if reference.size != (1536, 1024):
        raise ValueError(f"expected 1536x1024 reference, got {reference.size}")

    output_dir = args.output_dir
    sprites_dir = output_dir / "sprites"
    preview_dir = output_dir / "previews"
    sprites_dir.mkdir(parents=True, exist_ok=True)
    preview_dir.mkdir(parents=True, exist_ok=True)

    floor_names = [
        "top_left",
        "top_middle",
        "top_right",
        "middle_left",
        "middle_right",
        "bottom_left",
        "bottom_middle",
        "bottom_right",
    ]
    floor_atlas = Image.new("RGBA", (CELL * len(floor_names), CELL))
    for index, name in enumerate(floor_names):
        floor_atlas.paste(
            build_floor_tile(reference, PANEL_CELLS[name]),
            (index * CELL, 0),
        )
    floor_atlas.save(sprites_dir / "stone_floor_atlas.png")

    crest = build_floor_tile(reference, PANEL_CELLS["center_crest"])
    crest.save(sprites_dir / "eagle_crest_floor.png")

    sprites: dict[str, Image.Image] = {}
    manifest: dict[str, object] = {
        "source": "source/reference.png",
        "source_size": [1536, 1024],
        "cell_size": CELL,
        "floor_atlas": {
            "file": "sprites/stone_floor_atlas.png",
            "size": [CELL * len(floor_names), CELL],
            "variants": floor_names,
        },
        "sprites": {},
    }
    for name, crop_box in OBJECT_CROPS.items():
        extracted = make_transparent(reference.crop(crop_box))
        footprint = SPRITE_FOOTPRINTS[name]
        sprite = fit_on_grid(extracted, footprint)
        sprite.save(sprites_dir / f"{name}.png")
        sprites[name] = sprite
        manifest["sprites"][name] = {
            "file": f"sprites/{name}.png",
            "crop": list(crop_box),
            "footprint": list(footprint),
            "size": [footprint[0] * CELL, footprint[1] * CELL],
        }

    make_preview(sprites, floor_atlas, preview_dir / "catalog.png")
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
