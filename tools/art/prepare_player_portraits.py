"""Build aligned dialogue portraits from the user-supplied white-background art.

Requires Pillow and numpy. Run from any directory; sources are never modified.
Edge-connected near-white pixels and two background gaps are removed, preserving
eye whites and clothing highlights. Both expressions share one crop, without resampling.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "assets/characters/apron_man"
SOURCES = ("player_neutral.jpg", "player_talking.png")
# Keep the established canvas and registration when cleanup removes residue.
PORTRAIT_CROP = (331, 30, 721, 925)
# Original-canvas white gaps between the bent arm/torso and between the legs.
BACKGROUND_SEEDS = ((463, 465), (553, 765))
# Boot outlines in the shared (303, 25) crop coordinates. The original painted
# ground shadow contains white/gray paper; exclude it from the reusable cutout.
BOOT_OUTLINES = (
    ((159, 795), (230, 795), (230, 804), (230, 812), (230, 818),
     (233, 825), (237, 831), (241, 836), (247, 842), (255, 848),
     (262, 854), (268, 860), (271, 867), (271, 873), (264, 877),
     (251, 880), (232, 882), (209, 883), (196, 880), (183, 874),
     (173, 868), (164, 861), (158, 857), (154, 850), (154, 837),
     (155, 824), (157, 811)),
    ((265, 795), (336, 795), (347, 801), (363, 806), (386, 809),
     (395, 817), (401, 830), (399, 837), (380, 843), (338, 846),
     (306, 843), (280, 835), (266, 828)),
)


def remove_background(path: Path) -> Image.Image:
    image = Image.open(path).convert("RGBA")
    pixels = np.array(image)
    rgb = pixels[:, :, :3].astype(np.int16)
    near_white = (rgb.min(axis=2) >= 225) & (np.ptp(rgb, axis=2) <= 25)
    # The compressed black hair has a wider gray/white matte between spikes.
    # Use a stricter edge-connected matte only in the head area; enclosed dark
    # hair highlights, eyes and colored skin remain inside the foreground.
    hair_matte = (rgb.min(axis=2) >= 65) & (np.ptp(rgb, axis=2) <= 30)
    near_white[:305] |= hair_matte[:305]
    # Shoe edges meet a painted ground shadow, whose gray matte is darker than
    # the white paper. Follow light, neutral pixels from outside to the black
    # boot outline; enclosed sole highlights remain inside the foreground.
    boot_matte = (rgb.min(axis=2) >= 55) & (np.ptp(rgb, axis=2) <= 35)
    near_white[760:] |= boot_matte[760:]
    # A transparent border joins all four edges into one flood-fill seed.
    mask = Image.fromarray(np.pad(near_white.astype(np.uint8) * 255, 1, constant_values=255)).copy()
    ImageDraw.floodfill(mask, (0, 0), 128)
    for x, y in BACKGROUND_SEEDS:
        if near_white[y, x]:
            ImageDraw.floodfill(mask, (x + 1, y + 1), 128)
    background = np.array(mask)[1:-1, 1:-1] == 128
    # Remove the ground outside both boot silhouettes, on the original canvas.
    silhouette = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(silhouette)
    draw.rectangle((0, 0, image.width, 825), fill=255)
    for outline in BOOT_OUTLINES:
        draw.polygon([(x + 303, y + 25) for x, y in outline], fill=255)
    background |= np.array(silhouette) == 0
    # Unmatte the one-pixel silhouette edge to avoid a white fringe on dark UI.
    expanded = Image.fromarray(background.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(3))
    edge = (np.array(expanded) > 0) & ~background
    opacity = 1.0 - rgb.min(axis=2)[edge] / 255.0
    opacity = np.maximum(opacity, 1.0 / 255.0)
    pixels[edge, :3] = np.clip((rgb[edge] - 255 * (1 - opacity[:, None])) / opacity[:, None], 0, 255).astype(np.uint8)
    pixels[edge, 3] = (pixels[edge, 3] * opacity).astype(np.uint8)
    pixels[background] = 0
    return Image.fromarray(pixels)


def main() -> None:
    images = [remove_background(ART / "source" / name) for name in SOURCES]
    if len({image.size for image in images}) != 1:
        raise ValueError("Expression source canvases must have identical dimensions")
    crop = PORTRAIT_CROP
    for name, image in zip(SOURCES, images):
        target = ART / (Path(name).stem + "_portrait.png")
        image.crop(crop).save(target, optimize=True)
        print(f"{target.relative_to(ROOT)}: {image.crop(crop).size}, source crop {crop}")


if __name__ == "__main__":
    main()
