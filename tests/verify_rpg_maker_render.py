"""Compare converted atlas pixels against the original MZ Tilemap drawing code.

Requires Pillow and Node.js. The original engine is read locally, never copied
into the repository. Tests every map at six animation times, including tables,
shadow quadrants and star layers. No browser or RPG Maker runtime is launched.
"""

import argparse
import json
from pathlib import Path
import subprocess

from PIL import Image, ImageChops

REFERENCE_JS = r"""
const fs = require('fs'), vm = require('vm');
const root = process.argv[1];
const text = fs.readFileSync(root + '/js/rmmz_core.js', 'utf8');
const start = text.indexOf('function Tilemap()');
const end = text.indexOf('Tilemap.Layer = function()', start);
if(start < 0 || end < 0) throw Error('MZ Tilemap source not found');
const sandbox = {PIXI:{Container:function(){}}};
vm.createContext(sandbox);
vm.runInContext(text.slice(start, end), sandbox);
const sets = JSON.parse(fs.readFileSync(root + '/data/Tilesets.json','utf8'));
const out = [];
for(const name of fs.readdirSync(root + '/data').filter(n => /^Map\d+\.json$/.test(n)).sort()) {
 const data = JSON.parse(fs.readFileSync(root + '/data/' + name,'utf8'));
 for(let frame=0;frame<6;frame++) {
  const map = Object.create(sandbox.Tilemap.prototype), lower=[],upper=[];
  Object.assign(map,{tileWidth:48,tileHeight:48,_mapWidth:data.width,_mapHeight:data.height,
   _mapData:data.data,flags:sets[data.tilesetId].flags,animationFrame:frame,
   _lowerLayer:{addRect:(...r)=>lower.push(r)},_upperLayer:{addRect:(...r)=>upper.push(r)}});
  for(let y=0;y<data.height;y++) for(let x=0;x<data.width;x++) map._addSpot(0,0,x,y);
  out.push({id:Number(name.slice(3,6)),frame,lower,upper});
 }
}
process.stdout.write(JSON.stringify(out));
"""


def read(path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def verify(source: Path, catalog_path: Path, node: str):
    catalog = read(catalog_path)
    sets = read(source / "data/Tilesets.json")
    result = subprocess.run([node, "-e", REFERENCE_JS, str(source)], text=True, encoding="utf-8", capture_output=True, check=True)
    references = json.loads(result.stdout)
    converted = {s["id"]: s for s in catalog["tilesets"]}
    maps = {m["id"]: m for m in catalog["maps"]}
    for set_id, tileset in converted.items():
        tileset["lookup"] = {t["id"]: t for t in tileset["tiles"]}
        tileset["images"] = {p["source_id"]: Image.open(p["texture"].removeprefix("res://")).convert("RGBA") for p in tileset["pages"]}
        tileset["originals"] = [Image.open(source / "img/tilesets" / f"{n}.png").convert("RGBA") if n else None for n in sets[set_id]["tilesetNames"]]
    shadow_image = Image.open(catalog_path.parent / "shadow_tiles.png").convert("RGBA")
    for ref in references:
        data = maps[ref["id"]]
        tileset = converted[data["tileset_id"]]
        dimensions = (data["width"] * 48, data["height"] * 48)
        expected = Image.new("RGBA", dimensions)
        # Reference rectangles are emitted by the actual original MZ methods.
        for sheet, sx, sy, dx, dy, w, h in ref["lower"] + ref["upper"]:
            patch = Image.new("RGBA", (w, h), (0, 0, 0, 128)) if sheet == -1 else tileset["originals"][sheet].crop((sx, sy, sx + w, sy + h))
            expected.alpha_composite(patch, (dx, dy))
        actual = Image.new("RGBA", dimensions)

        def tile_blit(cell):
            x, y, tile_id = cell
            tile = tileset["lookup"][tile_id]
            frame = ref["frame"] % tile["frames"]
            sx, sy = (tile["x"] + frame) * 48, tile["y"] * 48
            actual.alpha_composite(tileset["images"][tile["source_id"]].crop((sx, sy, sx + 48, sy + 48)), (x * 48, y * 48))

        for z, layer in enumerate(data["layers"]):
            for cell in layer:
                if not tileset["lookup"][cell[2]]["star"]:
                    tile_blit(cell)
            if z == 1:
                for x, y, mask in data["shadows"]:
                    actual.alpha_composite(shadow_image.crop((mask * 48, 0, (mask + 1) * 48, 48)), (x * 48, y * 48))
                for cell in data["table_edges"]:
                    tile_blit(cell)
        for layer in data["layers"]:
            for cell in layer:
                if tileset["lookup"][cell[2]]["star"]:
                    tile_blit(cell)
        diff = ImageChops.difference(expected, actual)
        if any(channel.getbbox() for channel in diff.split()):
            raise AssertionError(f"Map {ref['id']} frame {ref['frame']}: converted pixels differ from original MZ renderer")
        print(f"PASS map_{ref['id']:03} animation_frame={ref['frame']}")
    print(f"PASS: {len(references)} full-map pixel comparisons against original MZ drawing code")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument("--node", default="node")
    args = parser.parse_args()
    verify(args.source, args.catalog, args.node)
