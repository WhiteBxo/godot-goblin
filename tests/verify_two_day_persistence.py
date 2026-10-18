"""Run the real two-day flow, then restore its autosaves in fresh Godot processes."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="/Applications/Godot.app/Contents/MacOS/Godot")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="goblin-two-day-persistence-") as directory:
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
                return 1
            if index == 0:
                saves = sorted(path.parent for path in folder.glob("*/autosave.dat"))
                assert len(saves) == 20, f"Expected 20 real waiting boundaries, got {len(saves)}"
                phases.extend(("two_day_persistence", [str(path)]) for path in saves)
            index += 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
