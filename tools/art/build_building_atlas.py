"""从现有美术素材裁出单栋建筑，拼成带标注的图集。

只读取既有素材，不改动运行时资源，在 artifacts/building_atlas/ 下生成：
  shop_buildings.png   奶茶店：整店剖面 + 内部结构拆解
  nest_buildings.png   哥布林巢穴（洞窟聚落）15 栋建筑剖面
  crop/shop/*.png      单张裁切
  crop/nest/*.png      单张裁切
"""

from __future__ import annotations

import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "artifacts", "building_atlas")
CROP_DIR = os.path.join(OUT, "crop")

FONT_PATH = "/System/Library/Fonts/Hiragino Sans GB.ttc"
BG = (18, 15, 14)
CARD = (32, 27, 24)
PANEL = (45, 39, 35)
EDGE = (86, 72, 62)
TEXT = (238, 228, 211)
MUTED = (168, 152, 134)
ACCENT = (214, 160, 92)

SHOP_SRC = os.path.join(ROOT, "assets", "map", "milkTea", "milkTea.png")

# 奶茶店：整店剖面 + 内部结构（坐标为 milkTea.png 原始像素）
SHOP_MAIN = "assets/map/milkTea/milkTea.png　1672 × 941"
SHOP_PARTS = [
    ("原料货架与储藏区", "备料与库存集中区", (55, 25, 485, 345)),
    ("后厨煮茶操作区", "水槽、煮茶机与配料台", (395, 25, 1265, 435)),
    ("封装出货区", "封口机、杯架与侧门通道", (1150, 20, 1672, 520)),
    ("前吧台与点单台", "收银机、展示柜与取餐口", (320, 600, 1265, 815)),
    ("冷柜与果料角", "左侧冰箱、果箱与备料货架", (60, 180, 360, 680)),
]

# 哥布林巢穴：洞窟聚落 15 栋建筑剖面（素材为 1536 × 1024 透明 PNG）
NEST_PARTS = [
    ("祭坛大厅", "聚落核心仪式建筑", "09_ritual"),
    ("长老住处", "体量最大的居所", "10_elder"),
    ("军营训练", "铁笼与训练场", "03_training"),
    ("仓库", "临河储物仓", "12_warehouse"),
    ("聚餐区", "中央公共食堂", "08_dining"),
    ("酒馆", "裂牙酒馆", "06_tavern"),
    ("赌场", "黑齿赌场", "07_casino"),
    ("厨房备料", "大锅与烤架", "05_kitchen"),
    ("住宿休息", "通铺宿舍", "04_lodging"),
    ("入口前厅", "南侧入口通道", "02_vestibule"),
    ("种植区", "洞内农田与棚架", "11_growing"),
    ("河岸工坊", "水边作坊", "15_workshop"),
    ("公共火塘", "露天集会火堆", "14_hearth"),
    ("卸货庭院", "货箱与卸货场地", "13_yard"),
    ("集结区", "旗杆与撤离空地", "01_muster"),
]


def font(size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_PATH, size)


def fit(im: Image.Image, box_w: int, box_h: int) -> Image.Image:
    ratio = min(box_w / im.width, box_h / im.height)
    size = (max(1, round(im.width * ratio)), max(1, round(im.height * ratio)))
    return im.resize(size, Image.LANCZOS)


def trim_rgba(im: Image.Image) -> Image.Image:
    bbox = im.getbbox()
    return im.crop(bbox) if bbox else im


def draw_card(sheet, draw, xy, im, title, subtitle, box_w, box_h, index, rgba=False):
    x, y = xy
    pad = 12
    draw.rounded_rectangle([x, y, x + box_w, y + box_h], radius=10, fill=CARD,
                           outline=EDGE, width=2)
    inner_w, inner_h = box_w - pad * 2 - 8, box_h - 94 - 8
    draw.rounded_rectangle([x + 6, y + 6, x + box_w - 6, y + box_h - 82], radius=6,
                           fill=PANEL)
    thumb = fit(im, inner_w, inner_h)
    tx = x + (box_w - thumb.width) // 2
    ty = y + 10 + (inner_h + 4 - thumb.height) // 2
    if rgba:
        sheet.paste(thumb, (tx, ty), thumb)
    else:
        sheet.paste(thumb, (tx, ty))
    draw.text((x + pad, y + box_h - 76), title, font=font(21), fill=TEXT)
    draw.text((x + pad, y + box_h - 46), subtitle, font=font(15), fill=MUTED)
    tag = f"{index:02d}"
    tw = draw.textlength(tag, font=font(15))
    draw.rounded_rectangle([x + box_w - pad - tw - 12, y + 12,
                            x + box_w - pad + 4, y + 36],
                           radius=5, fill=(22, 18, 16), outline=EDGE)
    draw.text((x + box_w - pad - tw - 4, y + 15), tag, font=font(15), fill=ACCENT)


def save_crop(im: Image.Image, group: str, index: int, name: str, box=None) -> Image.Image:
    crop = im.crop(box) if box else im
    directory = os.path.join(CROP_DIR, group)
    os.makedirs(directory, exist_ok=True)
    crop.save(os.path.join(directory, f"{index:02d}_{name}.png"))
    return crop


def build_shop() -> None:
    im = Image.open(SHOP_SRC).convert("RGB")
    main_crop = save_crop(im, "shop", 0, "shop_overview")

    margin, gap = 28, 18
    sheet_w = 1560
    main_h = round(main_crop.height * (sheet_w - margin * 2) / main_crop.width)
    cols = 3
    card_w = (sheet_w - margin * 2 - gap * (cols - 1)) // cols
    card_h = 300
    rows = (len(SHOP_PARTS) + cols - 1) // cols
    header = 108
    sheet_h = header + main_h + 26 + rows * card_h + gap * (rows - 1) + margin

    sheet = Image.new("RGB", (sheet_w, sheet_h), BG)
    draw = ImageDraw.Draw(sheet)
    draw.text((margin, 24), "奶茶店 · 场景建筑", font=font(30), fill=TEXT)
    draw.text((margin, 66), "整店剖面与内部结构　素材：" + SHOP_MAIN,
              font=font(16), fill=MUTED)

    thumb = fit(main_crop, sheet_w - margin * 2, main_h)
    mx = (sheet_w - thumb.width) // 2
    sheet.paste(thumb, (mx, header))
    draw.rectangle([mx - 1, header - 1, mx + thumb.width, header + thumb.height],
                   outline=EDGE, width=2)

    top = header + main_h + 26
    for i, (name, desc, cbox) in enumerate(SHOP_PARTS, start=1):
        crop = save_crop(im, "shop", i, f"shop_{i}", cbox)
        r, c = divmod(i - 1, cols)
        draw_card(sheet, draw, (margin + c * (card_w + gap), top + r * (card_h + gap)),
                  crop, name, desc, card_w, card_h, i)

    sheet.save(os.path.join(OUT, "shop_buildings.png"))


def build_nest() -> None:
    margin, gap = 28, 18
    cols = 4
    sheet_w = 1600
    card_w = (sheet_w - margin * 2 - gap * (cols - 1)) // cols
    card_h = 300
    rows = (len(NEST_PARTS) + cols - 1) // cols
    header = 108
    sheet_h = header + rows * card_h + gap * (rows - 1) + margin

    sheet = Image.new("RGB", (sheet_w, sheet_h), BG)
    draw = ImageDraw.Draw(sheet)
    draw.text((margin, 24), "哥布林巢穴 · 场景建筑", font=font(30), fill=TEXT)
    draw.text((margin, 66),
              "洞窟聚落 15 栋建筑剖面　素材：assets/map/settlement/（1536 × 1024 透明 PNG）",
              font=font(16), fill=MUTED)

    for i, (name, desc, slug) in enumerate(NEST_PARTS, start=1):
        src = Image.open(os.path.join(ROOT, "assets", "map", "settlement", f"{slug}.png"))
        crop = trim_rgba(src.convert("RGBA"))
        directory = os.path.join(CROP_DIR, "nest")
        os.makedirs(directory, exist_ok=True)
        crop.save(os.path.join(directory, f"{i:02d}_{name}.png"))
        r, c = divmod(i - 1, cols)
        draw_card(sheet, draw, (margin + c * (card_w + gap), header + r * (card_h + gap)),
                  crop, name, desc, card_w, card_h, i, rgba=True)

    sheet.save(os.path.join(OUT, "nest_buildings.png"))


if __name__ == "__main__":
    build_shop()
    build_nest()
    print("done")
