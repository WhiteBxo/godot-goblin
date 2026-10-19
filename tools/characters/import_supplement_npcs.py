"""Import supplied NPC archives, keeping originals and the revised drunk sources.

Usage: python tools/characters/import_supplement_npcs.py --source-dir <attachment directory>
Raw PNG bytes and provenance are retained. Derived sheets use 64px square frames,
88px strides and uniformly fit the actual artwork using nearest-neighbour sampling.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import zipfile
from pathlib import Path

from PIL import Image

from build_character_frames import build

ROOT = Path(__file__).resolve().parents[2]
REVISED_DRUNKS = "酒鬼（改后(1).zip"
DEFINITIONS = [
    ("warehouse_sentry", "仓库守卫", "仓库前的守卫。", "侍卫3(1).zip", "侍卫3/", {
        "idle_down": "待机.png", "idle_up": "待机2.png", "idle_right": "待机3.png",
        "run_down": "走路1.png", "run_right": "走路2.png", "run_up": "走路3.png",
        "fall": "尝试的倒地.png",
    }),
    ("prayer_man", "祈祷者", "祭坛前的祈祷者。", "祈祷者(1).zip", "祈祷者/男/", {
        "idle_down": "待机.png", "idle_up": "待机2.png", "idle_right": "待机3.png",
        "run_down": "走.png", "run_right": "走2.png", "run_up": "走3.png",
    }),
    ("prayer_woman", "同伴", "祭坛前与祈祷者交谈的同伴。", "祈祷者(1).zip", "祈祷者/女/", {
        "idle_down": "待机.png", "idle_up": "待机2.png", "idle_right": "待机👉.png",
        "run_down": "待机3.png", "run_right": "走路3.png", "run_up": "走路.png",
    }),
    ("prayer_elder", "年迈祈祷者", "祭坛旁静坐的年迈祈祷者。", "祈祷者(1).zip", "祈祷者/老头/", {
        "idle_down": "待机.png",
    }),
    ("tavern_drunk", "醉鬼", "酒馆外与哲人争论的醉鬼。", "酒鬼.zip", "酒鬼/1/", {
        "idle_down": "待机.png",
    }),
    ("tavern_drinker", "买醉者", "酒馆内独自买醉的客人。", "酒鬼.zip", "酒鬼/2/", {
        "idle_down": "合并图片.png",
    }),
    ("goblin_boy", "哥布林小男孩", "集市上和母亲一起的哥布林小男孩。", "小男孩.zip", "小男孩/", {
        "idle_down": "待机2.png", "idle_up": "待机1.png",
        "run_down": "走路1.png", "run_right": "走路2.png", "run_up": "走路3.png",
        "emote_sit": "待机3.png", "emote_slingshot": "打弹弓.png", "emote_stones": "坐着抛石子.png",
    }),
    ("goblin_girl", "哥布林小孩", "村庄里谈论茱丽叶骑士的哥布林小孩。", "女孩.zip", "女孩/", {
        "idle_down": "待机1.png", "idle_up": "待机1.png", "idle_right": "待机1.png",
        "run_down": "走路.png", "run_up": "走路.png", "run_right": "走路.png",
    }),
]


def save_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text.rstrip() + "\n", encoding="utf-8", newline="\n")


def source_entries(path: Path) -> dict[str, bytes]:
    with zipfile.ZipFile(path) as archive:
        result = {}
        for entry in archive.infolist():
            name = entry.filename if entry.flag_bits & 0x800 else entry.filename.encode("cp437").decode("utf-8")
            if name.startswith("__MACOSX/") or not name.lower().endswith(".png"):
                continue
            if ".." in Path(name).parts:
                raise ValueError("Unsafe archive entry")
            result[name] = archive.read(entry)
        return result


def normalize(data: bytes, height=58, direction: str | None = None) -> tuple[Image.Image, int, int, dict]:
    image = Image.open(io.BytesIO(data)).convert("RGBA")
    size, stride = (256, 280) if image.width == 1656 else ((128, 152) if image.width == 888 else (64, 88))
    frames = []
    transform = {}
    if direction is not None:
        # Girl sheets mix directions in a 4x2 grid with no cell padding.
        indices = {"up": [0, 1, 4], "right": [2, 5], "down": [3, 6, 7]}[direction]
        for index in indices:
            col, row = index % 4, index // 4
            frames.append(image.crop((col * image.width // 4, row * image.height // 2,
                                      (col + 1) * image.width // 4, (row + 1) * image.height // 2)))
        size = max(frame.height for frame in frames)
        transform = {"grid": [4, 2], "source_indices": indices}
    else:
        for y in range(0, image.height - size + 1, stride):
            for x in range(0, image.width - size + 1, stride):
                frame = image.crop((x, y, x + size, y + size))
                if frame.getchannel("A").getbbox() is not None:
                    frames.append(frame)
    if not frames:
        raise ValueError("Empty animation sheet")
    # Some 128px cells contain a 64px character. Fit actual artwork, rather
    # than shrinking by cell size and making those directions half as tall.
    boxes = [frame.getchannel("A").getbbox() for frame in frames]
    crop = (min(b[0] for b in boxes), min(b[1] for b in boxes),
            max(b[2] for b in boxes), max(b[3] for b in boxes))
    factor = min(60 / (crop[2] - crop[0]), height / (crop[3] - crop[1]))
    target = (round((crop[2] - crop[0]) * factor), round((crop[3] - crop[1]) * factor))
    rows = (len(frames) + 5) // 6
    output = Image.new("RGBA", (504, rows * 88 - 24))
    for index, frame in enumerate(frames):
        art = frame.crop(crop).resize(target, Image.Resampling.NEAREST)
        output.paste(art, ((index % 6) * 88 + (64 - target[0]) // 2,
                           (index // 6) * 88 + 62 - target[1]))
    return output, len(frames), size, {**transform, "crop": crop, "scale": factor}


def preserve_sources(directory: Path, images: dict[str, bytes], archive_name: str,
                     prefix: str, bindings: dict, revision="") -> list[dict]:
    sources = []
    inverse = {prefix + source: key for key, source in bindings.items()}
    for index, (entry, data) in enumerate(images.items()):
        raw_name = inverse.get(entry, f"unused_{index:02d}")
        if Image.open(io.BytesIO(data)).size == (1024, 1024) or entry.endswith("/女孩.png"):
            raw_name = "portrait"
        raw_path = directory / "source" / revision / (raw_name + ".png")
        raw_path.parent.mkdir(parents=True, exist_ok=True)
        if raw_path.exists() and raw_path.read_bytes() != data:
            raise ValueError(f"Refusing to overwrite {raw_path}")
        raw_path.write_bytes(data)
        sources.append({"archive": archive_name, "entry": entry, "path": raw_path.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(data).hexdigest()})
        if raw_name == "portrait":
            image = Image.open(io.BytesIO(data))
            box = image.getchannel("A").getbbox()
            box = (max(0, box[0] - 4), max(0, box[1] - 4), min(image.width, box[2] + 4), min(image.height, box[3] + 4))
            image.crop(box).save(directory / "portrait.png")
            sources[-1]["portrait_crop"] = box
    return sources


def main(source_dir: Path) -> None:
    names = {definition[3] for definition in DEFINITIONS} | {REVISED_DRUNKS}
    archives = {name: source_entries(source_dir / name) for name in names}
    catalog = []
    for slug, name, role, archive_name, prefix, bindings in DEFINITIONS:
        directory = ROOT / "assets/characters/npc" / slug
        images = {entry: data for entry, data in archives[archive_name].items() if entry.startswith(prefix)}
        sources = preserve_sources(directory, images, archive_name, prefix, bindings)
        if slug in ["tavern_drunk", "tavern_drinker"]:
            archive_name = REVISED_DRUNKS
            images = {entry: data for entry, data in archives[archive_name].items() if entry.startswith(prefix)}
            sources += preserve_sources(directory, images, archive_name, prefix, bindings, "revised")
        animations = {}
        for animation, source in bindings.items():
            direction = animation.rsplit("_", 1)[1] if slug == "goblin_girl" else None
            height = 44 if slug == "goblin_boy" else (50 if slug == "goblin_girl" else 58)
            sheet, count, frame_size, transform = normalize(images[prefix + source], height, direction)
            sheet.save(directory / (animation + ".png"))
            animations[animation] = {"source": animation, "fps": 6 if animation.startswith("idle") else 8, "first_only": False, "frame_count": count, "source_frame_size": frame_size, "transform": transform}
        if slug == "prayer_woman":
            # The supplied 待机3 is a back-facing idle, not a front walk.
            animations["run_down"] = animations["idle_down"].copy()
        if slug == "goblin_boy":
            animations["idle_right"] = {**animations["run_right"], "first_only": True}
        for direction in ["down", "up", "right", "left"]:
            for kind in ["idle", "run"]:
                key = f"{kind}_{direction}"
                if key not in animations:
                    reference = f"{kind}_right" if direction == "left" else "idle_down"
                    animations[key] = animations[reference].copy()
        catalog.append({"id": slug, "display_name": name, "role": role, "active_archive": archive_name, "side_faces_left": slug == "goblin_girl", "animations": animations})
        save_text(directory / "source/sources.json", json.dumps(sources, ensure_ascii=False, indent=2))
        scene = (ROOT / "src/gameplay/characters/casino_sentry.tscn").read_text(encoding="utf-8")
        scene = scene.replace("CasinoSentry", "".join(part.title() for part in slug.split("_"))).replace("casino_sentry", slug).replace('display_name = "侍卫"', f'display_name = "{name}"').replace('story_role = "赌场的侍卫，负责看守赌场。"', f'story_role = "{role}"')
        if slug == "goblin_girl":
            scene = scene.replace("side_faces_left = false", "side_faces_left = true")
        save_text(ROOT / f"src/gameplay/characters/{slug}.tscn", scene)
        scene = (ROOT / "src/gameplay/characters/rpg_casino_sentry.tscn").read_text(encoding="utf-8").replace("CasinoSentry", "".join(part.title() for part in slug.split("_"))).replace("casino_sentry", slug)
        save_text(ROOT / f"src/gameplay/characters/rpg_{slug}.tscn", scene)
        print(slug, {key: value["frame_count"] for key, value in animations.items()})
    path = ROOT / "src/gameplay/characters/supplement_npc_catalog.json"
    save_text(path, json.dumps(catalog, ensure_ascii=False, indent=2))
    build(path)
    for slug, actions in {"warehouse_sentry": ["fall"], "goblin_boy": ["emote_slingshot", "emote_stones"]}.items():
        frames = ROOT / f"src/gameplay/characters/{slug}_frames.tres"
        text = frames.read_text(encoding="utf-8")
        for action in actions:
            text = text.replace(f'"loop": true,\n"name": &"{action}"', f'"loop": false,\n"name": &"{action}"')
        save_text(frames, text)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-dir", type=Path, required=True)
    main(parser.parse_args().source_dir)
