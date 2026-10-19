"""Import the supplied annotated griffin sheet without resizing its artwork.

Default input is the archived original. --source accepts the initial attachment.
Writes six hard-alpha PNGs, placement scenes, a preview and catalog provenance.
Requires the existing modular pipeline's Pillow and NumPy dependencies.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image

from extract_modular_assets import ART, ROOT, components, prefab, preview


PACK_ID = "griffin_faith"
SOURCE = ART / "source" / (PACK_ID + ".png")
OBJECTS = [
    ("lamp_post", "格里芬信仰路灯", (205, 10, 400, 420), [1, 3], 274),
    ("emblem_stone_tile", "格里芬徽记石砖", (530, 55, 875, 392), [1, 1], None),
    ("emblem_manhole_cover", "格里芬徽记铸铁井盖", (972, 54, 1325, 393), [1, 1], None),
    ("emblem_shield_sign", "格里芬徽记盾牌形木牌", (115, 550, 442, 894), [1, 1], None),
    ("faith_pillar", "大型格里芬信仰石柱", (645, 492, 810, 904), [1, 3], None),
    ("altar_statue", "大型格里芬祭坛圣像", (980, 489, 1394, 904), [3, 3], None),
]


def crop_object(sheet, region):
    """Keep the largest connected silhouette, excluding labels and arrows."""
    pixels = np.array(sheet.crop(region))
    groups = components(pixels[:, :, 3] >= 170)
    if not groups:
        raise ValueError(f"No opaque artwork in source region {region}")
    group = max(groups, key=lambda item: item["area"])
    left, top, right, bottom = group["box"]
    if min(left, top, pixels.shape[1] - right, pixels.shape[0] - bottom) < 1:
        raise ValueError(f"Silhouette touches extraction region {region}")
    cut = np.zeros((bottom - top + 4, right - left + 4, 4), dtype=np.uint8)
    for y, start, end in group["runs"]:
        cut[y - top + 2, start - left + 2:end - left + 2, :3] = pixels[y, start:end, :3]
        cut[y - top + 2, start - left + 2:end - left + 2, 3] = 255
    box = [region[0] + left, region[1] + top, right - left, bottom - top]
    return Image.fromarray(cut), box


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE)
    args = parser.parse_args()
    source_bytes = args.source.read_bytes()
    source_hash = hashlib.sha256(source_bytes).hexdigest()
    with Image.open(args.source) as original:
        if original.size != (1536, 1024):
            raise ValueError(f"Expected the original 1536x1024 sheet, got {original.size}")
        sheet = original.convert("RGBA")
    if args.source.resolve() != SOURCE.resolve():
        if SOURCE.exists() and SOURCE.read_bytes() != source_bytes:
            raise ValueError("The archived source differs; preserve it instead of overwriting")
        SOURCE.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(args.source, SOURCE)
    output = ART / PACK_ID
    output.mkdir(parents=True, exist_ok=True)
    pack = {
        "id": PACK_ID,
        "title": "格里芬信仰装饰",
        "kind": "props",
        "source_kind": "user_supplied",
        "source": "res://" + SOURCE.relative_to(ROOT).as_posix(),
        "source_sha256": source_hash,
        "license": "User-supplied for project import; no external license supplied.",
        "processing": "Largest connected alpha>=170 silhouette in each ROI; hard alpha; 2px padding; no resizing.",
        "assets": [],
    }
    for asset_id, description, region, grid, ground_x in OBJECTS:
        image, box = crop_object(sheet, region)
        texture = output / (asset_id + ".png")
        image.save(texture)
        anchor = [image.width // 2, image.height - 2]
        if ground_x is not None:
            anchor[0] = ground_x - box[0] + 2
        scene, anchor = prefab(PACK_ID, asset_id, image.size, anchor)
        pack["assets"].append({
            "id": asset_id,
            "description": description,
            "texture": "res://" + texture.relative_to(ROOT).as_posix(),
            "scene": scene,
            "native_size": list(image.size),
            "anchor": anchor,
            "sheet_box": box,
            "extraction_region": list(region),
            "source": pack["source"],
            "source_annotation_grid": grid,
            "source_annotation_size": [value * 48 for value in grid],
        })
    preview(pack, pack["assets"])
    catalog_path = ART / "catalog.json"
    data = json.loads(catalog_path.read_text(encoding="utf-8"))
    # Replace this pack in place on repeated imports, preserving gallery order.
    packs = data["packs"]
    for index, existing in enumerate(packs):
        if existing["id"] == PACK_ID:
            packs[index] = pack
            break
    else:
        packs.append(pack)
    data["count"] = sum(len(item["assets"]) for item in packs)
    catalog_path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Imported {len(pack['assets'])} native-size PNG/scene pairs; source SHA256: {source_hash}")


if __name__ == "__main__":
    main()
