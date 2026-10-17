"""One-time spatial authoring, calibrated against the selected native-size art."""
from pathlib import Path
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
LAYOUT = ROOT / "src/levels/settlement/settlement_layout.json"


def obstacle(name, collision, visual=None):
    result = {"name": name, "collision": collision}
    if visual:
        result["visual"] = visual
    return result


def main():
    data = json.loads(LAYOUT.read_text(encoding="utf-8"))
    zones = {zone["id"]: zone for zone in data["zones"]}
    for zone in zones.values():
        image = Image.open(ROOT / zone["asset"].removeprefix("res://")).convert("RGBA")
        left, top, right, bottom = image.getchannel("A").getbbox()
        zone["walls"] = []
        if zone["kind"] != "building":
            continue
        gap_left, gap_right = (1228, 1350) if zone["id"] == "00_shop" else (700, 836)
        if zone["id"] == "03_training":
            gap_left, gap_right = 688, 912
        if zone["id"] == "09_ritual":
            gap_left, gap_right = 674, 862
        if zone["id"] == "10_elder":
            gap_left, gap_right = 660, 870
        zone["entry"] = [(gap_left + gap_right) // 2, bottom + 40]
        zone["walls"] = [
            {"collision": [left, top, 30, bottom - top], "visual": [left, top, 42, bottom - top], "sort_y": bottom},
            {"collision": [right - 30, top, 30, bottom - top], "visual": [right - 42, top, 42, bottom - top], "sort_y": bottom},
            {"collision": [left, bottom - 32, gap_left - left, 32], "visual": [left, bottom - 118, gap_left - left, 118], "sort_y": bottom},
            {"collision": [gap_right, bottom - 32, right - gap_right, 32], "visual": [gap_right, bottom - 118, right - gap_right, 118], "sort_y": bottom},
        ]
        if zone["id"] == "02_vestibule":
            zone["walls"] += [{"collision": [left, top, 700 - left, 145]}, {"collision": [836, top, right - 836, 145]}]
        else:
            zone["walls"].append({"collision": [left, top, right - left, 145]})

    furniture = {
        "00_shop": [
            obstacle("BedroomDivider", [420, 130, 35, 300], [410, 100, 50, 335]),
            obstacle("StorageDivider", [690, 125, 38, 455], [615, 100, 115, 480]),
            obstacle("BedroomSouth", [115, 503, 215, 28], [105, 490, 235, 110]),
            obstacle("BathroomDivider", [312, 535, 30, 272], [300, 525, 42, 285]),
            obstacle("StockPartition", [425, 420, 82, 120], [418, 408, 90, 138]),
            obstacle("StockPartitionEast", [600, 430, 28, 110], [595, 420, 40, 130]),
            obstacle("Pantry", [462, 200, 205, 145], [458, 155, 220, 240]),
            obstacle("TeaEquipment", [732, 275, 607, 85], [730, 180, 610, 180]),
            obstacle("Refrigerator", [1340, 345, 70, 135], [1334, 288, 80, 195]),
            obstacle("ServiceCounter", [808, 530, 500, 57], [805, 447, 505, 143]),
            obstacle("RestChair", [1314, 566, 91, 57], [1310, 497, 101, 132]),
            obstacle("WaitingBench", [797, 775, 287, 31], [790, 737, 300, 70]),
            obstacle("WestPlanter", [719, 779, 64, 33], [700, 710, 85, 106]),
            obstacle("EastPlanter", [1093, 784, 61, 28], [1080, 709, 80, 104]),
            obstacle("StoredBoxes", [483, 731, 186, 75], [475, 684, 205, 124]),
            obstacle("LowerDivider", [675, 674, 30, 155], [668, 667, 39, 168]),
        ],
        "02_vestibule": [obstacle("LeftDesk", [350, 435, 160, 62], [347, 382, 166, 146]), obstacle("Register", [915, 439, 325, 57], [910, 388, 335, 116]), obstacle("Supplies", [180, 713, 148, 75], [174, 646, 165, 145]), obstacle("RightChair", [1225, 730, 125, 52], [1220, 670, 135, 120])],
        "03_training": [
            obstacle("CageA", [102, 408, 221, 135], [97, 354, 232, 190]), obstacle("CageB", [102, 553, 221, 137], [97, 495, 232, 201]), obstacle("CageC", [102, 702, 221, 135], [97, 641, 232, 200]),
            obstacle("StrategyTable", [205, 234, 200, 52], [196, 177, 215, 123]), obstacle("OfficeDivider", [466, 92, 28, 263], [452, 83, 54, 275]), obstacle("OfficeSouth", [110, 332, 285, 26], [103, 307, 300, 70]),
            obstacle("DummyLine", [752, 289, 416, 32], [735, 217, 460, 121]), obstacle("Targets", [1210, 290, 151, 25], [1195, 216, 185, 110]),
        ],
        "04_lodging": [obstacle(f"Bed{side}{row}", [x, 280 + row * 192, 205, 119], [x - 6, 232 + row * 192, 218, 177]) for side, x in enumerate([200, 1130]) for row in range(3)],
        "05_kitchen": [obstacle("Preparation", [182, 318, 435, 45], [170, 197, 458, 183]), obstacle("Cooking", [721, 322, 458, 83], [698, 154, 500, 266]), obstacle("Washing", [180, 600, 112, 170], [166, 456, 145, 315]), obstacle("EastStock", [1250, 511, 105, 260], [1235, 390, 130, 399]), obstacle("ServingLeft", [346, 784, 299, 56], [340, 714, 315, 130]), obstacle("ServingRight", [887, 784, 365, 56], [873, 718, 393, 128])],
        "06_tavern": [obstacle("Hearth", [277, 237, 220, 40], [271, 53, 231, 225]), obstacle("BarNorth", [914, 222, 443, 63], [900, 120, 465, 170]), obstacle("BarWest", [912, 280, 64, 127], [905, 164, 78, 258]), obstacle("BarFront", [920, 360, 440, 65], [910, 301, 455, 126]), obstacle("TableNorth", [332, 359, 146, 55], [325, 302, 157, 136]), obstacle("TableSouthWest", [404, 680, 137, 55], [395, 621, 156, 135]), obstacle("TableSouthEast", [1019, 683, 139, 54], [1010, 624, 156, 128]), obstacle("EastBarrels", [1302, 641, 73, 110], [1290, 575, 93, 184])],
        "07_casino": [obstacle("WestPartition", [649, 87, 30, 399], [645, 80, 40, 411]), obstacle("EastPartition", [818, 87, 30, 375], [812, 80, 45, 391]), obstacle("WestCrossWall", [169, 475, 331, 32], [166, 462, 339, 53]), obstacle("EastCrossWall", [949, 451, 422, 32], [945, 427, 432, 62]), obstacle("DiceTable", [280, 352, 170, 58], [268, 272, 194, 155]), obstacle("CardTable", [313, 732, 187, 58], [303, 638, 210, 160]), obstacle("WheelTable", [1033, 732, 167, 58], [1020, 639, 190, 160]), obstacle("BossDesk", [998, 350, 195, 50], [987, 294, 217, 114]), obstacle("Collection", [1190, 220, 175, 55], [1182, 120, 190, 167])],
        "08_dining": [obstacle("Serving", [580, 301, 445, 63], [570, 219, 462, 151]), obstacle("TableWest", [400, 502, 192, 238], [390, 412, 217, 340]), obstacle("TableEast", [1012, 502, 193, 238], [998, 411, 223, 342]), obstacle("WestStock", [145, 596, 120, 185], [130, 514, 145, 278])],
        "09_ritual": [obstacle("Altar", [596, 266, 349, 72], [580, 115, 384, 227]), obstacle("OfferingsWest", [364, 401, 160, 50], [346, 327, 196, 132]), obstacle("OfferingsEast", [1014, 401, 160, 50], [996, 327, 196, 132])] + [obstacle(f"Brazier{col}{row}", [x, 510 + 119 * row, 45, 25], [x - 5, 454 + 119 * row, 57, 90]) for col, x in enumerate([588, 942]) for row in range(3)],
        "10_elder": [obstacle("Bookshelves", [178, 280, 201, 56], [167, 124, 223, 221]), obstacle("DocumentDesk", [308, 426, 270, 49], [298, 343, 292, 152]), obstacle("Bed", [929, 380, 253, 80], [914, 209, 280, 260]), obstacle("Vault", [1218, 636, 125, 64], [1210, 506, 142, 202]), obstacle("CenterTable", [676, 632, 157, 45], [668, 558, 176, 133])],
        "11_growing": [obstacle("GardenShed", [130, 100, 300, 200], [110, 42, 340, 310]), obstacle("SortingTable", [672, 548, 168, 48], [668, 481, 175, 117])],
        "12_warehouse": [obstacle("ShelvesWest", [423, 282, 287, 68], [416, 151, 301, 207]), obstacle("ShelvesEast", [829, 281, 310, 70], [818, 150, 330, 213]), obstacle("InventoryDesk", [198, 431, 210, 56], [186, 375, 234, 125]), obstacle("WestStacks", [185, 718, 277, 65], [178, 631, 294, 164]), obstacle("EastStacks", [1138, 675, 215, 108], [1127, 572, 240, 224])],
        "13_yard": [obstacle("NorthShelter", [876, 250, 370, 67], [834, 50, 439, 295]), obstacle("Cart", [333, 422, 224, 58], [308, 315, 266, 184]), obstacle("WestCargo", [140, 800, 178, 66], [120, 692, 220, 194]), obstacle("EastCargo", [1300, 712, 120, 135], [1285, 620, 160, 260])],
        "14_hearth": [obstacle("FireRing", [694, 517, 139, 55], [675, 422, 177, 160]), obstacle("BenchNW", [510, 393, 173, 31], [499, 343, 195, 84]), obstacle("BenchNE", [1026, 393, 173, 31], [1010, 342, 199, 88]), obstacle("BenchSW", [511, 704, 173, 31], [499, 654, 195, 84]), obstacle("BenchSE", [1026, 704, 173, 31], [1010, 653, 199, 88])],
        "15_workshop": [obstacle("WorkshopRear", [197, 175, 625, 194], [190, 132, 640, 246]), obstacle("Anvil", [471, 449, 71, 32], [451, 378, 113, 110]), obstacle("HideRack", [118, 794, 222, 46], [109, 653, 243, 192]), obstacle("RepairTable", [660, 807, 156, 42], [642, 730, 197, 125]), obstacle("Timber", [925, 501, 225, 88], [911, 421, 251, 180])],
    }
    for slug, items in furniture.items():
        zones[slug]["obstacles"] = items

    data["spawn"] = [5180, 8560]
    data["river"] = [1920, 0, 830, 7540]
    data["river_outline"] = [[1970, 0], [1952, 1000], [1984, 2300], [1920, 3500], [1952, 4700], [1940, 6000], [1990, 7150], [2030, 7350], [2100, 7480], [2336, 7540], [2570, 7480], [2650, 7350], [2700, 7150], [2720, 6000], [2736, 4700], [2750, 3500], [2690, 2300], [2720, 1000], [2700, 0]]
    data["story_anchors"] = [
        {"id": "shop_rest_chair", "position": [5180, 8480]},
        {"id": "shop_workbench", "position": [4940, 8220]},
        {"id": "drunken_guard", "position": [4300, 6250]},
        {"id": "tavern_bartender", "position": [3870, 4340]},
        {"id": "casino_boss", "position": [6890, 4270]},
        {"id": "elder_document", "position": [5990, 1170]},
        {"id": "elder_blood_storage", "position": [6800, 1400]},
        {"id": "ritual_hidden_cover", "position": [4000, 1010]},
        {"id": "elder_hidden_bookcase", "position": [6800, 870]},
    ]
    data["service_points"] = [
        {"id": "orders", "name": "订单板", "position": [4970, 8450], "description": "今日订单 #001\n珍珠奶茶 × 1 · 常温 · 少糖\n\n查看订单 → 仓库备料 → 制作台调配。"},
        {"id": "storage", "name": "原料仓储", "position": [4470, 8380], "description": "原料库存\n红茶 12 份　牛奶 12 份\n珍珠 8 份　糖浆 10 份\n\n货架原料充足，可以准备今日营业。"},
        {"id": "tea_station", "name": "奶茶制作台", "position": [4940, 8220], "description": "珍珠奶茶 · 配方\n红茶 × 1 + 牛奶 × 1 + 珍珠 × 1\n\n加入茶底和牛奶，放入珍珠、糖浆后摇匀封杯。"},
    ]
    main_road = [[5190, 8750], [5480, 8860], [5480, 7540], [3968, 7540], [3968, 6430], [4300, 6100], [4300, 5504], [4500, 5100], [4500, 3500], [4300, 3500], [4300, 1900], [3768, 1900], [3768, 1580]]
    data["streets"] = [main_road, [[3500, 3328], [1500, 3328], [1500, 2900]], [[3968, 5504], [1500, 5504]], [[3000, 5050], [7400, 5050]], [[6320, 1850], [6320, 1580]], [[4300, 1900], [6320, 1900], [7800, 1900], [7800, 8200]], [[6900, 6900], [7800, 6900]], [[6800, 8200], [7800, 8200]], [[5100, 3400], [7800, 3400]], [[3568, 5050], [3568, 4800]], [[6568, 5050], [6568, 4800]]]
    data["routes"]["day1"] = [[5180, 8560]] + main_road + [[3768, 1580], [3768, 1900], [6320, 1900], [6320, 1550]]
    data["routes"]["day2"] = [[5180, 8560]] + main_road[:7] + [[4300, 5050], [3568, 5050], [3568, 4800], [3568, 5050], [6568, 5050], [6568, 4800], [6568, 5050], [5480, 5504], [4300, 6100], [4300, 6250]]
    data["routes"]["supply"] = [[1400, 8000], [1400, 6000], [1400, 5504], [2820, 5504], [2820, 3328], [3568, 3328], [3568, 3270], [3568, 3328], [1400, 3328], [1400, 3100]]
    data["streets"].append([[2820, 5504], [2820, 3328]])
    data["street_props"] = []
    # Pillars/crates provide sight breaks on streets, never enclose individual zones.
    placements = [
        ("EntranceLamp", [5660, 8620], [0, 3], True), ("SouthSignCrates", [3600, 7600], [2, 1], True),
        ("GuardPillarWest", [4050, 6250], [0, 1], True), ("GuardPillarEast", [4510, 6060], [1, 1], True),
        ("HearthApproach", [4070, 5350], [0, 3], True), ("TavernLamp", [3650, 4860], [0, 3], True),
        ("CasinoCrates", [6910, 4860], [2, 1], True), ("CasinoLamp", [6440, 4890], [0, 3], True),
        ("WestBridgeLamp", [1800, 5380], [0, 3], True), ("EastBridgeLamp", [3020, 5380], [0, 3], True),
        ("SupplyBridgeCrates", [2870, 3140], [2, 1], True), ("WarehouseLamp", [3660, 3340], [0, 3], True),
        ("UpperStreetPillar", [4340, 3690], [1, 1], True), ("RitualPillarWest", [3410, 1820], [0, 1], True),
        ("RitualPillarEast", [4130, 1820], [1, 1], True), ("ElderLamp", [6570, 1730], [0, 3], True),
    ]
    for i, at in enumerate([[1800, 4120], [1840, 5900], [2830, 5520], [2900, 3610], [7400, 5250], [6020, 7070], [7430, 1800], [1250, 7280]]):
        placements.append((f"NightGather{i}", at, [i % 3, 2], False))
        approach = -90 if at[0] < 1950 else 90
        data["story_anchors"].append({"id": f"night_gather_{i}", "position": [at[0] + approach, at[1]]})
    data["street_props"] = [{"id": name, "position": at, "cell": cell, "solid": solid} for name, at, cell, solid in placements]
    LAYOUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print("Calibrated native art collision, 16 entrances, story anchors and open streets.")


if __name__ == "__main__":
    main()
