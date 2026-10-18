class_name Day1StealthSetup
extends Node
## Level-owned bindings. Empty fields remain pending instead of inventing mission design.

@export var guards: Array[Day1GuardResponse] = []
@export var flammable_targets: Array[Day1FlammableTarget] = []
@export var destructible_targets: Array[Day1DestructibleTarget] = []
@export var checkpoint: Marker2D
@export var escape_zone: Area2D
@export var coin_item_id := "strange_coin"
@export var torch_item_id := ""
## Published two-day route: currency coins, no arson, whole-attempt rollback.
@export var wallet_coins := false
@export var interior_only := false
## Confirms P08's actual requirements; a blank reference disables mission activation.
@export_multiline var escape_rules_reference := ""
@export var required_flags: Array[StringName] = [&"day1.s05.blood_acquired"]
@export var required_items: Dictionary = {"day1_griffin_blood": 1}
@export var confusion_required := false
@export_range(1.0, 1200.0) var throw_range := 460.0
## World-space scale for projectile speed/art and recipe effect distances; time is unchanged.
@export_range(0.1, 4.0, 0.05) var effect_scale := 1.0

func get_issues(inventory: WarehouseInventory, actor_lookup: Callable) -> PackedStringArray:
	var issues := PackedStringArray()
	if interior_only and wallet_coins:
		return issues
	for item: String in [coin_item_id, torch_item_id]:
		if wallet_coins:
			continue
		if item.is_empty() or inventory.get_definition(item) == null:
			issues.append("未绑定真实投掷物品：%s" % (item if not item.is_empty() else "火把（P09）"))
	if not is_instance_valid(checkpoint) or not checkpoint.is_inside_tree() or not checkpoint.global_position.is_finite():
		issues.append("检查点尚未确认（P09）")
	if not has_escape_shape():
		issues.append("正式撤离区域尚未绑定（P08/P09）")
	if escape_rules_reference.strip_edges().is_empty() or required_flags.is_empty() or required_items.is_empty():
		issues.append("撤离任务条件及混乱要求尚未确认（P08）")
	if not required_items.has("day1_griffin_blood") or &"day1.s05.blood_acquired" not in required_flags:
		issues.append("撤离必须校验真实血液及其取得事实")
	for id: Variant in required_items:
		if not id is String or inventory.get_definition(id) == null or not required_items[id] is int or required_items[id] <= 0:
			issues.append("撤离物品配置无效")
	var roles := {}
	var actors := {}
	for guard: Variant in guards:
		if not is_instance_valid(guard) or not guard.is_inside_tree() or not is_instance_valid(guard.actor) or not guard.actor.is_inside_tree():
			issues.append("守卫必须绑定实际角色，Marker 不代表 NPC")
			continue
		if guard.role not in Day1GuardResponse.Role.values() or guard.actor.accepts_player_input or guard.discovery_seconds <= 0.0 or guard.distraction_seconds <= 0.0 or guard.sight_range <= 0.0:
			issues.append("守卫职责、角色输入或感知参数无效")
		if roles.has(guard.role) or actors.has(guard.actor) or guard.actor.actor_id == &"guard_captain" or not actor_lookup.is_valid() or actor_lookup.call(guard.actor.actor_id) != guard.actor:
			issues.append("守卫角色未独立注册，或错误复用了守卫长")
		roles[guard.role] = true
		actors[guard.actor] = true
		if guard.role in [Day1GuardResponse.Role.MANSION_GATE, Day1GuardResponse.Role.DRUNKEN] and guard.clearance_flag == &"":
			issues.append("守卫放行事实尚未确认（P06）")
		if guard.role == Day1GuardResponse.Role.DRUNKEN and guard.encounter_event_id.is_empty():
			issues.append("醉酒守卫事件尚未绑定（P09）")
	for role: int in Day1GuardResponse.Role.values():
		if not roles.has(role):
			issues.append("缺少独立守卫职责：%s（P09）" % Day1GuardResponse.Role.keys()[role])
	if flammable_targets.is_empty() and not wallet_coins:
		issues.append("没有已确认的可燃目标（P09）")
	var target_ids := {}
	for target: Variant in flammable_targets:
		if not is_instance_valid(target) or not target.is_inside_tree() or not target.is_confirmed() or target_ids.has(target.target_id):
			issues.append("可燃目标缺少有效碰撞、唯一 ID 或确认依据（P09）")
		else:
			target_ids[target.target_id] = true
	for target: Variant in destructible_targets:
		if not is_instance_valid(target) or not target.is_inside_tree() or not target.is_confirmed() or target_ids.has(target.target_id):
			issues.append("可腐蚀目标缺少有效阻挡、唯一 ID 或确认依据")
		else:
			target_ids[target.target_id] = true
	return issues

func has_escape_shape() -> bool:
	if not is_instance_valid(escape_zone) or not escape_zone.is_inside_tree():
		return false
	for owner_id: int in escape_zone.get_shape_owners():
		if not escape_zone.is_shape_owner_disabled(owner_id) and escape_zone.shape_owner_get_shape_count(owner_id) > 0:
			return true
	return false

## Test current feet against the authored shapes, avoiding cached overlaps after teleport.
func contains_escape_position(position: Vector2) -> bool:
	if not has_escape_shape():
		return false
	var point := CircleShape2D.new()
	point.radius = 0.1
	for owner_id: int in escape_zone.get_shape_owners():
		if escape_zone.is_shape_owner_disabled(owner_id):
			continue
		for index in range(escape_zone.shape_owner_get_shape_count(owner_id)):
			var shape := escape_zone.shape_owner_get_shape(owner_id, index)
			if shape.collide(escape_zone.global_transform * escape_zone.shape_owner_get_transform(owner_id), point, Transform2D(0, position)):
				return true
	return false
