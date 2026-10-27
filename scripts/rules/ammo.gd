class_name Ammo
extends RefCounted
## Magazine + limited reserve. Reloading pulls from the reserve; wall-buy refills and Restock top it up.

var weapon: WeaponDef
var rounds: int
var reserve: int
var reload_left := 0.0
var reload_mult := 1.0  ## Quickhand Draught perk sets 0.5

func _init(w: WeaponDef) -> void:
	swap(w)

func reloading() -> bool: return reload_left > 0.0
func can_fire() -> bool: return not reloading() and rounds > 0
func max_reserve() -> int: return weapon.mag_size * weapon.reserve_mags
func is_empty() -> bool: return rounds == 0 and reserve == 0
func is_full() -> bool: return rounds == weapon.mag_size and reserve == max_reserve()
func refill() -> void: rounds = weapon.mag_size; reserve = max_reserve(); reload_left = 0.0

## Uses one round. Returns true if that emptied the mag and a reload began.
func fire() -> bool:
	assert(can_fire())
	rounds -= 1
	if rounds == 0 and reserve > 0:
		reload_left = weapon.reload_time * reload_mult
		return true
	return false

## Manual reload; false if already full or reloading.
func reload() -> bool:
	if reloading() or rounds >= weapon.mag_size or reserve <= 0: return false
	reload_left = weapon.reload_time * reload_mult
	return true

func update(dt: float) -> void:
	if not reloading(): return
	reload_left -= dt
	if reload_left <= 0.0:
		reload_left = 0.0
		var take := mini(weapon.mag_size - rounds, reserve)
		rounds += take; reserve -= take

func swap(w: WeaponDef) -> void:
	weapon = w; refill()
