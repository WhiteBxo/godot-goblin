from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "map" / "rpg_maker" / "elder_room"
C = {
    "ink": (14, 14, 19, 255), "iron": (34, 36, 45, 255), "iron_hi": (88, 91, 105, 255),
    "wood": (64, 38, 30, 255), "wood_hi": (137, 82, 45, 255), "gold": (157, 109, 38, 255),
    "gold_hi": (226, 184, 76, 255), "stone": (72, 75, 86, 255), "stone_hi": (140, 144, 157, 255),
    "stone_dark": (43, 45, 55, 255), "wine": (82, 17, 39, 255), "wine_hi": (154, 36, 57, 255),
    "blood": (128, 24, 39, 255), "blood_hi": (202, 53, 60, 255), "paper": (204, 174, 116, 255),
    "paper_hi": (239, 215, 159, 255), "olive": (74, 86, 55, 255), "olive_hi": (123, 137, 77, 255),
    "bone": (196, 190, 165, 255), "flame": (239, 176, 49, 255), "flame_hi": (255, 228, 132, 255),
    "silver": (183, 190, 204, 255), "silver_hi": (236, 240, 240, 255),
}

def new(w, h): return Image.new("RGBA", (w, h), (0, 0, 0, 0))
def box(d, xy, fill, outline=None, width=1): d.rectangle(xy, fill=C[fill], outline=C[outline] if outline else None, width=width)
def poly(d, pts, fill, outline=None, width=1):
    d.polygon(pts, fill=C[fill])
    if outline: d.line(list(pts)+[pts[0]], fill=C[outline], width=width, joint="curve")
def line(d, pts, color, width=1): d.line(pts, fill=C[color], width=width, joint="curve")
def griffin(d, x, y, s=1, color="gold"):
    poly(d, [(x,y-8*s),(x-4*s,y-5*s),(x-9*s,y-6*s),(x-6*s,y-s),(x-8*s,y+6*s),(x-2*s,y+4*s),(x,y+8*s),(x+2*s,y+4*s),(x+8*s,y+6*s),(x+6*s,y-s),(x+9*s,y-6*s),(x+4*s,y-5*s)], color, "ink")
    poly(d, [(x-2*s,y-3*s),(x,y-6*s),(x+3*s,y-2*s),(x+2*s,y+4*s),(x-2*s,y+4*s)], "blood", "ink")
    d.point((x-2*s,y-2*s), fill=C["gold_hi"]); d.point((x+2*s,y-2*s), fill=C["gold_hi"])
def fire(d, x, y):
    poly(d, [(x,y+8),(x+2,y+3),(x+4,y),(x+7,y+5),(x+6,y+10),(x+3,y+13)], "flame", "ink")
    poly(d, [(x+3,y+8),(x+4,y+3),(x+6,y+8),(x+5,y+11)], "flame_hi")

def candlestick():
    a=new(48,48); d=ImageDraw.Draw(a); box(d,(7,39,41,43),"ink"); box(d,(10,36,38,41),"iron","iron_hi"); poly(d,[(14,36),(18,31),(20,19),(28,19),(30,31),(34,36)],"gold","ink"); box(d,(21,19,27,30),"wine","ink"); box(d,(22,21,26,28),"wine_hi"); griffin(d,24,35,color="gold_hi"); fire(d,21,4); return a

def bookcase():
    a=new(96,144); d=ImageDraw.Draw(a); box(d,(6,9,89,139),"ink"); box(d,(10,12,85,136),"wood","wood_hi"); poly(d,[(7,10),(14,4),(82,4),(89,10)],"wood_hi","ink"); poly(d,[(28,11),(39,5),(57,5),(68,11),(64,18),(32,18)],"iron","gold"); griffin(d,48,14,2,"gold_hi")
    for y in (29,55,81,107):
        box(d,(12,y,83,y+5),"wood_hi","ink"); line(d,[(15,y+3),(80,y+3)],"gold"); x=16
        while x<79:
            w=4+((x+y)%4); color=("wine","olive","stone","gold","blood")[(x+y)%5]; box(d,(x,y+3,min(79,x+w),y+23),color,"ink"); d.point((x+2,y+5),fill=C["paper_hi"]); x+=w+3
    box(d,(12,133,83,139),"wood_hi","ink"); line(d,[(15,135),(80,135)],"gold_hi"); return a

def chair(d,x,y): box(d,(x,y,x+15,y+12),"ink"); box(d,(x+2,y+1,x+13,y+7),"wood","wood_hi"); box(d,(x+4,y+7,x+11,y+13),"wine","ink")
def dining():
    a=new(96,336); d=ImageDraw.Draw(a)
    for y in (28,98,168,238): chair(d,3,y); chair(d,78,y)
    box(d,(20,10,75,326),"ink"); box(d,(24,14,71,322),"wood","wood_hi"); box(d,(29,18,66,318),"wine","gold"); line(d,[(47,20),(47,316)],"wine_hi")
    for y in (30,100,170,240):
        box(d,(33,y,61,y+18),"wine","gold"); griffin(d,47,y+9,color="gold_hi")
        for x in (27,63): box(d,(x,y+25,x+6,y+33),"gold","ink"); fire(d,x+1,y+8)
        for x in (37,51): box(d,(x,y+47,x+6,y+52),"iron_hi","ink")
    box(d,(20,8,75,15),"gold","ink"); box(d,(20,321,75,327),"wood_hi","ink"); return a

def relief():
    a=new(96,96); d=ImageDraw.Draw(a); poly(d,[(48,5),(82,17),(91,47),(80,82),(48,91),(16,82),(5,47),(14,17)],"stone_dark","ink"); poly(d,[(48,12),(75,22),(83,47),(73,74),(48,83),(23,74),(13,47),(22,22)],"stone","stone_hi")
    for end in ((18,22),(30,72),(66,72),(78,22)): line(d,[(48,47),end],"gold")
    poly(d,[(48,24),(39,31),(35,42),(42,53),(48,59),(54,53),(61,42),(57,31)],"stone_hi","ink"); poly(d,[(42,31),(30,35),(21,31),(30,43),(41,42)],"stone","ink"); poly(d,[(54,31),(66,35),(75,31),(66,43),(55,42)],"stone","ink"); poly(d,[(48,34),(43,40),(48,48),(53,40)],"stone_dark","ink"); d.point((44,37),fill=C["blood_hi"]); d.point((52,37),fill=C["blood_hi"]); line(d,[(22,76),(31,79),(38,77)],"blood"); return a

def heart():
    a=new(96,96); d=ImageDraw.Draw(a); poly(d,[(48,5),(39,16),(34,12),(28,27),(16,37),(23,68),(38,78),(48,89),(58,78),(73,68),(80,37),(68,27),(62,12),(57,16)],"stone_dark","ink"); poly(d,[(48,14),(41,27),(30,24),(25,39),(31,64),(44,73),(48,82),(52,73),(65,64),(71,39),(66,24),(55,27)],"stone","gold"); poly(d,[(48,27),(39,35),(38,55),(48,69),(58,55),(57,35)],"blood","ink"); poly(d,[(48,33),(43,39),(43,55),(48,63),(53,55),(53,39)],"blood_hi");
    for q in [[(35,32),(28,42),(38,46)],[(61,32),(68,42),(58,46)],[(42,18),(48,26),(54,18)]]: poly(d,q,"bone","ink")
    line(d,[(29,55),(36,58),(40,65)],"blood_hi"); line(d,[(67,55),(60,58),(56,65)],"blood_hi"); return a

def letter():
    a=new(96,96); d=ImageDraw.Draw(a); poly(d,[(18,24),(76,15),(84,67),(29,80)],"paper","ink"); poly(d,[(18,24),(49,47),(76,15)],"paper_hi","wood_hi"); poly(d,[(29,80),(49,47),(84,67)],"paper_hi","wood_hi"); poly(d,[(18,24),(49,47),(29,80)],"paper","wood_hi"); poly(d,[(76,15),(49,47),(84,67)],"paper","wood_hi")
    for y in (57,62,67): line(d,[(36,y),(59,y-4)],"wood_hi")
    box(d,(42,39,57,55),"blood","ink"); griffin(d,49,47,color="gold_hi"); return a

def vial():
    a=new(48,48); d=ImageDraw.Draw(a); box(d,(19,5,29,10),"iron","ink"); box(d,(18,8,30,13),"gold","ink"); poly(d,[(15,12),(33,12),(37,19),(35,39),(28,44),(20,44),(13,39),(11,19)],"stone_dark","ink"); poly(d,[(16,19),(32,19),(33,37),(27,40),(21,40),(15,37)],"wine","gold"); griffin(d,24,22,color="gold_hi"); box(d,(13,44,35,46),"iron","ink"); return a

def plant():
    a=new(48,144); d=ImageDraw.Draw(a); box(d,(13,123,35,139),"stone_dark","ink"); box(d,(9,137,39,142),"stone","stone_hi"); poly(d,[(17,124),(13,119),(16,113),(32,113),(35,119),(31,124)],"stone","gold"); griffin(d,24,118,color="gold_hi"); line(d,[(24,114),(22,91),(27,72),(21,55),(25,31),(20,18)],"wood",3); line(d,[(25,94),(33,76),(29,56),(36,38)],"wood_hi",2)
    for q in [[(17,95),(7,91),(11,87)],[(28,78),(39,73),(35,68)],[(21,61),(10,56),(14,51)],[(31,45),(41,42),(37,35)]]: poly(d,q,"wine","ink")
    for x,y in ((15,80),(34,63),(18,39),(29,22)): poly(d,[(x,y),(x-4,y-8),(x+2,y-4),(x+6,y-9),(x+4,y)],"olive","ink")
    poly(d,[(24,18),(20,8),(24,12),(28,4),(29,17)],"bone","ink"); return a


def bed():
    a=new(48,96); d=ImageDraw.Draw(a); box(d,(5,5,43,91),"ink"); box(d,(9,9,39,87),"wood","wood_hi"); box(d,(12,13,36,30),"iron","gold"); griffin(d,24,21,color="gold_hi"); box(d,(13,31,35,42),"stone_dark","ink"); box(d,(14,40,34,82),"wine","ink"); poly(d,[(14,45),(24,41),(34,45),(34,57),(14,57)],"wine_hi","ink"); box(d,(16,62,32,73),"wine","gold"); box(d,(10,84,38,90),"wood_hi","ink"); return a

def portrait():
    a=new(48,96); d=ImageDraw.Draw(a); box(d,(4,4,44,92),"ink"); box(d,(7,7,41,89),"gold","gold_hi"); box(d,(10,10,38,86),"wood","ink"); poly(d,[(24,19),(15,24),(13,39),(18,47),(24,51),(30,47),(35,39),(33,24)],"olive","ink"); poly(d,[(20,25),(15,28),(10,25),(16,34)],"olive_hi","ink"); poly(d,[(28,25),(33,28),(38,25),(32,34)],"olive_hi","ink"); d.point((20,31),fill=C["blood_hi"]); d.point((28,31),fill=C["blood_hi"]); poly(d,[(22,34),(27,34),(25,42)],"olive_hi","ink"); line(d,[(20,45),(29,45)],"ink"); poly(d,[(13,52),(35,52),(38,84),(10,84)],"iron","ink"); griffin(d,24,65,color="gold"); return a

def sconce():
    a=new(48,48); d=ImageDraw.Draw(a); box(d,(18,5,30,10),"iron","gold"); poly(d,[(24,10),(16,17),(11,21),(16,25),(24,22),(32,25),(37,21),(32,17)],"iron","ink"); griffin(d,24,17,color="gold_hi"); line(d,[(18,24),(12,33),(21,34)],"gold"); line(d,[(30,24),(36,33),(27,34)],"gold"); box(d,(12,32,20,38),"wine","ink"); box(d,(28,32,36,38),"wine","ink"); fire(d,13,22); fire(d,29,22); return a

def bedside():
    a=new(48,96); d=ImageDraw.Draw(a); box(d,(7,8,41,15),"wood","wood_hi"); box(d,(5,5,43,10),"wood_hi","ink"); poly(d,[(10,15),(38,15),(36,77),(32,85),(16,85),(12,77)],"wood","ink");
    for y in (26,47): box(d,(14,y,34,y+16),"wood_hi","ink"); box(d,(21,y+6,27,y+9),"gold","ink")
    griffin(d,24,19,color="gold"); line(d,[(12,77),(10,91)],"ink",3); line(d,[(36,77),(38,91)],"ink",3); return a

def upholstered():
    a=new(48,48); d=ImageDraw.Draw(a); poly(d,[(12,6),(36,6),(39,12),(37,31),(32,37),(16,37),(11,31),(9,12)],"wood","ink"); poly(d,[(15,10),(33,10),(35,15),(33,28),(29,32),(19,32),(15,28),(13,15)],"wine","gold"); line(d,[(19,14),(29,14)],"wine_hi"); line(d,[(19,25),(29,25)],"wine_hi"); box(d,(14,29,34,38),"wine","gold"); line(d,[(16,37),(13,46)],"wood_hi",3); line(d,[(32,37),(35,46)],"wood_hi",3); griffin(d,24,39,color="gold"); return a

def reading():
    a=new(48,48); d=ImageDraw.Draw(a); poly(d,[(7,42),(13,36),(35,36),(41,42)],"wood","ink"); box(d,(10,40,38,44),"gold","ink"); poly(d,[(17,36),(17,26),(21,22),(27,22),(31,26),(31,36)],"iron","gold"); griffin(d,24,29,color="gold_hi"); box(d,(20,16,28,25),"paper_hi","ink"); fire(d,21,5); return a

def statue():
    a=new(48,96); d=ImageDraw.Draw(a); box(d,(8,80,40,92),"stone_dark","ink"); box(d,(12,73,36,82),"iron","iron_hi"); poly(d,[(24,13),(18,20),(15,31),(17,55),(21,70),(27,70),(33,55),(34,31),(30,20)],"iron","ink"); poly(d,[(20,23),(8,29),(3,42),(15,37),(21,31)],"iron_hi","ink"); poly(d,[(28,23),(40,29),(45,42),(33,37),(27,31)],"iron_hi","ink"); poly(d,[(19,31),(14,43),(20,48),(24,43),(29,48),(34,43),(29,31)],"iron_hi","ink"); d.point((20,36),fill=C["gold_hi"]); d.point((28,36),fill=C["gold_hi"]); poly(d,[(22,42),(27,42),(25,47)],"gold","ink"); poly(d,[(18,49),(24,54),(30,49),(31,66),(24,71),(17,66)],"wine","gold"); return a

def chest(w,h,large):
    a=new(w,h); d=ImageDraw.Draw(a); t=20 if large else 12; l,r,b=5,w-6,h-7; poly(d,[(l+4,t),(r-4,t),(r,t+8),(r,b-5),(r-4,b),(l+4,b),(l,b-5),(l,t+8)],"wood","ink"); poly(d,[(l+1,t+1),(r-1,t+1),(r-5,t+10),(l+5,t+10)],"wood_hi","gold"); box(d,(l+3,t+12,r-3,t+16),"iron","iron_hi"); box(d,(l+3,b-11,r-3,b-7),"iron","iron_hi"); griffin(d,w//2,(t+b)//2+3,color="gold_hi"); box(d,(w//2-4,b-3,w//2+4,b+1),"gold","ink"); return a

def painting():
    a=new(48,48); d=ImageDraw.Draw(a); box(d,(4,4,43,43),"silver","ink"); box(d,(7,7,40,40),"silver_hi","silver"); box(d,(10,10,37,37),"ink","stone_dark"); poly(d,[(10,35),(17,25),(23,30),(31,18),(37,32),(37,37),(10,37)],"stone_dark","iron_hi"); poly(d,[(23,23),(18,27),(20,32),(24,34),(28,31),(29,27),(26,24)],"iron","ink"); poly(d,[(23,25),(18,27),(13,26),(18,30),(23,29)],"iron_hi","ink"); poly(d,[(25,25),(30,27),(35,26),(30,30),(25,29)],"iron_hi","ink"); d.point((22,27),fill=C["silver_hi"]); d.point((26,27),fill=C["silver_hi"]); return a

ASSETS = [
    ("01_old_candlestick.png", candlestick), ("02_elder_bookcase.png", bookcase), ("03_elder_dining_table_8_chairs.png", dining),
    ("04_griffin_stone_head_relief.png", relief), ("05_griffin_blood_heart_relic.png", heart), ("06_sealed_wax_letter.png", letter),
    ("07_griffin_blood_vial.png", vial), ("08_twisted_plant_griffin_pedestal.png", plant), ("09_griffin_elder_bed.png", bed),
    ("10_goblin_elder_portrait.png", portrait), ("11_griffin_wall_sconce.png", sconce), ("12_elder_bedside_table.png", bedside),
    ("13_elder_upholstered_chair.png", upholstered), ("14_griffin_reading_candle.png", reading), ("15_griffin_black_iron_statue.png", statue),
    ("16_griffin_emblem_large_chest.png", lambda: chest(48,96,True)), ("17_griffin_emblem_small_chest.png", lambda: chest(48,48,False)),
    ("18_griffin_silver_frame_painting.png", painting),
]

def main():
    OUT.mkdir(parents=True, exist_ok=True); sheet=Image.new("RGBA",(576,920),C["ink"]); font=ImageFont.load_default()
    for i,(name,make) in enumerate(ASSETS):
        asset=make(); asset.save(OUT/name,"PNG",optimize=True); scale=max(1,min(124//asset.width,150//asset.height)); preview=asset.resize((asset.width*scale,asset.height*scale),Image.Resampling.NEAREST); x=(i%4)*144+(144-preview.width)//2; y=(i//4)*184+7+(150-preview.height)//2; sheet.alpha_composite(preview,(x,y)); ImageDraw.Draw(sheet).text(((i%4)*144+6,(i//4)*184+166),f"{i+1:02d} {name[3:-4]}",fill=C["paper_hi"],font=font)
    sheet.save(OUT/"elder_room_contact_sheet.png","PNG",optimize=True)

if __name__ == "__main__": main()
