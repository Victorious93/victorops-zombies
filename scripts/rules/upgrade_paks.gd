class_name UpgradePaks
extends RefCounted
## v7.13 Upgrade Paks: short boosts that feed on kills. A pak starts at BASE seconds; every kill
## while it runs adds KILL_ADD (HEAD_ADD for headshots), never past CAP seconds in total.
## One pak at a time: grabbing the same pak tops it back up to at least BASE; a different pak
## replaces the running one (simple to read on the HUD, and no stacked multipliers to balance).
## Got as a rare zombie drop (rewards the killing that keeps it alive; no extra map clutter).

const ALL := {
	"overdrive": {"name": "OVERDRIVE", "desc": "Damage x1.6", "color": Color(1.0, 0.35, 0.2), "icon": "▲"},
	"hyperloop": {"name": "HYPERLOOP", "desc": "Fire rate x1.6", "color": Color(1.0, 0.85, 0.2), "icon": "≫"},
	"bottomless": {"name": "BOTTOMLESS", "desc": "No ammo used", "color": Color(0.3, 0.9, 1.0), "icon": "∞"},
	"quickstep": {"name": "QUICKSTEP", "desc": "Move speed x1.3", "color": Color(0.5, 1.0, 0.4), "icon": "»"},
}
const BASE := 10.0
const KILL_ADD := 1.5
const HEAD_ADD := 2.5
const CAP := 45.0
const WARN := 3.0
const DAMAGE_MULT := 1.6
const FIRE_MULT := 1.0 / 1.6
const SPEED_MULT := 1.3
const CHANCE := 0.012
const PITY_KILLS := 70

var id := ""
var time_left := 0.0
var total := 0.0          ## seconds granted so far this activation (BASE + kill time), capped at CAP
var kills_since_drop := 0

func active() -> bool: return id != "" and time_left > 0.0
func is_on(pak: String) -> bool: return active() and id == pak

func activate(pak: String) -> void:
	if is_on(pak):
		var add := maxf(0.0, BASE - time_left)
		add = minf(add, CAP - total); time_left += add; total += add
		return
	id = pak; time_left = BASE; total = BASE

## A kill while a pak runs: returns the seconds actually added (0 at the cap or with no pak).
func on_kill(headshot: bool) -> float:
	if not active(): return 0.0
	var add := minf(HEAD_ADD if headshot else KILL_ADD, CAP - total)
	if add <= 0.0: return 0.0
	time_left += add; total += add
	return add

## Ticks the timer; returns the pak id that just expired, or "".
func update(dt: float) -> String:
	if not active(): return ""
	time_left -= dt
	if time_left > 0.0: return ""
	var ended := id
	id = ""; time_left = 0.0; total = 0.0
	return ended

func warning() -> bool: return active() and time_left <= WARN
func damage_mult() -> float: return DAMAGE_MULT if is_on("overdrive") else 1.0
func fire_mult() -> float: return FIRE_MULT if is_on("hyperloop") else 1.0
func infinite_ammo() -> bool: return is_on("bottomless")
func speed_mult() -> float: return SPEED_MULT if is_on("quickstep") else 1.0

## Rare kill drop (separate from the classic power-ups): CHANCE per kill, forced after PITY_KILLS.
func roll(rng: RandomNumberGenerator) -> String:
	kills_since_drop += 1
	if rng.randf() >= CHANCE and kills_since_drop < PITY_KILLS: return ""
	kills_since_drop = 0
	var keys := ALL.keys()
	return keys[rng.randi_range(0, keys.size() - 1)]
