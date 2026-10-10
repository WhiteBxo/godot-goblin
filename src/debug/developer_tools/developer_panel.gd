class_name DeveloperPanel
extends Control

signal speed_multiplier_selected(multiplier: float)

@onready var speed_selector: OptionButton = $Panel/Tools/SpeedSelector

func _ready() -> void:
	speed_selector.item_selected.connect(_on_speed_selected)

func configure_choices(multipliers: PackedInt32Array) -> void:
	speed_selector.clear()
	for multiplier: int in multipliers:
		speed_selector.add_item("玩家移速 %d×" % multiplier, multiplier)

func set_speed_multiplier(multiplier: float) -> void:
	speed_selector.select(speed_selector.get_item_index(int(multiplier)))

func _on_speed_selected(index: int) -> void:
	speed_multiplier_selected.emit(float(speed_selector.get_item_id(index)))
	speed_selector.release_focus()
