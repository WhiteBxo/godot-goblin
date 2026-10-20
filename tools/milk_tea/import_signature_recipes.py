"""Import the source workbook into the shared RecipeRules resource.

Run from the repository root with Python + openpyxl. --check is read only.
Ingredient IDs are resolved from source_ids in both menus; workbook prose and
empty discovery fields are preserved without authoring new dialogue.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import re

import openpyxl

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs/design/source/signature_recipes_development_2026_10_19.xlsx"
TARGET = ROOT / "src/resources/milk_tea/recipe_rules.tres"


def ingredient_ids(menu: Path) -> dict[str, str]:
    result = {}
    for block in re.split(r"(?=^\[)", menu.read_text(encoding="utf-8"), flags=re.M):
        identity = re.search(r'^id = "([^"]+)"$', block, re.M)
        sources = re.search(r"^source_ids = PackedStringArray\(([^\n]+)\)", block, re.M)
        if identity and sources:
            for source in re.findall(r'"([CF]\d+)"', sources[1]):
                if source in result:
                    raise ValueError(f"Duplicate source ID {source}")
                result[source] = identity[1]
    return result


def read_signatures() -> list[dict]:
    mapping = ingredient_ids(ROOT / "src/resources/milk_tea/basic_menu.tres")
    if mapping != ingredient_ids(ROOT / "src/resources/milk_tea/day1_menu.tres"):
        raise ValueError("Both menus must resolve the same C/F IDs")
    book = openpyxl.load_workbook(SOURCE, data_only=False)
    try:
        rows = [list(r) for r in book.active.values if any(v is not None for v in r)]
    finally:
        book.close()
    if len(rows[0]) != 15:
        raise ValueError("Expected the 15-field development workbook")
    result = []
    for row in rows[1:]:
        ingredients = []
        for value in row[2:5]:
            match = re.fullmatch(r".+\(([CF]\d+)\)", value)
            if not match or match[1] not in mapping:
                raise ValueError(f"Unknown ingredient {value}")
            ingredients.append(mapping[match[1]])
        if row[5] not in ["是", "否"]:
            raise ValueError(f"Invalid ice requirement for {row[0]}")
        for value in row[13:15]:
            if type(value) is not int or value <= 0:
                raise ValueError(f"Invalid price/reward for {row[0]}")
        entry = dict(id=row[0], name=row[1], ingredients=ingredients, iced=row[5] == "是",
                     price=row[13], first_reward=row[14], appearance=row[6] or "",
                     tasting_note=row[7] or "", discovery_flow=row[8] or "",
                     discovery_note=row[9] or "",
                     discovery_kind="clue" if row[8] else "experiment")
        for field, value in zip(["flavors", "textures", "effects"], row[10:13]):
            entry[field] = [] if value in [None, "空", ""] else [tag.strip() for tag in value.split(",")]
        result.append(entry)
    if [r["id"] for r in result] != [f"S{i:02}" for i in range(1, 11)]:
        raise ValueError("Expected S01-S10 exactly once in source order")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    entries = read_signatures()
    # JSON scalar/list/dictionary syntax is valid inside a Godot text resource.
    generated = "signatures = Array[Dictionary](" + json.dumps(entries, ensure_ascii=False, indent=2) + ")\n"
    text = TARGET.read_text(encoding="utf-8")
    text = re.sub(r"signatures = Array\[Dictionary\]\([\s\S]*?\)\n(?=throw_tuning =)", "", text)
    output = text.replace('throw_tuning = ExtResource("2")', generated + 'throw_tuning = ExtResource("2")')
    if args.check:
        if TARGET.read_text(encoding="utf-8") != output:
            print("Signature resource is stale")
            return 1
    else:
        TARGET.write_text(output, encoding="utf-8", newline="\n")
    print(f"SIGNATURE_IMPORT: PASS ({len(entries)} source recipes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
