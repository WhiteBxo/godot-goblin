class_name EconomyRules
extends Resource
## Static economy table from the 2026-10-19 sheet. Confirmed prices, claims and
## balances never live here: those are session snapshots owned by GameState.

const TIERS: Array[int] = [1, 2, 3, 4, 5]
const HUMAN_SLOT_MARKUP := 1

## Fixed human menu price per cup. H01-H06 use it; teaching drinks keep it only
## as a debug default and are no longer offered by the formal order board.
@export_range(0, 2147483647) var human_cup_price: int = 3
## One-time reward for the first successful craft of a configured signature.
@export_range(0, 2147483647) var signature_first_reward: int = 150
## 可使用次数 per whole portion for every traded ingredient.
@export_range(1, 99) var uses_per_portion: int = 5
## Standard market price per portion, keyed by tier number.
@export var tier_market_prices: Dictionary = {1: 10, 2: 20, 3: 50, 4: 100, 5: 200}
## Inclusive integer markup range per goblin slot, keyed by tier number.
@export var tier_markup_min: Dictionary = {1: 1, 2: 2, 3: 5, 4: 10, 5: 20}
@export var tier_markup_max: Dictionary = {1: 1, 2: 4, 3: 8, 4: 15, 5: 30}
@export_range(1, 2147483647) var pricing_version: int = 1
## One physical 古怪金币 is worth this much G; the coin is not a second wallet.
@export_range(1, 2147483647) var coin_face_value: int = 10

## Prices and markup ranges are configuration; a broken table must fail closed.
func validate() -> bool:
	if human_cup_price < 0 or signature_first_reward < 0 or uses_per_portion < 1 or pricing_version < 1 or coin_face_value < 1:
		return false
	for tier: int in TIERS:
		if not tier_market_prices.has(tier) or not tier_markup_min.has(tier) or not tier_markup_max.has(tier):
			return false
		var price: Variant = tier_market_prices[tier]
		var low: Variant = tier_markup_min[tier]
		var high: Variant = tier_markup_max[tier]
		if not price is int or price < 0 or not low is int or not high is int:
			return false
		if low < 0 or high < low or price % uses_per_portion != 0:
			return false
	return true

func has_tier(tier: int) -> bool:
	return tier in TIERS and tier_market_prices.has(tier)

## Cost of one use of a traded portion. -1 when the tier/price is unusable.
func slot_cost(tier: int) -> int:
	if not has_tier(tier):
		return -1
	var price: int = int(tier_market_prices[tier])
	if price < 0 or price % uses_per_portion != 0:
		return -1
	return price / uses_per_portion

func markup_range(tier: int) -> Vector2i:
	if not has_tier(tier):
		return Vector2i(-1, -1)
	return Vector2i(int(tier_markup_min[tier]), int(tier_markup_max[tier]))
