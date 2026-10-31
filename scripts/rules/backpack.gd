class_name Backpack
extends RefCounted
## v7.13 Backpack: SLOTS gadget slots, each stacking up to STACK of one gadget. A pickup tops up a
## slot already holding that gadget, else takes the first free slot; a full bag rejects it.

const SLOTS := 3
const STACK := 2
const GADGETS := {
	"sentry": {"name": "Sentry Pod", "desc": "Auto-turret, 20 s", "color": Color(1.0, 0.6, 0.2), "icon": "Ψ"},
	"aegis": {"name": "Aegis Bubble", "desc": "Blocks hits for 8 s", "color": Color(0.4, 0.8, 1.0), "icon": "◎"},
	"pulse": {"name": "Pulse Charge", "desc": "EMP: stuns and slows", "color": Color(0.35, 0.6, 1.0), "icon": "ϟ"},
}
## Gadget tuning (pure numbers, used by game.gd and the tests).
const SENTRY_LIFE := 20.0
const SENTRY_AMMO := 80
const SENTRY_INTERVAL := 0.22
const SENTRY_DAMAGE := 120
const SENTRY_RANGE := 14.0
const AEGIS_TIME := 8.0
const AEGIS_HITS := 6
const PULSE_RADIUS := 6.5
const PULSE_STUN := 2.0       ## frozen in place (no swings)
const PULSE_SLOW := 5.0       ## then slowed until 5 s
const DROP_CHANCE := 0.008
const LOCKER_PRICE := 1500

## EMP reach test (flat distance), shared by game.emp_blast and the tests.
static func in_pulse(center: Vector3, pos: Vector3) -> bool:
	var off := pos - center; off.y = 0.0
	return off.length() <= PULSE_RADIUS

var slots: Array = []   ## each {id, count}; empty slot = {}
var selected := 0

func _init() -> void:
	for i in SLOTS: slots.append({})

func is_full_for(gid: String) -> bool:
	for s in slots:
		if s.is_empty() or (s.id == gid and s.count < STACK): return false
	return true

## Returns the slot index the gadget went into, or -1 when the bag is full.
func add(gid: String) -> int:
	for i in slots.size():
		if not slots[i].is_empty() and slots[i].id == gid and slots[i].count < STACK:
			slots[i].count += 1; return i
	for i in slots.size():
		if slots[i].is_empty():
			slots[i] = {id = gid, count = 1}; return i
	return -1

## Consumes one gadget from slot i; returns its id ("" if empty).
func use(i := -1) -> String:
	if i < 0: i = first_filled()
	if i < 0 or i >= slots.size() or slots[i].is_empty(): return ""
	var gid: String = slots[i].id
	slots[i].count -= 1
	if slots[i].count <= 0: slots[i] = {}
	return gid

func first_filled() -> int:
	for i in slots.size():
		if not slots[i].is_empty(): return i
	return -1

## v7.14: slot holding gadget gid (-1 if none) — lets the sim bot pick a specific gadget.
func slot_of(gid: String) -> int:
	for i in slots.size():
		if not slots[i].is_empty() and slots[i].id == gid: return i
	return -1

func count(gid: String) -> int:
	var n := 0
	for s in slots:
		if not s.is_empty() and s.id == gid: n += s.count
	return n

## Personal barrier: absorbs whole hits until time or hits run out.
class Aegis:
	var time_left := 0.0
	var hits_left := 0
	func start() -> void: time_left = Backpack.AEGIS_TIME; hits_left = Backpack.AEGIS_HITS
	func up() -> bool: return time_left > 0.0 and hits_left > 0
	## Returns the damage that gets through (0 while the shield is up).
	func absorb(d: float) -> float:
		if not up(): return d
		hits_left -= 1
		return 0.0
	## Returns true on the tick it drops.
	func update(dt: float) -> bool:
		if time_left <= 0.0: return false
		time_left -= dt
		if time_left <= 0.0 or hits_left <= 0: time_left = 0.0; return true
		return false

## Auto-turret state: limited life and ammo.
class Sentry:
	var life := Backpack.SENTRY_LIFE
	var ammo := Backpack.SENTRY_AMMO
	var cd := 0.0
	func alive() -> bool: return life > 0.0 and ammo > 0
	## Ticks; returns true when it may fire this frame (caller spends the shot via fire()).
	func update(dt: float) -> bool:
		life -= dt; cd -= dt
		return alive() and cd <= 0.0
	func fire() -> void: ammo -= 1; cd = Backpack.SENTRY_INTERVAL
