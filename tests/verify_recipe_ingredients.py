"""Run with: python tests/verify_recipe_ingredients.py (requires openpyxl)."""
from __future__ import annotations

import importlib.util
import io
import json
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch

import openpyxl

ROOT = Path(__file__).resolve().parents[1]
# Importing the tool must not leave untracked __pycache__ files in the repo.
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("recipe_import", ROOT / "tools/milk_tea/import_recipe_ingredients.py")
importer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(importer)


class RecipeImportTests(unittest.TestCase):
    def test_real_sheet_matches_both_menus(self):
        rows = importer.read_rows()
        self.assertEqual(len(rows), 22)
        self.assertEqual(rows["F09"]["market_price"], "-1")
        self.assertEqual(rows["F09"]["free_recipe_allowed"], "false")
        self.assertEqual(sum(row["throw_kind"] != '\"\"' for row in rows.values()), 12)
        for menu in importer.MENUS:
            source = menu.read_text(encoding="utf-8")
            rewritten, seen = importer.rewrite(source, rows)
            self.assertEqual(seen, set(rows))
            self.assertEqual(rewritten, source)
            self.assertEqual(importer.rewrite(rewritten, rows)[0], rewritten)

    def test_numbers_reject_bool_nonfinite_and_fraction(self):
        for value in [True, False, None, "1", -1, 0.5, float("nan"), float("inf")]:
            with self.subTest(value=value), self.assertRaises(ValueError):
                importer.number(value, "F01", "甜度")
        self.assertEqual(importer.number(3.0, "F01", "甜度"), 3)

    def test_godot_strings_escape_control_characters(self):
        text = '薄荷"\\\n\t'
        escaped = importer.gd_string(text)
        self.assertEqual(json.loads(escaped), text)
        self.assertNotIn("\n", escaped)

    def test_generated_fields_preserve_authored_fields(self):
        rows = importer.read_rows()
        block = '[sub_resource type="Resource" id="mint"]\nsource_ids = PackedStringArray("C03")\ndisplay_name = "custom"\nprice = 7\n'
        updated, seen = importer.rewrite(block, rows)
        self.assertEqual(seen, {"C03"})
        self.assertIn('display_name = "custom"\nprice = 7\n', updated)
        self.assertIn('throw_kind = "paralyze"', updated)
        self.assertEqual(importer.rewrite(updated, rows)[0], updated)

    def test_duplicate_runtime_mapping_rejects(self):
        block = '[sub_resource type="Resource" id="a"]\nsource_ids = PackedStringArray("C03")\n'
        with self.assertRaises(ValueError):
            importer.rewrite(block + block.replace('id="a"', 'id="b"'), importer.read_rows())

    def test_ambiguous_runtime_mapping_rejects(self):
        with self.assertRaises(ValueError):
            importer.rewrite('[sub_resource type="Resource" id="a"]\nsource_ids = PackedStringArray("C03", "C05")\n', importer.read_rows())

    def _sheet_case(self, mutate, expected_error):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "ingredients.xlsx"
            workbook = openpyxl.load_workbook(importer.SHEET)
            mutate(workbook.worksheets[0])
            workbook.save(target)
            workbook.close()
            with patch.object(importer, "SHEET", target), self.assertRaisesRegex(ValueError, expected_error):
                importer.read_rows()

    def test_duplicate_sheet_row_rejects(self):
        self._sheet_case(lambda sheet: sheet.append([cell.value for cell in sheet[2]]), "duplicate ingredient row")

    def test_missing_column_rejects(self):
        self._sheet_case(lambda sheet: sheet.cell(1, 1, "unknown"), "missing columns")

    def test_unknown_role_row_rejects(self):
        with tempfile.TemporaryDirectory() as directory:
            roles = Path(directory) / "roles.json"
            roles.write_text(json.dumps({"roles": {"F99": "burn"}}), encoding="utf-8")
            with patch.object(importer, "ROLES", roles), self.assertRaisesRegex(ValueError, "outside the sheet"):
                importer.read_rows()

    def test_check_never_writes_and_missing_mapping_does_not_partially_write(self):
        with tempfile.TemporaryDirectory() as directory:
            first, second = [Path(directory) / name for name in ["first.tres", "second.tres"]]
            source = importer.MENUS[0].read_text(encoding="utf-8")
            stale = source.replace('throw_kind = "paralyze"', 'throw_kind = ""')
            first.write_text(stale, encoding="utf-8")
            second.write_text(source, encoding="utf-8")
            with patch.object(importer, "MENUS", [first, second]), patch.object(sys, "argv", ["import", "--check"]), redirect_stdout(io.StringIO()):
                self.assertEqual(importer.main(), 1)
            self.assertEqual(first.read_text(encoding="utf-8"), stale)
            second.write_text(source.replace('source_ids = PackedStringArray("C03")', 'source_ids = PackedStringArray("missing")'), encoding="utf-8")
            with patch.object(importer, "MENUS", [first, second]), patch.object(sys, "argv", ["import"]), self.assertRaises(ValueError):
                importer.main()
            self.assertEqual(first.read_text(encoding="utf-8"), stale)


if __name__ == "__main__":
    unittest.main(verbosity=2)
