"""Check pending source fidelity; --check-import also checks frozen import MD.

After migration edit the engineering source and dialogue together, never rebuild
from old Markdown. The optional import audit is for the original transfer only.
"""

import argparse
import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PROJECTS = ["day1_stages_03_06", "day2_stages_01_05"]
SPEAKERS = "主角·内心|主角|胖哥布林|醉酒守卫|守卫|系统|酒馆老板|赌场老板|哥布林顾客甲|哥布林顾客乙|哥布林顾客"


def verify(stem, check_import):
    path = ROOT / f"docs/story_authoring/{stem}_project.json"
    project = json.loads(path.read_text(encoding="utf-8"))
    pending = project["pending"]
    imported_lines = None
    if check_import:
        source = ROOT / project["manifest"]["source"].removeprefix("res://")
        assert hashlib.sha256(source.read_bytes()).hexdigest() == project["manifest"]["source_sha256"], "Frozen import changed"
        imported_lines = source.read_text(encoding="utf-8").splitlines(keepends=True)
        assert re.findall(r"^### Beat (\w+)", "".join(imported_lines), re.M) == [beat["id"] for beat in pending["beats"]]
    spoken = 0
    for beat in pending["beats"]:
        excerpt = beat["source_markdown"]
        start = int(beat["source_start"])
        lines = excerpt.splitlines()
        if imported_lines is not None:
            assert excerpt == "".join(imported_lines[start - 1:int(beat["source_end"])]), beat["id"]
        expected = [i + start for i, line in enumerate(lines) if re.match(r"\s*- (" + SPEAKERS + r")：「", line)]
        observed = []
        for origin in beat["ordered_lines"]:
            dialogue = pending["dialogues"][origin["dialogue"]]["lines"][origin["line"]]
            if origin["kind"] == "document":
                assert dialogue["speaker"] == ""
                assert dialogue["text"].split("\n\n") == re.findall(r"^  > (.+)$", excerpt, re.M)
            else:
                index = int(origin["source_line"]) - start
                quoted = dialogue["speaker"] + "：「" + dialogue["text"] + "」"
                assert quoted in lines[index], (beat["id"], origin["line"])
                observed.append(int(origin["source_line"]))
                spoken += 1
        assert observed == expected, f"Missing, duplicated or reordered dialogue in {beat['id']}"
        for record in beat["chronicles"]:
            for step in record["steps"]:
                if step["command"] == "chronicle_append":
                    assert "：「" + step["content"] + "」" in lines[int(record["source_line"]) - start]
        if "choice" in beat:
            choices = pending["dialogues"][beat["choice"]["dialogue"]]["lines"]["choice"]["choices"]
            assert [(row["id"], row["text"]) for row in choices] == [("accept", "接受委托"), ("refuse", "拒绝委托")]
            for row in choices:
                assert f"`{row['id']}`：「{row['text']}」" in excerpt
    print(f"{stem}: {len(pending['beats'])} Beats, {spoken} spoken lines, fidelity PASS")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-import", action="store_true")
    args = parser.parse_args()
    for project_stem in PROJECTS:
        verify(project_stem, args.check_import)
