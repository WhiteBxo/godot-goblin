"""Trim transparent margins from supplied dialogue illustrations, without resampling.

Original RGBA files and archive entries are kept in assets/characters/dialogue/source.
Run from the repository root with Pillow installed.
"""
from pathlib import Path

from PIL import Image

ART = Path(__file__).resolve().parents[2] / "assets/characters/dialogue"


def main():
    for name in ("guard", "tavern", "casino", "common_goblin", "fat_goblin_sick"):
        image = Image.open(ART / "source" / f"{name}.png").convert("RGBA")
        bounds = image.getchannel("A").getbbox()
        if bounds is None:
            raise ValueError(f"Empty illustration: {name}")
        left, top, right, bottom = bounds
        image.crop((max(0, left - 4), max(0, top - 4),
                    min(image.width, right + 4), min(image.height, bottom + 4))).save(
            ART / f"{name}_portrait.png", optimize=True)


if __name__ == "__main__":
    main()
