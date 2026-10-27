class_name PowerUps
extends RefCounted
## Kill drops (original names). Timed ones last 30 s. At most MAX_PER_ROUND drops per round;
## each kill rolls CHANCE, and a "pity" drop is forced after PITY_KILLS kills without one.
## The drop order cycles through a shuffled bag so every type shows up.

const ALL := {
	"restock": {"name": "RESTOCK", "desc": "All weapons and grenades refilled", "color": Color(0.3, 1.0, 0.4), "timed": false},
	"onetouch": {"name": "ONE TOUCH", "desc": "Every hit kills", "color": Color(1.0, 0.95, 0.9), "timed": true},
	"doublepay": {"name": "DOUBLE PAY", "desc": "All points x2", "color": Color(1.0, 0.85, 0.2), "timed": true},
	"blackout": {"name": "BLACKOUT", "desc": "Every zombie drops (+400)", "color": Color(1.0, 0.35, 0.15), "timed": false},
	"handyman": {"name": "HANDYMAN", "desc": "Every window reboarded (+200)", "color": Color(0.4, 0.7, 1.0), "timed": false},
}
## Original glyph icons drawn on the floating pickup and the HUD timers.
const ICONS := {"restock": "▮▮", "onetouch": "☠", "doublepay": "×2", "blackout": "✹", "handyman": "▤"}
const DURATION := 30.0
const PICKUP_LIFE := 25.0
const MAX_PER_ROUND := 4
const CHANCE := 0.025
const PITY_KILLS := 40
const BLACKOUT_POINTS := 400
const HANDYMAN_POINTS := 200

var bag: Array = []
var dropped_this_round := 0
var kills_since_drop := 0
var timers := {}  ## id -> seconds left (timed power-ups only)

func on_round_start() -> void:
	dropped_this_round = 0

## Called per kill; returns a power-up id to drop, or "".
func roll(rng: RandomNumberGenerator) -> String:
	kills_since_drop += 1
	if dropped_this_round >= MAX_PER_ROUND: return ""
	if rng.randf() >= CHANCE and kills_since_drop < PITY_KILLS: return ""
	if bag.is_empty():
		bag = ALL.keys()
		for i in range(bag.size() - 1, 0, -1):
			var j := rng.randi_range(0, i); var tmp = bag[i]; bag[i] = bag[j]; bag[j] = tmp
	dropped_this_round += 1; kills_since_drop = 0
	return bag.pop_back()

## Starts a timed effect (refreshes if already running).
func activate(id: String) -> void:
	if ALL[id].timed: timers[id] = DURATION

func active(id: String) -> bool: return timers.get(id, 0.0) > 0.0

## Ticks timers; returns ids that just expired.
func update(dt: float) -> Array:
	var ended := []
	for id in timers.keys():
		timers[id] -= dt
		if timers[id] <= 0.0: timers.erase(id); ended.append(id)
	return ended
