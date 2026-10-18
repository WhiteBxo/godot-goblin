class_name ThrowTuning
extends Resource
## Thrown milk tea parameters. Ingredients only name a throw_kind; every number lives
## here so balance changes never touch the ingredient sheet or code.
## Order of evaluation (奶茶材料 design note): modifiers shape the area first, then
## effects run inside it. A repeated ingredient stacks its contribution per copy.

## Area before modifiers, in world pixels; one design "grid" is CELL pixels.
@export_range(1.0, 512.0) var cell := 64.0
@export_range(0.1, 60.0) var base_duration := 3.0
## Upper bounds keep stacked modifiers (and future larger slot counts) playable.
@export_range(1.0, 64.0) var max_area_cells := 9.0
@export_range(0.1, 120.0) var max_duration := 30.0

## kind -> per-copy parameters. Modifiers change area, timing or attachment.
@export var modifiers: Dictionary = {
	"burst": {"name": "扩散/击退", "area_cells_add": 4.0, "push_cells": 2.0},
	"sticky": {"name": "粘留/延时", "duration_add": 10.0},
	"contagion": {"name": "附着/传染", "follow_seconds": 8.0, "follow_area_cells": 3.0},
	"mine": {"name": "地雷化", "arm_trigger_cells": 1.0, "arm_timeout": 3.0},
	"vortex": {"name": "聚拢", "pull_cells": 5.0},
	"phantom": {"name": "静音/穿墙", "silent": true, "ignore_walls": true},
}

## kind -> per-copy parameters. Day 1 maps every effect onto guard states; no HP.
@export var effects: Dictionary = {
	"lure": {"name": "引诱", "pulse_seconds": 1.0, "pulse_cells": 3.0},
	"toxic": {"name": "毒气", "repel": true},
	"burn": {"name": "灼烧", "ignite": true, "confuse": true},
	"corrode": {"name": "腐蚀/迟缓", "detect_multiplier": 3.0, "damage_per_second": 1.0},
	"paralyze": {"name": "麻痹/定身", "stun": true},
	"hallucinate": {"name": "致幻", "confuse": true},
}

func is_known_kind(kind: String) -> bool:
	return modifiers.has(kind) or effects.has(kind)

func display_name(kind: String) -> String:
	var entry: Dictionary = modifiers.get(kind, effects.get(kind, {}))
	return str(entry.get("name", ""))
