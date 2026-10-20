"""一次性：把第一天第二次来客改成三只哥布林一起进场。

只改 `docs/story_authoring/day1_stages_01_02_project.json`（真实源稿），
产物由 `tools/story/edit_story_project.gd -- <工程> --save` 生成。
重跑会整段重建这两个 beat 的 steps，并让 `next_step_id` 继续递增（产生额外 diff），
只在需要还原这段编排时使用。
"""

import json
from pathlib import Path

PROJECT = Path("docs/story_authoring/day1_stages_01_02_project.json")

# 站位：a=赌徒（点单，柜台正中），b=说教的（右），c=爱收集的（左）
GROUP_SLOTS = {
    "goblin_a": "day1_group_b",
    "goblin_b": "day1_group_c",
    "goblin_c": "day1_group_a",
}


def main() -> int:
    data = json.loads(PROJECT.read_text(encoding="utf-8"))
    next_id = int(data["next_step_id"])

    def step(data_dict):
        nonlocal next_id
        next_id += 1
        return {"id": f"step_{next_id}", "data": data_dict}

    beats = {beat["id"]: beat for beat in data["beats"]}

    # --- 群客进场：三只同时进来，各站一个锚点 ---
    arrival = [
        step({"command": "play_sfx", "id": "shop.door_bell", "wait": False}),
    ]
    for actor in ("goblin_a", "goblin_b", "goblin_c"):
        arrival.append(step({"command": "actor_show", "actor": actor, "wait": False}))
    arrival.append(step({"command": "wait", "seconds": 0.25}))
    # 三条路线大致平行（左/中/右），同时起步；最靠里的那只最后发并以它为准等待。
    for actor in ("goblin_b", "goblin_a", "goblin_c"):
        arrival.append(
            step({
                "command": "actor_move",
                "actor": actor,
                "target": GROUP_SLOTS[actor],
                "speed": 300.0,
                "wait": actor == "goblin_c",
            })
        )
    for index, actor in enumerate(("goblin_a", "goblin_b", "goblin_c")):
        arrival.append(
            step({"command": "actor_face", "actor": actor, "direction": "up", "wait": index == 2})
        )
    arrival.append(step({"command": "camera_focus", "target": "day1_group_b", "duration": 0.6}))
    arrival.append(step({"command": "dialogue", "id": "day1.goblin_group_customers"}))
    beats["goblin_group_customers"]["steps"] = arrival

    # --- 交付后：赌徒与说教的先后离开，爱收集的留在原地接着点单 ---
    # 只走已验证可走的 door ↔ aisle 那条路，避免和家具或彼此互挤。
    departure = []
    for actor in ("goblin_a", "goblin_b"):
        departure.extend([
            step({"command": "actor_move", "actor": actor, "target": "day1_aisle", "speed": 240.0}),
            step({"command": "actor_move", "actor": actor, "target": "day1_door", "speed": 240.0}),
            step({"command": "actor_hide", "actor": actor, "wait": False}),
        ])
    departure.extend([
        step({"command": "actor_move", "actor": "goblin_c", "target": "day1_counter", "speed": 120.0}),
        step({"command": "actor_face", "actor": "goblin_c", "direction": "up"}),
        step({"command": "dialogue", "id": "day1.customer_c"}),
        step({"command": "set_flag", "key": "day1.group_c_open"}),
        step({"command": "set_stage", "value": "day1.wait_group_c"}),
        step({"command": "camera_reset"}),
    ])
    beats["customer_c_arrives"]["steps"] = departure

    # --- 点单者必须是赌徒，订单的交付目标就是 goblin_a ---
    group_dialogue = data["dialogues"]["day1.goblin_group_customers"]["lines"]
    group_dialogue["line_5"]["speaker"] = "赌徒哥布林"

    data["next_step_id"] = float(next_id)
    PROJECT.write_text(
        json.dumps(data, ensure_ascii=False, indent="\t") + "\n", encoding="utf-8", newline="\n"
    )
    print(f"next_step_id -> {next_id}")
    print("beat goblin_group_customers steps:", len(arrival))
    print("beat customer_c_arrives steps:", len(departure))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
