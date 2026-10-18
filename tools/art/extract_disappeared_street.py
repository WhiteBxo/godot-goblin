"""Crop the generated street into native-size sprites; never resample artwork.

Run after the extraction jobs in docs/disappeared_street/README.md. The original
concept, accepted API outputs and their prompts remain available for review.
"""
from pathlib import Path
import argparse
import json
import shutil

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from extract_modular_assets import object_masks


ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "assets/map/disappeared_street"
MODULES = ROOT / "src/levels/disappeared_street/modules"
SELECTED = {
    "shop": "shop",
    "dwelling": "dwelling_compact",
    "stalls": "stalls",
    "props": "props_compact",
    "cave_rim": "cave_rim",
    "ground": "ground",
}


def clean(image):
    pixels = np.array(image.convert("RGBA"))
    rgb = pixels[:, :, :3].astype(np.int16)
    magenta = ((rgb[:, :, 0] - rgb[:, :, 1] > 20)
               & (rgb[:, :, 2] - rgb[:, :, 1] > 25)
               & (np.abs(rgb[:, :, 0] - rgb[:, :, 2]) < 90))
    # Discard soft model glow outside the solid sprite, retaining opaque outlines.
    pixels[:, :, 3] = np.where((pixels[:, :, 3] >= 200) & ~magenta, 255, 0)
    pixels[pixels[:, :, 3] == 0, :3] = 0
    return Image.fromarray(pixels)


def prefab(name, size, collision):
    width, height = size
    anchor_x = 24 if name == "lamp_post" else width // 2
    title = "".join(part.title() for part in name.split("_"))
    text = f'''[gd_scene format=3]

[ext_resource type="Texture2D" path="res://assets/map/disappeared_street/{name}.png" id="1"]
'''
    if collision:
        x, y, w, h = collision
        text += f'''
[sub_resource type="RectangleShape2D" id="Footprint"]
size = Vector2({w}, {h})
'''
    text += f'''
[node name="{title}" type="Node2D"]
texture_filter = 1
metadata/asset_id = "{name}"
metadata/native_size = Vector2i({width}, {height})

[node name="Visual" type="Sprite2D" parent="."]
position = Vector2({-anchor_x}, {-height})
texture = ExtResource("1")
centered = false

[node name="GroundAnchor" type="Marker2D" parent="."]
'''
    if collision:
        text += f'''
[node name="Solid" type="StaticBody2D" parent="."]
collision_layer = 1
collision_mask = 2

[node name="Footprint" type="CollisionShape2D" parent="Solid"]
position = Vector2({x + w / 2}, {y + h / 2})
shape = SubResource("Footprint")
'''
    (MODULES / f"{name}.tscn").write_text(text, encoding="utf-8", newline="\n")


def save_asset(name, image, box, source, kind, assets):
    # Padding and cropping only: final Sprite2D scale must stay (1, 1).
    cut = image.crop(box)
    padded = Image.new("RGBA", (cut.width + 4, cut.height + 4))
    padded.paste(cut, (2, 2))
    padded.save(ART / f"{name}.png")
    w, h = padded.size
    collision = None
    if kind == "building":
        collision = [-w // 2 + 8, -h + 65, w - 16, h - 70]
    elif kind == "stall":
        collision = [-int(w * .36), -92, int(w * .72), 82]
    elif kind == "prop" and name != "coins":
        depth = {"bench": 24, "planter": 35, "crate": 45, "barrel": 40,
                 "jar": 35, "lamp_post": 20, "shop_sign": 28}[name]
        footprint = min(w - 8, 32 if name == "lamp_post" else int(w * .78))
        collision = [-footprint // 2, -depth, footprint, depth]
    prefab(name, padded.size, collision)
    assets.append({"id": name, "kind": kind,
                   "texture": f"res://assets/map/disappeared_street/{name}.png",
                   "scene": f"res://src/levels/disappeared_street/modules/{name}.tscn",
                   "native_size": [w, h], "source": source,
                   "source_box": list(box), "collision_rect": collision})


def contact_sheet(assets):
    canvas = Image.new("RGB", (1536, 1024), "#323844")
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype("C:/Windows/Fonts/consola.ttf", 20)
    for i, asset in enumerate(a for a in assets if a["kind"] != "rock"):
        image = Image.open(ROOT / asset["texture"].removeprefix("res://"))
        image.thumbnail((360, 270))  # Review sheet only; source PNGs never resize.
        x, y = i % 4 * 384, i // 4 * 340
        canvas.paste(image, (x + (384 - image.width) // 2, y + 15), image)
        draw.text((x + 16, y + 294), f'{asset["id"]} {asset["native_size"]}', font=font, fill="#e8dbbc")
    target = ROOT / "docs/disappeared_street/captures"
    target.mkdir(parents=True, exist_ok=True)
    canvas.save(target / "extracted_assets.png")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw-dir", type=Path)
    args = parser.parse_args()
    (ART / "source").mkdir(parents=True, exist_ok=True)
    MODULES.mkdir(parents=True, exist_ok=True)
    assets = []
    images = {}
    for key, job in SELECTED.items():
        target = ART / "source" / f"{key}.png"
        if args.raw_dir:
            shutil.copy2(args.raw_dir / f"{job}.png", target)
        image = Image.open(target)
        if image.size != (1536, 1024):
            raise ValueError(f"Unexpected source size for {key}; regenerate, do not stretch")
        images[key] = clean(image) if key != "ground" else image.convert("RGB")
    for name in ["shop", "dwelling"]:
        image = images[name]
        save_asset(name, image, image.getbbox(), name, "building", assets)
    for i, (cut, box) in enumerate(object_masks(images["stalls"], (768, 1024), 2, 2)):
        save_asset(["green_stall", "red_stall"][i], cut,
                   (0, 0, cut.width, cut.height), "stalls", "stall", assets)
        assets[-1]["source_box"] = box
    names = ["bench", "planter", "crate", "barrel", "jar", "lamp_post", "shop_sign", "coins"]
    for name, (cut, box) in zip(names, object_masks(images["props"], (384, 512), 4, 8)):
        if name == "coins":
            continue
        save_asset(name, cut, (0, 0, cut.width, cut.height), "props", "prop", assets)
        assets[-1]["source_box"] = box
    # The runtime comparison showed the prop-sheet coins were too large.
    # Reuse the smaller coins already painted on the generated stall counter,
    # selecting their gold silhouettes at their native pixel size, not scaling.
    from PIL import ImageFilter
    coin_area = Image.open(ART / "red_stall.png").convert("RGBA").crop((214, 273, 294, 296))
    pixels = np.array(coin_area)
    gold = (pixels[:, :, 0] > 180) & (pixels[:, :, 1] > 115) & (pixels[:, :, 2] < 130)
    mask = Image.fromarray(gold.astype(np.uint8) * 255).filter(ImageFilter.MaxFilter(3))
    pixels[:, :, 3] = np.array(mask)
    pixels[pixels[:, :, 3] == 0, :3] = 0
    coins = Image.fromarray(pixels)
    save_asset("coins", coins, coins.getbbox(), "stalls/red_stall counter", "prop", assets)
    assets[-1]["derivation"] = "native counter crop [214,273,294,296], gold selection plus 1px outline; no scaling"
    # Native 384x256 rim pieces remain individually movable. No baked map sprite.
    for y in range(4):
        for x in range(4):
            box = (x * 384, y * 256, (x + 1) * 384, (y + 1) * 256)
            piece = images["cave_rim"].crop(box)
            if not piece.getbbox():
                continue
            name = f"rim_{x}_{y}"
            save_asset(name, images["cave_rim"], box, "cave_rim", "rock", assets)
            assets[-1]["map_top_left"] = [box[0] - 2, box[1] - 2]
    images["ground"].save(ART / "ground.png")
    result = {"version": 1, "model": "gpt-image-2.5-sunburst",
              "processing": "native crop, 2px padding, hard alpha and magenta cleanup; no artwork scaling",
              "concept": "res://assets/map/disappeared_street/source/concept.png", "assets": assets}
    (ART / "catalog.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    contact_sheet(assets)
    for asset in assets:
        print(asset["id"], asset["native_size"])


if __name__ == "__main__":
    main()
