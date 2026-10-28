class_name TouchLayout
## Thumb-arc layout for the right-hand touch buttons. Buttons sit on two rings around FIRE so
## nothing overlaps and every action is one short thumb move from the fire button.

const HIT_PAD := 1.15  ## touch hit area is a bit bigger than the drawn circle
## name: [ring, angle in degrees (0 = right, 90 = up), radius, label]
const RIGHT := {
	"ads": [1, 190.0, 55.0, "AIM"],
	"reload": [1, 145.0, 50.0, "RLD"],
	"use": [1, 100.0, 55.0, "USE"],
	"swap": [1, 55.0, 45.0, "SWAP"],
	"knife": [2, 160.0, 42.0, "KNIFE"],
	"skill": [2, 135.0, 45.0, "SKILL"],
	"grenade": [2, 70.0, 42.0, "NADE"],
}

## Returns name -> [center, radius, label] in pixels for a screen of [s].
static func buttons(s: Vector2, fire_scale := 1.3) -> Dictionary:
	var u := s.y / 720.0
	var rf := 85.0 * fire_scale
	var fc := Vector2(s.x - 170 * u, s.y - 190 * u)
	var out := {"fire": [fc, rf * u, "FIRE"]}
	for n in RIGHT:
		var d: Array = RIGHT[n]
		var r: float = d[2]
		# rings are spaced by the padded touch radii so hit areas never overlap
		var ring := (rf + r) * HIT_PAD + 4.0
		if d[0] == 2: ring = (rf + 110.0 + r) * HIT_PAD + 8.0
		var a := deg_to_rad(d[1])
		out[n] = [fc + Vector2(cos(a), -sin(a)) * ring * u, r * u, d[3]]
	out["sprint"] = [Vector2(330 * u, s.y - 300 * u), 45 * u, "RUN"]
	out["pause"] = [Vector2(s.x / 2, 40 * u), 28 * u, "II"]
	return out

## Pairs of buttons whose touch areas overlap (should be empty).
static func overlaps(b: Dictionary) -> Array:
	var bad := []
	var names := b.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var x: Array = b[names[i]]; var y: Array = b[names[j]]
			if x[0].distance_to(y[0]) < (x[1] + y[1]) * HIT_PAD: bad.append([names[i], names[j]])
	return bad
