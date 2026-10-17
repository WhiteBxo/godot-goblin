"""Reconstruct the approved composition using native, coordinate-preserving layers.

Tutorial sources: HD-2D extraction + 2D layered scenes. No image is resampled.
The generated plate supplies hidden floor; visible reference pixels stay exact.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw, ImageChops, ImageFilter, ImageFont

ROOT=Path(__file__).resolve().parents[2]
ART=ROOT/'assets/map/night_infiltration'
MOD=ROOT/'src/levels/night_infiltration/modules'
MOD.mkdir(parents=True,exist_ok=True)
source=Image.open(ART/'source/concept.png').convert('RGBA')
SIZE=source.size
assets=[]


def mask(poly):
    out=Image.new('L',SIZE); ImageDraw.Draw(out).polygon(poly,fill=255); return out


def translated_plate(name, offset=(0,0)):
    # Model returned 1673x940, reference 1678x937. Translation/padding ONLY.
    im=Image.open(ART/'source'/f'{name}.png').convert('RGBA')
    canvas=source.copy();canvas.paste(im,offset);return canvas


def patch_region(base, patch, polygon, feather=0):
    area=mask(polygon)
    if feather:area=area.filter(ImageFilter.GaussianBlur(feather))
    return Image.composite(patch,base,area)

# Local completion is intentionally restricted to the confirmed door/exit changes.
patched=translated_plate('door_and_exit_patch',(4,-1))
closed=patch_region(source,patched,[(1225,779),(1275,752),(1320,749),(1370,790),(1390,937),(1215,937)],3)
closed.save(ART/'source/approved_with_closed_exit.png')
opened=patch_region(closed,patched,[(1178,352),(1339,352),(1339,450),(1178,450)])
# The guard silhouettes are separate actors, so the facade behind them is completed.
guard_boxes=[[(1180,406),(1252,406),(1252,483),(1180,483)],[(1299,406),(1373,406),(1373,483),(1299,483)]]
room_source=closed.copy()
for poly in guard_boxes:room_source=patch_region(room_source,patched,poly)

# Pixel masks are authored in the original canvas. Parent modules stay in place.
parts=[
 ('west_home',[(273,178),(303,158),(304,115),(619,115),(619,95),(666,95),(668,195),(700,204),(701,297),(741,297),(741,324),(338,337),(306,297),(291,280)],(500,326),[[306,150,386,160]],'building'),
 ('south_home',[(355,492),(380,475),(380,447),(414,448),(414,421),(463,421),(463,441),(641,441),(641,419),(690,419),(690,512),(731,532),(766,556),(768,665),(744,678),(383,665),(354,612)],(560,669),[[386,455,366,204]],'building'),
 ('fuel_shed',[(47,254),(164,240),(182,250),(200,319),(214,349),(269,376),(305,389),(318,420),(308,459),(279,480),(192,506),(83,498),(58,460)],(180,505),[[60,349,249,134]],'prop'),
 ('middle_cargo',[(630,356),(645,353),(650,370),(728,384),(731,362),(741,358),(747,383),(772,385),(784,410),(816,412),(849,441),(850,483),(814,506),(767,500),(695,521),(690,445),(630,439)],(740,510),[[697,434,149,65]],'prop'),
 ('east_cargo',[(923,606),(949,604),(974,624),(982,552),(1000,551),(1008,572),(1118,571),(1131,550),(1144,549),(1147,562),(1174,562),(1204,556),(1213,566),(1217,697),(1190,699),(1175,715),(1015,715),(953,700),(925,671)],(1080,715),[[951,636,247,70]],'prop'),
 ('checkpoint',[(61,643),(87,640),(106,645),(139,645),(142,596),(152,577),(168,578),(168,596),(270,597),(272,576),(288,576),(286,594),(344,599),(349,621),(339,635),(336,744),(376,744),(375,697),(396,697),(398,710),(428,710),(429,684),(447,683),(449,703),(468,702),(468,739),(484,740),(485,712),(502,711),(502,732),(530,741),(543,737),(546,750),(595,752),(598,747),(614,749),(615,782),(596,782),(594,774),(549,770),(545,779),(529,779),(526,767),(503,759),(498,774),(374,777),(355,780),(340,774),(337,776),(315,770),(315,647),(177,642),(177,778),(160,782),(147,776),(122,782),(109,781),(105,761),(64,751)],(240,778),[[65,666,77,104],[142,622,35,155],[315,635,46,141],[368,736,258,40]],'prop'),
 ('north_bench',[(768,77),(852,77),(856,78),(874,78),(883,87),(886,115),(775,115),(771,105)],(826,115),[[776,94,106,21]],'prop'),
 ('north_crate',[(500,58),(519,44),(543,58),(543,97),(511,105),(499,92)],(521,104),[[502,70,42,30]],'prop'),
 ('west_home_cargo',[(684,208),(733,208),(737,254),(760,244),(769,251),(772,283),(758,300),(696,310),(688,285)],(730,310),[[696,250,67,53]],'prop'),
 ('elder_side_cargo',[(931,221),(961,211),(975,219),(975,319),(956,330),(940,317),(939,298),(927,283)],(957,330),[[934,258,43,64]],'prop'),
 ('elder_door_barrels',[(1018,416),(1034,405),(1054,410),(1060,420),(1076,415),(1084,425),(1087,466),(1071,472),(1028,468),(1018,453)],(1050,472),[[1023,443,62,26]],'prop'),
 ('elder_front_crate',[(1513,438),(1524,425),(1566,425),(1568,485),(1555,492),(1519,490)],(1540,492),[[1520,459,47,29]],'prop'),
 ('drunk_guard',[(850,435),(865,433),(879,432),(887,438),(890,432),(894,445),(887,453),(895,459),(903,451),(911,456),(915,475),(913,484),(904,489),(892,484),(889,493),(897,500),(893,508),(880,508),(870,498),(863,510),(850,505),(851,490),(840,483),(839,465),(847,451)],(870,509),[[852,490,36,16]],'actor'),
 ('entrance_guard',[(212,692),(224,691),(237,685),(251,688),(260,695),(270,694),(272,682),(277,676),(283,685),(283,713),(280,746),(272,749),(270,729),(262,724),(261,744),(252,751),(242,747),(236,738),(229,750),(216,749),(218,732),(209,729),(207,714)],(241,750),[[223,735,36,18]],'actor'),
 ('door_guard_left',[(1187,412),(1203,413),(1217,408),(1230,414),(1243,413),(1236,429),(1239,439),(1246,439),(1248,410),(1252,400),(1257,412),(1255,476),(1248,478),(1247,457),(1238,460),(1242,477),(1229,482),(1217,471),(1210,481),(1195,480),(1196,462),(1184,458),(1181,444),(1188,430)],(1217,481),[[1199,468,36,18]],'actor'),
 ('door_guard_right',[(1304,410),(1318,411),(1331,407),(1345,411),(1356,411),(1349,428),(1353,439),(1361,442),(1361,415),(1366,405),(1370,415),(1368,477),(1362,481),(1355,458),(1348,464),(1352,477),(1339,481),(1328,470),(1322,480),(1308,481),(1307,461),(1299,459),(1298,444),(1305,431)],(1333,482),[[1315,469,36,18]],'actor'),
]
# Torch silhouettes remain at their exact original places; ambient light stays in ground.
for name,x,y in [('torch_north',714,80),('torch_west',224,199),('torch_elder_side',933,170),('torch_fuel',88,490),('torch_gate_left',112,708),('torch_gate_right',358,710),('torch_south_home',674,652),('torch_east',1625,590)]:
    parts.append((name,[(x-14,y-85),(x+12,y-85),(x+19,y-49),(x+10,y-36),(x+7,y),(x-7,y),(x-9,y-35),(x-17,y-50)],(x,y),[[x-5,y-15,10,15]],'prop'))

all_mask=Image.new('L',SIZE)

def save(name, im, area, anchor, blocks, kind):
    global all_mask
    box=area.getbbox()
    cut=im.copy();cut.putalpha(area);cut=cut.crop(box)
    cut.save(ART/f'{name}.png')
    off=[box[0]-anchor[0],box[1]-anchor[1]]
    title=''.join(t.title() for t in name.split('_'))
    text=f'''[gd_scene format=3]

[ext_resource type="Texture2D" path="res://assets/map/night_infiltration/{name}.png" id="1"]

[node name="{title}" type="Node2D"]
texture_filter = 1
metadata/native_size = Vector2i({cut.width}, {cut.height})

[node name="Visual" type="Sprite2D" parent="."]
position = Vector2({off[0]}, {off[1]})
texture = ExtResource("1")
centered = false

[node name="GroundAnchor" type="Marker2D" parent="."]
'''
    (MOD/f'{name}.tscn').write_text(text,encoding='utf-8',newline='\n')
    assets.append(dict(id=name,scene=f'res://src/levels/night_infiltration/modules/{name}.tscn',native_size=list(cut.size),source_box=list(box),position=list(anchor),kind=kind,blocks=blocks))
    all_mask=ImageChops.lighter(all_mask,area)

for name,poly,anchor,blocks,kind in parts:
    save(name,closed if kind!='actor' else source,mask(poly),anchor,blocks,kind)

# Roofless residence is a ground/back layer; its furniture and facade sort separately.
room_poly=[(969,35),(1586,35),(1586,299),(1608,299),(1608,451),(1345,459),(1340,448),(1180,448),(1180,456),(971,453)]
room_mask=mask(room_poly)
save('elder_room',room_source,room_mask,(970,35),[],'room')
for name,poly,anchor in [
 ('elder_desk',[(1085,203),(1237,203),(1237,286),(1193,286),(1193,304),(1178,304),(1178,287),(1122,287),(1122,296),(1107,296),(1107,285),(1085,285)],(1160,304)),
 ('elder_bed',[(1300,112),(1438,112),(1438,285),(1300,285)],(1370,285)),
 ('elder_front_left',[(969,326),(1175,326),(1182,349),(1182,459),(969,453)],(1070,459)),
 ('elder_front_right',[(1338,326),(1586,299),(1608,299),(1608,452),(1338,459)],(1460,459)),
 ('elder_header',[(1175,326),(1340,326),(1340,354),(1175,354)],(1260,458)),
 ('elder_west_wall',[(969,35),(1008,35),(1008,352),(969,352)],(990,352)),
 ('elder_cabinet',[(1478,81),(1566,81),(1566,260),(1478,260)],(1522,260)),
]:save(name,room_source,mask(poly),anchor,[],'occlusion')

# Open door artwork is a translated crop, not a scaled replacement scene.
door_area=mask([(1182,354),(1338,354),(1338,449),(1182,449)])
save('elder_door_closed',closed,door_area,(1260,450),[],'door_closed')
save('elder_door_open',opened,door_area,(1260,450),[],'door_open')

# Outer cavern and foreground rock retain the exact irregular silhouette and void.
walkable=[(129,937),(127,861),(105,801),(90,778),(95,649),(57,573),(83,503),(47,454),(59,341),(119,283),(187,251),(239,194),(280,139),(330,109),(460,119),(504,88),(621,105),(669,88),(710,53),(778,70),(824,51),(870,80),(930,116),(960,80),(982,35),(1614,35),(1624,103),(1638,178),(1614,259),(1642,329),(1619,389),(1646,447),(1678,431),(1678,576),(1610,603),(1580,628),(1510,655),(1490,686),(1400,691),(1370,759),(1337,794),(1342,937),(1210,937),(1195,811),(1150,782),(1080,792),(1020,807),(974,815),(932,774),(902,746),(883,756),(859,723),(818,735),(778,750),(750,779),(720,771),(700,799),(657,762),(628,778),(600,768),(540,782),(485,768),(450,756),(420,780),(381,772),(347,801),(346,862),(326,937)]
rim_mask=ImageChops.subtract(ImageChops.invert(mask(walkable)),all_mask)
# Make closure visible even where the original outline had an opening.
closure=mask([(1222,780),(1278,751),(1320,748),(1372,792),(1390,937),(1215,937)])
rim_mask=ImageChops.lighter(rim_mask,ImageChops.subtract(closure,all_mask))
for name,box in [('rim_north',(0,0,1678,356)),('rim_west',(0,356,350,937)),('rim_east',(1370,356,1678,937)),('rim_south',(350,570,1370,937))]:
    clip=Image.new('L',SIZE);ImageDraw.Draw(clip).rectangle((box[0],box[1],box[2]-1,box[3]-1),fill=255)
    area=ImageChops.darker(rim_mask,clip)
    if area.getbbox():save(name,closed,area,(0,0),[],'rock')

# Every original visible floor pixel remains. Hidden areas use the generated plate.
plate=translated_plate('ground_plate')
floor=Image.composite(plate,closed,all_mask)
atlas=Image.new('RGBA',(1728,960),(17,20,31,255));atlas.paste(floor,(0,0));atlas.save(ART/'ground_atlas.png')
# Offline recomposition is an exact audit; the runtime loads only modules + tiles.
composed=floor.copy()
for a in sorted(assets,key=lambda a: (-10 if a['kind']=='room' else (2 if a['kind']=='rock' else 0), a['position'][1])):
    if a['kind']=='door_open':continue
    im=Image.open(ART/f"{a['id']}.png")
    composed.alpha_composite(im,(a['source_box'][0],a['source_box'][1]))
cap=ROOT/'docs/night_infiltration/captures';cap.mkdir(parents=True,exist_ok=True)
composed.save(cap/'offline_recomposition.png')
error=np.abs(np.array(composed.convert('RGB'),dtype=np.int16)-np.array(closed.convert('RGB'),dtype=np.int16))
print('recomposition mean error:',float(error.mean()),'exact pixels:',float((error.max(axis=2)==0).mean()))
(ART/'catalog.json').write_text(json.dumps(dict(version=2,world_size=list(SIZE),units='native reference pixels; no resampling',reference='source/concept.png',tutorial_sources=['AI游戏美术/二维分层场景/提示词合集.txt','AI游戏美术/HD-2D游戏场景/批量生图提示词.txt','AI游戏美术/HD-2D游戏场景/场景模版搭建提示词.md'],generated_plate_translation=[0,0],generated_edit_translation=[4,-1],assets=assets),ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')
print('modules:',len(assets))
