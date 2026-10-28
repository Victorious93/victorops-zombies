class_name ZombieTypes
## Special zombie archetypes (original designs). Pure data + spawn rules so they can be unit tested.
##  sprinter: lean, fast, low HP, hunched; panting chatter is its tell.
##  brute:    armoured mini-boss every BRUTE_EVERY rounds; slow, huge, chain rattle + roar; drops RESTOCK.
##  bloater:  swollen, slow; gurgles when close, bursts into a lingering gas cloud on death or when it reaches you.

const BRUTE_EVERY := 8
const SPRINTER_FROM := 3
const BLOATER_FROM := 4

const ALL := {
	"walker":   {"hp": 1.0, "speed": 1.0, "scale": 1.0, "dmg": 1.0, "armor": 0.0, "tint": Color(1, 1, 1), "points": 0},
	"sprinter": {"hp": 0.6, "speed": 1.9, "scale": 0.9, "dmg": 0.7, "armor": 0.0, "tint": Color(0.75, 0.85, 0.7), "points": 20},
	"brute":    {"hp": 8.0, "speed": 0.75, "scale": 1.45, "dmg": 2.2, "armor": 0.5, "tint": Color(0.55, 0.5, 0.48), "points": 500},
	"warden":   {"hp": 30.0, "speed": 0.9, "scale": 1.85, "dmg": 3.0, "armor": 0.6, "tint": Color(0.45, 0.35, 0.6), "points": 2500},
	"bloater":  {"hp": 1.6, "speed": 0.7, "scale": 1.15, "dmg": 1.0, "armor": 0.0, "tint": Color(0.75, 0.9, 0.45), "points": 60},
}
const BLOATER_RADIUS := 3.2      ## burst damage radius (m)
const BLOATER_BURST := 35        ## burst damage to the player at the centre
const GAS_TIME := 6.0            ## the cloud lingers this long
const GAS_DPS := 8.0             ## player damage per second inside the cloud
const BLOATER_TRIGGER := 1.6     ## bursts on its own when this close to the player

static func is_brute_round(round: int) -> bool:
	return round >= BRUTE_EVERY and round % BRUTE_EVERY == 0

## Share of normal spawns that become sprinters / bloaters for a round.
static func sprinter_chance(round: int) -> float:
	return 0.0 if round < SPRINTER_FROM else clampf(0.08 + (round - SPRINTER_FROM) * 0.03, 0.0, 0.3)

static func bloater_chance(round: int) -> float:
	return 0.0 if round < BLOATER_FROM else clampf(0.05 + (round - BLOATER_FROM) * 0.02, 0.0, 0.18)

## Picks a type for one spawn. [roll] in 0..1. The brute is placed separately (one per brute round).
static func pick(round: int, roll: float) -> String:
	var b := bloater_chance(round)
	if roll < b: return "bloater"
	if roll < b + sprinter_chance(round): return "sprinter"
	return "walker"

static func health(type: String, base_hp: int) -> int:
	return maxi(1, int(round(base_hp * float(ALL[type].hp))))

## Damage after armour; armour shrugs off body shots but not headshots or explosives.
static func damage_taken(type: String, dmg: int, headshot: bool, explosive: bool) -> int:
	if headshot or explosive: return dmg
	return maxi(1, int(round(dmg * (1.0 - float(ALL[type].armor)))))

## Player damage from a bloater burst at [dist] metres (linear falloff).
static func burst_damage(dist: float) -> int:
	if dist >= BLOATER_RADIUS: return 0
	return int(round(BLOATER_BURST * (1.0 - dist / BLOATER_RADIUS)))

static func guaranteed_drop(type: String) -> String:
	return "restock" if type == "brute" or type == "warden" else ""

## Armoured, heavy types (brute mini-boss and the Warden boss) share most behaviour.
static func is_heavy(type: String) -> bool: return type == "brute" or type == "warden"
