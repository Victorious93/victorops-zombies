class_name BloodTrail
## v7.14 blood trails: wounded, maimed and crawling zombies leave drips/smears behind them.
## Pure rules (testable) + a fixed-size ring pool so marks are recycled, never allocated per drop.

const MAX_TRAIL := 32          ## hard cap on live trail marks (mobile budget: one shared material, no shadows)
const WOUND_FRAC := 0.6        ## below this hp fraction a walker starts to drip
const SPACING := 1.4           ## metres between marks for a badly hurt walker
const CRAWL_SPACING := 0.7     ## crawlers drag a near-continuous smear

## Metres between marks; INF when the zombie isn't hurt enough to bleed.
static func spacing(hp_frac: float, crawler: bool) -> float:
	if crawler: return CRAWL_SPACING
	if hp_frac >= WOUND_FRAC: return INF
	return lerpf(SPACING * 0.6, SPACING * 1.6, clampf(hp_frac / WOUND_FRAC, 0.0, 1.0))

static func should_drop(dist_since_last: float, hp_frac: float, crawler: bool) -> bool:
	return dist_since_last >= spacing(hp_frac, crawler)

## Mark size: crawl smears are long and wide, drips are small.
static func mark_size(hp_frac: float, crawler: bool) -> Vector2:
	if crawler: return Vector2(0.55, 1.1)
	var s := lerpf(0.45, 0.25, clampf(hp_frac / WOUND_FRAC, 0.0, 1.0))
	return Vector2(s, s * 1.3)

## Ring pool: returns the slot index for the next mark (recycles the oldest once full).
class Ring:
	var cap: int
	var next := 0
	var used := 0
	func _init(c := MAX_TRAIL) -> void: cap = maxi(1, c)
	func take() -> int:
		var i := next
		next = (next + 1) % cap
		used = mini(used + 1, cap)
		return i
