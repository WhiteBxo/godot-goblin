from pathlib import Path
import random
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).parent
C = {
    "ink": (20, 17, 24, 255), "deep": (31, 24, 31, 255), "wood": (91, 51, 38, 255),
    "wood_dark": (58, 35, 31, 255), "wood_hi": (151, 91, 54, 255), "wood_light": (190, 126, 70, 255),
    "gold": (190, 142, 51, 255), "gold_hi": (242, 204, 105, 255), "bronze": (116, 76, 47, 255),
    "iron": (42, 42, 51, 255), "iron_hi": (94, 94, 110, 255), "stone": (77, 79, 88, 255),
    "stone_hi": (145, 148, 160, 255), "stone_shadow": (45, 46, 56, 255), "red": (117, 26, 39, 255),
    "red_hi": (214, 65, 69, 255), "red_dark": (66, 20, 32, 255), "wine": (79, 19, 42, 255),
    "blue": (45, 72, 104, 255), "blue_hi": (97, 146, 181, 255), "cream": (222, 194, 139, 255),
    "paper": (214, 186, 128, 255), "leaf": (45, 88, 67, 255), "leaf_hi": (99, 151, 91, 255),
    "flame": (255, 207, 90, 255), "flame_hi": (255, 245, 168, 255),
}

def canvas(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))

def save(im, name):
    im.save(OUT / name, "PNG", optimize=True)

def rect(d, box, fill, outline=None, width=1):
    d.rectangle(box, fill=fill, outline=outline, width=int(max(1, width)))

def line(d, points, fill, width=1):
    d.line(points, fill=fill, width=int(max(1, width)), joint="curve")

def poly(d, points, fill, outline=None, width=1):
    d.polygon(points, fill=fill)
    if outline:
        line(d, points + [points[0]], outline, width)

def pixel(d, x, y, fill):
    rect(d, (x, y, x, y), fill)

def color_shift(color, amount):
    return tuple(max(0, min(255, channel + amount)) for channel in color[:3]) + (color[3],)

def pixel_texture(im, seed, density=0.14):
    """Add deterministic clustered material pixels while preserving outlines and symbols."""
    rng = random.Random(seed)
    px = im.load()
    w, h = im.size
    clusters = max(10, int(w * h * density / 6))
    for _ in range(clusters):
        x = rng.randrange(w)
        y = rng.randrange(h)
        base = px[x, y]
        if base[3] == 0:
            continue
        if max(base[:3]) < 48 or sum(base[:3]) < 100:
            continue
        size = 1 if rng.random() < 0.78 else 2
        delta = rng.choice((-22, -16, -11, 10, 16, 23))
        shade = color_shift(base, delta)
        for oy in range(size):
            for ox in range(size):
                tx, ty = x + ox, y + oy
                if tx < w and ty < h and px[tx, ty][3] > 0 and max(px[tx, ty][:3]) >= 48:
                    px[tx, ty] = shade
    return im

def material_glints(im, seed):
    """Place sparse one-to-three pixel glints on solid pixels for a hand-pixeled finish."""
    rng = random.Random(seed + 991)
    px = im.load()
    w, h = im.size
    for _ in range(max(5, (w * h) // 180)):
        x = rng.randrange(w)
        y = rng.randrange(h)
        base = px[x, y]
        if base[3] == 0 or sum(base[:3]) < 150:
            continue
        if rng.random() < 0.6:
            px[x, y] = color_shift(base, rng.choice((24, 32, 40)))
        if rng.random() < 0.35 and x + 1 < w and px[x + 1, y][3] > 0:
            px[x + 1, y] = color_shift(base, 18)
    return im

def render_asset(fn, seed):
    return material_glints(pixel_texture(fn(), seed), seed)

def flame(d, x, y):
    poly(d, [(x, y + 8), (x + 2, y + 2), (x + 4, y), (x + 7, y + 5), (x + 6, y + 10), (x + 3, y + 13)], C["flame"], C["ink"])
    poly(d, [(x + 3, y + 8), (x + 4, y + 3), (x + 6, y + 8), (x + 5, y + 11)], C["flame_hi"])

def griffin_emblem(d, cx, cy, color=None):
    color = color or C["gold"]
    poly(d, [(cx, cy - 8), (cx - 3, cy - 4), (cx - 8, cy - 5), (cx - 5, cy), (cx - 7, cy + 7), (cx, cy + 4), (cx + 7, cy + 7), (cx + 5, cy), (cx + 8, cy - 5), (cx + 3, cy - 4)], color, C["ink"])
    poly(d, [(cx - 2, cy - 2), (cx, cy - 6), (cx + 2, cy - 2), (cx + 1, cy + 4), (cx - 1, cy + 4)], C["red"], C["ink"])
    pixel(d, cx - 1, cy - 3, C["gold_hi"]); pixel(d, cx + 1, cy - 3, C["gold_hi"])

def draw_candlestick():
    im = canvas(48, 48); d = ImageDraw.Draw(im)
    rect(d, (7, 39, 40, 43), C["ink"]); rect(d, (9, 37, 38, 41), C["bronze"], C["ink"]); rect(d, (13, 34, 34, 38), C["gold"], C["ink"])
    rect(d, (15, 35, 32, 36), C["gold_hi"]); pixel(d, 11, 40, C["bronze"]); pixel(d, 35, 40, C["wood_dark"])
    poly(d, [(17, 34), (19, 27), (20, 19), (28, 19), (29, 27), (31, 34)], C["bronze"], C["ink"])
    rect(d, (21, 20, 27, 29), C["gold"], C["ink"]); rect(d, (22, 22, 26, 29), C["gold_hi"]); line(d, [(20, 26), (21, 31)], C["red_dark"], 2); line(d, [(28, 25), (28, 31)], C["red"])
    poly(d, [(17, 19), (19, 15), (21, 17), (24, 14), (27, 17), (29, 15), (31, 19)], C["gold"], C["ink"])
    rect(d, (20, 16, 28, 19), C["wood_dark"], C["ink"]); flame(d, 21, 3); pixel(d, 18, 10, (190, 100, 57, 190)); pixel(d, 30, 11, (190, 100, 57, 190))
    line(d, [(14, 36), (33, 36)], C["gold_hi"]); pixel(d, 18, 32, C["bronze"]); pixel(d, 29, 31, C["gold_hi"])
    return im

def draw_bookcase():
    im = canvas(96, 144); d = ImageDraw.Draw(im)
    rect(d, (7, 7, 88, 139), C["ink"]); rect(d, (10, 10, 85, 136), C["wood_dark"], C["wood_hi"]); poly(d, [(5, 10), (11, 4), (85, 4), (91, 10)], C["wood"], C["ink"])
    rect(d, (14, 13, 81, 23), C["wood"], C["gold"]); griffin_emblem(d, 48, 18)
    line(d, [(17, 14), (31, 14)], C["wood_light"]); line(d, [(64, 22), (78, 22)], C["wood_dark"])
    for y in (28, 54, 80, 106): rect(d, (13, y, 82, y + 4), C["wood"], C["ink"]); rect(d, (16, y + 3, 79, y + 5), C["wood_hi"])
    colors = [C["red"], C["blue"], C["gold"], C["leaf"], C["wine"], C["cream"]]
    for row, (y0, y1) in enumerate(((31, 51), (57, 77), (83, 103), (109, 130))):
        x = 17
        while x < 77:
            width = [5, 6, 4, 7][(x + row) % 4]; col = colors[(x + row * 2) % len(colors)]
            rect(d, (x, y0, min(x + width, 77), y1), col, C["ink"]); line(d, [(x + 2, y0 + 2), (min(x + width - 1, 77), y0 + 2)], C["gold_hi"]); pixel(d, x, y1 - 2, C["wood_dark"]); x += width + 3
    rect(d, (14, 133, 81, 138), C["wood"], C["ink"]); rect(d, (18, 135, 77, 136), C["gold"]); line(d, [(11, 14), (11, 132)], C["wood_light"], 2); line(d, [(85, 14), (85, 132)], C["wood_light"])
    for y in (29, 55, 81, 107): pixel(d, 12, y + 2, C["gold_hi"]); pixel(d, 84, y + 2, C["gold_hi"])
    return im

def chair(d, x, y, color=None):
    color = color or C["wood"]; rect(d, (x - 8, y, x + 8, y + 22), C["ink"]); rect(d, (x - 6, y + 2, x + 6, y + 14), color, C["wood_hi"])
    rect(d, (x - 5, y + 5, x + 5, y + 12), C["red_dark"], C["gold"]); rect(d, (x - 9, y + 15, x + 9, y + 19), color, C["ink"])
    line(d, [(x - 7, y + 19), (x - 8, y + 28)], C["ink"], 2); line(d, [(x + 7, y + 19), (x + 8, y + 28)], C["ink"], 2); line(d, [(x - 7, y + 2), (x - 10, y + 7)], C["wood_hi"], 2)

def draw_dining_table():
    im = canvas(96, 336); d = ImageDraw.Draw(im); rect(d, (40, 13, 56, 322), (30, 22, 25, 150))
    poly(d, [(22, 15), (74, 15), (83, 26), (73, 297), (23, 297), (13, 26)], C["wood_dark"], C["ink"]); poly(d, [(25, 18), (71, 18), (77, 29), (69, 287), (27, 287), (19, 29)], C["wood"], C["wood_hi"])
    poly(d, [(29, 21), (67, 21), (72, 29), (68, 275), (28, 275), (24, 29)], C["wood_dark"])
    poly(d, [(32, 24), (64, 24), (68, 30), (64, 270), (32, 270), (28, 30)], C["wood"], C["wood_hi"])
    rect(d, (35, 25, 61, 268), C["deep"]); rect(d, (38, 27, 58, 267), C["wood_dark"])
    line(d, [(42, 31), (42, 264)], C["wood_hi"]); line(d, [(55, 33), (54, 260)], C["wood_light"])
    for y in (42, 102, 162, 222): rect(d, (27, y, 69, y + 8), C["wood_dark"], C["ink"]); rect(d, (30, y + 2, 66, y + 4), C["wood_hi"])
    for y in (34, 94, 154, 214): chair(d, 10, y, C["wood"]); chair(d, 86, y, C["wood_dark"])
    for y in (36, 96, 156, 216):
        line(d, [(5, y + 6), (15, y + 11)], C["wood_hi"]); line(d, [(81, y + 11), (91, y + 6)], C["wood_light"])
    poly(d, [(30, 285), (66, 285), (72, 300), (64, 310), (32, 310), (24, 300)], C["wood_dark"], C["ink"]); rect(d, (30, 289, 66, 295), C["wood"], C["gold"]); rect(d, (38, 290, 58, 293), C["red_dark"], C["ink"])
    for y in (28, 88, 148, 208):
        rect(d, (40, y, 44, y + 6), C["gold"], C["ink"]); rect(d, (41, y + 1, 43, y + 4), C["gold_hi"]); flame(d, 40, y - 7)
        rect(d, (52, y + 1, 56, y + 5), C["cream"], C["ink"]); pixel(d, 53, y + 2, C["gold_hi"])
    line(d, [(31, 26), (32, 280)], C["wood_light"]); line(d, [(65, 26), (64, 280)], C["wood_dark"])
    for x, y in ((29, 54), (66, 74), (31, 126), (65, 188), (30, 248), (67, 260)):
        line(d, [(x, y), (x + 2, y + 5)], C["wood_light"])
    return im

def draw_stone_relief():
    im = canvas(96, 96); d = ImageDraw.Draw(im)
    # Thick shield slab: the relief must read as a protruding stone object, not a flat emblem.
    poly(d, [(10, 28), (18, 15), (38, 6), (58, 6), (79, 15), (87, 29), (83, 70), (66, 88), (30, 88), (13, 70)], C["stone_shadow"], C["ink"])
    poly(d, [(16, 29), (24, 19), (40, 12), (56, 12), (72, 19), (80, 30), (75, 66), (62, 80), (34, 80), (21, 66)], C["stone"], C["stone_hi"])
    poly(d, [(19, 30), (14, 35), (17, 54), (27, 47), (33, 32)], C["stone_hi"], C["ink"])
    poly(d, [(77, 30), (82, 35), (79, 54), (69, 47), (63, 32)], C["stone_hi"], C["ink"])
    # Brow, cheek and beak planes use separate stepped silhouettes for depth.
    poly(d, [(27, 31), (36, 19), (47, 25), (59, 19), (69, 31), (64, 48), (48, 59), (32, 48)], C["stone_shadow"], C["ink"])
    poly(d, [(32, 32), (40, 24), (47, 31), (53, 31), (60, 24), (65, 32), (59, 45), (48, 51), (37, 45)], C["stone_hi"], C["ink"])
    poly(d, [(37, 34), (42, 29), (47, 35), (52, 35), (58, 29), (61, 34), (56, 43), (48, 47), (40, 43)], C["stone"], C["stone_hi"])
    rect(d, (39, 35, 43, 39), C["ink"]); rect(d, (53, 35, 57, 39), C["ink"])
    pixel(d, 40, 35, C["stone_hi"]); pixel(d, 54, 35, C["stone_hi"])
    poly(d, [(42, 42), (48, 45), (54, 42), (51, 51), (48, 55), (45, 51)], C["stone_shadow"], C["ink"])
    poly(d, [(38, 52), (48, 59), (58, 52), (65, 67), (48, 79), (31, 67)], C["stone_shadow"], C["ink"])
    poly(d, [(42, 57), (48, 63), (54, 57), (58, 67), (48, 73), (38, 67)], C["stone"], C["stone_hi"])
    line(d, [(48, 61), (48, 72)], C["stone_hi"])
    # Chipped edges, cracks and ritual stains survive at native 96px scale.
    line(d, [(22, 58), (28, 62), (25, 70)], C["stone_shadow"])
    line(d, [(73, 56), (67, 61), (70, 69)], C["stone_shadow"])
    line(d, [(29, 20), (26, 25), (29, 28)], C["stone_shadow"])
    line(d, [(67, 20), (70, 25), (67, 29)], C["stone_shadow"])
    for x, y in ((24, 53), (72, 53), (30, 72), (66, 72), (18, 43), (78, 43)):
        pixel(d, x, y, C["red_dark"])
    return im

def draw_heart_relic():
    im = canvas(96, 96); d = ImageDraw.Draw(im)
    # A stone shell with a real heart-shaped opening and a suspended blood core.
    poly(d, [(48, 10), (38, 14), (28, 12), (20, 23), (24, 39), (18, 53), (29, 67), (36, 82), (48, 77), (60, 82), (67, 67), (78, 53), (72, 39), (76, 23), (68, 12), (58, 14)], C["stone_shadow"], C["ink"])
    poly(d, [(48, 17), (39, 20), (31, 18), (26, 28), (30, 42), (25, 53), (34, 63), (40, 74), (48, 69), (56, 74), (62, 63), (71, 53), (66, 42), (70, 28), (65, 18), (57, 20)], C["stone"], C["stone_hi"])
    # Wing-like stone plates fold inward around the core.
    poly(d, [(30, 26), (20, 35), (24, 49), (37, 43), (44, 29), (39, 22)], C["stone_hi"], C["ink"])
    poly(d, [(66, 26), (76, 35), (72, 49), (59, 43), (52, 29), (57, 22)], C["stone_hi"], C["ink"])
    poly(d, [(48, 27), (40, 22), (34, 28), (36, 41), (48, 58), (60, 41), (62, 28), (56, 22)], C["red_dark"], C["ink"])
    poly(d, [(48, 30), (42, 26), (38, 31), (40, 41), (48, 53), (56, 41), (58, 31), (54, 26)], C["red"], C["red_hi"])
    poly(d, [(48, 34), (43, 30), (41, 35), (43, 42), (48, 48), (53, 42), (55, 35), (53, 30)], C["red_hi"])
    line(d, [(48, 29), (48, 60)], C["red_dark"], 2)
    line(d, [(47, 40), (39, 35), (34, 29)], C["red_hi"])
    line(d, [(49, 44), (57, 37), (63, 29)], C["red_hi"])
    # Crown-like bone prongs and claw base make the relic feel assembled, not like a gem.
    poly(d, [(42, 18), (39, 8), (45, 12), (48, 4), (51, 12), (57, 8), (54, 20)], C["stone_hi"], C["ink"])
    poly(d, [(31, 68), (39, 72), (44, 78), (48, 72), (52, 78), (57, 72), (65, 68), (60, 86), (48, 90), (36, 86)], C["stone_shadow"], C["ink"])
    line(d, [(48, 75), (48, 87)], C["stone_hi"])
    line(d, [(38, 76), (34, 83)], C["stone_hi"]); line(d, [(58, 76), (62, 83)], C["stone_hi"])
    for x, y in ((24, 23), (72, 24), (22, 57), (74, 56), (31, 66), (65, 66)):
        pixel(d, x, y, C["red_dark"])
    return im

def draw_letter():
    im = canvas(96, 96); d = ImageDraw.Draw(im)
    poly(d, [(17, 20), (78, 14), (83, 69), (23, 79)], C["paper"], C["ink"]); poly(d, [(18, 20), (50, 49), (78, 14)], C["cream"], C["wood"]); poly(d, [(23, 79), (50, 49), (83, 69)], (190, 151, 101, 255), C["wood"])
    line(d, [(20, 22), (25, 73)], C["gold_hi"]); line(d, [(77, 18), (80, 64)], C["paper"]); line(d, [(25, 76), (46, 51)], C["wood_light"])
    line(d, [(28, 30), (70, 24)], C["wood_light"]); line(d, [(30, 36), (64, 31)], C["wood_light"]); line(d, [(30, 43), (58, 38)], C["wood_light"])
    rect(d, (41, 42, 59, 59), C["red_dark"], C["ink"]); rect(d, (43, 44, 57, 57), C["red"], C["gold"]); griffin_emblem(d, 50, 51, C["gold_hi"]); pixel(d, 43, 58, C["gold"]); pixel(d, 57, 58, C["gold"]); line(d, [(45, 46), (55, 46)], C["red_hi"]); pixel(d, 54, 55, C["red_hi"])
    return im

def draw_vial():
    im = canvas(48, 48); d = ImageDraw.Draw(im)
    rect(d, (17, 5, 31, 10), C["wood_dark"], C["ink"]); rect(d, (19, 9, 29, 14), C["gold"], C["ink"]); rect(d, (21, 10, 27, 12), C["gold_hi"])
    poly(d, [(15, 13), (33, 13), (36, 19), (34, 39), (29, 43), (19, 43), (14, 39), (12, 19)], C["blue"], C["ink"])
    poly(d, [(16, 15), (31, 15), (33, 20), (31, 38), (27, 40), (20, 40), (16, 37), (14, 20)], (75, 112, 138, 255), C["blue_hi"])
    poly(d, [(15, 24), (33, 24), (34, 38), (29, 41), (19, 41), (14, 38)], C["red"], C["red_hi"]); rect(d, (17, 20, 31, 24), C["red_hi"], C["ink"])
    line(d, [(18, 16), (15, 35)], C["blue_hi"], 2); pixel(d, 30, 18, C["cream"]); pixel(d, 19, 27, C["red_hi"]); pixel(d, 28, 34, C["red_dark"]); griffin_emblem(d, 24, 31, C["gold_hi"])
    return im

def draw_plant():
    im = canvas(48, 144); d = ImageDraw.Draw(im)
    rect(d, (8, 126, 40, 137), C["stone_shadow"], C["ink"]); rect(d, (12, 119, 36, 130), C["stone"], C["stone_hi"]); rect(d, (14, 121, 34, 124), C["stone_hi"]); poly(d, [(16, 119), (20, 112), (28, 112), (32, 119)], C["iron"], C["ink"]); griffin_emblem(d, 24, 116, C["gold"])
    line(d, [(24, 113), (22, 98), (26, 85), (21, 71), (25, 55), (21, 41)], C["wood_dark"], 3); line(d, [(24, 112), (22, 98), (27, 85), (23, 70), (28, 56), (24, 41)], C["wood_hi"])
    line(d, [(26, 106), (22, 101)], C["wood_light"]); line(d, [(24, 78), (28, 72)], C["wood_dark"]); pixel(d, 24, 92, C["red_dark"]); pixel(d, 25, 63, C["wood_light"])
    for a, b in [((23, 93), (12, 84)), ((25, 82), (37, 72)), ((24, 67), (13, 57)), ((26, 56), (38, 47)), ((22, 44), (13, 32))]: line(d, [a, b], C["wood_dark"], 2)
    leaves = [((9, 79), (17, 85), C["leaf"]), ((34, 66), (41, 73), C["leaf_hi"]), ((9, 53), (17, 59), C["leaf_hi"]), ((35, 42), (42, 49), C["leaf"]), ((9, 27), (16, 35), C["wine"]), ((32, 23), (40, 31), C["red"])]
    for (x0, y0), (x1, y1), col in leaves:
        poly(d, [(x0, y0), (x1, y0 + 2), (x1 - 2, y1), (x0 - 2, y1 - 2)], col, C["ink"])
        line(d, [(x0 + 1, y0 + 2), (x1 - 3, y1 - 2)], color_shift(col, 28))
    for x, y in ((16, 20), (31, 35), (14, 70), (34, 84)): rect(d, (x - 2, y - 2, x + 2, y + 2), C["red_hi"], C["ink"])
    return im

def draw_bed():
    im = canvas(48, 96); d = ImageDraw.Draw(im)
    rect(d, (5, 5, 42, 89), C["wood_dark"], C["ink"]); rect(d, (8, 8, 39, 86), C["wood"], C["wood_hi"]); rect(d, (10, 12, 37, 31), C["red_dark"], C["gold"])
    line(d, [(11, 10), (16, 10)], C["wood_light"]); line(d, [(33, 11), (37, 11)], C["gold_hi"]); pixel(d, 9, 20, C["wood_dark"]); pixel(d, 38, 24, C["wood_light"])
    poly(d, [(11, 29), (37, 29), (36, 73), (11, 73)], C["red"], C["ink"]); poly(d, [(12, 43), (35, 38), (37, 70), (12, 70)], C["wine"], C["red_hi"])
    rect(d, (12, 27, 36, 39), C["cream"], C["ink"]); poly(d, [(12, 28), (22, 25), (36, 28), (36, 38), (12, 38)], C["paper"], C["wood"]); line(d, [(14, 31), (33, 29)], C["cream"]); line(d, [(13, 46), (34, 42)], C["red_hi"]); line(d, [(13, 61), (32, 57)], C["red_dark"]); griffin_emblem(d, 25, 56, C["gold_hi"])
    rect(d, (5, 73, 42, 80), C["wood"], C["ink"]); rect(d, (8, 80, 39, 88), C["wood_dark"], C["ink"]); line(d, [(10, 84), (37, 84)], C["gold"]); line(d, [(12, 87), (34, 87)], C["wood_hi"]); pixel(d, 9, 91, C["gold"]); pixel(d, 38, 91, C["gold"])
    return im

def draw_portrait():
    im = canvas(48, 96); d = ImageDraw.Draw(im)
    rect(d, (4, 4, 43, 91), C["wood_dark"], C["ink"]); rect(d, (6, 6, 41, 89), C["wood"], C["gold"]); rect(d, (10, 10, 37, 86), C["deep"], C["wood_hi"])
    line(d, [(8, 12), (8, 82)], C["wood_light"]); line(d, [(39, 12), (39, 84)], C["wood_dark"]); pixel(d, 13, 13, C["gold_hi"]); pixel(d, 34, 84, C["bronze"])
    poly(d, [(16, 34), (17, 23), (24, 17), (32, 23), (33, 36), (29, 47), (20, 47)], C["red_dark"], C["ink"]); poly(d, [(18, 29), (21, 21), (27, 21), (31, 28), (29, 39), (24, 44), (19, 38)], (110, 82, 66, 255), C["ink"])
    poly(d, [(17, 27), (20, 18), (26, 15), (33, 24), (29, 28), (27, 24), (21, 27)], C["stone_shadow"], C["ink"]); pixel(d, 21, 19, C["stone_hi"]); pixel(d, 28, 22, C["stone_hi"]); rect(d, (20, 30, 22, 32), C["gold_hi"]); rect(d, (27, 30, 29, 32), C["gold_hi"]); line(d, [(21, 38), (25, 40), (29, 37)], C["ink"]); pixel(d, 18, 35, C["stone_hi"]); pixel(d, 29, 35, C["stone_shadow"])
    poly(d, [(13, 49), (24, 42), (36, 49), (39, 78), (9, 78)], C["wine"], C["ink"]); poly(d, [(21, 48), (24, 55), (27, 48), (32, 78), (16, 78)], C["red"], C["gold"]); line(d, [(15, 53), (13, 73)], C["red_hi"]); line(d, [(34, 53), (36, 74)], C["red_dark"]); griffin_emblem(d, 24, 60, C["gold_hi"]); rect(d, (11, 80, 36, 85), C["wood"], C["gold"])
    return im

def draw_sconce():
    im = canvas(48, 48); d = ImageDraw.Draw(im)
    rect(d, (17, 5, 31, 39), C["iron"], C["ink"]); rect(d, (20, 8, 28, 35), C["iron_hi"]); line(d, [(21, 10), (21, 33)], C["stone_hi"])
    poly(d, [(24, 7), (18, 14), (20, 21), (15, 29), (21, 26), (24, 34), (27, 26), (33, 29), (28, 21), (30, 14)], C["gold"], C["ink"])
    line(d, [(19, 17), (23, 12)], C["gold_hi"]); line(d, [(29, 17), (25, 12)], C["bronze"])
    rect(d, (21, 18, 27, 29), C["red_dark"], C["ink"]); rect(d, (22, 19, 26, 24), C["red"], C["red_hi"]); griffin_emblem(d, 24, 20, C["gold_hi"]); flame(d, 18, 5); flame(d, 26, 5); rect(d, (12, 37, 36, 41), C["iron_hi"], C["ink"]); line(d, [(15, 38), (33, 38)], C["stone_hi"])
    return im

def draw_bedside_table():
    im = canvas(48, 96); d = ImageDraw.Draw(im)
    rect(d, (8, 28, 40, 80), C["wood_dark"], C["ink"]); rect(d, (10, 31, 38, 76), C["wood"], C["wood_hi"]); line(d, [(13, 33), (13, 72)], C["wood_light"]); line(d, [(35, 33), (35, 71)], C["wood_dark"])
    rect(d, (12, 36, 36, 48), C["red_dark"], C["gold"]); rect(d, (14, 38, 34, 45), C["red"], C["red_hi"]); rect(d, (12, 50, 36, 64), C["wood_dark"], C["gold"])
    rect(d, (21, 40, 27, 43), C["gold_hi"], C["ink"]); rect(d, (21, 55, 27, 58), C["gold_hi"], C["ink"]); rect(d, (7, 72, 41, 78), C["wood"], C["ink"]); line(d, [(13, 77), (11, 88)], C["ink"], 2); line(d, [(35, 77), (37, 88)], C["ink"], 2)
    rect(d, (13, 18, 35, 29), C["wood"], C["ink"]); line(d, [(15, 20), (32, 20)], C["wood_light"]); rect(d, (17, 12, 31, 22), C["cream"], C["gold"]); rect(d, (19, 14, 29, 20), C["paper"]); flame(d, 21, 1)
    return im

def draw_chair():
    im = canvas(48, 48); d = ImageDraw.Draw(im)
    rect(d, (10, 4, 38, 40), C["wood_dark"], C["ink"]); rect(d, (13, 7, 35, 30), C["red"], C["gold"]); line(d, [(15, 9), (32, 9)], C["red_hi"]); poly(d, [(16, 12), (32, 12), (33, 27), (15, 27)], C["wine"], C["red_hi"]); line(d, [(17, 15), (17, 24)], C["red_dark"]); line(d, [(30, 15), (31, 24)], C["red_hi"]); griffin_emblem(d, 24, 19, C["gold_hi"])
    rect(d, (9, 29, 39, 36), C["wood"], C["ink"]); rect(d, (14, 32, 34, 36), C["red_dark"], C["gold"]); line(d, [(16, 33), (32, 33)], C["red_hi"]); line(d, [(13, 36), (11, 45)], C["ink"], 2); line(d, [(35, 36), (37, 45)], C["ink"], 2)
    return im

def draw_reading_candle():
    im = canvas(48, 48); d = ImageDraw.Draw(im)
    rect(d, (9, 38, 39, 42), C["ink"]); rect(d, (13, 35, 35, 39), C["iron"], C["gold"]); line(d, [(16, 36), (32, 36)], C["iron_hi"]); rect(d, (19, 23, 29, 36), C["cream"], C["ink"]); rect(d, (20, 29, 28, 36), C["paper"], C["gold"]); line(d, [(21, 25), (27, 25)], C["flame_hi"]); griffin_emblem(d, 24, 34, C["red"]); flame(d, 21, 9); pixel(d, 17, 17, (242, 160, 65, 200)); pixel(d, 31, 17, (242, 160, 65, 200)); poly(d, [(7, 44), (16, 40), (33, 40), (41, 44)], C["wood_dark"], C["ink"]); line(d, [(11, 43), (37, 43)], C["wood_hi"])
    return im

def draw_statue():
    im = canvas(48, 96); d = ImageDraw.Draw(im)
    rect(d, (9, 80, 39, 91), C["stone_shadow"], C["ink"]); rect(d, (13, 74, 35, 82), C["iron"], C["iron_hi"])
    poly(d, [(24, 16), (17, 23), (14, 39), (17, 58), (22, 70), (30, 70), (35, 58), (34, 39), (31, 23)], C["iron"], C["ink"]); poly(d, [(20, 20), (7, 28), (3, 42), (14, 37), (19, 31)], C["iron_hi"], C["ink"]); poly(d, [(28, 20), (41, 28), (45, 42), (34, 37), (29, 31)], C["iron_hi"], C["ink"])
    poly(d, [(18, 31), (14, 42), (19, 46), (24, 42), (29, 46), (34, 42), (30, 31)], C["iron_hi"], C["ink"]); rect(d, (19, 34, 22, 37), C["gold_hi"]); rect(d, (26, 34, 29, 37), C["gold_hi"]); poly(d, [(22, 41), (27, 41), (25, 47)], C["gold"], C["ink"])
    poly(d, [(18, 49), (24, 54), (29, 49), (31, 66), (24, 72), (17, 66)], C["red_dark"], C["gold"]); poly(d, [(21, 53), (24, 56), (27, 53), (28, 65), (24, 68), (20, 65)], C["red"], C["red_hi"]); line(d, [(24, 54), (24, 68)], C["gold_hi"]); line(d, [(18, 54), (11, 64)], C["iron_hi"]); line(d, [(30, 54), (37, 64)], C["iron_hi"]); pixel(d, 16, 39, C["stone_hi"]); pixel(d, 32, 45, C["iron_hi"])
    return im

def draw_chest(w, h, large=True):
    im = canvas(w, h); d = ImageDraw.Draw(im); x0, x1 = 5, w - 6; y0, y1 = (22 if large else 14), h - 8
    poly(d, [(x0 + 4, y0), (x1 - 4, y0), (x1, y0 + 8), (x1, y1 - 6), (x1 - 4, y1), (x0 + 4, y1), (x0, y1 - 6), (x0, y0 + 8)], C["wood_dark"], C["ink"])
    rect(d, (x0 + 3, y0 + 8, x1 - 3, y1 - 4), C["wood"], C["wood_hi"]); poly(d, [(x0 + 1, y0 + 1), (x1 - 1, y0 + 1), (x1 - 5, y0 + 9), (x0 + 5, y0 + 9)], C["wood"], C["gold"])
    rect(d, (x0 + 3, y0 + 12, x1 - 3, y0 + 15), C["iron"], C["iron_hi"]); rect(d, (x0 + 3, y1 - 11, x1 - 3, y1 - 7), C["iron"], C["iron_hi"]); rect(d, (w // 2 - 4, y0 + 10, w // 2 + 4, y0 + 18), C["gold"], C["ink"]); griffin_emblem(d, w // 2, (y0 + y1) // 2 + 3, C["gold_hi"]); rect(d, (w // 2 - 3, y1 - 3, w // 2 + 3, y1 + 1), C["gold"], C["ink"])
    line(d, [(x0 + 5, y0 + 19), (x0 + 5, y1 - 14)], C["wood_light"]); line(d, [(x1 - 5, y0 + 19), (x1 - 5, y1 - 14)], C["wood_dark"])
    for x, y in ((x0 + 10, y0 + 25), (x1 - 11, y0 + 34), (x0 + 11, y1 - 20), (x1 - 10, y1 - 28)):
        pixel(d, x, y, C["wood_light"]); pixel(d, x + 1, y, C["wood_hi"])
    return im

def draw_painting():
    im = canvas(48, 48); d = ImageDraw.Draw(im)
    rect(d, (4, 4, 43, 43), C["iron"], C["ink"]); rect(d, (7, 7, 40, 40), C["iron_hi"], C["gold_hi"]); rect(d, (9, 9, 38, 38), C["gold"], C["ink"]); rect(d, (10, 10, 37, 37), C["blue"], C["ink"]); line(d, [(11, 11), (20, 11)], C["blue_hi"]); line(d, [(38, 12), (38, 34)], C["iron_hi"])
    poly(d, [(10, 33), (18, 23), (24, 29), (31, 17), (37, 33)], C["stone_shadow"], C["ink"]); poly(d, [(10, 37), (10, 31), (18, 24), (23, 29), (31, 18), (37, 29), (37, 37)], C["stone"], C["ink"]); rect(d, (29, 12, 33, 16), C["gold_hi"])
    poly(d, [(23, 24), (19, 27), (20, 31), (24, 34), (28, 31), (29, 27), (26, 24)], C["iron"], C["ink"]); poly(d, [(23, 25), (18, 27), (14, 26), (18, 30), (23, 29)], C["iron_hi"], C["ink"]); poly(d, [(25, 25), (30, 27), (34, 26), (30, 30), (25, 29)], C["iron_hi"], C["ink"]); pixel(d, 22, 27, C["gold_hi"]); pixel(d, 26, 27, C["gold_hi"]); pixel(d, 16, 32, C["stone_hi"]); pixel(d, 31, 34, C["stone_shadow"])
    return im

ASSETS = [
    ("01_old_candlestick.png", draw_candlestick), ("02_elder_bookcase.png", draw_bookcase), ("03_elder_dining_table_8_chairs.png", draw_dining_table),
    ("04_griffin_stone_head_relief.png", draw_stone_relief), ("05_griffin_blood_heart_relic.png", draw_heart_relic), ("06_sealed_wax_letter.png", draw_letter),
    ("07_griffin_blood_vial.png", draw_vial), ("08_twisted_plant_griffin_pedestal.png", draw_plant), ("09_griffin_elder_bed.png", draw_bed),
    ("10_goblin_elder_portrait.png", draw_portrait), ("11_griffin_wall_sconce.png", draw_sconce), ("12_elder_bedside_table.png", draw_bedside_table),
    ("13_elder_upholstered_chair.png", draw_chair), ("14_griffin_reading_candle.png", draw_reading_candle), ("15_griffin_black_iron_statue.png", draw_statue),
    ("16_griffin_emblem_large_chest.png", lambda: draw_chest(48, 96, True)), ("17_griffin_emblem_small_chest.png", lambda: draw_chest(48, 48, False)),
    ("18_griffin_silver_frame_painting.png", draw_painting),
]

def contact_sheet():
    thumb_w, thumb_h = 144, 184; sheet = Image.new("RGBA", (thumb_w * 4, thumb_h * 5), (24, 23, 29, 255)); font = ImageFont.load_default()
    for idx, (name, fn) in enumerate(ASSETS):
        im = render_asset(fn, idx + 1); scale = max(1, min((thumb_w - 20) // im.width, (thumb_h - 28) // im.height)); preview = im.resize((im.width * scale, im.height * scale), Image.Resampling.NEAREST)
        x = (idx % 4) * thumb_w + (thumb_w - preview.width) // 2; y = (idx // 4) * thumb_h + 8 + (thumb_h - 28 - preview.height) // 2; sheet.alpha_composite(preview, (x, y)); d = ImageDraw.Draw(sheet)
        d.text(((idx % 4) * thumb_w + 6, (idx // 4) * thumb_h + thumb_h - 18), f"{idx + 1:02d} {name[3:-4]}", fill=C["cream"], font=font)
    sheet.save(OUT / "elder_room_contact_sheet.png", "PNG", optimize=True)

if __name__ == "__main__":
    for idx, (name, fn) in enumerate(ASSETS): save(render_asset(fn, idx + 1), name)
    contact_sheet()
