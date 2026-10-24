"""Check every supplemental frame against retained source pixels, without resampling."""
import sys
import json
from pathlib import Path

from PIL import Image, ImageOps

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools/characters"))
from import_pixel_supplement import REVISION, SHEETS


def main():
    count = 0
    for slug, bindings in SHEETS.items():
        directory = ROOT / "assets/characters/npc" / slug
        for key, _, mirror in bindings:
            original = Image.open(directory / "source" / REVISION / f"{key}.png").convert("RGBA")
            output = Image.open(directory / f"{REVISION}_{key}.png").convert("RGBA")
            size, stride = (128, 152) if original.width == 888 else (64, 88)
            assert output.width == original.width, (slug, key, "native frame size changed")
            index = 0
            for y in range(0, original.height - size + 1, stride):
                for x in range(0, original.width - size + 1, stride):
                    frame = original.crop((x, y, x + size, y + size))
                    box = frame.getchannel("A").getbbox()
                    if box is None:
                        continue
                    expected = frame.crop(box)
                    if mirror:
                        expected = ImageOps.mirror(expected)
                    ox, oy = index % 6 * stride, index // 6 * stride
                    actual = output.crop((ox, oy, ox + size, oy + size))
                    actual = actual.crop(actual.getchannel("A").getbbox())
                    assert expected.size == actual.size and expected.tobytes() == actual.tobytes(), (slug, key, index)
                    count += 1
                    index += 1
    directory = ROOT / "assets/characters/npc/goblin_girl"
    catalog = json.loads((ROOT / "src/gameplay/characters/supplement_npc_catalog.json").read_text(encoding="utf-8"))
    girl = next(entry for entry in catalog if entry["id"] == "goblin_girl")
    seen = set()
    for animation in girl["animations"].values():
        name = animation["source"]
        if name in seen:
            continue
        seen.add(name)
        key = "walk" if name.startswith("run_") else "idle" if name.startswith("idle_") else name.removeprefix("emote_")
        original = Image.open(directory / "source/update_2026_10_20" / f"{key}.png").convert("RGBA")
        output = Image.open(directory / f"{name}.png").convert("RGBA")
        transform = animation["transform"]
        assert output.width == 888 and transform["scale"] == 1.0 and transform["native_pixels"]
        for index, source_index in enumerate(transform["source_indices"]):
            x, y = source_index % 4, source_index // 4
            frame = original.crop((x * original.width // 4, y * original.height // 2,
                                   (x + 1) * original.width // 4, (y + 1) * original.height // 2))
            expected = frame.crop(frame.getchannel("A").getbbox())
            if source_index in transform["mirror_indices"]:
                expected = ImageOps.mirror(expected)
            ox, oy = index % 6 * 152, index // 6 * 152
            actual = output.crop((ox, oy, ox + 128, oy + 128))
            actual = actual.crop(actual.getchannel("A").getbbox())
            assert expected.size == actual.size and expected.tobytes() == actual.tobytes(), (name, index)
            count += 1
    print(f"NATIVE_NPC_PIXELS: PASS ({count} frames preserve every source RGBA pixel)")


if __name__ == "__main__":
    main()
