class_name Ammo
extends RefCounted
## Magazine + limited reserve. Reloading pulls from the reserve; wall-buy refills and Restock top it up.
## v8 rules: a magazine reload is all-or-nothing and is lost if you switch weapons; a pump-action
## (weapon.shell_reload > 0) loads one shell at a time and can be interrupted by firing what is loaded.

var weapon: WeaponDef
var rounds: int
var reserve: int
var reload_left := 0.0
var reload_mult := 1.0  ## Quickhand Draught perk sets 0.5
var locked := false     ## the gun is inside the Overcharge Forge: it cannot fire, reload or be cancelled

func _init(w: WeaponDef) -> void:
	swap(w)

func reloading() -> bool: return locked or reload_left > 0.0
func can_fire() -> bool: return not reloading() and rounds > 0
func max_reserve() -> int: return weapon.mag_size * weapon.reserve_mags
func is_empty() -> bool: return rounds == 0 and reserve == 0
func is_full() -> bool: return rounds == weapon.mag_size and reserve == max_reserve()
func refill() -> void: rounds = weapon.mag_size; reserve = max_reserve(); reload_left = 0.0

func by_shell() -> bool: return weapon.shell_reload > 0.0
## Seconds for one reload step: the whole magazine, or a single shell on a pump-action.
func reload_step() -> float:
	return (weapon.shell_reload if by_shell() else weapon.reload_time) * reload_mult

## Uses one round. Returns true if that emptied the mag and a reload began.
func fire() -> bool:
	assert(can_fire())
	rounds -= 1
	if rounds == 0 and reserve > 0:
		reload_left = reload_step()
		return true
	return false

## Manual reload; false if already full or reloading.
func reload() -> bool:
	if reloading() or rounds >= weapon.mag_size or reserve <= 0: return false
	reload_left = reload_step()
	return true

## A shell reload with at least one shell in the tube can be cut short by pulling the trigger.
func can_interrupt() -> bool:
	return not locked and reload_left > 0.0 and by_shell() and rounds > 0

## Abandons a reload in progress (weapon switch, or firing mid shell-reload). Loaded shells are kept.
func cancel_reload() -> void:
	if not locked: reload_left = 0.0

func update(dt: float) -> void:
	if locked or reload_left <= 0.0: return
	reload_left -= dt
	while reload_left <= 0.0:
		if by_shell():
			if rounds < weapon.mag_size and reserve > 0:
				rounds += 1; reserve -= 1
			if rounds >= weapon.mag_size or reserve <= 0:
				reload_left = 0.0; return
			reload_left += reload_step()
		else:
			reload_left = 0.0
			var take := mini(weapon.mag_size - rounds, reserve)
			rounds += take; reserve -= take
			return

func swap(w: WeaponDef) -> void:
	weapon = w; locked = false; refill()
