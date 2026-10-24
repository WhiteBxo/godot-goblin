"""Rebuild the portrait-matched drunken guard from its retained generated atlas."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image

from build_character_frames import ROOT, build
from import_supplement_npcs import save_text


def main() -> None:
    directory = ROOT / "assets/characters/npc/drunken_guard"
    source = directory / "source/generated_sheet.png"
    image = Image.open(source).convert("RGBA")
    if image.width != image.height:
        raise ValueError("Expected a square 4-by-4 source atlas")
    cell = image.width / 4
    frames = [image.crop((round(x * cell), round(y * cell), round((x + 1) * cell), round((y + 1) * cell)))
              for y in range(4) for x in range(4)]
    boxes = [frame.getchannel("A").getbbox() for frame in frames]
    if any(box is None for box in boxes):
        raise ValueError("Missing generated frame")
    crop = (min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes))
    factor = min(120 / (crop[2] - crop[0]), 116 / (crop[3] - crop[1]))
    target = (round((crop[2] - crop[0]) * factor), round((crop[3] - crop[1]) * factor))
    rows = ["idle_down", "run_down", "run_right", "run_up"]
    for row, name in enumerate(rows):
        sheet = Image.new("RGBA", (888, 128))
        for index in range(4):
            art = frames[row * 4 + index].crop(crop).resize(target, Image.Resampling.NEAREST)
            sheet.paste(art, (index * 152 + (128 - target[0]) // 2, 126 - target[1]))
        sheet.save(directory / f"{name}.png")
    animations = {}
    for direction in ["down", "up", "right", "left"]:
        side = "right" if direction == "left" else direction
        for moving in [False, True]:
            name = f"{'run' if moving else 'idle'}_{direction}"
            animations[name] = {
                "source": f"run_{side}" if moving or side != "down" else "idle_down",
                "frame_count": 4, "first_only": not moving and side != "down",
                "fps": 8 if moving else 4,
            }
    catalog = ROOT / "src/gameplay/characters/drunken_guard_catalog.json"
    save_text(catalog, json.dumps([{"id": "drunken_guard", "animations": animations}], indent=2))
    build(catalog)
    save_text(directory / "source/processing.json", json.dumps({
        "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
        "identity_reference": "res://assets/characters/dialogue/guard_portrait.png",
        "source_grid": [4, 4], "source_cell": cell, "crop": crop,
        "uniform_scale": factor, "target_frame": 128, "feet_anchor": 126,
        "sampling": "nearest", "rows": rows,
    }, indent=2))


if __name__ == "__main__":
    main()
