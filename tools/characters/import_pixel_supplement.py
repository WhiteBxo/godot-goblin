"""Import the 2026-10-24 pixel NPC supplement; rebuild with --from-retained.

Raw PNGs and hashes stay in each character's source/supplement_2026_10_24/.
Only selected characters are rebuilt; portraits, scenes and story staging stay intact.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import tempfile
from pathlib import Path

from PIL import Image

from build_character_frames import build
from import_supplement_npcs import ROOT, save_text, source_entries

REVISION = "supplement_2026_10_24"
ARCHIVE = "像素小人补充.zip"
BASE = "像素小人补充/"
# Source suffix, ZIP entry, horizontal flip. Mother side idle faces right while
# her side walk faces left. Unpacked goblins retain the controller's right-side convention.
SHEETS = {
    "market_mother": [
        ("run_up", "妇女/妇女走路2.png", False),
        ("run_right", "妇女/妇女走路3.png", False),
        ("run_down", "妇女/妇女走路1.png", False),
        ("idle_right", "妇女/妇女待机2.png", True),
        ("idle_down", "妇女/妇女待机3.png", False),
        ("idle_up", "妇女/妇女待机1.png", False),
    ],
    "common_goblin": [
        ("unpacked_walk_side", "普通哥布林/左走路.png", True),
        ("unpacked_idle_right", "普通哥布林/待机1.png", True),
        ("unpacked_idle_down", "普通哥布林/待机2.png", False),
        ("unpacked_idle_up", "普通哥布林/待机3.png", False),
        ("backpack_idle_down", "普通哥布林/背包/背包待机1.png", False),
        ("backpack_idle_right", "普通哥布林/背包/背包待机3.png", False),
        ("backpack_idle_up", "普通哥布林/背包/背包待机2.png", False),
    ],
    "casino_poet": [("idle", "诗人/诗人待机.png", False)],
    "market_vendor_1": [("idle", "商人/商人1待机.png", False)],
    "market_vendor_2": [("idle", "商人/商人2待机.png", False)],
    "market_vendor_3": [("idle", "商人/商人3待机.png", False)],
    "casino_sentry": [
        ("emote_laugh", "守卫2/大笑.png", False),
        ("emote_sit", "守卫2/坐着.png", False),
        ("run_down", "守卫2/走路1.png", False),
        ("run_right", "守卫2/走路2.png", False),
        ("run_up", "守卫2/走路3.png", False),
        ("idle_up", "守卫2/待机1.png", False),
        ("idle_down", "守卫2/待机2.png", False),
    ],
}
CATALOGS = {
    "market_mother": "supplement_npc_catalog.json",
    "common_goblin": "character_catalog.json",
    "casino_poet": "talkable_npc_catalog.json",
    "market_vendor_1": "market_vendor_catalog.json",
    "market_vendor_2": "market_vendor_catalog.json",
    "market_vendor_3": "market_vendor_catalog.json",
    "casino_sentry": "sentry_catalog.json",
}


def normalize_native(data: bytes) -> tuple[Image.Image, int, int, dict]:
    """Repack native cells; translate the whole animation without resampling pixels."""
    image = Image.open(io.BytesIO(data)).convert("RGBA")
    if image.width not in (504, 888):
        raise ValueError(f"Unexpected native sheet width: {image.width}")
    size, stride = (128, 152) if image.width == 888 else (64, 88)
    frames = []
    for y in range(0, image.height - size + 1, stride):
        for x in range(0, image.width - size + 1, stride):
            frame = image.crop((x, y, x + size, y + size))
            if frame.getchannel("A").getbbox() is not None:
                frames.append(frame)
    if not frames:
        raise ValueError("Empty native animation sheet")
    boxes = [frame.getchannel("A").getbbox() for frame in frames]
    crop = (min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes))
    # Share the translation across all frames, preserving source foot bounce.
    dx = (size - crop[2] + crop[0]) // 2 - crop[0]
    dy = size - 2 - crop[3]
    if crop[1] + dy < 0:
        raise ValueError("Native artwork does not fit above the feet anchor")
    rows = (len(frames) + 5) // 6
    output = Image.new("RGBA", (6 * stride - 24, rows * stride - 24))
    for index, frame in enumerate(frames):
        output.paste(frame.crop(crop), (index % 6 * stride + crop[0] + dx,
                                         index // 6 * stride + crop[1] + dy))
    return output, len(frames), size, {
        "crop": crop, "scale": 1.0, "translation": [dx, dy], "native_pixels": True,
    }


def animation(sheet: dict, moving: bool = False, first_only: bool = False) -> dict:
    return {**sheet, "fps": 8 if moving else 6, "first_only": first_only}


def main(archive: Path | None) -> None:
    images = source_entries(archive) if archive else None
    expected = {BASE + entry for sheets in SHEETS.values() for _, entry, _ in sheets}
    if images is not None and set(images) != expected:
        raise ValueError(f"Unexpected ZIP contents: {set(images) ^ expected}")
    catalogs = {}
    for name in set(CATALOGS.values()):
        path = ROOT / "src/gameplay/characters" / name
        catalogs[name] = json.loads(path.read_text(encoding="utf-8"))
    touched = []
    common = None
    for slug, bindings in SHEETS.items():
        directory = ROOT / "assets/characters/npc" / slug
        manifest_path = directory / "source/sources.json"
        provenance = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else []
        manifest = provenance["sources"] if isinstance(provenance, dict) else provenance
        sheets = {}
        for key, entry, mirror in bindings:
            raw = directory / "source" / REVISION / f"{key}.png"
            if images is not None:
                data = images[BASE + entry]
                if raw.exists() and raw.read_bytes() != data:
                    raise ValueError(f"Refusing to overwrite a different original: {raw}")
                raw.parent.mkdir(parents=True, exist_ok=True)
                raw.write_bytes(data)
            else:
                data = raw.read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            record = {"archive": ARCHIVE, "entry": BASE + entry,
                      "path": raw.relative_to(ROOT).as_posix(), "sha256": digest}
            previous = next((r for r in manifest if r["path"] == record["path"]), None)
            if previous is not None and previous["sha256"] != digest:
                raise ValueError(f"Retained source hash mismatch: {raw}")
            if previous is None:
                if images is None:
                    raise ValueError(f"No provenance record for retained source: {raw}")
                manifest.append(record)
            sheet, count, source_size, transform = normalize_native(data)
            if mirror:
                # Flip individual cells, preserving row order and the shared feet anchor.
                for index in range(count):
                    stride = source_size + 24
                    x, y = index % 6 * stride, index // 6 * stride
                    cell = sheet.crop((x, y, x + source_size, y + source_size))
                    sheet.paste(cell.transpose(Image.Transpose.FLIP_LEFT_RIGHT), (x, y))
            source = f"{REVISION}_{key}"
            sheet.save(directory / f"{source}.png")
            sheets[key] = {"source": source, "frame_count": count,
                           "source_entry": BASE + entry, "source_frame_size": source_size,
                           "transform": {**transform, "mirror": mirror}}
        save_text(manifest_path, json.dumps(provenance, ensure_ascii=False, indent=2))
        character = next(c for c in catalogs[CATALOGS[slug]] if c["id"] == slug)
        actions = {}
        if slug == "common_goblin":
            for key, sheet in sheets.items():
                actions[key] = animation(sheet, moving="walk" in key)
            for prefix in ["unpacked", "backpack"]:
                actions[f"{prefix}_idle_left"] = actions[f"{prefix}_idle_right"].copy()
            character["supplemental_animations"] = actions
            common = {"id": slug, "animations": actions}
        else:
            for direction in ["down", "up", "right", "left"]:
                side = "right" if direction == "left" else direction
                if "idle" in sheets:
                    actions[f"idle_{direction}"] = animation(sheets["idle"])
                    actions[f"run_{direction}"] = animation(sheets["idle"], True, True)
                else:
                    actions[f"idle_{direction}"] = animation(
                        sheets.get(f"idle_{side}", sheets[f"run_{side}"]),
                        first_only=f"idle_{side}" not in sheets)
                    actions[f"run_{direction}"] = animation(sheets[f"run_{side}"], True)
            for key in ["emote_laugh", "emote_sit"]:
                if key in sheets:
                    actions[key] = animation(sheets[key])
            character["animations"] = actions
            character["active_archive"] = ARCHIVE
            touched.append(character)
        print(slug, {key: value["frame_count"] for key, value in actions.items()})
    for name, catalog in catalogs.items():
        save_text(ROOT / "src/gameplay/characters" / name, json.dumps(catalog, ensure_ascii=False, indent=2))
    with tempfile.TemporaryDirectory() as temp:
        selected = Path(temp) / "catalog.json"
        save_text(selected, json.dumps(touched, ensure_ascii=False))
        build(selected)
        # Reuse the existing builder with a temporary destination for the secondary
        # common-goblin resource; never overwrite its original locomotion library.
        import build_character_frames as builder
        destination = builder.DEST
        try:
            builder.DEST = Path(temp)
            save_text(selected, json.dumps([common], ensure_ascii=False))
            build(selected)
            save_text(destination / "common_goblin_idle_frames.tres",
                      (Path(temp) / "common_goblin_frames.tres").read_text(encoding="utf-8"))
        finally:
            builder.DEST = destination
    sentry = ROOT / "src/gameplay/characters/casino_sentry_frames.tres"
    text = sentry.read_text(encoding="utf-8")
    for name in ["emote_laugh", "emote_sit"]:
        text = text.replace(f'"loop": true,\n"name": &"{name}"',
                            f'"loop": false,\n"name": &"{name}"')
    save_text(sentry, text)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--archive", type=Path)
    source.add_argument("--from-retained", action="store_true")
    args = parser.parse_args()
    main(args.archive)
