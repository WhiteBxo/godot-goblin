"""Update three NPC appearances from retained PNGs or the supplied ZIP directory.

First import: --source-dir <directory containing 妇女(1).zip and 女孩(3).zip>.
Subsequent runs need only Python + Pillow and the versioned source PNGs.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import re
import tempfile
from pathlib import Path

from PIL import Image

from build_character_frames import build
from import_supplement_npcs import ROOT, save_text, source_entries

REVISION = "update_2026_10_20"
DEFINITIONS = {
    "market_mother": ("妇女(1).zip", {
        "portrait": "妇女/妇女1.png", "idle": "妇女/妇女1待机.png",
        "walk": "妇女/妇女1走路.png",
    }),
    "prayer_woman": ("妇女(1).zip", {
        "portrait": "妇女/妇女2.png", "walk_duplicate": "妇女/妇女2走路.png",
        "wave": "妇女/妇女2待机1.png", "idle": "妇女/妇女2待机2.png",
    }),
    "goblin_girl": ("女孩(3).zip", {
        "portrait": "女孩/女孩.png", "walk": "女孩/走路.png",
        "idle": "女孩/待机1.png", "sweep": "女孩/待机2.png", "look": "女孩/待机3.png",
    }),
}
## The altar companion keeps her own prayer-woman portrait; 妇女2 is a reusable
## commoner, so its portrait is archived only (see PORTRAIT_ARCHIVE_NOTE).
## The displayed portrait is rebuilt from the retained 祈祷者(1).zip original
## with the crop recorded in sources.json, which reproduces the pre-update bytes.
OWN_PORTRAIT_SOURCES = {"prayer_woman": "source/portrait.png"}
PORTRAIT_ARCHIVE_NOTE = {
    "prayer_woman": "妇女2立绘原件：可复用的平民妇女素材，仅归档；祭坛同伴使用自己的祈祷者立绘，不由本件生成",
}


def make_sheet(data: bytes, indices: list[int], height: int,
               mirror_indices: tuple[int, ...] = ()) -> tuple[Image.Image, dict]:
    image = Image.open(io.BytesIO(data)).convert("RGBA")
    # These attachments use mixed directions in unpadded 4x2 sheets, not the
    # older 64px/88px source grid. Mirror opposite side poses before packing.
    frames = []
    for index in indices:
        col, row = index % 4, index // 4
        frame = image.crop((col * image.width // 4, row * image.height // 2,
                            (col + 1) * image.width // 4, (row + 1) * image.height // 2))
        if index in mirror_indices:
            frame = frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        frames.append(frame)
    boxes = [frame.getchannel("A").getbbox() for frame in frames]
    if any(box is None for box in boxes):
        raise ValueError("Selected an empty source cell")
    # The hand-packed cells drift horizontally and vertically across each row.
    # Remove that packing offset while keeping one uniform scale per sequence.
    factor = min(60 / max(b[2] - b[0] for b in boxes),
                 height / max(b[3] - b[1] for b in boxes))
    sheet = Image.new("RGBA", (504, ((len(frames) + 5) // 6) * 88 - 24))
    for index, (frame, box) in enumerate(zip(frames, boxes)):
        size = (round((box[2] - box[0]) * factor), round((box[3] - box[1]) * factor))
        art = frame.crop(box).resize(size, Image.Resampling.NEAREST)
        sheet.paste(art, (index % 6 * 88 + (64 - size[0]) // 2,
                          index // 6 * 88 + 62 - size[1]))
    return sheet, {"grid": [4, 2], "source_indices": indices,
                   "mirror_indices": list(mirror_indices), "source_boxes": boxes,
                   "alignment": "cell artwork centered, feet at y=62", "scale": factor}


def rebuild_own_portrait(directory: Path, source: str) -> None:
    """Recut the character's own retained portrait using its recorded crop."""
    manifest = json.loads((directory / "source/sources.json").read_text(encoding="utf-8"))
    entry = next((item for item in manifest if item["path"].endswith(source)), None)
    if entry is None or "portrait_crop" not in entry:
        raise ValueError(f"Missing recorded portrait crop for {directory.name}/{source}")
    image = Image.open(ROOT / entry["path"]).convert("RGBA")
    image.crop(tuple(entry["portrait_crop"])).save(directory / "portrait.png")


def main(source_dir: Path | None) -> None:
    catalog_path = ROOT / "src/gameplay/characters/supplement_npc_catalog.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    entries = {entry["id"]: entry for entry in catalog}
    if "market_mother" not in entries:
        entries["market_mother"] = {"id": "market_mother", "display_name": "哥布林母亲",
                                    "role": "带孩子逛集市的母亲。"}
        catalog.append(entries["market_mother"])
    archives = {} if source_dir is None else {
        name: source_entries(source_dir / name) for name, _ in DEFINITIONS.values()
    }
    for slug, (archive, bindings) in DEFINITIONS.items():
        directory = ROOT / "assets/characters/npc" / slug
        manifest_path = directory / "source/sources.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else []
        raw = {}
        for name, entry in bindings.items():
            path = directory / "source" / REVISION / (name + ".png")
            data = archives[archive][entry] if source_dir else path.read_bytes()
            if path.exists() and path.read_bytes() != data:
                raise ValueError(f"Refusing to overwrite retained source: {path}")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            raw[name] = data
            record = {"archive": archive, "entry": entry,
                      "path": path.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(data).hexdigest()}
            if name == "portrait" and slug in PORTRAIT_ARCHIVE_NOTE:
                record["note"] = PORTRAIT_ARCHIVE_NOTE[slug]
            manifest = [old for old in manifest if old["path"] != record["path"]]
            manifest.append(record)
        if slug in OWN_PORTRAIT_SOURCES:
            rebuild_own_portrait(directory, OWN_PORTRAIT_SOURCES[slug])
        else:
            portrait = Image.open(io.BytesIO(raw["portrait"])).convert("RGBA")
            portrait.save(directory / "portrait.png")
        save_text(manifest_path, json.dumps(manifest, ensure_ascii=False, indent=2))
        animations = {}

        def animation(name, source, indices, mirrors=(), first_only=False):
            sheet, transform = make_sheet(raw[source], indices, 50 if slug == "goblin_girl" else 58, mirrors)
            sheet.save(directory / (name + ".png"))
            animations[name] = {"source": name, "source_entry": bindings[source],
                                "fps": 8 if name.startswith("run") else 6,
                                "first_only": first_only, "frame_count": len(indices),
                                "transform": transform}

        if slug == "market_mother":
            animation("idle_right", "idle", list(range(8)))  # Source faces left.
            animation("run_up", "walk", [0, 1, 7])
            animation("run_down", "walk", [3, 4, 6])
            animation("run_right", "walk", [2, 5], (5,))
            for direction in ("down", "up"):
                animations["idle_" + direction] = {**animations["run_" + direction], "first_only": True}
            side_faces_left = True
            note = "Front/back idle use the first matching walk pose; side source faces left."
        elif slug == "prayer_woman":
            animation("idle_down", "wave", list(range(8)))
            animation("idle_right", "idle", list(range(8)))  # Source faces left.
            animations["idle_up"] = animations["idle_down"].copy()
            for direction in ("down", "up", "right"):
                animations["run_" + direction] = animations["idle_" + direction].copy()
            side_faces_left = True
            mother_walk = ROOT / "assets/characters/npc/market_mother/source" / REVISION / "walk.png"
            if raw["walk_duplicate"] != mother_walk.read_bytes():
                raise ValueError("Reinspect woman 2 walking sheet: expected the supplied duplicate")
            note = ("Portrait stays the prayer-woman original (祈祷者/女/🚺.png), not woman 2. "
                    "Woman 2 walk is byte-identical to woman 1; retain but never display it. "
                    "Movement uses own idle; back view unavailable.")
        else:
            for kind, source in (("idle", "idle"), ("run", "walk")):
                animation(kind + "_up", source, [0, 1, 4])
                animation(kind + "_down", source, [3, 6, 7])
                animation(kind + "_right", source, [2, 5], (2,) if kind == "idle" else (5,))
            animation("emote_sweep", "sweep", list(range(8)))
            animation("emote_look", "look", list(range(8)))
            side_faces_left = False
            note = "Mixed side poses are mirrored individually to face right; optional sweep/look loops have no new story triggers."
        for kind in ("idle", "run"):
            animations[kind + "_left"] = animations[kind + "_right"].copy()
        entries[slug].update(active_archive=archive, side_faces_left=side_faces_left,
                             animations=animations, appearance_notes=note)
        scene_path = ROOT / f"src/gameplay/characters/{slug}.tscn"
        template = scene_path if scene_path.exists() else ROOT / "src/gameplay/characters/prayer_woman.tscn"
        text = template.read_text(encoding="utf-8")
        if slug == "market_mother":
            text = text.replace("PrayerWoman", "MarketMother").replace("prayer_woman", slug)
            text = text.replace('display_name = "同伴"', 'display_name = "哥布林母亲"')
            text = text.replace('story_role = "祭坛前与祈祷者交谈的同伴。"', 'story_role = "带孩子逛集市的母亲。"')
            rpg = (ROOT / "src/gameplay/characters/rpg_prayer_woman.tscn").read_text(encoding="utf-8")
            save_text(ROOT / "src/gameplay/characters/rpg_market_mother.tscn",
                      rpg.replace("PrayerWoman", "MarketMother").replace("prayer_woman", slug))
        text = re.sub(r"side_faces_left = (true|false)", f"side_faces_left = {str(side_faces_left).lower()}", text)
        save_text(scene_path, text)
        print(slug, {key: value["frame_count"] for key, value in animations.items()})
    save_text(catalog_path, json.dumps(catalog, ensure_ascii=False, indent=2))
    # Build only these three resources: preserve unrelated hand-edited loops.
    with tempfile.TemporaryDirectory() as temporary:
        selected = Path(temporary) / "catalog.json"
        save_text(selected, json.dumps([entries[slug] for slug in DEFINITIONS], ensure_ascii=False))
        build(selected)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path)
    main(parser.parse_args().source_dir)
