"""Sync the 2026-10-19 ingredient sheet into both runtime menus.

Input : docs/design/source/recipe_ingredients_revised_2026_10_19.xlsx (sheet 1)
        tools/milk_tea/throw_roles.json (row ID -> ThrowTuning kind)
Output: src/resources/milk_tea/basic_menu.tres and day1_menu.tres, in place.

Only the generated recipe/economy/throw fields of rows already mapped through
source_ids are rewritten; names, icons, descriptions, stock and orders stay as
they are. Run from the repository root:

    python tools/milk_tea/import_recipe_ingredients.py          # write
    python tools/milk_tea/import_recipe_ingredients.py --check  # exit 1 if stale
"""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parents[2]
SHEET = ROOT / "docs/design/source/recipe_ingredients_revised_2026_10_19.xlsx"
ROLES = ROOT / "tools/milk_tea/throw_roles.json"
MENUS = [ROOT / "src/resources/milk_tea/basic_menu.tres", ROOT / "src/resources/milk_tea/day1_menu.tres"]

TASTE = ["sweetness", "sourness", "bitterness", "spiciness", "milkiness", "booziness"]
GENERATED = ["can_be_base", "base_suffix", "free_recipe_allowed", *TASTE, "recipe_flavors",
             "recipe_textures", "recipe_effects", "market_price", "uses_per_portion",
             "economy_tier", "economy_scope", "throw_kind"]
BEGIN = "; generated:recipe_ingredients"
SUFFIXES = {"奶茶", "茶", "咖啡", "特调"}


def flag(value: object, row_id: str, column: str) -> bool:
    text = str(value).strip().upper()
    if text not in {"TRUE", "FALSE"}:
        raise ValueError(f"{row_id} {column}: expected TRUE/FALSE, got {value!r}")
    return text == "TRUE"


def tags(value: object) -> list[str]:
    text = "" if value is None else str(value).strip()
    if text in {"", "空"}:
        return []
    return [part.strip() for part in text.split(",") if part.strip()]


def number(value: object, row_id: str, column: str) -> int:
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value != int(value) or value < 0:
        raise ValueError(f"{row_id} {column}: expected a non-negative integer, got {value!r}")
    return int(value)


def gd_string(text: str) -> str:
    return json.dumps(text, ensure_ascii=False)


## Tier labels differ between the sheet and the PDF; the T number is the identity.
def tier(value: object, row_id: str) -> int:
    text = "" if value is None else str(value).strip()
    match = re.search(r"\(T([1-5])\)", text, re.IGNORECASE) or re.fullmatch(r"T([1-5])", text, re.IGNORECASE)
    if not match:
        raise ValueError(f"{row_id} 稀有度档位: expected ...(T1)-...(T5), got {value!r}")
    return int(match.group(1))


## Standard market price per portion, by tier. Human slots are free (0G).
TIER_PRICE = {1: 10, 2: 20, 3: 50, 4: 100, 5: 200}


def packed(values: list[str]) -> str:
    return "PackedStringArray(" + ", ".join(gd_string(v) for v in values) + ")"


def read_rows() -> dict[str, dict[str, str]]:
    roles: dict[str, str] = json.loads(ROLES.read_text(encoding="utf-8"))["roles"]
    if not isinstance(roles, dict) or any(not isinstance(value, str) or not value for value in roles.values()):
        raise ValueError("throw_roles.json: roles must map row IDs to non-empty kind names")
    # The source workbook reports A1 as its dimension despite containing 22 rows;
    # normal loading discovers the actual cells instead of trusting that metadata.
    workbook = openpyxl.load_workbook(SHEET, data_only=True)
    try:
        rows = list(workbook.worksheets[0].iter_rows(values_only=True))
    finally:
        workbook.close()
    if not rows:
        raise ValueError("ingredient sheet is empty")
    header = [str(cell).strip() if cell is not None else "" for cell in rows[0]]
    col = {name: index for index, name in enumerate(header)}
    names = {"甜度": 0, "酸度": 1, "苦度": 2, "辣度": 3, "奶香度": 4, "酒香度": 5}
    required = {"原料ID", "原料来源", "稀有度档位", "可作为基底", "基底命名", "普通配方可用", "市场价格", "可使用次数",
                "风味标签", "质地标签", "特殊效果标签", *names}
    if required - col.keys():
        raise ValueError(f"ingredient sheet is missing columns: {sorted(required - col.keys())}")
    result: dict[str, dict[str, str]] = {}
    for raw in rows[1:]:
        row_id = raw[col["原料ID"]]
        if row_id is None or not str(row_id).strip():
            continue
        row_id = str(row_id).strip()
        if row_id in result:
            raise ValueError(f"duplicate ingredient row: {row_id}")
        origin = "" if raw[col["原料来源"]] is None else str(raw[col["原料来源"]]).strip()
        if origin not in {"人类", "哥布林"}:
            raise ValueError(f"{row_id} 原料来源: expected 人类/哥布林, got {raw[col['原料来源']]!r}")
        can_base = flag(raw[col["可作为基底"]], row_id, "可作为基底")
        suffix = "" if raw[col["基底命名"]] is None else str(raw[col["基底命名"]]).strip()
        if can_base != (suffix in SUFFIXES):
            raise ValueError(f"{row_id}: base flag and suffix {suffix!r} disagree")
        free = flag(raw[col["普通配方可用"]], row_id, "普通配方可用")
        # F09 is the authored quest-only row: it is a base but stays out of
        # ordinary recipes, purchase and later sale.
        scope = "trade" if free else "quest"
        economy_tier = tier(raw[col["稀有度档位"]], row_id)
        price = raw[col["市场价格"]]
        price_value = -1 if price is None or str(price).strip() == "" else number(price, row_id, "市场价格")
        if origin == "人类":
            if scope != "trade" or economy_tier != 1 or price_value != 0:
                raise ValueError(f"{row_id}: human ingredients must be T1, free and tradable")
        elif scope == "quest":
            if price_value != -1:
                raise ValueError(f"{row_id}: quest-only ingredients must keep a blank market price")
        elif price_value != TIER_PRICE[economy_tier]:
            raise ValueError(f"{row_id}: market price {price_value} does not match T{economy_tier} ({TIER_PRICE[economy_tier]})")
        fields = {
            "can_be_base": "true" if can_base else "false",
            "base_suffix": gd_string(suffix if can_base else ""),
            "free_recipe_allowed": "true" if free else "false",
            "recipe_flavors": packed(tags(raw[col["风味标签"]])),
            "recipe_textures": packed(tags(raw[col["质地标签"]])),
            "recipe_effects": packed(tags(raw[col["特殊效果标签"]])),
            "market_price": str(price_value),
            "uses_per_portion": str(number(raw[col["可使用次数"]], row_id, "可使用次数")),
            "economy_tier": str(economy_tier),
            "economy_scope": gd_string(scope),
            "throw_kind": gd_string(roles.get(row_id, "")),
        }
        for column, index in names.items():
            fields[TASTE[index]] = str(number(raw[col[column]], row_id, column))
        if not 1 <= int(fields["uses_per_portion"]) <= 99:
            raise ValueError(f"{row_id}: 可使用次数 must be between 1 and 99")
        if any(int(fields[key]) > 99 for key in TASTE):
            raise ValueError(f"{row_id}: taste values must not exceed 99")
        if can_base and fields["throw_kind"] != '""':
            raise ValueError(f"{row_id}: bases carry no throw role")
        result[row_id] = fields
    unknown = set(roles) - set(result)
    if unknown:
        raise ValueError(f"throw_roles.json names rows outside the sheet: {sorted(unknown)}")
    return result


def rewrite(text: str, rows: dict[str, dict[str, str]]) -> tuple[str, set[str]]:
    blocks = re.split(r"(?m)^(?=\[sub_resource |\[resource\])", text)
    seen: set[str] = set()
    for index, block in enumerate(blocks):
        match = re.search(r"(?m)^source_ids = PackedStringArray\(([^)]*)\)$", block)
        if not match:
            continue
        ids = re.findall(r'"([^"]+)"', match.group(1))
        sheet_ids = [row_id for row_id in ids if row_id in rows]
        if not sheet_ids:
            continue
        if len(sheet_ids) > 1:
            raise ValueError(f"block maps several sheet rows: {sheet_ids}")
        if sheet_ids[0] in seen:
            raise ValueError(f"several runtime items map sheet row: {sheet_ids[0]}")
        seen.add(sheet_ids[0])
        lines = [line for line in block.rstrip("\n").split("\n")
                 if line.split(" = ")[0] not in GENERATED and line != BEGIN]
        fields = rows[sheet_ids[0]]
        lines.append(BEGIN)
        lines.extend(f"{key} = {fields[key]}" for key in GENERATED)
        blocks[index] = "\n".join(lines) + "\n\n"
    return "".join(blocks), seen


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check without writing")
    check = parser.parse_args().check
    rows = read_rows()
    updates = []
    for menu in MENUS:
        text = menu.read_text(encoding="utf-8")
        updated, seen = rewrite(text, rows)
        missing = set(rows) - seen
        if missing:
            raise ValueError(f"{menu.name}: no runtime item for sheet rows {sorted(missing)}")
        if updated != text:
            updates.append((menu, updated))
    # Prepare and validate every menu before touching either file.
    stale = [menu.name for menu, _ in updates]
    if check:
        print("RECIPE_INGREDIENTS:", "STALE " + ", ".join(stale) if stale else "OK", f"({len(rows)} rows)")
        return 1 if stale else 0
    for menu, updated in updates:
        menu.write_text(updated, encoding="utf-8", newline="\n")
    print("RECIPE_INGREDIENTS: wrote", ", ".join(stale) if stale else "nothing (already current)", f"({len(rows)} rows)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
