"""Run the real two-day flow, then restore its autosaves in fresh Godot processes."""
import argparse
from pathlib import Path
import subprocess
import tempfile
from contextlib import nullcontext


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="/Applications/Godot.app/Contents/MacOS/Godot")
    parser.add_argument("--fixtures-directory", type=Path, help="Keep isolated fixtures and logs for diagnosis; directory must be empty")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    if args.fixtures_directory:
        args.fixtures_directory.mkdir(parents=True, exist_ok=True)
        if any(args.fixtures_directory.iterdir()):
            parser.error("--fixtures-directory must be empty")
    context = nullcontext(str(args.fixtures_directory.resolve())) if args.fixtures_directory else tempfile.TemporaryDirectory(prefix="goblin-two-day-persistence-")
    failures = 0
    with context as directory:
        folder = Path(directory)
        phases = [("two_day_flow", ["--save-fixtures=" + directory])]
        index = 0
        while index < len(phases):
            script, parameters = phases[index]
            command = [args.godot, "--headless", "--path", str(root), "--log-file",
                       str(folder / f"process-{index}.log"), "--script",
                       "res://tests/verify_" + script + ".gd", "--", *parameters]
            result = subprocess.run(command, capture_output=True, text=True, timeout=120)
            output = result.stdout + result.stderr
            print(output, end="", flush=True)
            if result.returncode or "SCRIPT ERROR" in output:
                print(f"FAILED process {index}: {script} {parameters} (exit {result.returncode})", flush=True)
                failures += 1
                if index == 0:
                    return 1
            if index == 0:
                saves = sorted(path.parent for path in folder.glob("*/autosave.dat"))
                expected = {
                    "day1_01_human", "day1_02_goblin", "day1_03_group", "day1_04_coin",
                    "day1_05_market", "day1_06_commission", "day1_07_before_stealth",
                    "day1_03_customer_a", "day1_03_customer_c", "day1_03_customer_d", "day1_03_customer_e", "day1_06_trial_taste",
                    "day1_08_blood_recipe", "wait_festival", "wait_elder", "wait_emissary",
                    "wait_rumor", "wait_close", "closed", "tavern_exterior", "wait_wine",
                    "purchased", "casino_exterior", "wait_first", "first_round", "second_round",
                    "return_shop", "wait_special", "crafted_special", "wait_guard",
                    "delivered_guard", "day3_handoff", "day4_expired",
                }
                assert {path.name for path in saves} == expected, "Real checkpoint coverage changed"
                phases.extend(("two_day_persistence", [str(path)]) for path in saves)
            index += 1
    print(f"TWO_DAY_PROCESSES: {len(phases) - 1} checkpoints, {failures} failed processes", flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
