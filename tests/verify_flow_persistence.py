#!/usr/bin/env python3
"""One writer and eight fresh Godot readers; all save files/logs in a temp dir."""
import argparse
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="/Applications/Godot.app/Contents/MacOS/Godot")
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="goblin-flow-persistence-") as directory:
        failed = False
        phases = [("write", "all")] + [("read", key) for key in (
            "delivered", "closed", "purchased", "round_one", "round_two", "waived", "new_game", "second_reward")]
        for mode, checkpoint in phases:
            command = [args.godot, "--headless", "--path", str(args.project),
                       "--log-file", str(Path(directory) / f"{mode}-{checkpoint}.log"),
                       "--script", "res://tests/verify_flow_persistence.gd", "--",
                       mode, directory, checkpoint]
            result = subprocess.run(command, capture_output=True, text=True, timeout=60)
            print(result.stdout, end="")
            print(result.stderr, end="")
            if result.returncode or "SCRIPT ERROR" in result.stderr:
                failed = True
                if mode == "write":
                    break
        return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
