#!/usr/bin/env python3
"""Gate pushes on "no new red" instead of "zero red".

Running the full suite as an unconditional gate fails on day one of any project that
already carries known failures, and the usual outcome is `SKIP_REGRESSION=1` forever.
So the contract is directional: the accepted-failure list in
tests/regression_baseline.json may shrink, never grow silently.

    python tools/git/check_regression.py --report .godot/test_logs/run_all.json

退出码：0 允许推送；1 出现新增红或基线文件损坏。
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

RED_STATUSES = ("FAIL", "CRASH", "HANG")
BASELINE = Path("tests") / "regression_baseline.json"


def load_baseline(root: Path) -> set[str]:
    path = root / BASELINE
    if not path.exists():
        raise SystemExit(f"找不到 {BASELINE}，无法判断是否新增了红。")
    raw = json.loads(path.read_text(encoding="utf-8"))
    return {str(name) for name in raw.get("accepted_failures", [])}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--report", type=Path, required=True, help="tests/run_all.py 产出的 JSON 报告")
    parser.add_argument("--root", type=Path, help="仓库根目录，默认为脚本上两级")
    args = parser.parse_args()

    root = args.root or Path(__file__).resolve().parents[2]
    report_path = args.report if args.report.is_absolute() else root / args.report
    if not report_path.exists():
        raise SystemExit(f"找不到报告 {report_path}，请先运行 python tests/run_all.py")

    report = json.loads(report_path.read_text(encoding="utf-8"))
    baseline = load_baseline(root)

    current: dict[str, str] = {}
    for item in report.get("results", []):
        status = item.get("status", "")
        if status in RED_STATUSES:
            current[str(item.get("name", ""))] = status

    added = sorted(name for name in current if name not in baseline)
    fixed = sorted(name for name in baseline if name not in current)

    if fixed:
        print(f"回归基线可以收紧：以下 {len(fixed)} 项已不再失败，请从 {BASELINE} 删除——")
        for name in fixed:
            print(f"  - {name}")

    if added:
        print("")
        print(f"出现 {len(added)} 项新增红，已阻止推送：")
        for name in added:
            print(f"  {current[name]:<5} {name}")
        print("")
        print("修掉它；若确认是可接受的既有问题，登记到 tests/known_red.json；")
        print(f"若确认是本次改动带出的新债且必须推，把它加进 {BASELINE} 并写清原因。")
        return 1

    if baseline:
        print(f"回归基线无新增红（当前已知红 {len(current)} 项，均已登记）。")
    else:
        print("回归全绿。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
