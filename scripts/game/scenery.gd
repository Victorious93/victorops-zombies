class_name Scenery
extends RefCounted
## Victorious Framework town dressing for Ashgrove's Main Street: everything that tells the story of an
## evacuation gone wrong. Diner furniture, the garage bay, stripped store shelves, abandoned vehicles,
## the army blockade, the courtyard evacuation point, signage, decals and the distant burning skyline.
## Mobile-safe: static pieces are batched through TownKit, clutter is MultiMesh, distant scenery is a
## few unshaded cards, effects are bounded. Deterministic (seeded) so screenshots are comparable.
## Collision rule: only things you would expect to block you get a collider, and combat lanes, doors,
## windows, machines and quest pick-ups are kept clear.

var map: FacilityMap
var k: TownKit
var m: Dictionary
var rng := RandomNumberGenerator.new()
static var _decal_tex := {}

func _init(p_map: FacilityMap) -> void:
	map = p_map; k = p_map.kit; m = p_map.mats; rng.seed = 7707

func build() -> void:
	_diner()
	_alley()
	_garage()
	_store()
	_street()
	_court()
	_outskirts()
	_skyline()
	_decals()
	_area_moods()
	_rubble()
	_weeds()

# ---------------------------------------------------------------- helpers
func _p(name: String, size: float, pos: Vector3, rot := 0.0, by_h := false, collide := false) -> Node3D:
	return map.prop(("props/" + name) if ResourceLoader.exists("res://assets/models/props/%s.glb" % name) else name, size, pos, rot if rot != 0.0 else rng.randf_range(-PI, PI), by_h, collide)

## Small always-on practical light (lantern, candle, work lamp): no shadows, short range.
func _practical(pos: Vector3, col: Color, energy: float, rng_m: float, flicker := false) -> OmniLight3D:
	var l := OmniLight3D.new(); l.light_color = col; l.light_energy = energy; l.omni_range = rng_m
	l.omni_attenuation = 1.3; l.position = pos; l.light_specular = 0.3
	if flicker: l.set_script(load("res://scripts/game/flicker_light.gd"))
	map.add_child(l)
	return l

func _carton_pile(at: Vector3, n: int, spread := 0.7) -> void:
	for i in n:
		var s := Vector3(rng.randf_range(0.3, 0.55), rng.randf_range(0.22, 0.42), rng.randf_range(0.3, 0.5))
		k.box(m.carton, s, at + Vector3(rng.randf_range(-spread, spread), s.y * 0.5 + (0.4 if i % 3 == 2 else 0.0), rng.randf_range(-spread, spread)), rng.randf_range(-0.6, 0.6))

func _luggage(at: Vector3, n: int) -> void:
	var cols := [m.awn_red, m.awn_green, m.dark, m.carton, m.tin]
	for i in n:
		var s := Vector3(rng.randf_range(0.45, 0.7), rng.randf_range(0.2, 0.42), rng.randf_range(0.28, 0.4))
		k.box(cols[i % cols.size()], s, at + Vector3(rng.randf_range(-0.8, 0.8), s.y * 0.5, rng.randf_range(-0.5, 0.5)), rng.randf_range(-0.8, 0.8))

# ---------------------------------------------------------------- Victory Diner
func _diner() -> void:
	k.outdoor = false
	# counter + back bar along the east wall (one solid block: no dead-end aisle to get trapped in)
	map.collider(Vector3(4.15, 1.1, 4.4), Vector3(7.72, 0.55, -4.4))
	k.box(m.diner_red, Vector3(0.7, 1.0, 4.4), Vector3(6.75, 0.5, -4.4))
	k.box(m.chrome, Vector3(0.74, 0.06, 4.44), Vector3(6.75, 0.3, -4.4))
	k.box(m.formica, Vector3(0.95, 0.06, 4.5), Vector3(6.7, 1.04, -4.4))
	k.box(m.chrome, Vector3(0.99, 0.03, 4.54), Vector3(6.7, 1.0, -4.4))
	k.box(m.steel, Vector3(0.9, 0.95, 4.4), Vector3(9.3, 0.475, -4.4))            # back bar
	k.box(m.steel, Vector3(0.5, 0.04, 4.4), Vector3(9.5, 1.5, -4.4)); k.box(m.steel, Vector3(0.5, 0.04, 4.4), Vector3(9.5, 1.95, -4.4))
	k.box(m.dark, Vector3(0.06, 0.9, 2.2), Vector3(9.76, 1.55, -5.2))             # kitchen pass-through
	k.box(m.red_glow, Vector3(0.05, 0.06, 2.0), Vector3(9.72, 1.96, -5.2), 0.0, Vector2.ZERO, false)   # heat lamps still glowing
	k.box(m.chrome, Vector3(0.36, 0.5, 0.3), Vector3(9.3, 1.2, -3.0)); k.cyl(m.chrome, 0.11, 0.42, Vector3(9.3, 1.16, -3.6), 8)   # coffee machine + urn
	for i in 4:
		k.stool(m, Vector3(5.95, 0, -6.0 + i * 1.07), false)
	k.stool(m, Vector3(4.9, 0, -2.6), true)
	for i in 6: k.cyl(m.cream, 0.05, 0.1, Vector3(6.6 + (i % 2) * 0.2, 1.12, -6.2 + i * 0.7), 6, false)   # mugs left mid-shift
	k.box(m.cream, Vector3(0.3, 0.02, 0.22), Vector3(6.7, 1.08, -3.3), 0.3, Vector2.ZERO, false)
	# booths under the west windows
	map.collider(Vector3(1.4, 1.1, 4.0), Vector3(-9.1, 0.55, -7.4))
	k.booth(m, Vector3(-9.78, 0, -8.4), Vector3(0, 0, 1), Vector3(1, 0, 0))
	k.booth(m, Vector3(-9.78, 0, -6.4), Vector3(0, 0, 1), Vector3(1, 0, 0))
	# overturned tables and scattered chairs: people left in a hurry
	map.collider(Vector3(0.5, 0.9, 1.15), Vector3(-5.2, 0.45, -0.8), 0.5)
	k.table(m, Vector3(-5.2, 0, -0.8), 0.5 + PI / 2, true)
	map.collider(Vector3(1.1, 0.8, 0.75), Vector3(2.8, 0.4, -4.4), 0.2)
	k.table(m, Vector3(2.8, 0, -4.4), 0.2)
	k.chair(m, Vector3(1.9, 0, -3.6), 2.2, true); k.chair(m, Vector3(3.6, 0, -5.2), 0.4); k.chair(m, Vector3(-6.4, 0, -1.6), 1.0, true)
	k.chair(m, Vector3(-8.6, 0, 4.4), 2.6, true); k.chair(m, Vector3(8.7, 0, 3.0), -0.6)
	for i in 3: k.cyl(m.cream, 0.11, 0.015, Vector3(2.55 + i * 0.25, 0.795, -4.5 + (i % 2) * 0.2), 8, false)   # plates
	# walls: neon above the counter, menu, notices taped up before the evacuation
	k.banner("diner", Vector3(9.74, 3.1, -4.4), Vector3(-1, 0, 0), 5.2, m, true)
	k.poster("special", Vector3(9.74, 2.3, -1.9), Vector3(-1, 0, 0), 0.8, m)
	k.poster("evac_notice", Vector3(-1.9, 1.7, -9.74), Vector3(0, 0, 1), 0.62, m, 0.04)
	k.poster("infection", Vector3(2.0, 1.7, -9.74), Vector3(0, 0, 1), 0.6, m, -0.05)
	k.poster("missing", Vector3(9.74, 1.7, 2.4), Vector3(-1, 0, 0), 0.5, m, 0.07)
	k.poster("missing", Vector3(9.74, 1.62, 3.0), Vector3(-1, 0, 0), 0.5, m, -0.04)
	k.banner("open", Vector3(0.4, 3.35, 9.74), Vector3(0, 0, -1), 2.4, m, true)
	# wainscot + chair rail tie the room together
	for w in [[Vector3(19.5, 0.1, 0.05), Vector3(0, 1.05, -9.77)], [Vector3(0.05, 0.1, 19.5), Vector3(9.77, 1.05, 0)]]:
		k.box(m.diner_red, w[0], w[1], 0.0, Vector2.ZERO, false)
	# battery lanterns: the warm pools the survivors left burning
	k.box(m.amber_glow, Vector3(0.12, 0.2, 0.12), Vector3(6.7, 1.17, -4.9), 0.0, Vector2.ZERO, false)
	_practical(Vector3(6.4, 1.6, -4.9), Color(1.0, 0.72, 0.42), 1.5, 7.5, true)
	k.box(m.amber_glow, Vector3(0.12, 0.2, 0.12), Vector3(-9.0, 0.9, -7.4), 0.0, Vector2.ZERO, false)
	_practical(Vector3(-8.6, 1.4, -7.4), Color(1.0, 0.72, 0.42), 1.1, 6.0)
	_p("debris_papers", 1.2, Vector3(-2, 0, -3)); _p("debris_papers", 1.0, Vector3(3, 0, 4.6))
	# outside the front door: the diner's back-of-house sign faces the alley
	k.outdoor = true
	k.banner("diner", Vector3(-4.6, 3.3, -10.26), Vector3(0, 0, -1), 3.6, m)
	var bulb := k.wall_lamp(m, Vector3(0, 3.45, -10.24), Vector3(0, 0, -1), m.amber_glow)
	_practical(bulb, Color(1.0, 0.7, 0.4), 1.2, 6.5)
	for u in [Vector3(-5, 0, 4), Vector3(5.5, 0, -3)]:   # rooftop plant seen from the alley and street
		k.box(m.steel, Vector3(1.6, 0.9, 1.2), u + Vector3(0, FacilityMap.H + 1.15, 0)); k.cyl(m.trim, 0.22, 1.3, u + Vector3(1.4, FacilityMap.H + 1.35, 0.2), 8)

# ---------------------------------------------------------------- Back Alley
func _alley() -> void:
	k.outdoor = true
	# towable generator (the power switch is mounted on its control panel) + fuel
	map.collider(Vector3(4, 2.4, 2), Vector3(0, 1.2, -24.5))
	k.box(m.corr_olive, Vector3(3.9, 1.7, 1.9), Vector3(0, 1.25, -24.5), 0.0, Vector2(1.3, 1.7))
	k.box(m.trim, Vector3(4.1, 0.14, 2.0), Vector3(0, 0.38, -24.5)); k.box(m.trim, Vector3(4.0, 0.1, 2.0), Vector3(0, 2.14, -24.5))
	for sx: float in [-1.3, 1.3]: k.cyl(m.dark, 0.36, 0.3, Vector3(sx, 0.36, -23.55), 10, true, -1.0, Vector3(PI / 2, 0, 0))
	k.cyl(m.rust, 0.09, 1.1, Vector3(-1.5, 2.7, -24.9), 8); k.box(m.trim, Vector3(1.6, 0.1, 0.1), Vector3(-2.7, 0.45, -24.5))   # exhaust, tow bar
	k.box(m.dark, Vector3(1.2, 0.5, 0.05), Vector3(1.0, 1.5, -23.52)); k.box(m.amber_glow, Vector3(0.1, 0.06, 0.03), Vector3(0.6, 1.62, -23.49), 0.0, Vector2.ZERO, false)
	k.cable(m.dark, Vector3(1.9, 1.0, -24.2), Vector3(9.7, 3.6, -19.4), 0.9, 0.05); k.cable(m.dark, Vector3(-1.0, 2.1, -24.2), Vector3(0, 3.9, -10.3), 0.8, 0.05)
	_p("gas_tank", 1.5, Vector3(-3.3, 0, -24.7), 0.01, true, true)
	_p("barrel", 0.95, Vector3(5, 0, -24.6), 0.01, true, true); _p("barrel", 0.95, Vector3(5.8, 0, -25.0), 0.01, true, true)
	# service-lane clutter kept against the walls
	_p("dumpster", 2.1, Vector3(-6.4, 0, -11.3), PI, false, true); _p("dumpster", 2.1, Vector3(5.6, 0, -11.3), PI + 0.06, false, true)
	_p("pallet_broken", 1.3, Vector3(-8.4, 0, -12.6)); _p("tires", 1.1, Vector3(8.6, 0, -24.6), 0.01, false, true)
	_p("cardboard_boxes", 1.2, Vector3(-3.4, 0, -11.0), 0.3); _p("trashcan", 0.9, Vector3(8.9, 0, -12.2), 0.01, true, true)
	_p("traffic_barrier", 1.8, Vector3(-6.2, 0, -16.4), 1.2, false, true)
	_p("debris_pile", 1.4, Vector3(8.6, 0, -15.0)); _p("debris_papers", 1.1, Vector3(1.5, 0, -14))
	fire_barrel(Vector3(6.6, 0, -21.4))
	# fire escape on the tenement, laundry no one came back for, the garage's painted side sign
	for lv in 2:
		var y := 4.3 + lv * 3.4
		k.box(m.trim, Vector3(1.1, 0.06, 4.4), Vector3(-9.2, y, -22.0)); k.box(m.trim, Vector3(0.04, 0.9, 4.4), Vector3(-8.68, y + 0.45, -22.0), 0.0, Vector2.ZERO, false)
		for z: float in [-24.1, -19.9]: k.box(m.trim, Vector3(1.1, 0.9, 0.04), Vector3(-9.2, y + 0.45, z), 0.0, Vector2.ZERO, false)
		k.box(m.trim, Vector3(0.06, 3.5, 0.5), Vector3(-9.0, y + 1.7 - (3.4 if lv == 0 else 0.0) * 0.0, -23.6 + lv * 3.2), 0.0, Vector2.ZERO, false, Vector3(0.5, 0, 0))
	k.box(m.trim, Vector3(0.06, 1.6, 0.5), Vector3(-9.0, 3.4, -20.3), 0.0, Vector2.ZERO, false)   # drop ladder, stuck half down
	for row in [[-14.6, 5.4], [-20.6, 6.3]]:
		k.cable(m.dark, Vector3(-9.7, row[1], row[0]), Vector3(9.7, row[1] - 0.5, row[0] + 0.6), 0.5, 0.02)
		for i in 5:
			var t := 0.18 + i * 0.15
			var cm: Material = [m.cream, m.sandbag, m.canvas, m.cream, m.awn_green][i]
			k.box(cm, Vector3(rng.randf_range(0.5, 0.9), rng.randf_range(0.6, 1.0), 0.02), Vector3(lerpf(-9.7, 9.7, t), row[1] - 0.25 * t - 0.75, row[0] + 0.6 * t), 0.03, Vector2.ZERO, false)
	k.banner("garage", Vector3(9.74, 3.3, -14.0), Vector3(-1, 0, 0), 4.6, m)
	var b2 := k.wall_lamp(m, Vector3(9.76, 3.5, -18.0), Vector3(-1, 0, 0), m.amber_glow)
	_practical(b2, Color(1.0, 0.7, 0.4), 1.2, 6.5, true)
	k.poster("evac_notice", Vector3(-9.74, 1.7, -12.4), Vector3(1, 0, 0), 0.6, m, 0.05)
	k.poster("missing", Vector3(2.2, 1.6, -10.26), Vector3(0, 0, -1), 0.5, m, -0.06)
	# drain pipes down the diner's back wall
	for x: float in [-8.6, 8.4]: k.cyl(m.rust, 0.07, FacilityMap.H, Vector3(x, FacilityMap.H / 2.0, -10.34), 6)

# ---------------------------------------------------------------- Hollis Auto Repair
func _garage() -> void:
	k.outdoor = false
	# a customer's car left on the two-post lift: the bay you circle
	_p("sports_car", 4.2, Vector3(14.6, 1.25, -17.6), PI / 2, false, true)
	for sx: float in [-1.25, 1.25]:
		map.collider(Vector3(0.3, 2.6, 0.4), Vector3(14.6 + sx, 1.3, -17.6))
		k.box(m.corr_blue, Vector3(0.26, 2.6, 0.36), Vector3(14.6 + sx, 1.3, -17.6))
		k.box(m.steel, Vector3(0.9, 0.1, 0.16), Vector3(14.6 + sx * 0.66, 1.2, -16.9), sx * 0.5); k.box(m.steel, Vector3(0.9, 0.1, 0.16), Vector3(14.6 + sx * 0.66, 1.2, -18.3), -sx * 0.5)
	k.box(m.steel, Vector3(2.8, 0.14, 0.2), Vector3(14.6, 2.66, -17.6))
	k.box(m.paint_yellow, Vector3(0.1, 0.012, 5.4), Vector3(12.6, 0.045, -17.6), 0.0, Vector2.ZERO, false); k.box(m.paint_yellow, Vector3(0.1, 0.012, 5.4), Vector3(16.6, 0.045, -17.6), 0.0, Vector2.ZERO, false)
	# workbench + pegboard on the west wall
	map.collider(Vector3(0.8, 0.95, 3.6), Vector3(10.6, 0.48, -12.6))
	k.box(m.wood, Vector3(0.8, 0.08, 3.6), Vector3(10.6, 0.92, -12.6))
	for z: float in [-14.2, -11.0]: k.box(m.steel, Vector3(0.7, 0.88, 0.1), Vector3(10.6, 0.44, z))
	k.box(m.steel, Vector3(0.7, 0.04, 3.4), Vector3(10.6, 0.3, -12.6))
	k.box(m.carton, Vector3(0.04, 1.1, 3.2), Vector3(10.24, 1.9, -12.6))
	for i in 7:
		k.box(m.steel if i % 2 == 0 else m.tin, Vector3(0.03, rng.randf_range(0.25, 0.55), 0.07), Vector3(10.28, 1.9 + rng.randf_range(-0.2, 0.2), -14.0 + i * 0.45), 0.0, Vector2.ZERO, false, Vector3(rng.randf_range(-0.3, 0.3), 0, 0))
	k.box(m.tin, Vector3(0.3, 0.26, 0.5), Vector3(10.6, 1.09, -13.6)); k.box(m.steel, Vector3(0.22, 0.2, 0.3), Vector3(10.65, 1.06, -11.6))   # toolbox, vise
	# the Forge's corner: welding rig and gas bottles
	for i in 2: k.cyl(m.corr_olive if i == 0 else m.corr_red, 0.14, 1.4, Vector3(20.0 + i * 0.36, 0.7, -25.4), 8)
	k.cable(m.dark, Vector3(20.2, 1.3, -25.3), Vector3(18.8, 0.6, -24.6), 0.3, 0.03)
	map.collider(Vector3(0.9, 1.4, 0.5), Vector3(20.2, 0.7, -25.4))
	# stock: parts shelves, tyres, oil drums, a roller shutter rusted shut onto Main Street
	_p("shelf", 2.0, Vector3(25.2, 0, -18), PI / 2, true, true); _p("shelf", 2.0, Vector3(25.2, 0, -21), PI / 2, true, true)
	_p("tires", 1.2, Vector3(11.2, 0, -24.8), 0.01, false, true); _p("tires", 1.0, Vector3(24.9, 0, -24.6), 0.6, false, true)
	_p("barrel", 0.95, Vector3(11.0, 0, -21.2), 0.01, true, true); _p("barrel_explosive", 0.95, Vector3(16.2, 0, -25.0), 0.01, true, true)
	_p("cardboard_boxes", 1.1, Vector3(24.6, 0, -15.4), 0.4); _p("debris_papers", 1.0, Vector3(19, 0, -13))
	k.box(m.corr, Vector3(0.1, 3.2, 4.6), Vector3(25.74, 1.6, -13.2), 0.0, Vector2(1.2, 1.6)); k.box(m.trim, Vector3(0.14, 0.3, 4.9), Vector3(25.74, 3.35, -13.2))
	k.poster("infection", Vector3(13.4, 1.8, -10.26), Vector3(0, 0, -1), 0.6, m, 0.04)
	# an orange work lamp on a stand still running off a car battery
	k.cyl(m.trim, 0.03, 1.5, Vector3(12.2, 0.75, -22.6), 6); k.box(m.amber_glow, Vector3(0.3, 0.2, 0.1), Vector3(12.2, 1.56, -22.6), 0.6, Vector2.ZERO, false)
	_practical(Vector3(12.5, 1.6, -22.3), Color(1.0, 0.66, 0.34), 1.6, 8.0)
	k.outdoor = true
	k.box(m.corr, Vector3(0.1, 3.2, 4.6), Vector3(26.26, 1.6, -13.2), 0.0, Vector2(1.2, 1.6)); k.box(m.trim, Vector3(0.2, 0.3, 5.0), Vector3(26.28, 3.35, -13.2))
	k.banner("garage", Vector3(26.3, 4.25, -13.2), Vector3(1, 0, 0), 5.4, m)

# ---------------------------------------------------------------- Mercer's General Store
func _store() -> void:
	k.outdoor = false
	for sx: float in [14.0, 18.0]:   # two stripped aisles north of the through-route
		map.collider(Vector3(0.9, 1.75, 3.8), Vector3(sx, 0.875, -4.1))
		k.shelf_unit(m, Vector3(sx, 0, -4.1), 3.8, rng)
	# checkout counter + register, a toppled shelf, the last of the stock on the floor
	map.collider(Vector3(2.6, 1.0, 0.8), Vector3(20.2, 0.5, 4.2))
	k.box(m.wood, Vector3(2.6, 0.95, 0.8), Vector3(20.2, 0.475, 4.2)); k.box(m.formica, Vector3(2.7, 0.05, 0.9), Vector3(20.2, 0.98, 4.2))
	k.box(m.dark, Vector3(0.4, 0.3, 0.36), Vector3(19.6, 1.15, 4.2), 0.2); k.box(m.steel, Vector3(0.42, 0.1, 0.4), Vector3(19.6, 1.33, 4.25), 0.2, Vector2.ZERO, true, Vector3(-0.5, 0, 0))
	map.collider(Vector3(3.0, 0.9, 1.0), Vector3(13.2, 0.45, 4.0), 0.25)
	k.box(m.steel, Vector3(3.0, 0.06, 0.9), Vector3(13.2, 0.5, 4.0), 0.25, Vector2.ZERO, true, Vector3(0.0, 0, 0.5))
	for i in 3: k.box(m.steel, Vector3(0.04, 0.035, 0.86), Vector3(12.2 + i, 0.32, 4.0 + (i - 1) * 0.26), 0.25)
	k.box(m.amber_glow, Vector3(0.12, 0.2, 0.12), Vector3(20.9, 1.1, 4.2), 0.0, Vector2.ZERO, false)   # lantern on the counter
	_practical(Vector3(20.9, 1.6, 3.8), Color(1.0, 0.72, 0.42), 1.4, 7.5)
	_carton_pile(Vector3(13.6, 0, 5.4), 5, 0.8); _carton_pile(Vector3(24.6, 0, -1.9), 3, 0.4)
	for i in 9: k.cyl(m.tin if i % 2 == 0 else m.steel, 0.05, 0.11, Vector3(15.6 + rng.randf_range(-1.6, 1.6), 0.055, 2.4 + rng.randf_range(-0.8, 0.8)), 6, false, -1.0, Vector3(PI / 2 if i % 3 == 0 else 0.0, 0, 0))
	_p("debris_papers", 1.0, Vector3(16, 0, 0.4)); _p("cardboard_boxes", 1.1, Vector3(11.0, 0, -8.6), 0.3)
	_carton_pile(Vector3(13.8, 1.88, -8.8), 4, 0.6)   # stock still up on the mezzanine
	k.poster("evac_notice", Vector3(10.26, 1.7, 3.0), Vector3(1, 0, 0), 0.62, m, -0.03)
	k.poster("infection", Vector3(10.26, 1.7, -3.2), Vector3(1, 0, 0), 0.6, m, 0.05)
	k.banner("curfew", Vector3(21.8, 2.9, -9.74), Vector3(0, 0, 1), 2.4, m)
	k.box(m.red_glow, Vector3(0.5, 0.18, 0.06), Vector3(25.72, 3.3, 0), 0.0, Vector2.ZERO, false)   # EXIT box over the street door
	_practical(Vector3(25.0, 3.1, 0), Color(1.0, 0.2, 0.12), 0.7, 5.0)
	# storefront on Main Street
	k.outdoor = true
	k.banner("store", Vector3(26.3, 3.5, 0), Vector3(1, 0, 0), 6.4, m)
	k.awning(m.awn_green, m.trim, Vector3(26.26, 3.05, 3.8), Vector3(1, 0, 0), 3.0); k.awning(m.awn_green, m.trim, Vector3(26.26, 3.05, -6.5), Vector3(1, 0, 0), 3.0, 1.3, 0.25)
	# Side Alley
	_p("trashcan", 0.9, Vector3(20.8, 0, 13.3), 0.01, true); _p("debris_papers", 0.9, Vector3(23.6, 0, 12.4))
	k.poster("missing", Vector3(23.2, 1.6, 13.76), Vector3(0, 0, -1), 0.5, m, 0.05); k.poster("evac_notice", Vector3(24.0, 1.7, 13.76), Vector3(0, 0, -1), 0.6, m, -0.04)
	var b := k.wall_lamp(m, Vector3(20.26, 3.2, 12.2), Vector3(1, 0, 0), m.red_glow)
	_practical(b, Color(1.0, 0.16, 0.1), 0.6, 5.5)

# ---------------------------------------------------------------- Main Street
func _street() -> void:
	k.outdoor = true
	# pavements, kerbs and worn road paint
	for sx in [[26.2, 28.6], [43.4, 45.8]]:
		map.floor_rect(m.kerb, sx[0], -10.8, sx[1], 9.8, 0.05)
	for i in 6: k.box(m.paint, Vector3(0.16, 0.012, 2.0), Vector3(36, 0.03, 7.0 - i * 3.6), 0.0, Vector2.ZERO, false)
	for i in 7: k.box(m.paint, Vector3(0.5, 0.012, 3.0), Vector3(30.0 + i * 2.0, 0.03, 7.6), 0.0, Vector2.ZERO, false)   # crossing by the gate
	k.cyl(m.rust, 0.42, 0.02, Vector3(33.0, 0.035, -3.0), 12, false)
	# abandoned vehicles: a patrol car slewed across the road, a burning wreck, a car left at the kerb
	_p("police_car", 4.6, Vector3(36, 0, -1), 0.4, false, true)
	k.box(m.red_glow, Vector3(0.9, 0.1, 0.24), Vector3(36, 1.56, -1), 0.4 + PI / 2, Vector2.ZERO, false)
	var beacon := _practical(Vector3(36, 2.1, -1), Color(1.0, 0.1, 0.06), 1.5, 8.0, true); beacon.set("rate", 0.5)
	_p("sports_car", 4.2, Vector3(43.0, 0, -7.0), 1.9, false, true)
	wreck_fire(Vector3(43.0, 0.9, -7.0))
	_p("sports_car", 4.2, Vector3(29.9, 0, 4.0), 0.06, false, true)
	# checkpoint: barriers, cones, sandbags, floodlights on the platform, the blockade notice
	_p("traffic_barrier", 1.9, Vector3(31.4, 0, -8.6), 0.1, false, true); _p("traffic_barrier", 1.9, Vector3(40.4, 0, -9.2), -0.2, false, true)
	for c in [Vector3(38.0, 0, 2.0), Vector3(33.0, 0, -5.0), Vector3(39.5, 0, -6.4), Vector3(34.4, 0, -8.9)]: _p("traffic_cone", 0.6, c, 0.01, true)
	k.sandbags(m.sandbag, Vector3(32.0, 1.44, -11.5), Vector3(35.4, 1.44, -11.5)); k.sandbags(m.sandbag, Vector3(36.8, 1.44, -11.5), Vector3(40.2, 1.44, -11.5), 2)
	_carton_pile(Vector3(38.6, 1.44, -14.4), 4, 0.5)
	k.box(m.corr_olive, Vector3(1.2, 0.7, 0.8), Vector3(33.4, 1.79, -14.6), 0.2, Vector2(1.2, 0.7))   # ammo crate
	k.banner("quarantine", Vector3(36, 3.6, -16.2), Vector3(0, 0, 1), 7.6, m)
	k.banner("closed", Vector3(31.4, 1.25, -8.48), Vector3(0, 0, 1), 1.7, m)
	for x: float in [32.0, 40.0]:
		k.cyl(m.trim, 0.04, 2.2, Vector3(x, 2.5, -15.0), 6); k.box(m.lamp_cool, Vector3(0.5, 0.3, 0.1), Vector3(x, 3.7, -14.95), 0.0, Vector2.ZERO, false, Vector3(0.4, 0, 0))
		var fl := map.light(Vector3(x, 3.6, -13.2), Color(0.8, 0.88, 1.0), 2.2, 13.0)
		map.shadow_lights.append(fl)
	_p("dumpster", 2.0, Vector3(27.5, 0, -14.6), PI / 2, false, true); _p("pallet_broken", 1.3, Vector3(41.0, 1.44, -14.2))
	_p("tires", 1.1, Vector3(44.4, 0, -14.4), 0.01, false, true); _p("debris_pile", 1.6, Vector3(29.0, 0, -6.4)); _p("debris", 1.6, Vector3(41.6, 0, 7.6), 1.0)
	_p("barrel", 0.95, Vector3(33.2, 0, 1.4), 0.01, true, true); _p("barrel_explosive", 0.95, Vector3(38.9, 0, -3.2), 0.01, true, true)
	_p("debris_papers", 1.2, Vector3(31, 0, 0.6)); _p("debris_papers", 1.1, Vector3(40.5, 0, 3.5))
	# street furniture
	for sp in [Vector3(27.0, 0, -9.0), Vector3(45.2, 0, 0.5)]:
		_p("street_light", 5.0, sp, 0.01, true, false)
		map.light(sp + Vector3(0, 4.6, 0), Color(1.0, 0.7, 0.4), 1.7, 10.0)
	map.collider(Vector3(1.2, 2.4, 3.0), Vector3(44.9, 1.2, -2.2))   # bus shelter
	for z: float in [-3.6, -0.8]: k.box(m.trim, Vector3(0.08, 2.4, 0.08), Vector3(44.4, 1.2, z))
	k.box(m.trim, Vector3(1.5, 0.08, 3.2), Vector3(44.9, 2.42, -2.2)); k.quad(m.glass, 2.8, 1.7, Transform3D(Basis(Vector3.UP, PI / 2), Vector3(45.5, 1.3, -2.2)))
	k.bench(m, Vector3(45.1, 0, -2.2), -PI / 2)
	k.poster("evac_notice", Vector3(45.47, 1.5, -1.4), Vector3(-1, 0, 0), 0.6, m)
	k.box(m.corr_blue, Vector3(0.5, 1.1, 0.45), Vector3(27.1, 0.6, 9.0), 0.0, Vector2(0.5, 1.1)); k.cyl(m.awn_red, 0.13, 0.7, Vector3(28.3, 0.4, -4.4), 8)   # mailbox, hydrant
	_luggage(Vector3(44.6, 0.05, 8.0), 4)
	# east side storefronts (ground floor): pharmacy, barber, hotel
	var face := Vector3(-1, 0, 0)
	k.banner("pharmacy", Vector3(45.74, 3.4, -11.6), face, 4.2, m); k.banner("barber", Vector3(45.74, 3.4, -2.4), face, 3.6, m); k.banner("hotel", Vector3(45.74, 3.4, 6.6), face, 4.0, m)
	k.doorway(m, Vector3(45.78, 0, -13.6), face, 1.1, true); k.doorway(m, Vector3(45.78, 0, 0.9), face); k.doorway(m, Vector3(45.78, 0, 8.4), face, 1.3, true)
	k.display_window(m, Vector3(45.78, 1.75, -11.0), face, 2.6); k.display_window(m, Vector3(45.78, 1.75, -4.6), face, 2.4, 1.7, 2); k.display_window(m, Vector3(45.78, 1.75, 6.4), face, 1.9, 1.7, 2)
	k.awning(m.awn_cream, m.trim, Vector3(45.76, 3.0, -11.6), face, 4.4); k.awning(m.awn_red, m.trim, Vector3(45.76, 3.0, -3.6), face, 4.6, 1.3, 0.2)
	k.cyl(m.cream, 0.1, 0.9, Vector3(45.6, 2.2, -5.9), 8); k.box(m.awn_red, Vector3(0.22, 0.12, 0.22), Vector3(45.6, 2.7, -5.9))   # barber pole
	# west side: posters on the store front; south: the evacuation banner over the courtyard gate
	k.poster("missing", Vector3(26.3, 1.6, 8.2), Vector3(1, 0, 0), 0.5, m, 0.05); k.poster("infection", Vector3(26.3, 1.7, -9.0), Vector3(1, 0, 0), 0.6, m, -0.04)
	k.banner("evac", Vector3(36, 4.05, 9.72), Vector3(0, 0, -1), 5.6, m); k.banner("mainst", Vector3(27.2, 3.0, 9.72), Vector3(0, 0, -1), 1.6, m)
	# overhead: power lines sagging across the street from two leaning poles
	for pz in [[27.4, 9.2, -0.05], [44.8, -10.2, 0.07]]:
		k.cyl(m.plank, 0.13, 8.5, Vector3(pz[0], 4.25, pz[1]), 8, true, 0.1, Vector3(0, 0, pz[2])); k.box(m.plank, Vector3(0.1, 0.1, 1.8), Vector3(pz[0], 7.9, pz[1]))
	for off: float in [-0.7, 0.0, 0.7]: k.cable(m.dark, Vector3(27.4, 7.9, 9.2 + off), Vector3(44.8, 7.9, -10.2 + off), 1.1)
	fire_barrel(Vector3(42.6, 0, 3.4))

## The wreck burning on Main Street: flames, a thin smoke column and a flickering fire light.
func wreck_fire(at: Vector3) -> void:
	var f := _flames(at, 46, 0.9, 1.1); f.name = "WreckFire"
	var s := CPUParticles3D.new(); s.amount = 12; s.lifetime = 5.0; s.preprocess = 5.0; s.position = at + Vector3(0, 1.0, 0)
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; s.emission_sphere_radius = 0.5
	s.direction = Vector3(0.25, 1, 0.1); s.spread = 8; s.gravity = Vector3(0.12, 0.5, 0); s.initial_velocity_min = 0.8; s.initial_velocity_max = 1.4
	s.scale_amount_min = 1.6; s.scale_amount_max = 3.2
	var cv := Curve.new(); cv.add_point(Vector2(0, 0.3)); cv.add_point(Vector2(1, 1.0)); s.scale_amount_curve = cv
	var g := Gradient.new(); g.set_color(0, Color(0.1, 0.1, 0.11, 0.0)); g.add_point(0.15, Color(0.12, 0.12, 0.13, 0.5)); g.set_color(g.get_point_count() - 1, Color(0.2, 0.21, 0.24, 0.0)); s.color_ramp = g
	var q := QuadMesh.new(); q.size = Vector2(1, 1)
	var sm := StandardMaterial3D.new(); sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES; sm.vertex_color_use_as_albedo = true; sm.albedo_texture = _radial(); q.material = sm
	s.mesh = q; map.add_child(s); map.dust.append(s)
	var l := map.light(at + Vector3(0, 1.0, 0.6), Color(1.0, 0.5, 0.18), 2.6, 10.0); l.set("rate", 0.6)

func _flames(at: Vector3, amount: int, radius: float, size: float) -> CPUParticles3D:
	var f := CPUParticles3D.new(); f.amount = amount; f.lifetime = 0.8; f.position = at
	f.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; f.emission_sphere_radius = radius
	f.direction = Vector3.UP; f.spread = 12; f.gravity = Vector3(0, 2.2, 0); f.initial_velocity_min = 0.3; f.initial_velocity_max = 0.9
	f.scale_amount_min = 0.6; f.scale_amount_max = 1.2
	var cv := Curve.new(); cv.add_point(Vector2(0, 0.6)); cv.add_point(Vector2(0.3, 1.0)); cv.add_point(Vector2(1, 0)); f.scale_amount_curve = cv
	var g := Gradient.new(); g.set_color(0, Color(1.0, 0.85, 0.35)); g.set_color(1, Color(0.6, 0.1, 0.02, 0.0)); f.color_ramp = g
	var q := QuadMesh.new(); q.size = Vector2(size, size); f.mesh = q
	var fm := StandardMaterial3D.new(); fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES; fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.vertex_color_use_as_albedo = true; fm.albedo_texture = _radial(); fm.disable_fog = true; q.material = fm
	map.add_child(f); map.dust.append(f)
	return f

# ---------------------------------------------------------------- Courtyard
func _court() -> void:
	k.outdoor = true
	# dry fountain in the middle: the thing you circle
	var sb := StaticBody3D.new(); sb.position = Vector3(36, 0, 20); map.add_child(sb)
	var cs := CollisionShape3D.new(); var cy := CylinderShape3D.new(); cy.radius = 2.3; cy.height = 1.2; cs.shape = cy; cs.position.y = 0.6; sb.add_child(cs)
	k.cyl(m.kerb, 2.3, 0.55, Vector3(36, 0.275, 20), 16); k.cyl(m.dark, 1.95, 0.02, Vector3(36, 0.56, 20), 16, false)
	k.cyl(m.kerb, 0.5, 1.5, Vector3(36, 0.75, 20), 10, true, 0.36); k.cyl(m.kerb, 0.95, 0.16, Vector3(36, 1.56, 20), 12, true, 0.7)
	k.cyl(m.conc, 0.22, 0.9, Vector3(36, 2.05, 20), 8, true, 0.12)
	_p("debris_papers", 1.0, Vector3(36.6, 0.56, 20.4))
	# relief tent, cots, supply tables: Evacuation Point B, abandoned mid-queue
	k.tent(m, Vector3(41.4, 0, 15.6), 0.0)
	map.collider(Vector3(0.9, 0.6, 2.0), Vector3(40.5, 0.3, 15.6)); map.collider(Vector3(0.9, 0.6, 2.0), Vector3(42.4, 0.3, 15.6))
	for cx: float in [40.5, 42.4]:
		k.box(m.canvas, Vector3(0.8, 0.06, 1.9), Vector3(cx, 0.42, 15.6)); k.box(m.cream, Vector3(0.7, 0.05, 0.9), Vector3(cx, 0.47, 15.9), 0.1)
		for z: float in [14.8, 16.4]: k.box(m.steel, Vector3(0.8, 0.4, 0.04), Vector3(cx, 0.2, z))
	k.box(m.amber_glow, Vector3(0.12, 0.2, 0.12), Vector3(41.45, 0.1, 15.2), 0.0, Vector2.ZERO, false)
	_practical(Vector3(41.45, 1.0, 15.4), Color(1.0, 0.72, 0.42), 1.2, 6.5)
	map.collider(Vector3(3.9, 0.9, 0.8), Vector3(41.4, 0.45, 11.2))
	k.supply_table(m, Vector3(40.4, 0, 11.2), 0.02, rng); k.supply_table(m, Vector3(42.4, 0, 11.2), -0.03, rng)
	_carton_pile(Vector3(44.6, 0, 12.4), 5, 0.6); _luggage(Vector3(30.0, 0, 15.6), 5); _luggage(Vector3(33.6, 0, 27.6), 4)
	k.banner("evac", Vector3(41.4, 3.0, 10.46), Vector3(0, 0, 1), 4.4, m)
	# benches, a dead tree in its planter, queue barriers
	map.collider(Vector3(1.7, 0.9, 0.5), Vector3(36, 0.45, 24.4)); k.bench(m, Vector3(36, 0, 24.4), PI)
	map.collider(Vector3(0.5, 0.9, 1.7), Vector3(31.4, 0.45, 20)); k.bench(m, Vector3(31.4, 0, 20), PI / 2)
	map.collider(Vector3(2.0, 0.7, 2.0), Vector3(30.6, 0.35, 25.2)); k.box(m.kerb, Vector3(2.0, 0.6, 2.0), Vector3(30.6, 0.3, 25.2)); k.box(m.dirt, Vector3(1.7, 0.04, 1.7), Vector3(30.6, 0.61, 25.2))
	_p("dead_tree", 6.0, Vector3(30.6, 0.55, 25.2), 0.4, true)
	_p("traffic_barrier", 1.8, Vector3(33.0, 0, 13.4), 0.2, false, true)
	_p("barrel", 0.95, Vector3(43.6, 0, 27.4), 0.3, true, true); _p("barrel_explosive", 0.95, Vector3(38.6, 0, 27.6), 0.01, true, true)
	_p("trashcan", 0.9, Vector3(27.2, 0, 28.6), 0.01, true, true); _p("debris_pile", 1.4, Vector3(44.6, 0, 28.6))
	fire_barrel(Vector3(29.0, 0, 28.0))
	# the wall of the missing, with candles still burning under it
	for i in 7:
		k.poster("missing" if i % 3 != 1 else "evac_notice", Vector3(26.26, 1.2 + (i % 2) * 0.62 + rng.randf_range(-0.05, 0.05), 16.2 + i * 0.6), Vector3(1, 0, 0), 0.5, m, rng.randf_range(-0.12, 0.12))
	for i in 6: k.cyl(m.cream, 0.035, 0.12 + (i % 3) * 0.05, Vector3(26.5 + (i % 2) * 0.16, 0.08, 16.6 + i * 0.55), 6, false)
	k.box(m.amber_glow, Vector3(0.05, 0.03, 3.0), Vector3(26.56, 0.2, 18.0), 0.0, Vector2.ZERO, false)
	_practical(Vector3(27.1, 0.6, 18.0), Color(1.0, 0.62, 0.3), 1.3, 5.5, true)
	# balconies and shutters on the surrounding tenements, laundry lines overhead
	for z: float in [14.0, 20.0, 26.0]:
		k.box(m.trim, Vector3(1.0, 0.08, 2.6), Vector3(45.3, 4.5, z)); k.box(m.trim, Vector3(0.04, 0.9, 2.6), Vector3(44.82, 4.95, z), 0.0, Vector2.ZERO, false)
	for x: float in [30.0, 42.0]:
		k.box(m.trim, Vector3(2.6, 0.08, 1.0), Vector3(x, 4.5, 29.3)); k.box(m.trim, Vector3(2.6, 0.9, 0.04), Vector3(x, 4.95, 28.82), 0.0, Vector2.ZERO, false)
	k.cable(m.dark, Vector3(26.3, 6.2, 22.0), Vector3(45.7, 5.6, 17.0), 0.7, 0.02)

# ---------------------------------------------------------------- beyond the walls
## What you glimpse through the diner's windows and over the rooftops: the parking lot, the side
## street, the continuation of Main Street. Visual only apart from a few wrecks; spawn lanes stay clear.
func _outskirts() -> void:
	k.outdoor = true
	map.floor_rect(m.ground, -30, 10.2, 8, 34)      # diner parking lot + the road beyond
	map.floor_rect(m.ground, -30, -27, -10.2, 10.2)  # side street west of the diner
	for i in 5: k.box(m.paint, Vector3(0.12, 0.012, 4.6), Vector3(-8.0 + i * 2.9, 0.03, 14.2), 0.0, Vector2.ZERO, false)   # parking bays
	_p("sports_car", 4.2, Vector3(5.4, 0, 14.6), PI / 2 + 0.05, false, true); _p("police_car", 4.6, Vector3(-9.6, 0, 20.5), 0.9, false, true)
	_p("sports_car", 4.2, Vector3(-17.5, 0, -9.5), 0.3, false, true); _p("dumpster", 2.0, Vector3(-11.4, 0, 8.6), PI / 2, false, true)
	_p("street_light", 5.0, Vector3(1.6, 0, 21.0), 0.01, true); _p("street_light", 5.0, Vector3(-21.0, 0, 4.0), 0.01, true)
	_practical(Vector3(1.6, 4.6, 21.0), Color(1.0, 0.7, 0.4), 1.6, 12.0, true)
	fire_barrel(Vector3(-15.5, 0, 8.0))
	# the diner's roadside pylon sign, dark now
	k.cyl(m.trim, 0.16, 6.0, Vector3(-6.5, 3.0, 22.5), 8); k.banner("diner", Vector3(-6.5, 6.6, 22.5), Vector3(0, 0, -1), 4.4, m, true)
	k.banner("closed", Vector3(-1.0, 1.0, 24.0), Vector3(0, 0, -1), 2.2, m)
	for t in [Vector3(-16, 0, 18), Vector3(8.5, 0, 23.5), Vector3(-22, 0, -4), Vector3(-21, 0, -19)]:
		_p("dead_tree" if rng.randf() < 0.5 else "dead_trees", rng.randf_range(5.5, 7.5), t, 0.01, true)
	# rows of houses across the road (south) and across the side street (west)
	k.block(Rect2(-32, 27, 14, 9), 0.0, 8.6, m.facade_brick, m.brick_dark, m.kerb)
	k.block(Rect2(-17.5, 27, 12, 9), 0.0, 11.4, m.facade_plaster, m.conc, m.kerb)
	k.block(Rect2(-5, 27, 13, 9), 0.0, 7.8, m.facade_brick, m.brick, m.kerb)
	k.block(Rect2(-36, -30, 9, 20), 0.0, 9.4, m.facade_plaster, m.conc, m.kerb)
	k.block(Rect2(-36, -9.5, 9, 14), 0.0, 12.0, m.facade_brick, m.brick, m.kerb)
	k.block(Rect2(-36, 5, 9, 21.5), 0.0, 8.0, m.facade_brick, m.brick_dark, m.kerb)
	# Main Street north of the blockade: wrecks left where the column stopped
	_p("police_car", 4.6, Vector3(33.0, 0, -24.0), 2.4); _p("sports_car", 4.2, Vector3(40.5, 0, -30.0), 0.4)

# ---------------------------------------------------------------- skyline
## Distant damaged city: two unshaded silhouette rings (fog-free, drawn behind everything), a handful
## of mid-distance tower blocks with broken tops, three slow smoke columns and their fire glows.
func _skyline() -> void:
	for ring in [[150.0, 46.0, Color(0.85, 0.9, 1.0), 0.0], [190.0, 74.0, Color(0.62, 0.68, 0.8, 0.9), 1.9]]:
		var cm := CylinderMesh.new(); cm.top_radius = ring[0]; cm.bottom_radius = ring[0]; cm.height = ring[1]
		cm.radial_segments = 32; cm.rings = 1; cm.cap_top = false; cm.cap_bottom = false
		var sm := StandardMaterial3D.new(); sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.albedo_texture = map._town("skyline"); sm.albedo_color = ring[2]; sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.cull_mode = BaseMaterial3D.CULL_FRONT; sm.disable_fog = true; sm.uv1_scale = Vector3(3, 1, 1); sm.render_priority = -10
		sm.disable_receive_shadows = true
		var mi := MeshInstance3D.new(); mi.mesh = cm; mi.material_override = sm; mi.name = "Skyline"
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(18, ring[1] * 0.5 - 4.0, -8); mi.rotation.y = ring[3]
		map.add_child(mi)
	k.outdoor = true
	for t in [[Vector3(-62, 0, -70), Vector3(20, 34, 16), 0.3], [Vector3(-20, 0, -86), Vector3(16, 46, 16), -0.2], [Vector3(36, 0, -92), Vector3(24, 30, 14), 0.1],
			[Vector3(92, 0, -58), Vector3(18, 40, 18), 0.5], [Vector3(104, 0, 8), Vector3(16, 28, 22), 1.4], [Vector3(84, 0, 66), Vector3(22, 38, 16), -0.6],
			[Vector3(14, 0, 82), Vector3(20, 26, 16), 0.2], [Vector3(-58, 0, 60), Vector3(18, 42, 18), 0.9], [Vector3(-82, 0, -8), Vector3(16, 32, 20), 1.7]]:
		var sz: Vector3 = t[1]; var at: Vector3 = t[0]
		k.box(m.facade_concrete, sz, at + Vector3(0, sz.y * 0.5, 0), t[2], Vector2(12, 12.8), false)
		# shelled top floors: a leaning slab and a stump of core
		k.box(m.facade_concrete, Vector3(sz.x * 0.6, 5.0, sz.z * 0.7), at + Vector3(sz.x * 0.12, sz.y + 1.6, 0), t[2] + 0.2, Vector2(12, 12.8), false, Vector3(0.0, 0, 0.16))
		k.box(m.conc, Vector3(4, 7, 4), at + Vector3(-sz.x * 0.25, sz.y + 3.0, sz.z * 0.1), t[2], Vector2.ZERO, false)
	for s in [[Vector3(-44, 30, -78), 26.0], [Vector3(98, 30, -26), 22.0], [Vector3(40, 22, 96), 20.0]]:
		_smoke_column(s[0], s[1])

func _smoke_column(at: Vector3, size: float) -> void:
	var s := CPUParticles3D.new(); s.amount = 9; s.lifetime = 22.0; s.preprocess = 22.0; s.position = at
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; s.emission_sphere_radius = 3.0
	s.direction = Vector3(0.35, 1, 0.1); s.spread = 5; s.gravity = Vector3(0.05, 0, 0); s.initial_velocity_min = 1.6; s.initial_velocity_max = 2.2
	s.scale_amount_min = 0.7; s.scale_amount_max = 1.2
	var cv := Curve.new(); cv.add_point(Vector2(0, 0.35)); cv.add_point(Vector2(1, 1.0)); s.scale_amount_curve = cv
	var g := Gradient.new(); g.set_color(0, Color(0.09, 0.09, 0.1, 0.0)); g.add_point(0.12, Color(0.1, 0.1, 0.12, 0.42)); g.set_color(g.get_point_count() - 1, Color(0.24, 0.26, 0.3, 0.0)); s.color_ramp = g
	var q := QuadMesh.new(); q.size = Vector2(size, size)
	var sm := StandardMaterial3D.new(); sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES; sm.vertex_color_use_as_albedo = true; sm.albedo_texture = _radial(); sm.disable_fog = true
	q.material = sm; s.mesh = q; s.visibility_aabb = AABB(Vector3(-40, -10, -40), Vector3(80, 90, 80))
	map.add_child(s); map.dust.append(s)
	# fire glow at the base of the column (flickered by the map)
	var gm := StandardMaterial3D.new(); gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; gm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; gm.albedo_texture = _radial()
	gm.albedo_color = Color(1.0, 0.42, 0.12, 0.5); gm.disable_fog = true
	var gq := QuadMesh.new(); gq.size = Vector2(size * 1.3, size * 0.8); gq.material = gm
	var gi := MeshInstance3D.new(); gi.mesh = gq; gi.position = at - Vector3(0, 4, 0); gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	map.add_child(gi); map.fires.append(gm)

# ---------------------------------------------------------------- fire barrels
func fire_barrel(p: Vector3) -> Node3D:
	var root := Node3D.new(); root.position = p; map.add_child(root)
	var mi := MeshInstance3D.new(); var cm := CylinderMesh.new(); cm.top_radius = 0.3; cm.bottom_radius = 0.3; cm.height = 0.9
	cm.cap_top = false; mi.mesh = cm; mi.material_override = map.mats.rust; mi.position.y = 0.45; root.add_child(mi)
	var f := _flames(p + Vector3(0, 0.9, 0), 24, 0.18, 0.35)
	f.name = "BarrelFire"
	var l := map.light(p + Vector3(0, 1.4, 0), Color(1.0, 0.5, 0.18), 2.2, 8.0)
	l.set("rate", 0.6)
	var sb := StaticBody3D.new(); var cs := CollisionShape3D.new(); var cy := CylinderShape3D.new(); cy.radius = 0.3; cy.height = 0.9
	cs.shape = cy; cs.position.y = 0.45; sb.add_child(cs); root.add_child(sb)
	return root

static func _radial() -> Texture2D:
	if _decal_tex.has("radial"): return _decal_tex.radial
	var g := Gradient.new(); g.set_color(0, Color.WHITE); g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new(); t.gradient = g; t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5); t.fill_to = Vector2(0.5, 0.0); t.width = 32; t.height = 32
	_decal_tex.radial = t; return t

# ---------------------------------------------------------------- decals (original, generated)
static func decal_tex(kind: String) -> Texture2D:
	if _decal_tex.has(kind): return _decal_tex[kind]
	var n := FastNoiseLite.new(); n.seed = kind.hash() & 0xffff; n.frequency = 0.035 if kind != "crack" else 0.02
	n.fractal_octaves = 4
	var sz := 128; var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in sz:
		for x in sz:
			var d := Vector2(x - sz / 2.0, y - sz / 2.0).length() / (sz / 2.0)
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var c := Color(0, 0, 0, 0)
			match kind:
				"blood":
					var a := clampf((v * 1.4 - d) * 3.0, 0, 1)
					c = Color(0.28 + v * 0.1, 0.01, 0.01, a * 0.95)
				"grime":
					var a := clampf((v - d * 0.6) * 1.6, 0, 1)
					c = Color(0.05, 0.045, 0.035, a * 0.75)
				"crack":
					var r := absf(n.get_noise_2d(x * 1.0, y * 1.0))
					var a := clampf(1.0 - r * 18.0, 0, 1) * clampf(1.2 - d, 0, 1)
					c = Color(0.02, 0.02, 0.02, a)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img); _decal_tex[kind] = t
	return t

## Decals are alpha-blended quads batched into one MultiMesh per kind (3 draw calls for the whole map).
## Godot's Decal node is not supported by the GL Compatibility renderer, which is also the phone fallback.
const DECAL_KINDS := ["blood", "grime", "crack"]
const DECAL_LIFT := 0.015          ## metres off the surface (no z-fighting, no visible float)
var _decal_xf := {}                ## kind -> Array[Transform3D]

func decal(kind: String, pos: Vector3, size: float, normal := Vector3.UP) -> void:
	if not _decal_xf.has(kind): _decal_xf[kind] = [] as Array[Transform3D]
	_decal_xf[kind].append(decal_xform(pos, size, normal, rng.randf_range(-PI, PI)))

## Quad (faces +Z) laid on a surface: +Z = normal, spun about it, lifted DECAL_LIFT.
static func decal_xform(pos: Vector3, size: float, normal: Vector3, spin: float) -> Transform3D:
	var z := normal.normalized()
	var x := (Vector3.UP.cross(z) if absf(z.y) < 0.9 else Vector3.RIGHT).normalized()
	var b := Basis(x, z.cross(x), z).rotated(z, spin).scaled(Vector3(size, size, 1.0))
	return Transform3D(b, pos + z * DECAL_LIFT)

static func decal_material(kind: String) -> StandardMaterial3D:
	var dm := StandardMaterial3D.new(); dm.albedo_texture = decal_tex(kind)
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.roughness = 0.35 if kind == "blood" else 0.95   # wet blood catches the flashlight
	dm.shadow_to_opacity = false; dm.render_priority = -1
	return dm

func _flush_decals() -> void:
	for kind in _decal_xf:
		var q := QuadMesh.new(); q.material = decal_material(kind)
		var xs: Array[Transform3D] = _decal_xf[kind]
		var mm := multimesh(q, xs, "Decals_" + kind, 0.0)   # map-wide batch: no range cull
		mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		map.add_child(mm)

## Per-area dressing: [rect, blood, grime (oil / soot / damp), crack] counts. Busier where the horde breaks in.
const DECAL_ZONES := [
	[Rect2(-9, -9, 18, 18), 5, 5, 2],     # diner (spawn, window fights)
	[Rect2(-9, -25, 18, 14), 3, 10, 6],   # back alley: oil, damp, broken asphalt
	[Rect2(11, -9, 14, 18), 4, 4, 2],     # general store
	[Rect2(11, -25, 14, 14), 2, 9, 4],    # garage: oil stains
	[Rect2(27, -9, 18, 18), 6, 8, 8],     # main street
	[Rect2(27, 11, 18, 18), 4, 7, 5],     # courtyard
]
func _decals() -> void:
	for z in DECAL_ZONES:
		var r: Rect2 = z[0]
		for kind_i in 3:
			for i in int(z[kind_i + 1]):
				var p := Vector3(rng.randf_range(r.position.x + 0.5, r.end.x - 0.5), 0.03, rng.randf_range(r.position.y + 0.5, r.end.y - 0.5))
				decal(DECAL_KINDS[kind_i], p, rng.randf_range(0.8, 2.6) if kind_i != 2 else rng.randf_range(1.4, 3.4))
	# smears where the horde breaks in, cracks in the old walls, damp at wall bases
	for w in [[Vector3(-9.75, 1.2, 0.6), Vector3.RIGHT], [Vector3(-4.6, 1.0, 9.75), Vector3.FORWARD], [Vector3(9.75, 1.6, 6.0), Vector3.LEFT],
			[Vector3(-9.75, 2.6, -14.0), Vector3.RIGHT], [Vector3(14.0, 2.4, 9.75), Vector3.FORWARD], [Vector3(25.75, 1.4, -2.6), Vector3.LEFT],
			[Vector3(-9.75, 0.5, -21.0), Vector3.RIGHT], [Vector3(26.25, 0.6, 16.0), Vector3.RIGHT], [Vector3(45.75, 1.3, 2.0), Vector3.LEFT],
			[Vector3(45.75, 1.2, -10.0), Vector3.LEFT], [Vector3(34.0, 0.9, 29.75), Vector3.FORWARD], [Vector3(10.25, 1.4, -21.0), Vector3.RIGHT]]:
		var kind := "grime" if w[0].y < 0.8 else ("blood" if rng.randf() < 0.5 else "crack")
		decal(kind, w[0], rng.randf_range(1.0, 1.8), w[1])
	_flush_decals()

# ---------------------------------------------------------------- area accents
## One coloured accent per area so each place reads differently at a glance: sodium amber in the back
## alley, a work-lamp orange in the garage, the store's green exit glow, candle light in the courtyard.
## Unshadowed, no flicker, range-limited: cheap on mobile.
const AREA_MOODS := [
	[Vector3(-4, 2.6, -18), Color(1.0, 0.62, 0.25), 0.6, 8.0],   # back alley
	[Vector3(18, 2.6, -18), Color(1.0, 0.7, 0.4), 0.5, 8.0],     # garage
	[Vector3(18, 2.6, 2), Color(0.45, 0.9, 0.7), 0.4, 8.0],      # general store
	[Vector3(36, 2.4, 20), Color(1.0, 0.66, 0.36), 0.5, 9.0],    # courtyard
]
func _area_moods() -> void:
	for a in AREA_MOODS:
		var l := map.light(a[0], a[1], a[2], a[3], false)
		l.light_specular = 0.1; l.omni_attenuation = 1.0; l.name = "AreaMood"

## Rubble chunks: one MultiMesh of small boxes under windows, at wall feet and around wrecks.
func _rubble() -> void:
	var bm := BoxMesh.new(); bm.size = Vector3(0.18, 0.1, 0.14)
	var mat := StandardMaterial3D.new(); mat.albedo_color = Color(0.36, 0.33, 0.3); mat.roughness = 1.0; bm.material = mat
	var xs: Array[Transform3D] = []
	for c in [Vector3(-9, 0.06, 2), Vector3(-3, 0.06, 9), Vector3(-9, 0.06, -18), Vector3(16, 0.06, 9), Vector3(22, 0.06, -25), Vector3(45, 0.06, 4), Vector3(45, 0.06, -8),
			Vector3(38, 0.06, 29), Vector3(45, 0.06, 20), Vector3(-8, 0.06, -25), Vector3(43, 0.06, -7), Vector3(36, 0.06, -10.6), Vector3(26.6, 0.06, 12), Vector3(-9.2, 0.06, 6.2), Vector3(0.4, 0.06, 9.2)]:
		for i in 14:
			var o := Vector3(rng.randf_range(-1.4, 1.4), 0, rng.randf_range(-1.4, 1.4))
			var b := Basis.from_euler(Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(-PI, PI), 0)).scaled(Vector3.ONE * rng.randf_range(0.5, 1.6))
			xs.append(Transform3D(b, c + o))
	map.add_child(multimesh(bm, xs, "RubbleMM", 30.0))

## Weeds pushing through the paving along walls and kerbs (MultiMesh, outdoors only).
func _weeds() -> void:
	var g := Gradient.new(); g.set_color(0, Color(0.3, 0.33, 0.2)); g.set_color(1, Color(0.11, 0.14, 0.08))
	var gt := GradientTexture2D.new(); gt.gradient = g; gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1); gt.width = 4; gt.height = 32
	var wm := StandardMaterial3D.new(); wm.albedo_texture = gt; wm.cull_mode = BaseMaterial3D.CULL_DISABLED; wm.roughness = 1.0
	var mesh := _tuft_mesh(); mesh.surface_set_material(0, wm)
	var xs: Array[Transform3D] = []
	for a in [Rect2(-9.7, -25.7, 19.4, 0.8), Rect2(-9.7, -25.7, 0.8, 15), Rect2(26.3, 9.0, 19.4, 0.7), Rect2(45.0, -10, 0.7, 19), Rect2(26.3, 29.0, 19.4, 0.7), Rect2(26.3, 14.4, 0.7, 15),
			Rect2(45.0, 10.4, 0.7, 19), Rect2(29.6, 24.3, 2.0, 1.8), Rect2(-28, 10.6, 34, 2.0), Rect2(-22, -26, 3.0, 36), Rect2(26.4, -15.6, 4.0, 1.0)]:
		for i in int(a.get_area() * 2.2):
			var s := rng.randf_range(0.5, 1.2)
			xs.append(Transform3D(Basis(Vector3.UP, rng.randf_range(0, TAU)).scaled(Vector3(s, s * rng.randf_range(0.7, 1.4), s)), Vector3(rng.randf_range(a.position.x, a.end.x), 0.03, rng.randf_range(a.position.y, a.end.y))))
	var mmi := multimesh(mesh, xs, "WeedsMM", 45.0)
	map.add_child(mmi); map.dust.append(mmi)

## Three crossed tapered blades (12 tris) per tuft.
static func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var ang := i * PI / 3.0; var r := Vector3(cos(ang), 0, sin(ang)) * 0.22
		var lean := Vector3(sin(ang * 3.0), 0, cos(ang * 2.0)) * 0.08
		var top := Vector3(0, 0.45, 0) + lean
		for q in [[-r, r, top + r * 0.15, top - r * 0.15]]:
			st.set_normal(Vector3.UP); st.set_uv(Vector2(0, 1)); st.add_vertex(q[0])
			st.set_uv(Vector2(1, 1)); st.add_vertex(q[1])
			st.set_uv(Vector2(1, 0)); st.add_vertex(q[2])
			st.set_uv(Vector2(0, 1)); st.add_vertex(q[0])
			st.set_uv(Vector2(1, 0)); st.add_vertex(q[2])
			st.set_uv(Vector2(0, 0)); st.add_vertex(q[3])
	return st.commit()

static func multimesh(mesh: Mesh, xs: Array[Transform3D], nm: String, vis_end: float) -> MultiMeshInstance3D:
	var mm := MultiMesh.new(); mm.transform_format = MultiMesh.TRANSFORM_3D; mm.mesh = mesh; mm.instance_count = xs.size()
	for i in xs.size(): mm.set_instance_transform(i, xs[i])
	var mmi := MultiMeshInstance3D.new(); mmi.multimesh = mm; mmi.name = nm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; mmi.visibility_range_end = vis_end
	return mmi
