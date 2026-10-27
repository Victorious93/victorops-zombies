class_name Ammo
extends RefCounted
## Magazine + reload state. Reserve ammo is unlimited (original rule); reloading just takes time.

var weapon: WeaponDef
var rounds: int
var reload_left := 0.0
var reload_mult := 1.0  ## Quickhand Draught perk sets 0.5

func _init(w: WeaponDef) -> void:
	swap(w)

func reloading() -> bool: return reload_left > 0.0
func can_fire() -> bool: return not reloading() and rounds > 0

## Uses one round. Returns true if that emptied the mag and a reload began.
func fire() -> bool:
	assert(can_fire())
	rounds -= 1
	if rounds == 0:
		reload_left = weapon.reload_time * reload_mult
		return true
	return false

## Manual reload; false if already full or reloading.
func reload() -> bool:
	if reloading() or rounds >= weapon.mag_size: return false
	reload_left = weapon.reload_time * reload_mult
	return true

func update(dt: float) -> void:
	if not reloading(): return
	reload_left -= dt
	if reload_left <= 0.0:
		reload_left = 0.0
		rounds = weapon.mag_size

func swap(w: WeaponDef) -> void:
	weapon = w; rounds = w.mag_size; reload_left = 0.0
