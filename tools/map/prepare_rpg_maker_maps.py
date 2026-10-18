"""Explicit MZ -> Godot atlas/catalog conversion. Source images are never resized.

Requires Pillow. Run from the repository root; --output must be a new directory.
The companion Godot baker saves the catalog as editable TileMapLayer scenes.
"""

from __future__ import annotations

import argparse
from collections import deque
import json
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 48
HALF = SIZE // 2
PAGE_CELLS = 32


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def write_json(path: Path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")


class TileRenderer:
    def __init__(self, project: Path, tileset: dict, tables: dict):
        self.flags = tileset["flags"]
        self.tables = tables
        self.images = []
        for name in tileset["tilesetNames"]:
            self.images.append(Image.open(project / "img" / "tilesets" / f"{name}.png").convert("RGBA") if name else None)

    def flag(self, tile_id):
        return self.flags[tile_id] if tile_id < len(self.flags) else 0

    def is_table(self, tile_id):
        return 2816 <= tile_id < 4352 and bool(self.flag(tile_id) & 0x80)

    @staticmethod
    def frame_count(tile_id):
        if not 2048 <= tile_id < 2816:
            return 1
        kind = (tile_id - 2048) // 48
        if kind in (2, 3):
            return 1
        return 3 if kind >= 4 and kind % 2 else 4

    def render(self, tile_id: int, frame=0, edge=False):
        result = Image.new("RGBA", (SIZE, SIZE))

        def blit(sheet, sx, sy, dx, dy, width, height):
            image = self.images[sheet]
            if image is None or sx < 0 or sy < 0 or sx + width > image.width or sy + height > image.height:
                raise ValueError(f"Tile {tile_id}: unavailable source rectangle on sheet {sheet}: {(sx, sy, width, height)}")
            result.alpha_composite(image.crop((sx, sy, sx + width, sy + height)), (dx, dy))

        if tile_id < 2048:
            sheet = 4 if tile_id >= 1536 else 5 + tile_id // 256
            sx = ((tile_id // 128 % 2) * 8 + tile_id % 8) * SIZE
            sy = (tile_id % 256 // 8 % 16) * SIZE
            blit(sheet, sx, sy, 0, 0, SIZE, SIZE)
            return result
        kind, shape = divmod(tile_id - 2048, 48)
        tx, ty = kind % 8, kind // 8
        table = self.tables["floor"]
        if tile_id < 2816:
            sheet = 0
            water = [0, 1, 2, 1][frame % 4]
            if kind < 4:
                bx = water * 2 if kind < 2 else 6
                by = 3 if kind % 2 else 0
            else:
                bx = tx // 4 * 8
                by = ty * 6 + (tx // 2 % 2) * 3
                if kind % 2:
                    bx += 6
                    by += frame % 3
                    table = self.tables["waterfall"]
                else:
                    bx += water * 2
        elif tile_id < 4352:
            sheet, bx, by = 1, tx * 2, (ty - 2) * 3
        elif tile_id < 5888:
            sheet, bx, by = 2, tx * 2, (ty - 6) * 2
            table = self.tables["wall"]
        else:
            sheet, bx = 3, tx * 2
            by = int((ty - 10) * 2.5 + (0.5 if ty % 2 else 0))
            if ty % 2:
                table = self.tables["wall"]
        if shape >= len(table):
            raise ValueError(f"Invalid autotile shape {shape} for tile {tile_id}")
        quadrants = table[shape]
        if edge:
            for i in range(2):
                qx, qy = quadrants[2 + i]
                blit(sheet, (bx * 2 + qx) * HALF, (by * 2 + qy) * HALF + HALF // 2, i * HALF, 0, HALF, HALF // 2)
            return result
        for i, (qx, qy) in enumerate(quadrants):
            dx, dy = i % 2 * HALF, i // 2 * HALF
            sx, sy = (bx * 2 + qx) * HALF, (by * 2 + qy) * HALF
            if self.is_table(tile_id) and qy in (1, 5):
                qx2 = (4 - qx) % 4 if qy == 1 else qx
                blit(sheet, (bx * 2 + qx2) * HALF, (by * 2 + 3) * HALF, dx, dy, HALF, HALF)
                blit(sheet, sx, sy, dx, dy + HALF // 2, HALF, HALF // 2)
            else:
                blit(sheet, sx, sy, dx, dy, HALF, HALF)
        return result


def passage(renderer, stack):
    result = 0
    for bit in (1, 2, 4, 8):
        blocked = True
        for tile in reversed(stack):
            flag = renderer.flag(tile)
            if flag & 16:
                continue
            blocked = bool(flag & bit)
            break
        if blocked:
            result |= bit
    return result


def choose_spawn(width, height, masks):
    # The source has startMapId=0. Pick a deterministic point in the largest
    # connected walkable area, nearest the lower centre; never invent a story anchor.
    remaining = {i for i, mask in enumerate(masks) if mask != 15}
    components = []
    directions = ((0, 1, 1, 8), (-1, 0, 2, 4), (1, 0, 4, 2), (0, -1, 8, 1))
    while remaining:
        first = min(remaining)
        remaining.remove(first)
        queue, cells = deque([first]), [first]
        while queue:
            i = queue.popleft()
            x, y = i % width, i // width
            for dx, dy, bit, reverse in directions:
                nx, ny = x + dx, y + dy
                j = ny * width + nx
                if 0 <= nx < width and 0 <= ny < height and j in remaining and not masks[i] & bit and not masks[j] & reverse:
                    remaining.remove(j)
                    queue.append(j)
                    cells.append(j)
        components.append(cells)
    if not components:
        raise ValueError("Map has no walkable cells")
    cells = max(components, key=len)
    point = min(cells, key=lambda i: ((i % width - (width - 1) / 2) ** 2 + (i // width - (height - 2)) ** 2, i))
    return [point % width, point // width]


def convert(project: Path, output: Path, tables: dict):
    tilesets = read_json(project / "data/Tilesets.json")
    infos = read_json(project / "data/MapInfos.json")
    system = read_json(project / "data/System.json")
    if system.get("tileSize", SIZE) != SIZE:
        raise ValueError("This importer requires the source's native 48px tile size")
    maps = [(int(path.stem[3:]), read_json(path)) for path in sorted((project / "data").glob("Map[0-9]*.json"))]
    for map_id, data in maps:
        if data.get("scrollType", 0) or data.get("parallaxName") or any(data.get("events", [])):
            raise ValueError(f"Map {map_id}: looping, parallax or events need explicit migration support")
        if len(data["data"]) != data["width"] * data["height"] * 6:
            raise ValueError(f"Map {map_id}: invalid six-layer data")
    catalog = {"tile_size": SIZE, "tilesets": [], "maps": []}
    renderers = {}
    for set_id in sorted({data["tilesetId"] for _, data in maps}):
        renderer = TileRenderer(project, tilesets[set_id], tables)
        renderers[set_id] = renderer
        used = {tile for _, data in maps if data["tilesetId"] == set_id for tile in data["data"][:data["width"] * data["height"] * 4] if tile}
        entry = {"id": set_id, "pages": [], "tiles": []}
        pages = [Image.new("RGBA", (PAGE_CELLS * SIZE, PAGE_CELLS * SIZE))]
        x = y = 0

        def add(tile, frames, edge=False):
            nonlocal x, y
            if x + len(frames) > PAGE_CELLS:
                x, y = 0, y + 1
            if y >= PAGE_CELLS:
                pages.append(Image.new("RGBA", (PAGE_CELLS * SIZE, PAGE_CELLS * SIZE)))
                x = y = 0
            flag = renderer.flag(tile)
            entry["tiles"].append({"id": tile + (10000 if edge else 0), "source_id": len(pages) - 1, "x": x, "y": y, "frames": len(frames), "passage": flag & 15, "star": bool(flag & 16), "terrain": flag >> 12, "edge": edge})
            for index, frame in enumerate(frames):
                pages[-1].alpha_composite(frame, ((x + index) * SIZE, y * SIZE))
            x += len(frames)

        # Include the complete valid palette of each referenced tileset, including
        # unused tiles, so artists can paint additions immediately in Godot.
        candidates = list(range(1, 1024)) + list(range(1536, 1664)) + list(range(2048, 8192))
        for tile in candidates:
            try:
                frames = [renderer.render(tile, i) for i in range(renderer.frame_count(tile))]
            except ValueError:
                if tile in used:
                    raise
                continue
            add(tile, frames)
            if renderer.is_table(tile):
                add(tile, [renderer.render(tile, edge=True)], edge=True)
        available = {tile["id"] for tile in entry["tiles"]}
        if used - available:
            raise ValueError(f"Tileset {set_id}: missing tiles {used - available}")
        for page_id, page in enumerate(pages):
            name = f"tileset_{set_id:03}_{page_id:02}.png"
            page.save(output / name)
            entry["pages"].append({"source_id": page_id, "texture": f"res://{output.as_posix()}/{name}"})
        catalog["tilesets"].append(entry)
    shadows = Image.new("RGBA", (16 * SIZE, SIZE))
    draw = ImageDraw.Draw(shadows)
    for bits in range(1, 16):
        for q in range(4):
            if bits & 1 << q:
                x, y = bits * SIZE + q % 2 * HALF, q // 2 * HALF
                draw.rectangle((x, y, x + HALF - 1, y + HALF - 1), fill=(0, 0, 0, 128))
    shadows.save(output / "shadow_tiles.png")
    for map_id, data in maps:
        w, h = data["width"], data["height"]
        area = w * h
        renderer = renderers[data["tilesetId"]]
        entry = {"id": map_id, "name": infos[map_id]["name"], "width": w, "height": h, "tileset_id": data["tilesetId"], "layers": [], "shadows": [], "table_edges": [], "regions": []}
        masks = [passage(renderer, [data["data"][z * area + i] for z in range(4)]) for i in range(area)]
        entry["spawn"] = choose_spawn(w, h, masks)
        if system.get("startMapId") == map_id:
            sx, sy = system["startX"], system["startY"]
            if not (0 <= sx < w and 0 <= sy < h) or masks[sy * w + sx] == 15:
                raise ValueError(f"Map {map_id}: source start position is blocked")
            entry["spawn"] = [sx, sy]
        for z in range(4):
            entry["layers"].append([[i % w, i // w, tile] for i, tile in enumerate(data["data"][z * area:(z + 1) * area]) if tile])
        for i in range(area):
            x, y = i % w, i // w
            shadow, region = data["data"][4 * area + i], data["data"][5 * area + i]
            if shadow:
                entry["shadows"].append([x, y, shadow & 15])
            if region:
                entry["regions"].append([x, y, region])
            above = data["data"][area + i - w] if y else 0
            tile0, tile1 = data["data"][i], data["data"][area + i]
            if renderer.is_table(above) and not renderer.is_table(tile1) and not 4352 <= tile0 < 8192:
                entry["table_edges"].append([x, y, above + 10000])
        catalog["maps"].append(entry)
    write_json(output / "catalog.json", catalog)
    return catalog


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Archived project1 directory")
    parser.add_argument("--tables", type=Path, required=True, help="Archived MZ autotile lookup tables")
    parser.add_argument("--output", type=Path, required=True, help="New repository-relative output directory")
    args = parser.parse_args()
    if args.output.is_absolute() or ".." in args.output.parts:
        parser.error("--output must be a repository-relative path without parent traversal")
    if args.output.exists():
        parser.error("Output exists: use a new directory and review its results before replacing editor resources")
    args.output.mkdir(parents=True)
    raw_tables = read_json(args.tables)["tables"]
    tables = {name: raw_tables[f"{name.upper()}_AUTOTILE_TABLE"] for name in ("floor", "wall", "waterfall")}
    catalog = convert(args.source, args.output, tables)
    print(json.dumps({"maps": len(catalog["maps"]), "tilesets": len(catalog["tilesets"]), "palette_tiles": sum(len(t["tiles"]) for t in catalog["tilesets"]), "output": str(args.output)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
