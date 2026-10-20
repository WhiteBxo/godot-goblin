"""Convert the supplied artwork to desktop and Android launcher icon formats.

Run from the repository root: python tools/build/prepare_app_icons.py
Requires Pillow. The source is preserved; no artwork is redrawn or cropped.
"""

from pathlib import Path

from PIL import Image, ImageOps


def main() -> None:
    target = Path(__file__).resolve().parents[2] / "assets/ui/app_icon"
    with Image.open(target / "source/app_icon.jpg") as original:
        artwork = ImageOps.exif_transpose(original).convert("RGB")
    icon = ImageOps.pad(artwork, (512, 512), Image.Resampling.LANCZOS, color="black")
    icon.save(target / "app_icon.png")
    icon.save(
        target / "app_icon.ico",
        sizes=[(size, size) for size in (16, 32, 48, 64, 128, 256)],
    )
    # Android's adaptive icon safe circle is 264 px on a 432 px canvas.
    foreground = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
    safe_artwork = ImageOps.contain(artwork, (264, 264), Image.Resampling.LANCZOS)
    foreground.paste(safe_artwork, ((432 - safe_artwork.width) // 2, (432 - safe_artwork.height) // 2))
    foreground.save(target / "adaptive_foreground.png")
    Image.new("RGB", (432, 432), "black").save(target / "adaptive_background.png")
    print(f"Icons written to {target}")


if __name__ == "__main__":
    main()
