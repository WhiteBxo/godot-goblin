"""Prepare native-size generated art; chroma removal/cropping only, no resizing."""
from pathlib import Path
import json
import shutil
import subprocess
import sys
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "assets/map/settlement"
RAW = Path(r"D:\taptapgamejam\output\imagegen\cavern_v2")
SKILLS = Path.home() / ".codex/skills/.system/imagegen/scripts"


def main():
    data = json.loads((ROOT / "src/levels/settlement/settlement_layout.json").read_text(encoding="utf-8"))
    for item in data["zones"] + [{"id": key} for key in ["ground", "river", "props", "bridge"]]:
        slug = item["id"]
        src = RAW / (slug + ".png")
        # Selected corrections are versioned; the original output is kept outside the project.
        variants = sorted(RAW.glob(slug + "_v*.png"))
        if variants:
            src = variants[-1]
        if not src.exists():
            continue
        dest = ART / (slug + ".png")
        if dest.exists() and dest.stat().st_mtime >= src.stat().st_mtime:
            continue
        expected = (1536, 1024)
        with Image.open(src) as image:
            if image.size != expected:
                raise ValueError(f"{src.name}: expected {expected}, got {image.size}; regenerate instead of stretching")
        source = ART / "source" / (slug + ".png")
        shutil.copy2(src, source)
        if slug in ["ground", "river"]:
            shutil.copy2(src, dest)
        else:
            subprocess.run([sys.executable, str(SKILLS / "remove_chroma_key.py"), "--input", str(source), "--out", str(dest), "--key-color", "#ff00ff", "--tolerance", "100", "--force"], check=True)
            image = Image.open(dest).convert("RGBA")
            image.putalpha(image.getchannel("A").point(lambda value: 255 if value >= 128 else 0))
            image.save(dest)
        print(slug, expected)
    for slug, prompt in {"06_tavern": "tavern", "01_muster": "muster", "bridge": "bridge", "ground": "ground", "props": "props", "river": "river"}.items():
        chosen = Path(r"D:\taptapgamejam\output\cavern_rebuild") / (prompt + "_v2_prompt.txt")
        if chosen.exists():
            shutil.copy2(chosen, ART / f"prompts/{slug}.txt")
    images = sorted(p for p in ART.glob("*.png") if p.stem[:2].isdigit())
    if images:
        sheet = Image.new("RGB", (2048, ((len(images) + 3) // 4) * 370), "#49443d")
        draw = ImageDraw.Draw(sheet)
        for index, path in enumerate(images):
            im = Image.open(path).convert("RGBA")
            im.thumbnail((508, 339))  # Contact sheet only; production assets never resize.
            xy = (index % 4 * 512, index // 4 * 370 + 25)
            sheet.paste(im, xy, im)
            draw.text((xy[0] + 8, xy[1] - 21), path.stem, fill="white")
        sheet.save(r"D:\taptapgamejam\output\cavern_rebuild\scene_contact_sheet.png")


if __name__ == "__main__":
    main()
