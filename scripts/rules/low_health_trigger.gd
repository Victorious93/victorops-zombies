class_name LowHealthTrigger
extends RefCounted
## Fires once when health drops under [low]; re-arms after recovering above [rearm].
var low: float
var rearm: float
var armed := true

func _init(p_low := 0.3, p_rearm := 0.5) -> void:
	low = p_low; rearm = p_rearm

func check(health: float, max_health: float) -> bool:
	var f := health / max_health
	if f >= rearm: armed = true
	if armed and f > 0.0 and f < low:
		armed = false
		return true
	return false
