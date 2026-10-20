"""Separate generated/reference sheets into native-size transparent PNGs and scenes."""
from pathlib import Path
import argparse
import json
import shutil
from PIL import Image, ImageDraw, ImageFont
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "assets/map/settlement/modular"
RAW = ROOT / "output/imagegen/modular"
SCENES = ROOT / "src/levels/settlement/modules"


def opaque_edges(image):
    pixels = np.array(image.convert("RGBA"), dtype=np.uint8)
    rgb = pixels[:, :, :3].astype(np.int16)
    # Keep the generator's real alpha and remove residual key-colored edge pixels.
    key = (rgb[:, :, 0] > 145) & (rgb[:, :, 2] > 140) & (rgb[:, :, 1] < 135) & (abs(rgb[:, :, 0] - rgb[:, :, 2]) < 65) & ((rgb[:, :, 0] - rgb[:, :, 1]) > 70) & ((rgb[:, :, 2] - rgb[:, :, 1]) > 70)
    pixels[:, :, 3] = np.where((pixels[:, :, 3] >= 170) & ~key, 255, 0)
    pixels[pixels[:, :, 3] == 0, :3] = 0
    return Image.fromarray(pixels)


def prefab(pack, item, size, anchor=None):
    width, height = size
    anchor = anchor if anchor is not None else [width // 2, height - 2]
    name = "".join(part.capitalize() for part in item.split("_"))
    texture = f"res://assets/map/settlement/modular/{pack}/{item}.png"
    text = f'''[gd_scene load_steps=2 format=3]

[ext_resource type="Texture2D" path="{texture}" id="1_texture"]

[node name="{name}" type="Node2D"]
texture_filter = 1
metadata/pack = "{pack}"
metadata/asset_id = "{item}"
metadata/native_size = Vector2i({width}, {height})

[node name="Visual" type="Sprite2D" parent="."]
position = Vector2({-anchor[0]}, {-anchor[1]})
texture = ExtResource("1_texture")
centered = false

[node name="GroundAnchor" type="Marker2D" parent="."]
'''
    if any(word in item for word in ["table", "desk", "counter"]):
        text += f'\n[node name="SurfaceAnchor" type="Marker2D" parent="."]\nposition = Vector2(0, {-round(height * .60)})\n'
    if item in ["wall_west", "wall_east"] and "walls_" in pack:
        text += f'\n[node name="TopEnd" type="Marker2D" parent="."]\nposition = Vector2(0, {-height + 4})\n\n[node name="BottomEnd" type="Marker2D" parent="."]\n'
    elif item.startswith("wall_") and "walls_" in pack:
        text += f'\n[node name="LeftEnd" type="Marker2D" parent="."]\nposition = Vector2({-anchor[0] + 2}, 0)\n\n[node name="RightEnd" type="Marker2D" parent="."]\nposition = Vector2({width - anchor[0] - 2}, 0)\n'
    folder = SCENES / pack
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"{item}.tscn").write_text(text, encoding="utf-8", newline="\n")
    return f"res://src/levels/settlement/modules/{pack}/{item}.tscn", anchor


def checker(size):
    image = Image.new("RGB", size, "#353b47")
    draw = ImageDraw.Draw(image)
    for y in range(0, size[1], 24):
        for x in range(0, size[0], 24):
            if (x // 24 + y // 24) % 2:
                draw.rectangle((x, y, x + 23, y + 23), fill="#424958")
    return image


def components(mask):
    """Run-length connected components, preserving the complete pixel silhouette."""
    parents, runs, previous = [], [], []
    def find(value):
        while parents[value] != value:
            parents[value] = parents[parents[value]]
            value = parents[value]
        return value
    for y, row in enumerate(mask):
        edges = np.diff(np.pad(row.astype(np.int8), (1, 1)))
        starts, ends = np.flatnonzero(edges == 1), np.flatnonzero(edges == -1)
        current = []
        cursor = 0
        for start, end in zip(starts, ends):
            start, end = int(start), int(end)
            label = len(parents)
            parents.append(label)
            while cursor < len(previous) and previous[cursor][1] < start:
                cursor += 1
            for a, b, other in previous[cursor:]:
                if a > end:
                    break
                one, two = find(label), find(other)
                if one != two:
                    parents[one] = two
            current.append((start, end, label))
            runs.append((y, start, end, label))
        previous = current
    groups = {}
    for y, start, end, label in runs:
        key = find(label)
        group = groups.setdefault(key, {"runs": [], "box": [start, y, end, y + 1], "area": 0})
        group["runs"].append((y, start, end))
        group["area"] += end - start
        box = group["box"]
        box[:] = [min(box[0], start), min(box[1], y), max(box[2], end), max(box[3], y + 1)]
    return [group for group in groups.values() if group["area"] >= 3]


def object_masks(image, cell, columns, count):
    pixels = np.array(image)
    groups = components(pixels[:, :, 3] > 0)
    primary = []
    for i in range(count):
        x, y = i % columns * cell[0], i // columns * cell[1]
        candidates = [g for g in groups if x <= (g["box"][0] + g["box"][2]) / 2 < x + cell[0] and y <= (g["box"][1] + g["box"][3]) / 2 < y + cell[1]]
        if not candidates:
            raise ValueError(f"No complete silhouette for cell {i}")
        primary.append(max(candidates, key=lambda g: g["area"]))
    buckets = [[] for _ in range(count)]
    for group in groups:
        if any(group is item for item in primary):
            winner = next(i for i, item in enumerate(primary) if group is item)
        else:
            a, b, c, d = group["box"]
            def distance(item):
                left, top, right, bottom = item["box"]
                dx = max(left - c, a - right, 0)
                dy = max(top - d, b - bottom, 0)
                return dx * dx + dy * dy
            winner = min(range(count), key=lambda i: distance(primary[i]))
        buckets[winner].append(group)
    result = []
    for bucket in buckets:
        box = [min(g["box"][0] for g in bucket), min(g["box"][1] for g in bucket), max(g["box"][2] for g in bucket), max(g["box"][3] for g in bucket)]
        left, top, right, bottom = box
        cut = np.zeros((bottom - top, right - left, 4), dtype=np.uint8)
        for group in bucket:
            for y, start, end in group["runs"]:
                cut[y - top, start - left:end - left] = pixels[y, start:end]
        result.append((Image.fromarray(cut), box))
    return result


def preview(pack, assets):
    image = checker((1536, 1120))
    draw = ImageDraw.Draw(image)
    font = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 20)
    header = ImageFont.truetype(r"C:\Windows\Fonts\msyh.ttc", 32)
    draw.rectangle((0, 0, 1536, 72), fill="#202631")
    draw.text((22, 17), pack["title"] + " · 独立透明素材 · 原始像素比例", font=header, fill="#ecdfbe")
    for i, asset in enumerate(assets):
        im = Image.open(ROOT / asset["texture"].removeprefix("res://")).convert("RGBA")
        col, row = i % 4, i // 4
        at = (col * 384 + (384 - im.width) // 2, 74 + row * 512 + (420 - im.height) // 2)
        image.paste(im, at, im)
        draw.text((col * 384 + 14, 74 + row * 512 + 432), asset["id"], font=font, fill="white")
        draw.text((col * 384 + 14, 74 + row * 512 + 466), f"{im.width}×{im.height} px · 1:1", font=font, fill="#c4cbd8")
    folder = ART / "previews"
    folder.mkdir(exist_ok=True)
    image.save(folder / (pack["id"] + ".png"))


def extract(pack, sheet, cell, columns, source_name):
    clean = opaque_edges(sheet)
    output = ART / pack["id"]
    output.mkdir(parents=True, exist_ok=True)
    assets, issues = [], []
    isolated = object_masks(clean, cell, columns, len(pack["objects"]))
    for i, obj in enumerate(pack["objects"]):
        cut, box = isolated[i]
        if min(box[0], box[1], clean.width - box[2], clean.height - box[3]) <= 2:
            issues.append(f"{pack['id']}/{obj['id']}: touches source canvas boundary; regenerate if clipped")
        # Crop only. Pixel dimensions/proportions of the painted object never change.
        image = Image.new("RGBA", (cut.width + 4, cut.height + 4))
        image.paste(cut, (2, 2))
        target = output / (obj["id"] + ".png")
        image.save(target)
        scene, anchor = prefab(pack["id"], obj["id"], image.size)
        assets.append({"id": obj["id"], "description": obj["description"], "texture": "res://" + target.relative_to(ROOT).as_posix(), "scene": scene, "native_size": list(image.size), "anchor": anchor, "sheet_box": [box[0], box[1], box[2] - box[0], box[3] - box[1]], "source": source_name})
    preview(pack, assets)
    return {"id": pack["id"], "title": pack["title"], "kind": pack["kind"], "assets": assets}, issues


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--partial", action="store_true")
    parser.add_argument("--raw-dir", type=Path, default=RAW)
    args = parser.parse_args()
    data = json.loads((ART / "briefs.json").read_text(encoding="utf-8"))
    (ART / "source").mkdir(exist_ok=True)
    catalog, issues, missing = [], [], []
    for pack in data["packs"]:
        choices = [ART / "source" / (pack["id"] + ".png"), args.raw_dir / (pack["id"] + ".png")] + sorted(args.raw_dir.glob(pack["id"] + "_v*.png"))
        selected = next((path for path in reversed(choices) if path.exists()), None)
        if selected is None:
            missing.append(pack["id"])
            continue
        image = Image.open(selected).convert("RGBA")
        if image.size != (1536, 1024):
            raise ValueError(f"Wrong native size {selected.name}: {image.size}; regenerate instead of stretching")
        source = ART / "source" / (pack["id"] + ".png")
        if selected.resolve() != source.resolve():
            shutil.copy2(selected, source)
        group, warnings = extract(pack, image, (384, 512), 4, "res://" + source.relative_to(ROOT).as_posix())
        catalog.append(group)
        issues.extend(warnings)
    names = ["rock_a", "rock_b", "rock_c", "rock_d", "rock_e", "rock_f", "pillar_round", "pillar_square", "crate_barrel", "bench", "barrel", "grain_sacks", "blue_mushrooms", "white_mushrooms", "herbs", "brazier", "planter", "basket", "lamp_post", "sacks", "handcart", "firewood", "sign", "stone_marker"]
    original = Image.open(ROOT / "assets/map/settlement/props.png").convert("RGBA")
    for index, label in enumerate(["岩石与石柱", "常用补给道具", "常用生活道具"]):
        # Build a temporary sheet from exact 256x256 source cells; no resampling.
        sheet = Image.new("RGBA", (1024, 512))
        objects = []
        for j in range(8):
            item = index * 8 + j
            x, y = item % 6 * 256, item // 6 * 256
            sheet.paste(original.crop((x, y, x + 256, y + 256)), (j % 4 * 256, j // 4 * 256))
            objects.append({"id": names[item], "description": names[item]})
        pack = {"id": f"common_{index + 1}", "title": label, "kind": "common", "objects": objects}
        group, warnings = extract(pack, sheet, (256, 256), 4, "res://assets/map/settlement/props.png")
        catalog.append(group)
        issues.extend(warnings)
    # Supplementary user sheets have their own importer and provenance. Rebuilding
    # the generated packs must not remove those independent catalog entries.
    catalog_path = ART / "catalog.json"
    if catalog_path.exists():
        previous = json.loads(catalog_path.read_text(encoding="utf-8"))
        generated_ids = {pack["id"] for pack in catalog}
        catalog.extend(pack for pack in previous["packs"]
                       if pack.get("source_kind") == "user_supplied" and pack["id"] not in generated_ids)
    result = {"version": 1, "model": "gpt-image-2.5-sunburst", "processing": "native crop + hard alpha only; no resizing", "count": sum(len(pack["assets"]) for pack in catalog), "packs": catalog, "inspection_notes": issues}
    (ART / "catalog.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    docs = ROOT / "docs/assets/modular_assets/captures"
    docs.mkdir(parents=True, exist_ok=True)
    overview = Image.new("RGB", (1536, ((len(catalog) + 3) // 4) * 300), "#202631")
    for i, pack in enumerate(catalog):
        thumb = Image.open(ART / "previews" / (pack["id"] + ".png"))
        thumb.thumbnail((384, 280))  # Review artifact only.
        overview.paste(thumb, (i % 4 * 384, i // 4 * 300))
    overview.save(docs / "catalog.png")
    print(f"Extracted {result['count']} transparent PNGs and independent Godot scenes in {len(catalog)} packs.")
    for issue in issues:
        print("INSPECT", issue)
    if missing:
        print("Missing sheets:", ", ".join(missing))
        if not args.partial:
            raise SystemExit(1)


if __name__ == "__main__":
    main()
