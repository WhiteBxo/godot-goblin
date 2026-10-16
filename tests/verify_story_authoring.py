"""Exercise authoring validation through Godot and the real cinematic host.

Temporary fixtures never change the committed source or execution products.
Run: python3 tests/verify_story_authoring.py [--godot /path/to/Godot]
"""

import argparse
import copy
import json
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default="/Applications/Godot.app/Contents/MacOS/Godot")
    args = parser.parse_args()
    baseline = json.loads((ROOT / "docs/story_authoring/cinematic_opening.json").read_text())
    checks = 0

    with tempfile.TemporaryDirectory(prefix=".story_authoring_", dir=ROOT / "tests") as temp:
        folder = Path(temp)

        def resource(path):
            return "res://" + str(path.relative_to(ROOT))

        def verify(name, manifest, expected_error="", story=None, dialogue=None):
            nonlocal checks
            manifest = copy.deepcopy(manifest)
            if story is not None or dialogue is not None:
                story = story or json.loads((ROOT / "src/resources/story/cinematic_opening.json").read_text())
                dialogue = dialogue or json.loads((ROOT / "src/resources/dialogue/cinematic_opening.json").read_text())
                for key, data in [("story", story), ("dialogue", dialogue)]:
                    output = folder / (key + ".json")
                    output.write_text(json.dumps(data, ensure_ascii=False) + "\n")
                    manifest[key] = resource(output)
                host = folder / "host.tscn"
                host.write_text(
                    '[gd_scene load_steps=2 format=3]\n'
                    '[ext_resource type="PackedScene" path="res://src/debug/cinematic/cinematic_demo.tscn" id="1"]\n'
                    '[node name="CinematicDemo" instance=ExtResource("1")]\n'
                    f'story_file = "{manifest["story"]}"\n'
                    f'dialogue_file = "{manifest["dialogue"]}"\n'
                )
                manifest["scene"] = resource(host)
            path = folder / "manifest.json"
            path.write_text(json.dumps(manifest, ensure_ascii=False) + "\n")
            result = subprocess.run(
                [args.godot, "--headless", "--path", str(ROOT), "--log-file",
                 str(folder / "godot.log"), "--script", "res://tools/story/validate_story.gd",
                 "--", resource(path)],
                capture_output=True, text=True, timeout=65,
            )
            output = result.stdout + result.stderr
            expected_code = 1 if expected_error else 0
            assert result.returncode == expected_code, f"{name}: exit {result.returncode}\n{output}"
            assert "SCRIPT ERROR" not in output, f"{name}: unhandled script error\n{output}"
            assert (expected_error or "0 failures") in output, f"{name}: missing diagnostic\n{output}"
            checks += 1
            print("PASS:", name, flush=True)

        verify("unchanged cinematic source and real movement", baseline)
        changed = copy.deepcopy(baseline)
        changed["source_sha256"] = "stale"
        verify("stale source rejected", changed, "Source changed")
        changed = copy.deepcopy(baseline)
        changed["beats"][1]["start"] = 3
        verify("overlapping Beat rejected", changed, "Gap/overlap")

        original = json.loads((ROOT / "src/resources/story/cinematic_opening.json").read_text())
        for name, index, field, value, diagnostic in [
            ("unknown command", 0, "command", "invented", "Unknown command"),
            ("missing actor", 0, "actor", "absent", "missing actor absent"),
            ("missing Marker", 6, "target", "absent", "missing Marker absent"),
            ("missing audio", 4, "id", "absent", "missing audio absent"),
            ("missing dialogue", 2, "id", "absent", "Unknown mapped dialogue"),
            ("invalid actor scene root", 7, "scene", "res://src/core/audio/audio_manager.tscn", "scene root must extend PlayerController"),
        ]:
            story = copy.deepcopy(original)
            story["events"]["cinematic.opening"]["steps"][index][field] = value
            manifest = copy.deepcopy(baseline)
            if name == "missing dialogue":
                manifest["beats"][0]["dialogues"] = ["absent"]
            verify(name, manifest, diagnostic, story=story)

        # Four synthetic steps reuse the four source heading IDs to test mapping,
        # routing, choices and state independently of prose interpretation.
        event = "test.route"
        steps = [
            {"command": "dialogue", "id": "test.question"},
            {"command": "set_flag", "key": "test.chosen", "when": {
                "choice": {"dialogue": "test.question", "line": "question", "id": "yes"}}},
            {"command": "set_stage", "value": "test.done"},
            {"command": "wait", "seconds": 0},
        ]
        story = {"version": 1, "events": {event: {
            "trigger": "orders", "conditions": {"flags": {"test.ready": True}}, "steps": steps}}}
        dialogue = {"version": 1, "dialogues": {"test.question": {
            "start": "question", "lines": {"question": {"speaker": "测试", "text": "选择", "choices": [
                {"id": "yes", "text": "是"}, {"id": "no", "text": "否"}]}}}}}
        manifest = copy.deepcopy(baseline)
        for index, beat in enumerate(manifest["beats"]):
            beat.update(event=event, start=index, count=1, dialogues=["test.question"] if index == 0 else [])
        manifest["cases"] = [{
            "trigger": "orders", "expected_event": event,
            "state": {"flags": {"test.ready": True}},
            "choices": {"test.question/question": choice},
            "expected_skips": [] if choice == "yes" else [1],
            "expect_flags": {"test.chosen": choice == "yes"},
            "expect_stage": "test.done", "timeout": 3,
        } for choice in ["yes", "no"]]
        verify("two choice branches, interaction route and final state", manifest, story=story, dialogue=dialogue)
        negative_cases = copy.deepcopy(manifest)
        negative_cases["cases"] += [
            {"event": event, "request_error": "ERR_UNAUTHORIZED"},
            {"trigger": "orders", "expected_event": event, "request_error": "ERR_DOES_NOT_EXIST"},
            {"event": event, "state": {"flags": {"test.ready": True}, "completed_events": [event]},
             "request_error": "ERR_ALREADY_EXISTS"},
        ]
        verify("negative conditions, absent route and once rejection", negative_cases, story=story, dialogue=dialogue)
        broken = copy.deepcopy(story)
        broken["events"][event]["steps"][1]["when"]["choice"]["id"] = "absent"
        verify("invalid when.choice reference", manifest, "missing when.choice reference", broken, dialogue)
        broken_manifest = copy.deepcopy(manifest)
        broken_manifest["cases"][0]["choices"] = {}
        verify("choices require explicit coverage", broken_manifest, "explicitly select valid choice", story, dialogue)
        broken_manifest = copy.deepcopy(manifest)
        broken_manifest["cases"][0]["state"] = {}
        verify("unsatisfied trigger condition", broken_manifest, "Request rejected", story, dialogue)
        broken = copy.deepcopy(story)
        broken["events"][event]["steps"][3] = {
            "command": "actor_move", "actor": "player", "target": [9999, 9999], "speed": 1, "timeout": 0.1}
        verify("real movement timeout fails validation", manifest, "Execution:", broken, dialogue)

    print(f"STORY_AUTHORING_TESTS: {checks} checks, 0 failures")


if __name__ == "__main__":
    main()
