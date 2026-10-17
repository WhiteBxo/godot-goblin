"""Prepare reference-driven extraction briefs; no network/API operations."""
from pathlib import Path
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets/map/settlement/modular"
PACKS = [
    ("tavern", "酒馆", "06_tavern", [("round_table", "空圆木桌，不带椅子或桌面小物"), ("wood_stool", "一把独立木凳"), ("bar_straight", "一段256像素长的吧台直段"), ("bar_corner", "吧台L形转角单元"), ("bottle_rack", "酒瓶木架"), ("fireplace", "完整独立石壁炉，含烟囱下段"), ("ale_barrel", "单只木酒桶"), ("skull_banner", "兽骨红色墙旗，不带墙")]),
    ("casino", "赌场", "07_casino", [("dice_table", "骨骰绿布赌桌，不带椅子"), ("card_table", "卡牌绿布赌桌，不带椅子"), ("wheel_table", "符文轮盘桌，不带椅子"), ("gambling_stool", "单只赌桌木凳"), ("iron_safe", "完整铆钉铁保险箱"), ("boss_desk", "空老板账桌，不带椅子和桌面小物"), ("collection_rack", "稀有金菇与奖杯收藏架"), ("coin_tray", "金币钱袋托盘，不带桌子")]),
    ("dining", "聚餐区", "08_dining", [("long_table", "空纵向长木餐桌，不带碗盘或长凳"), ("long_bench", "单条纵向长木凳"), ("serving_counter", "一段独立分餐木台"), ("food_shelf", "碗碟与食材架"), ("cooking_pot", "炖汤铁锅"), ("dish_stack", "一摞独立碗盘"), ("grain_sack", "单只开口粮袋"), ("drink_barrel", "单只盛水木桶")]),
    ("kitchen", "厨房", "05_kitchen", [("prep_table", "空长木备菜桌，不带砧板、菜刀、食材或墙"), ("cauldron", "石圈火床上的完整大锅"), ("spit_roast", "转轴烤肉架与烤肉"), ("pantry_shelf", "粮袋和调料架"), ("stone_sink", "独立石水槽"), ("serving_table", "出餐木台"), ("meat_rack", "独立挂肉木架"), ("vegetable_basket", "蔬菜蘑菇木盆")]),
    ("training", "军营", "03_training", [("iron_cage", "单座完整铁笼，正面门"), ("strategy_desk", "空战略木桌，不带地图和卷轴"), ("training_dummy", "单个木训练假人"), ("archery_target", "单个草靶及支脚"), ("weapon_rack", "长矛和盾架"), ("commander_chair", "战略办公室单把椅子"), ("supply_chest", "军用补给箱"), ("war_banner", "独立旧军旗，不带墙")]),
    ("elder", "长老私房", "10_elder", [("large_bed", "完整较大木床，紫色被褥"), ("bookcase", "满书木书架"), ("document_desk", "空长老书桌，不带古文书和椅子"), ("bone_chair", "骨冠扶手椅"), ("meditation_table", "独立圆冥想茶几"), ("red_vial", "一只装红色液体的密封药瓶"), ("wardrobe", "完整木衣柜"), ("floor_cushion", "单只紫色软垫")]),
    ("ritual", "祭坛大厅", "09_ritual", [("altar", "完整石祭台，红布与贡碗"), ("offering_table", "单段贡品石桌"), ("carved_pillar", "一根完整刻纹石柱"), ("bone_idol", "独立兽骨图腾，不带墙"), ("brazier", "单个石座火盆"), ("prayer_mat", "一张编织跪拜垫"), ("ritual_banner", "独立红色仪式旗，不带墙"), ("secret_cover", "半开石盖与拉环，独立机关，不带台阶或地板")]),
    ("lodging", "住宿区", "04_lodging", [("straw_bed", "完整单人草垫木床"), ("bedside_chest", "床脚行李箱"), ("bedside_table", "单个床头木柜"), ("wash_basin", "单个木水盆及矮架"), ("coat_rack", "衣物挂钩板与旧衣，不带墙"), ("privacy_curtain", "一幅旧绿布帘及挂杆，不带墙"), ("bedside_lamp", "小油灯"), ("travel_bag", "单只旅行行囊")]),
    ("warehouse", "仓库", "12_warehouse", [("stock_rack", "完整木货架及箱罐"), ("crate", "单个方木箱"), ("crate_stack", "两只不同高的箱垛"), ("inventory_desk", "空盘点木桌，不带账本和墨瓶"), ("sealed_sack", "单只捆口粮袋"), ("clay_jar", "独立带盖陶罐"), ("water_barrel", "单只独立木桶"), ("rope_coil", "盘绕麻绳")]),
    ("milk_shop", "奶茶店营业区", "00_shop", [("shop_counter", "一段256像素长现代奶茶柜台"), ("tea_urn", "一台独立奶茶保温桶"), ("ingredient_tray", "独立六格配料盒"), ("espresso_machine", "独立小型奶茶咖啡制作机"), ("cash_register", "独立收银机"), ("cup_rack", "杯具壁挂木架，不带墙"), ("waiting_bench", "一张完整等候长凳"), ("rest_chair", "一把绿色休息扶手椅")]),
    ("milk_home", "奶茶店生活区", "00_shop", [("single_bed", "左侧完整单人床"), ("home_desk", "一张小书桌，不带凳子"), ("home_wardrobe", "木衣柜"), ("refrigerator", "完整双层冰箱"), ("toilet", "独立马桶"), ("bathroom_sink", "独立洗手池"), ("shower", "淋浴喷头和水管，不带墙地板"), ("storage_rack", "小型原料储物架")]),
    ("garden", "种植区", "11_growing", [("white_mushrooms", "一小丛白蘑菇，不带泥土色块"), ("blue_mushrooms", "一小丛蓝蘑菇，不带地板"), ("herb_basket", "草药木篮"), ("garden_fence", "一段矮木栅栏"), ("garden_gate", "独立矮木栅门"), ("tool_stand", "铁铲草叉工具架"), ("watering_bucket", "单只盛水木桶"), ("garden_table", "分拣木桌，不带凳子")]),
    ("workshop", "河岸工坊", "15_workshop", [("anvil", "独立铁砧和矮底座"), ("workbench", "修理工作台"), ("forge", "完整小型石炉"), ("tool_board", "铁锤钳子工具挂板，不带墙"), ("hide_rack", "晒皮木架和兽皮"), ("sawhorse", "木工作业锯架"), ("timber_stack", "捆扎木材堆"), ("small_cart", "完整双轮板车")]),
    ("hearth", "公共火塘", "14_hearth", [("stone_firepit", "独立低矮石圈篝火，只含火焰、柴和石圈"), ("empty_fire_ring", "没有火焰的空石圈火塘"), ("hanging_pot", "独立悬挂小铁锅，不带支架"), ("pot_tripod", "空木杆三脚锅架，不带锅"), ("bench_front", "一条正面粗木长凳"), ("bench_back", "一条背面粗木长凳"), ("kindling_pile", "一小堆柴薪"), ("water_bucket", "一只装水木桶")]),
    ("tabletop", "桌面小道具", "06_tavern", [("beer_mug", "单只麦酒杯"), ("wine_bottle", "单只绿色酒瓶"), ("candle_holder", "一支蜡烛与小烛台"), ("open_book", "一本摊开的账本"), ("scroll_bundle", "一组卷轴"), ("bone_dice", "三颗骨骰"), ("playing_cards", "一小摞独立卡牌"), ("coin_pile", "一小堆金币")]),
    ("kitchenware", "厨房小道具", "05_kitchen", [("kitchen_knife", "一把独立菜刀"), ("chopping_board", "一块空砧板"), ("raw_meat", "一块生肉"), ("vegetable_bowl", "一盆蔬菜"), ("wooden_bowl", "一只空木碗"), ("iron_pan", "一口独立铁锅"), ("ladle", "一把汤勺"), ("herb_bundle", "一束捆好的香草")]),
    ("yard", "庭院与集结点", "13_yard", [("cargo_cart", "完整双轮货车"), ("cargo_crates", "货物箱垛"), ("cargo_sacks", "三只粮袋组合"), ("canvas_shelter", "独立敞口遮雨棚，空棚不含货物和地面"), ("low_stone_fence", "一段低石矮墙"), ("wood_sign", "独立木路牌，无文字"), ("muster_flag", "独立旧红旗和旗杆底座"), ("outdoor_bench", "单张完整粗木长凳")]),
]


def main():
    entries = []
    for slug, title, source, objects in PACKS:
        entries.append({"id": slug, "title": title, "source": source, "kind": "props", "objects": [{"id": key, "description": text} for key, text in objects]})
    wall_objects = [
        [("wall_north", "后墙直段，横向256像素，正面可见墙面，高140，无柱帽"), ("wall_south", "前墙低剖面直段，横向256像素，高100，无柱帽"), ("wall_west", "左侧墙直段，竖向256像素，窄墙顶与外侧立面"), ("wall_east", "右侧墙直段，竖向256像素，窄墙顶与外侧立面"), ("corner_nw", "完整西北L形墙转角，两臂各128像素"), ("corner_ne", "完整东北L形墙转角，两臂各128像素"), ("door_south", "独立正南门框，两门柱之间敞开宽120像素，无门板"), ("wall_post", "一根独立墙体支柱")],
        [("corner_sw", "完整西南L形低墙转角，两臂各128像素"), ("corner_se", "完整东南L形低墙转角，两臂各128像素"), ("door_west", "独立向西敞开的侧门框，无门板"), ("door_east", "独立向东敞开的侧门框，无门板"), ("window", "独立窗框与窗格，不带墙面"), ("wall_torch", "一只独立壁挂火炬与支架，不带墙"), ("wall_lamp", "一只独立壁灯与支架，不带墙"), ("support_beam", "一根独立横向支撑木梁")],
    ]
    for theme, title, source, material in [("stone", "灰石木梁墙体", "06_tavern", "灰色砌石、深木梁，保持酒馆墙体的石块线条和材质"), ("fortress", "赌场深灰墙体", "07_casino", "深灰石块、近黑包边与少量深木材，保持赌场墙体材质"), ("plaster", "奶茶店墙体", "00_shop", "米白粉刷墙面、深棕包边和砖砌外墙，保持奶茶店墙体材质")]:
        for index, objects in enumerate(wall_objects):
            entries.append({"id": f"walls_{theme}_{index + 1}", "title": title + f" {index + 1}", "source": source, "kind": "walls", "material": material, "objects": [{"id": key, "description": text} for key, text in objects]})
    (OUT / "prompts").mkdir(parents=True, exist_ok=True)
    (OUT / "guides").mkdir(exist_ok=True)
    for pack in entries:
        sizes = [(220, 240)] * 8
        if pack["id"] == "tavern":
            sizes = [(174, 150), (58, 72), (258, 140), (190, 232), (205, 228), (232, 230), (75, 100), (148, 160)]
        elif pack["id"] in ["tabletop", "kitchenware"]:
            sizes = [(64, 72)] * 8
        elif pack["kind"] == "walls":
            sizes = [(256, 145), (256, 105), (64, 256), (64, 256), (160, 200), (160, 200), (256, 220), (60, 210)] if pack["id"].endswith("1") else [(160, 160), (160, 160), (150, 256), (150, 256), (85, 100), (55, 100), (55, 90), (256, 35)]
        else:
            for i, obj in enumerate(pack["objects"]):
                key = obj["id"]
                if any(word in key for word in ["stool", "vial", "lamp", "pot", "coil", "jar", "bucket", "sack", "dish", "bag", "tray", "register", "urn"]): sizes[i] = (90, 110)
                if "table" in key or "desk" in key or "counter" in key or "bench" in key: sizes[i] = (240, 150)
                if "bed" in key: sizes[i] = (200, 270)
                if key == "long_table": sizes[i] = (190, 300)
                if key == "long_bench": sizes[i] = (55, 290)
        guide = Image.new("RGB", (1536, 1024), "#ff00ff")
        draw = ImageDraw.Draw(guide)
        for i, (width, height) in enumerate(sizes):
            cx, cy = i % 4 * 384 + 192, i // 4 * 512 + 256
            draw.rectangle((cx-width//2, cy-height//2, cx+width//2, cy+height//2), fill="#b9d0d8", outline="#2196ff", width=2)
            pack["objects"][i]["target_size"] = [width, height]
        guide.save(OUT / "guides" / (pack["id"] + ".png"))
        items = "\n".join(f"第{i // 4 + 1}行第{i % 4 + 1}格：{obj['description']}。" for i, obj in enumerate(pack["objects"]))
        prompt = f"""任务：把原场景中的{pack['title']}提取成8件真正独立、可重复摆放的游戏素材。图1是必须保留尺寸和位置的版式目标，图2是原场景造型参考，图3只限定线条风格。
最高优先：仅在图1八个蓝框内部绘制对应物品，保持各蓝框的精确原始像素范围与中心位置；物品不允许超出蓝框，不要放大填充384×512格子。完成后彻底删除所有蓝框与蓝灰填色，框外仍是纯品红。
输出1536×1024横幅图集，严格4列2行，每格384×512，无格线、无文字、无编号。以下8件按顺序各占一格，不重复、不遗漏，各物件在格子内完整居中，彼此至少隔开30像素。
{items}
保持原场景中每件物品的造型、朝向、材质、配色与细节；补全原图被墙或其他物品遮挡的轮廓。每格只能有指定的一件物品。所有桌子、吧台、柜台必须为空家具，去掉其桌面的小物和周围的凳子、椅子；每把凳子只能出现在指定凳子的格子中；墙与家具分开。{pack.get('material', '')}
使用参考图的正交俯视RPG角度，水平和竖直轴对齐；近黑2~3像素清晰轮廓、阶梯状像素边缘、有限平涂色块。不要改成3D渲染、透视收缩、斜向等距、软笔刷或光晕。
尺度：人物高110像素、宽40像素；木凳宽45~65像素，圆桌直径150~190像素，床约180~250像素宽，长桌或吧台单元约256像素长。不要放大填满格子，保留适当留白；各件使用合理的原始像素尺度。禁止拉伸变形。大件保持完整，最多330像素宽、400像素高。
最高优先级：物件轮廓以外、镂空处和物件之间全部为均一纯品红RGB(255,0,255)，方便透明化；无投影、光晕、墙面、地板、地毯、泥土地台或整间屋子的背景。物件自身只包含其固有结构，桌面杯子、蜡烛、书籍等小物全部去掉，它们会作为独立小道具制作。墙体素材仅保留墙段本身，不含地面或家具。不要人物、生物、装饰画框、水印或UI。
"""
        (OUT / "prompts" / (pack["id"] + ".txt")).write_text(prompt, encoding="utf-8", newline="\n")
    (OUT / "briefs.json").write_text(json.dumps({"grid": [4, 2], "cell": [384, 512], "packs": entries}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"Prepared {len(entries)} packs / {len(entries) * 8} independent prop and wall briefs.")


if __name__ == "__main__":
    main()
