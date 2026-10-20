"""Convert the supplied artwork to desktop and Android launcher icon formats.

Run from the repository root: python tools/build/prepare_app_icons.py
Requires Pillow. The source is preserved; no artwork is redrawn or cropped, and the
transparency around the circular badge is kept instead of being flattened onto white.
"""

from pathlib import Path

from PIL import Image, ImageOps

CANVAS = 512
ICO_SIZES = (16, 32, 48, 64, 128, 256)
# Android's adaptive icon safe circle is 264 px on a 432 px canvas.
ADAPTIVE_CANVAS = 432
ADAPTIVE_SAFE = 264


def main() -> None:
    target = Path(__file__).resolve().parents[2] / "assets/ui/app_icon"
    with Image.open(target / "source/app_icon.png") as original:
        artwork = ImageOps.exif_transpose(original).convert("RGBA")
    # 原画自带圆形透明边，补边也用全透明，避免桌面 / 任务栏出现白方块。
    icon = ImageOps.pad(artwork, (CANVAS, CANVAS), Image.Resampling.LANCZOS, color=(0, 0, 0, 0))
    icon.save(target / "app_icon.png")
    icon.save(target / "app_icon.ico", sizes=[(size, size) for size in ICO_SIZES])
    foreground = Image.new("RGBA", (ADAPTIVE_CANVAS, ADAPTIVE_CANVAS), (0, 0, 0, 0))
    safe_artwork = ImageOps.contain(artwork, (ADAPTIVE_SAFE, ADAPTIVE_SAFE), Image.Resampling.LANCZOS)
    foreground.alpha_composite(safe_artwork, ((ADAPTIVE_CANVAS - safe_artwork.width) // 2,
                                              (ADAPTIVE_CANVAS - safe_artwork.height) // 2))
    foreground.save(target / "adaptive_foreground.png")
    # 自适应图标要求背景层不透明：徽章透明边之外由这一层填充，保持原来的白色。
    Image.new("RGB", (ADAPTIVE_CANVAS, ADAPTIVE_CANVAS), "white").save(target / "adaptive_background.png")
    print(f"Icons written to {target}")


if __name__ == "__main__":
    main()
