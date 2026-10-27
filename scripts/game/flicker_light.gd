extends OmniLight3D
## Randomly flickering facility light.
var base := 1.0
var t := 0.0
var rate := 0.0

func _ready() -> void:
	base = light_energy
	rate = randf_range(0.05, 0.25)

func _process(dt: float) -> void:
	t -= dt
	if t <= 0.0:
		t = randf_range(0.03, 0.4) if randf() < rate else randf_range(0.5, 3.0)
		light_energy = base * (randf_range(0.0, 0.35) if randf() < rate * 2.0 else randf_range(0.85, 1.05))
