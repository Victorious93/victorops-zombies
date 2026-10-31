class_name Gait
## Zombie movement tiers by round: early rounds shamble, the middle rounds mix in joggers,
## later rounds are mostly sprinting hordes. Pure numbers so they can be tested.

enum Tier { WALK, JOG, SPRINT }
const SPEED := {Tier.WALK: 1.05, Tier.JOG: 2.2, Tier.SPRINT: 3.6}

## Share of [walk, jog, sprint] for a round. Always sums to 1.
static func mix(round_no: int) -> Array:
	var r := maxi(round_no, 1)
	if r <= 2: return [1.0, 0.0, 0.0]
	var jog := clampf(0.2 + 0.12 * (r - 3), 0.0, 0.55)
	var sprint := clampf(0.15 * (r - 5), 0.0, 0.85) if r >= 6 else 0.0
	jog = minf(jog, 1.0 - sprint)
	var walk := maxf(0.0, 1.0 - jog - sprint)
	return [walk, jog, sprint]

## Pick a tier for a zombie given a uniform random roll in [0,1).
static func pick(round_no: int, roll: float) -> int:
	var m := mix(round_no)
	if roll < m[0]: return Tier.WALK
	if roll < m[0] + m[1]: return Tier.JOG
	return Tier.SPRINT

## Base speed for a tier, nudged up slightly each round past 10 (capped) so late rounds stay scary.
static func speed(tier: int, round_no: int) -> float:
	return SPEED[tier] * (1.0 + clampf((round_no - 10) * 0.015, 0.0, 0.15))

static func anim(tier: int) -> String:
	return "Walk" if tier == Tier.WALK else "Run"

## Animation playback speed so feet roughly match ground speed.
static func anim_speed(tier: int) -> float:
	match tier:
		Tier.JOG: return 1.5
		Tier.SPRINT: return 1.0
	return 1.0

## v7.12 sprint ramp: from round RAMP_ROUND a walker breaks into a jog after jog_after(r) seconds of
## chasing, and from SPRINT_ROUND a jogger breaks into a sprint after sprint_after(r) seconds.
const RAMP_ROUND := 4
const SPRINT_ROUND := 7
static func jog_after(r: int) -> float: return maxf(6.0, 22.0 - r)
static func sprint_after(r: int) -> float: return maxf(8.0, 30.0 - r)
static func ramp(tier: int, round_no: int, chase_t: float) -> int:
	if round_no < RAMP_ROUND: return tier
	if tier == Tier.WALK and chase_t >= jog_after(round_no): return Tier.JOG
	if tier == Tier.JOG and round_no >= SPRINT_ROUND and chase_t >= jog_after(round_no) + sprint_after(round_no): return Tier.SPRINT
	return tier
## Forward lean so a sprinter reads differently from a jogger at a glance (the run cycle is shared).
static func lean(tier: int) -> float:
	match tier:
		Tier.JOG: return 0.12
		Tier.SPRINT: return 0.32
	return 0.0
