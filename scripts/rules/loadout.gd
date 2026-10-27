class_name Loadout
extends RefCounted
## Two weapon slots (3D rule). Buying a third gun replaces the one in hand.
const MAX_SLOTS := 2
var slots: Array = []  # of Ammo
var current := 0

func _init(start: WeaponDef) -> void:
	slots = [Ammo.new(start)]

func ammo() -> Ammo: return slots[current]
func weapon() -> WeaponDef: return slots[current].weapon

func has(id: String) -> int:
	for i in slots.size():
		if slots[i].weapon.id == id: return i
	return -1

## Adds or replaces; returns the slot index now held.
func give(w: WeaponDef) -> int:
	var i := has(w.id)
	if i >= 0:
		slots[i].swap(w)
	elif slots.size() < MAX_SLOTS:
		slots.append(Ammo.new(w)); i = slots.size() - 1
	else:
		slots[current].swap(w); i = current
	current = i
	return i

func replace_current(w: WeaponDef) -> void:
	slots[current].swap(w)

func cycle() -> void:
	current = (current + 1) % slots.size()

func update(dt: float) -> void:
	for a in slots: a.update(dt)
