class_name AltAmmo
## Overcharge Forge alternate ammo + camo (original effects). Pure rules so they can be unit tested.
##  fire:   Cinder Rounds - sets the target burning (damage over time)
##  shock:  Arc Rounds    - arcs to nearby zombies and stuns them briefly
##  freeze: Rime Rounds   - slows the target; a frozen kill shatters

const FIRE := "fire"
const SHOCK := "shock"
const FREEZE := "freeze"
const KINDS := [FIRE, SHOCK, FREEZE]
const NAMES := {FIRE: "Cinder Rounds", SHOCK: "Arc Rounds", FREEZE: "Rime Rounds"}
const COLORS := {FIRE: Color(1.0, 0.45, 0.1), SHOCK: Color(0.4, 0.75, 1.0), FREEZE: Color(0.7, 0.95, 1.0)}
const PROC_CHANCE := 0.2      ## per hit
const COOLDOWN := 1.2         ## seconds between procs per weapon
const BURN_TIME := 3.0
const BURN_FRAC := 0.35       ## burn deals this share of the hit's damage per second
const CHAIN_TARGETS := 3
const CHAIN_RANGE := 6.0
const CHAIN_FRAC := 0.5
const STUN_TIME := 0.7
const SLOW_MULT := 0.35
const SLOW_TIME := 3.0

## Which alternate ammo the Forge bakes into a weapon at [tier] (0 = none). Mk.II gets one, Mk.III rotates to the next.
static func for_weapon(id: String, tier: int) -> String:
	if tier <= 0: return ""
	var base := 0
	for c in id: base += c.unicode_at(0)
	return KINDS[(base + tier - 1) % KINDS.size()]

## Whether this hit triggers the effect. [roll] in 0..1, [cd] = seconds since the last proc.
static func procs(kind: String, roll: float, cd: float) -> bool:
	return kind != "" and cd >= COOLDOWN and roll < PROC_CHANCE

static func burn_dps(hit_dmg: int) -> float: return hit_dmg * BURN_FRAC
static func chain_damage(hit_dmg: int) -> int: return maxi(1, int(hit_dmg * CHAIN_FRAC))

## Camo palette for a Forge tier: [base, accent, emission energy]. Tier 0 = no camo.
static func camo(tier: int) -> Array:
	match tier:
		1: return [Color(0.25, 0.12, 0.45), Color(0.55, 0.3, 1.0), 1.2]
		2: return [Color(0.4, 0.06, 0.3), Color(1.0, 0.35, 0.9), 2.0]
	return []
