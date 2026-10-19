class_name GatherSoundKit
extends RefCounted
## Maps a harvested item to the sound of its material. Every unknown item falls
## back to the generic confirm blip, so a new gather point is never silent.

const PLANT: String = "gather.plant"
const CRYSTAL: String = "gather.crystal"
const VIAL: String = "gather.vial"
const DEFAULT: String = "ui.confirm"

const ITEM_SOUNDS := {
	&"moss_green": PLANT,
	&"sugar_yam": PLANT,
	&"firefly_cap": PLANT,
	&"scorch_tongue_pepper": PLANT,
	&"insomnia_mushroom": PLANT,
	&"phantom_gold_mushroom": PLANT,
	&"red_mottled_wood": PLANT,
	&"honey_amber_crystal": CRYSTAL,
	&"rainbow_cube": CRYSTAL,
	&"day1_griffin_blood": VIAL,
}

static func for_item(item_id: String) -> String:
	return ITEM_SOUNDS.get(StringName(item_id), DEFAULT)
