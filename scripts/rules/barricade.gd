class_name Barricade
extends RefCounted
## Window barricade of planks. Zombies tear planks off; players repair them for points.

var max_planks: int
var plank_hp: int
var hp: int

func _init(p_max_planks: int = 6, p_plank_hp: int = 50) -> void:
	max_planks = p_max_planks; plank_hp = p_plank_hp; hp = max_planks * plank_hp

func max_hp() -> int: return max_planks * plank_hp
func is_broken() -> bool: return hp <= 0
func planks() -> int: return (hp + plank_hp - 1) / plank_hp

func damage(amount: int) -> void:
	assert(amount >= 0)
	hp = maxi(0, hp - amount)

func repair_plank() -> bool:
	if hp >= max_hp(): return false
	hp = mini(max_hp(), (hp / plank_hp + 1) * plank_hp)
	return true

func repair_planks(n: int) -> int:
	var done := 0
	while done < n and repair_plank(): done += 1
	return done

func repair_all() -> int: return repair_planks(max_planks)
