from pathlib import Path
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
    poly(d, [(17, 34), (19, 27), (20, 19), (28, 19), (29, 27), (31, 34)], C["bronze"], C["ink"])
    rect(d, (21, 20, 27, 29), C["gold"], C["ink"]); rect(d, (22, 22, 26, 29), C["gold_hi"])
    poly(d, [(17, 19), (19, 15), (21, 17), (24, 14), (27, 17), (29, 15), (31, 19)], C["gold"], C["ink"])
    rect(d, (20, 16, 28, 19), C["wood_dark"], C["ink"]); flame(d, 21, 3); pixel(d, 18, 10, (190, 100, 57, 190)); pixel(d, 30, 11, (190, 100, 57, 190))
    line(d, [(14, 36), (33, 36)], C["gold_hi"])
    return im

def draw_bookcase():
    im = canvas(96, 144); d = ImageDraw.Draw(im)
    rect(d, (7, 7, 88, 139), C["ink"]); rect(d, (10, 10, 85, 136), C["wood_dark"], C["wood_hi"]); poly(d, [(5, 10), (11, 4), (85, 4), (91, 10)], C["wood"], C["ink"])
    rect(d, (14, 13, 81, 23), C["wood"], C["gold"]); griffin_emblem(d, 48, 18)
    for y in (28, 54, 80, 106): rect(d, (13, y, 82, y + 4), C["wood"], C["ink"]); rect(d, (16, y + 3, 79, y + 5), C["wood_hi"])
    colors = [C["red"], C["blue"], C["gold"], C["leaf"], C["wine"], C["cream"]]
    for row, (y0, y1) in enumerate(((31, 51), (57, 77), (83, 103), (109, 130))):
        x = 17
        while x < 77:
            width = [5, 6, 4, 7][(x + row) % 4]; col = colors[(x + row * 2) % len(colors)]
            rect(d, (x, y0, min(x + width, 77), y1), col, C["ink"]); line(d, [(x + 2, y0 + 2), (min(x + width - 1, 77), y0 + 2)], C["gold_hi"]); x += width + 3
    rect(d, (14, 133, 81, 138), C["wood"], C["ink"]); rect(d, (18, 135, 77, 136), C["gold"]); line(d, [(11, 14), (11, 132)], C["wood_light"]); line(d, [(85, 14), (85, 132)], C["wood_light"])
    for y in (29, 55, 81, 107): pixel(d, 12, y + 2, C["gold_hi"]); pixel(d, 84, y + 2, C["gold_hi"])
    return im

def chair(d, x, y, color=None):
    color = color or C["wood"]; rect(d, (x - 8, y, x + 8, y + 22), C["ink"]); rect(d, (x - 6, y + 2, x + 6, y + 14), color, C["wood_hi"])
    rect(d, (x - 5, y + 5, x + 5, y + 12), C["red_dark"], C["gold"]); rect(d, (x - 9, y + 15, x + 9, y + 19), color, C["ink"])
    line(d, [(x - 7, y + 19), (x - 8, y + 28)], C["ink"], 2); line(d, [(x + 7, y + 19), (x + 8, y + 28)], C["ink"], 2); line(d, [(x - 7, y + 2), (x - 10, y + 7)], C["wood_hi"], 2)

def draw_dining_table():
    im = canvas(96, 336); d = ImageDraw.Draw(im); rect(d, (40, 13, 56, 322), (30, 22, 25, 150))
    poly(d, [(22, 15), (74, 15), (83, 26), (73, 297), (23, 297), (13, 26)], C["wood_dark"], C["ink"]); poly(d, [(25, 18), (71, 18), (77, 29), (69, 287), (27, 287), (19, 29)], C["wood"], C["wood_hi"])
    for y in (42, 102, 162, 222): rect(d, (27, y, 69, y + 8), C["wood_dark"], C["ink"]); rect(d, (30, y + 2, 66, y + 4), C["wood_hi"])
    for y in (34, 94, 154, 214): chair(d, 10, y); chair(d, 86, y)
    poly(d, [(30, 285), (66, 285), (72, 300), (64, 310), (32, 310), (24, 300)], C["wood_dark"], C["ink"]); rect(d, (30, 289, 66, 295), C["wood"], C["gold"]); rect(d, (38, 290, 58, 293), C["red_dark"], C["ink"])
    for y in (28, 88, 148, 208): rect(d, (40, y, 44, y + 6), C["gold"], C["ink"]); flame(d, 40, y - 7); rect(d, (52, y + 1, 56, y + 5), C["cream"], C["ink"])
    line(d, [(31, 26), (32, 280)], C["wood_light"]); line(d, [(65, 26), (64, 280)], C["wood_dark"])
    return im

def draw_stone_relief():
    im = canvas(96, 96); d = ImageDraw.Draw(im)
    poly(d, [(9, 30), (18, 15), (39, 7), (57, 7), (78, 15), (87, 30), (82, 71), (65, 87), (31, 87), (14, 71)], C["stone_shadow"], C["ink"])
    poly(d, [(16, 31), (24, 19), (40, 12), (56, 12), (72, 19), (80, 31), (75, 66), (62, 80), (34, 80), (21, 66)], C["stone"], C["stone_hi"])
    poly(d, [(22, 29), (14, 34), (19, 50), (29, 42), (35, 32)], C["stone_hi"], C["ink"]); poly(d, [(74, 29), (82, 34), (77, 50), (67, 42), (61, 32)], C["stone_hi"], C["ink"])
    poly(d, [(29, 31), (38, 20), (48, 26), (58, 20), (67, 31), (61, 48), (48, 57), (35, 48)], C["stone_shadow"], C["ink"])
    poly(d, [(34, 33), (42, 27), (47, 34), (53, 34), (58, 27), (63, 33), (57, 46), (48, 51), (39, 46)], C["stone_hi"], C["ink"])
    rect(d, (39, 35, 43, 39), C["ink"]); rect(d, (53, 35, 57, 39), C["ink"]); poly(d, [(44, 42), (52, 42), (48, 48)], C["stone_shadow"], C["ink"])
    poly(d, [(40, 52), (48, 59), (56, 52), (62, 65), (48, 76), (34, 65)], C["stone_shadow"], C["ink"]); line(d, [(48, 58), (48, 70)], C["stone_hi"])
    for x, y in ((25, 56), (71, 56), (31, 70), (65, 70), (18, 42), (78, 42)): pixel(d, x, y, C["gold"])
    return im

def draw_heart_relic():
    im = canvas(96, 96); d = ImageDraw.Draw(im)
    for box, fill in [((31, 12, 64, 15), (123, 55, 73, 140)), ((25, 18, 70, 75), (100, 28, 55, 80)), ((20, 29, 75, 68), (120, 38, 63, 45))]: rect(d, box, fill)
    poly(d, [(48, 18), (37, 12), (25, 18), (22, 33), (29, 50), (48, 76), (67, 50), (74, 33), (71, 18), (59, 12)], C["iron"], C["ink"])
    poly(d, [(48, 25), (39, 18), (30, 23), (29, 35), (35, 47), (48, 66), (61, 47), (67, 35), (66, 23), (57, 18)], C["red"], C["red_hi"])
    poly(d, [(48, 27), (42, 22), (37, 26), (39, 36), (48, 45), (57, 35), (59, 25), (54, 22)], C["red_hi"])
    line(d, [(48, 27), (48, 62)], C["red_dark"], 2); line(d, [(48, 38), (39, 34), (34, 28)], C["gold"]); line(d, [(48, 44), (58, 37), (64, 27)], C["gold"])
    rect(d, (45, 5, 51, 20), C["gold"], C["ink"]); rect(d, (42, 7, 54, 11), C["gold_hi"], C["ink"])
    for x, y in ((18, 22), (78, 28), (20, 61), (75, 58), (31, 79), (66, 79)): pixel(d, x, y, C["red_hi"])
    rect(d, (26, 78, 70, 85), C["stone_shadow"], C["ink"]); rect(d, (32, 73, 64, 80), C["stone"], C["stone_hi"])
    return im

def draw_letter():
    im = canvas(96, 96); d = ImageDraw.Draw(im)
    poly(d, [(17, 20), (78, 14), (83, 69), (23, 79)], C["paper"], C["ink"]); poly(d, [(18, 20), (50, 49), (78, 14)], C["cream"], C["wood"]); poly(d, [(23, 79), (50, 49), (83, 69)], (190, 151, 101, 255), C["wood"])
    line(d, [(28, 30), (70, 24)], C["wood_light"]); line(d, [(30, 36), (64, 31)], C["wood_light"]); line(d, [(30, 43), (58, 38)], C["wood_light"])
    rect(d, (41, 42, 59, 59), C["red_dark"], C["ink"]); rect(d, (43, 44, 57, 57), C["red"], C["gold"]); griffin_emblem(d, 50, 51, C["gold_hi"]); pixel(d, 43, 58, C["gold"]); pixel(d, 57, 58, C["gold"])
    return im

def draw_vial():
    im = canvas(48, 48); d = ImageDraw.Draw(im)
    rect(d, (17, 5, 31, 10), C["wood_dark"], C["ink"]); rect(d, (19, 9, 29, 14), C["gold"], C["ink"])
    poly(d, [(15, 13), (33, 13), (36, 19), (34, 39), (29, 43), (19, 43), (14, 39), (12, 19)], C["blue"], C["ink"])
    poly(d, [(15, 24), (33, 24), (34, 38), (29, 41), (19, 41), (14, 38)], C["red"], C["red_hi"]); rect(d, (17, 20, 31, 24), C["red_hi"], C["ink"])
    line(d, [(18, 16), (15, 35)], C["blue_hi"]); griffin_emblem(d, 24, 31, C["gold_hi"])
    return im

def draw_plant():
    im = canvas(48, 144); d = ImageDraw.Draw(im)
    rect(d, (8, 126, 40, 137), C["stone_shadow"], C["ink"]); rect(d, (12, 119, 36, 130), C["stone"], C["stone_hi"]); poly(d, [(16, 119), (20, 112), (28, 112), (32, 119)], C["iron"], C["ink"]); griffin_emblem(d, 24, 116, C["gold"])
    line(d, [(24, 113), (22, 98), (26, 85), (21, 71), (25, 55), (21, 41)], C["wood_dark"], 3); line(d, [(24, 112), (22, 98), (27, 85), (23, 70), (28, 56), (24, 41)], C["wood_hi"])
    for a, b in [((23, 93), (12, 84)), ((25, 82), (37, 72)), ((24, 67), (13, 57)), ((26, 56), (38, 47)), ((22, 44), (13, 32))]: line(d, [a, b], C["wood_dark"], 2)
    leaves = [((9, 79), (17, 85), C["leaf"]), ((34, 66), (41, 73), C["leaf_hi"]), ((9, 53), (17, 59), C["leaf_hi"]), ((35, 42), (42, 49), C["leaf"]), ((9, 27), (16, 35), C["wine"]), ((32, 23), (40, 31), C["red"])]
    for (x0, y0), (x1, y1), col in leaves: poly(d, [(x0, y0), (x1, y0 + 2), (x1 - 2, y1), (x0 - 2, y1 - 2)], col, C["ink"])
    for x, y in ((16, 20), (31, 35), (14, 70), (34, 84)): rect(d, (x - 2, y - 2, x + 2, y + 2), C["red_hi"], C["ink"])
    return im

def draw_bed():
    im = canvas(48, 96); d = ImageDraw.Draw(im)
    rect(d, (5, 5, 42, 89), C["wood_dark"], C["ink"]); rect(d, (8, 8, 39, 86), C["wood"], C["wood_hi"]); rect(d, (10, 12, 37, 31), C["red_dark"], C["gold"])
    poly(d, [(11, 29), (37, 29), (36, 73), (11, 73)], C["red"], C["ink"]); poly(d, [(12, 43), (35, 38), (37, 70), (12, 70)], C["wine"], C["red_hi"])
    rect(d, (12, 27, 36, 39), C["cream"], C["ink"]); poly(d, [(12, 28), (22, 25), (36, 28), (36, 38), (12, 38)], C["paper"], C["wood"]); griffin_emblem(d, 25, 56, C["gold_hi"])
    rect(d, (5, 73, 42, 80), C["wood"], C["ink"]); rect(d, (8, 80, 39, 88), C["wood_dark"], C["ink"]); line(d, [(10, 84), (37, 84)], C["gold"]); pixel(d, 9, 91, C["gold"]); pixel(d, 38, 91, C["gold"])
    return im

def draw_portrait():
    im = canvas(48, 96); d = ImageDraw.Draw(im)
    rect(d, (4, 4, 43, 91), C["wood_dark"], C["ink"]); rect(d, (6, 6, 41, 89), C["wood"], C["gold"]); rect(d, (10, 10, 37, 86), C["deep"], C["wood_hi"])
    poly(d, [(16, 34), (17, 23), (24, 17), (32, 23), (33, 36), (29, 47), (20, 47)], C["red_dark"], C["ink"]); poly(d, [(18, 29), (21, 21), (27, 21), (31, 28), (29, 39), (24, 44), (19, 38)], (110, 82, 66, 255), C["ink"])
    poly(d, [(17, 27), (20, 18), (26, 15), (33, 24), (29, 28), (27, 24), (21, 27)], C["stone_shadow"], C["ink"]); rect(d, (20, 30, 22, 32), C["gold_hi"]); rect(d, (27, 30, 29, 32), C["gold_hi"]); line(d, [(21, 38), (25, 40), (29, 37)], C["ink"])
    poly(d, [(13, 49), (24, 42), (36, 49), (39, 78), (9, 78)], C["wine"], C["ink"]); poly(d, [(21, 48), (24, 55), (27, 48), (32, 78), (16, 78)], C["red"], C["gold"]); griffin_emblem(d, 24, 60, C["gold_hi"]); rect(d, (11, 80, 36, 85), C["wood"], C["gold"])
    return im

def draw_sconce():
    im = canvas(48, 48); d = ImageDraw.Draw(im)
    rect(d, (17, 5, 31, 39), C["iron"], C["ink"]); poly(d, [(24, 7), (18, 14), (20, 21), (15, 29), (21, 26), (24, 34), (27, 26), (33, 29), (28, 21), (30, 14)], C["gold"], C["ink"])
    rect(d, (21, 18, 27, 29), C["red_dark"], C["ink"]); griffin_emblem(d, 24, 20, C["gold_hi"]); flame(d, 18, 5); flame(d, 26, 5); rect(d, (12, 37, 36, 41), C["iron_hi"], C["ink"])
    return im

def draw_bedside_table():
    im = canvas(48, 96); d = ImageDraw.Draw(im)
    rect(d, (8, 28, 40, 80), C["wood_dark"], C["ink"]); rect(d, (10, 31, 38, 76), C["wood"], C["wood_hi"]); rect(d, (12, 36, 36, 48), C["red_dark"], C["gold"]); rect(d, (12, 50, 36, 64), C["wood_dark"], C["gold"])
    rect(d, (21, 40, 27, 43), C["gold_hi"], C["ink"]); rect(d, (21, 55, 27, 58), C["gold_hi"], C["ink"]); rect(d, (7, 72, 41, 78), C["wood"], C["ink"]); line(d, [(13, 77), (11, 88)], C["ink"], 2); line(d, [(35, 77), (37, 88)], C["ink"], 2)
    rect(d, (13, 18, 35, 29), C["wood"], C["ink"]); rect(d, (17, 12, 31, 22), C["cream"], C["gold"]); flame(d, 21, 1)
    return im

def draw_chair():
    im = canvas(48, 48); d = ImageDraw.Draw(im)
    rect(d, (10, 4, 38, 40), C["wood_dark"], C["ink"]); rect(d, (13, 7, 35, 30), C["red"], C["gold"]); poly(d, [(16, 12), (32, 12), (33, 27), (15, 27)], C["wine"], C["red_hi"]); griffin_emblem(d, 24, 19, C["gold_hi"])
    rect(d, (9, 29, 39, 36), C["wood"], C["ink"]); rect(d, (14, 32, 34, 36), C["red_dark"], C["gold"]); line(d, [(13, 36), (11, 45)], C["ink"], 2); line(d, [(35, 36), (37, 45)], C["ink"], 2)
    return im

def draw_reading_candle():
    im = canvas(48, 48); d = ImageDraw.Draw(im)
    rect(d, (9, 38, 39, 42), C["ink"]); rect(d, (13, 35, 35, 39), C["iron"], C["gold"]); rect(d, (19, 23, 29, 36), C["cream"], C["ink"]); rect(d, (20, 29, 28, 36), C["paper"], C["gold"]); griffin_emblem(d, 24, 34, C["red"]); flame(d, 21, 9); pixel(d, 17, 17, (242, 160, 65, 200)); pixel(d, 31, 17, (242, 160, 65, 200)); poly(d, [(7, 44), (16, 40), (33, 40), (41, 44)], C["wood_dark"], C["ink"]); line(d, [(11, 43), (37, 43)], C["wood_hi"])
    return im

def draw_statue():
    im = canvas(48, 96); d = ImageDraw.Draw(im)
    rect(d, (9, 80, 39, 91), C["stone_shadow"], C["ink"]); rect(d, (13, 74, 35, 82), C["iron"], C["iron_hi"])
    poly(d, [(24, 16), (17, 23), (14, 39), (17, 58), (22, 70), (30, 70), (35, 58), (34, 39), (31, 23)], C["iron"], C["ink"]); poly(d, [(20, 20), (7, 28), (3, 42), (14, 37), (19, 31)], C["iron_hi"], C["ink"]); poly(d, [(28, 20), (41, 28), (45, 42), (34, 37), (29, 31)], C["iron_hi"], C["ink"])
    poly(d, [(18, 31), (14, 42), (19, 46), (24, 42), (29, 46), (34, 42), (30, 31)], C["iron_hi"], C["ink"]); rect(d, (19, 34, 22, 37), C["gold_hi"]); rect(d, (26, 34, 29, 37), C["gold_hi"]); poly(d, [(22, 41), (27, 41), (25, 47)], C["gold"], C["ink"])
    poly(d, [(18, 49), (24, 54), (29, 49), (31, 66), (24, 72), (17, 66)], C["red_dark"], C["gold"]); line(d, [(24, 54), (24, 68)], C["gold_hi"]); line(d, [(18, 54), (11, 64)], C["iron_hi"]); line(d, [(30, 54), (37, 64)], C["iron_hi"])
    return im

def draw_chest(w, h, large=True):
    im = canvas(w, h); d = ImageDraw.Draw(im); x0, x1 = 5, w - 6; y0, y1 = (22 if large else 14), h - 8
    poly(d, [(x0 + 4, y0), (x1 - 4, y0), (x1, y0 + 8), (x1, y1 - 6), (x1 - 4, y1), (x0 + 4, y1), (x0, y1 - 6), (x0, y0 + 8)], C["wood_dark"], C["ink"])
    rect(d, (x0 + 3, y0 + 8, x1 - 3, y1 - 4), C["wood"], C["wood_hi"]); poly(d, [(x0 + 1, y0 + 1), (x1 - 1, y0 + 1), (x1 - 5, y0 + 9), (x0 + 5, y0 + 9)], C["wood"], C["gold"])
    rect(d, (x0 + 3, y0 + 12, x1 - 3, y0 + 15), C["iron"], C["iron_hi"]); rect(d, (x0 + 3, y1 - 11, x1 - 3, y1 - 7), C["iron"], C["iron_hi"]); rect(d, (w // 2 - 4, y0 + 10, w // 2 + 4, y0 + 18), C["gold"], C["ink"]); griffin_emblem(d, w // 2, (y0 + y1) // 2 + 3, C["gold_hi"]); rect(d, (w // 2 - 3, y1 - 3, w // 2 + 3, y1 + 1), C["gold"], C["ink"])
    line(d, [(x0 + 5, y0 + 19), (x0 + 5, y1 - 14)], C["wood_light"]); line(d, [(x1 - 5, y0 + 19), (x1 - 5, y1 - 14)], C["wood_dark"])
    return im

def draw_painting():
    im = canvas(48, 48); d = ImageDraw.Draw(im)
    rect(d, (4, 4, 43, 43), C["iron"], C["ink"]); rect(d, (7, 7, 40, 40), C["iron_hi"], C["gold_hi"]); rect(d, (10, 10, 37, 37), C["blue"], C["ink"])
    poly(d, [(10, 33), (18, 23), (24, 29), (31, 17), (37, 33)], C["stone_shadow"], C["ink"]); poly(d, [(10, 37), (10, 31), (18, 24), (23, 29), (31, 18), (37, 29), (37, 37)], C["stone"], C["ink"]); rect(d, (29, 12, 33, 16), C["gold_hi"])
    poly(d, [(23, 24), (19, 27), (20, 31), (24, 34), (28, 31), (29, 27), (26, 24)], C["iron"], C["ink"]); poly(d, [(23, 25), (18, 27), (14, 26), (18, 30), (23, 29)], C["iron_hi"], C["ink"]); poly(d, [(25, 25), (30, 27), (34, 26), (30, 30), (25, 29)], C["iron_hi"], C["ink"]); pixel(d, 22, 27, C["gold_hi"]); pixel(d, 26, 27, C["gold_hi"])
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
        im = fn(); scale = max(1, min((thumb_w - 20) // im.width, (thumb_h - 28) // im.height)); preview = im.resize((im.width * scale, im.height * scale), Image.Resampling.NEAREST)
        x = (idx % 4) * thumb_w + (thumb_w - preview.width) // 2; y = (idx // 4) * thumb_h + 8 + (thumb_h - 28 - preview.height) // 2; sheet.alpha_composite(preview, (x, y)); d = ImageDraw.Draw(sheet)
        d.text(((idx % 4) * thumb_w + 6, (idx // 4) * thumb_h + thumb_h - 18), f"{idx + 1:02d} {name[3:-4]}", fill=C["cream"], font=font)
    sheet.save(OUT / "elder_room_contact_sheet.png", "PNG", optimize=True)

if __name__ == "__main__":
    for name, fn in ASSETS: save(fn(), name)
    contact_sheet()
