class_name Game
extends Node3D
## One solo match: map, player, round director, machines, HUD. Rules come from scripts/rules.

signal exit_to_menu
signal restart_requested

var character_id := "snoop"
var force_touch := false
var map: FacilityMap
var player: Player
var hud: Hud
var touch: TouchControls
var sfx: Sfx
var facility := Facility.new()
var crate := MysteryCrate.new()
var forge := OverchargeForge.new()
var crate_node: CrateNode
var rng := RandomNumberGenerator.new()
var round := 0
var to_spawn := 0
var spawn_cd := 0.0
var intermission := 4.0
var zombies: Array = []
var pickups: Array = []
var over := false
var kills := 0
var interactables: Array = []
var current_prompt := ""
var current_target = null
var env: Environment
var auto_rounds := true

func _ready() -> void:
	rng.randomize()
	sfx = Sfx.new(); add_child(sfx)
	_build_env()
	map = FacilityMap.new(); add_child(map); map.build(self)
	map.bake_navigation_mesh(false)
	player = Player.new(); player.game = self; player.char_id = character_id
	player.position = Vector3(0, 0.1, 3); add_child(player)
	hud = Hud.new(); hud.game = self; add_child(hud)
	touch = TouchControls.new()
	touch.visible = force_touch or DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	hud.add_child(touch)
	player.touch = touch
	sfx.start_ambient()
	hud.banner("Hold the line", 3.0)
	if not touch.visible and not OS.has_feature("headless"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.33, 0.42)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.07, 0.09)
	env.fog_density = 0.045
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)

func add_interactable(pos: Vector3, radius: float, prompt: Callable, use: Callable, hold := false) -> void:
	interactables.append({pos = pos, r = radius, prompt = prompt, use = use, hold = hold})

# ---------------------------------------------------------------- loop
func _process(dt: float) -> void:
	if over or player == null: return
	_update_prompt()
	_update_rounds(dt)
	_update_pickups(dt)

func _update_prompt() -> void:
	current_prompt = ""; current_target = null
	var best := 1e9
	var pp := player.global_position
	var fwd := -player.global_basis.z
	for it in interactables:
		var off: Vector3 = it.pos - pp; off.y = 0
		var d := off.length()
		if d > it.r: continue
		var score := d - fwd.dot(off.normalized()) * 0.8
		if score < best:
			var text: String = it.prompt.call(player)
			if text == "": continue
			best = score; current_prompt = text; current_target = it

func player_use(p: Player, just_pressed: bool, repeat_tick: bool) -> void:
	if current_target == null: return
	if current_target.hold:
		if repeat_tick: current_target.use.call(p)
	elif just_pressed:
		current_target.use.call(p)

func _update_rounds(dt: float) -> void:
	if not auto_rounds: return
	if intermission > 0.0:
		intermission -= dt
		if intermission <= 0.0:
			round += 1
			to_spawn = Rounds.zombie_count(round)
			spawn_cd = 1.0
			if Rounds.is_special(round):
				hud.banner("Round %d · FRENZY" % round, 3.5)
				env.fog_light_color = Color(0.2, 0.03, 0.02)
			else:
				hud.banner("Round %d" % round, 3.0)
				env.fog_light_color = Color(0.06, 0.07, 0.09)
			sfx.play("round_start", -2)
	elif to_spawn > 0:
		spawn_cd -= dt
		if spawn_cd <= 0.0 and zombies.size() < Rounds.MAX_ALIVE:
			spawn_zombie()
			to_spawn -= 1
			spawn_cd = Rounds.spawn_interval(round)
	elif zombies.is_empty():
		intermission = 8.0
		hud.banner("Round %d survived" % round, 3.0)
		sfx.play("round_end", -2)
		player.health = player.max_health

func spawn_zombie(win_id := "") -> Zombie:
	var ids := facility.active_windows()
	if win_id == "": win_id = ids[rng.randi() % ids.size()]
	var w: WindowBarricade = map.windows[win_id]
	var z := Zombie.new()
	z.setup(self, w, maxi(round, 1))
	z.position = w.spawn_point + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
	add_child(z)
	zombies.append(z)
	return z

# ---------------------------------------------------------------- combat
func hitscan(p: Player, origin: Vector3, dir: Vector3, w: WeaponDef) -> void:
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = [p.get_rid()]
	var pierce := w.pierce
	var from := origin
	var end_point := origin + dir * 80.0
	for i in 8:
		var q := PhysicsRayQueryParameters3D.create(from, origin + dir * 80.0, 1 | 2, exclude)
		var r := space.intersect_ray(q)
		if r.is_empty(): break
		end_point = r.position
		if r.collider is Zombie:
			var z: Zombie = r.collider
			var head: bool = r.position.y - z.global_position.y > Zombie.HEAD_Y
			var dmg := w.damage * (2 if head else 1)
			p.economy.on_hit()
			var was_alive := z.state != Zombie.State.DEAD
			z.take_damage(dmg, head, p)
			hud.hitmarker(was_alive and z.state == Zombie.State.DEAD)
			sfx.play("hitmarker", -10)
			_impact(r.position, Color(0.5, 0.05, 0.03))
			if w.splash > 0.0: _splash(p, r.position, w, z)
			if pierce > 0:
				pierce -= 1; exclude.append(z.get_rid()); from = r.position; continue
			break
		else:
			_impact(r.position, Color(0.7, 0.65, 0.5))
			if w.splash > 0.0: _splash(p, r.position, w, null)
			break
	_tracer(p.gun.get_node("Muzzle").global_position if p.gun else origin, end_point, w)

func _splash(p: Player, at: Vector3, w: WeaponDef, skip) -> void:
	var r := w.splash_m()
	for z in zombies.duplicate():
		if z == skip or not is_instance_valid(z) or z.state == Zombie.State.DEAD: continue
		if (z.global_position + Vector3.UP).distance_to(at) < r + 0.5:
			z.take_damage(w.damage / 2, false, p)
	var fx := _fx_sphere(at, r, Color(0.3, 1.0, 0.8, 0.5)); fx.scale = Vector3.ONE * 0.2

func _fx_sphere(at: Vector3, radius: float, c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var sm := SphereMesh.new(); sm.radius = radius; sm.height = radius * 2
	sm.radial_segments = 8; sm.rings = 4
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.mesh = sm; mi.material_override = m; add_child(mi); mi.global_position = at
	var tw := create_tween(); tw.tween_property(mi, "scale", Vector3.ONE, 0.15); tw.tween_property(m, "albedo_color:a", 0.0, 0.2)
	tw.tween_callback(mi.queue_free)
	return mi

func _impact(at: Vector3, c: Color) -> void:
	_fx_sphere(at, 0.06, c)

func _tracer(a: Vector3, b: Vector3, w: WeaponDef) -> void:
	var mi := MeshInstance3D.new(); var im := ImmediateMesh.new(); mi.mesh = im
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1, 0.85, 0.5, 0.6) if w.tier == 0 else Color(0.8, 0.5, 1, 0.8)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, m); im.surface_add_vertex(a); im.surface_add_vertex(b); im.surface_end()
	add_child(mi)
	get_tree().create_timer(0.04).timeout.connect(mi.queue_free)

func on_zombie_killed(z: Zombie, p: Player, headshot: bool) -> void:
	zombies.erase(z)
	kills += 1
	if p: p.economy.on_kill(headshot)
	if rng.randf() < ArmorState.DROP_CHANCE:
		_drop_armor(z.global_position)

func _drop_armor(at: Vector3) -> void:
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.4, 0.5, 0.15)
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.2, 1.0, 0.4)
	m.emission_enabled = true; m.emission = Color(0.2, 1.0, 0.4); m.emission_energy_multiplier = 2.0
	mi.mesh = bm; mi.material_override = m; add_child(mi); mi.global_position = at + Vector3.UP * 0.6
	pickups.append({node = mi, life = 20.0})

func _update_pickups(dt: float) -> void:
	for pk in pickups.duplicate():
		pk.life -= dt
		var n: MeshInstance3D = pk.node
		n.rotation.y += dt * 2.0
		if pk.life <= 0.0:
			n.queue_free(); pickups.erase(pk); continue
		var off := n.global_position - player.global_position; off.y = 0
		if off.length() < 1.0 and not player.armor.is_full():
			player.armor.add(ArmorState.PACKS.light.armor)
			hud.info("+%d armor" % ArmorState.PACKS.light.armor); sfx.play("buy", -6)
			n.queue_free(); pickups.erase(pk)

func on_player_downed(p: Player) -> void:
	over = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.banner("", 0)
	hud.show_game_over(round, kills)
	sfx.play("round_end", 0, 0.7)

func bark(text: String) -> void:
	hud.bark(text)

# ---------------------------------------------------------------- abilities
func use_ability(p: Player) -> void:
	match p.cdef.ability:
		"bass_drop":
			var dmg := Characters.bass_damage(maxi(round, 1))
			for z in zombies.duplicate():
				var off: Vector3 = z.global_position - p.global_position; off.y = 0
				if off.length() > Characters.BASS_RADIUS_M: continue
				if z.state == Zombie.State.CHASE and off.length() > 0.01:
					z.push(off.normalized() * Characters.BASS_KNOCKBACK_M * 6.0)
				z.take_damage(dmg, false, p)
			_fx_sphere(p.global_position + Vector3.UP, Characters.BASS_RADIUS_M, Color(0.5, 0.3, 1.0, 0.35))
			sfx.play("bass_drop")
			hud.info("%s!" % p.cdef.ability_name)
		"fortify":
			var total := 0
			for w in map.windows.values(): total += w.bar.repair_all(); w.refresh()
			if total == 0:
				hud.info("Nothing to repair"); return
			p.economy.on_repair(total)
			sfx.play("plank_place")
			hud.info("%s: +%d planks" % [p.cdef.ability_name, total])
	p.ability_cd = p.cdef.ability_cooldown

# ---------------------------------------------------------------- interactions
func _deny(msg: String) -> void:
	hud.info(msg); sfx.play("deny", -6)

func repair_window(p: Player, w: WindowBarricade) -> void:
	var n := w.bar.repair_planks(p.cdef.repair_planks_per_use)
	if n > 0:
		p.economy.on_repair(n, p.cdef.repair_points_mult)
		w.refresh(); sfx.play_at("plank_place", w.center(), -2)

func buy_door(p: Player, id: String) -> void:
	var err := facility.buy_door(id, p.economy)
	if err != "": _deny(err); return
	sfx.play("door"); sfx.play("buy", -6)
	map.open_door(id)
	hud.info("%s opened" % Facility.DOORS[id].label)

func throw_power(lever: Node3D) -> void:
	if not facility.throw_power(): return
	lever.rotation.x = -0.6
	map.set_power(true)
	sfx.play("power_on")
	hud.banner("Power restored", 3.0)
	env.ambient_light_energy = 0.5

func perk_prompt(p: Player, id: String) -> String:
	var d: Dictionary = Perks.ALL[id]
	if not facility.power_on: return "%s: power required" % d.name
	if p.perks.has(id): return ""
	return "%s (%s): %d" % [d.name, d.desc, d.cost]

func buy_perk(p: Player, id: String) -> void:
	var err := Perks.buy(id, p.perks, p.economy, facility.power_on)
	if err != "": _deny(err); return
	sfx.play("perk")
	if id == "ironhide": p.set_max_health_from_perks()
	if id == "quickhand": p.apply_reload_perk()
	hud.info("%s active" % Perks.ALL[id].name)

func forge_prompt(p: Player) -> String:
	if not facility.power_on: return "%s: power required" % OverchargeForge.NAME
	var c := forge.cost_for(p.weapon())
	if c < 0: return "%s: weapon maxed" % OverchargeForge.NAME
	return "%s -> Mk.%d: %d" % [OverchargeForge.NAME, p.weapon().tier + 2, c]

func use_forge(p: Player) -> void:
	if not facility.power_on: _deny("Power required"); return
	var up := forge.upgrade(p.weapon(), p.economy)
	if up == null:
		_deny("Already maxed" if p.weapon().is_maxed() else "Not enough points"); return
	p.loadout.replace_current(up); p.apply_reload_perk()
	sfx.play("forge"); hud.info("Upgraded: %s" % up.display_name())

func crate_prompt(p: Player) -> String:
	match crate_node.state:
		CrateNode.State.ROLLING: return ""
		CrateNode.State.READY: return "Take %s" % Weapons.make(crate_node.result).name
	return "Mystery Crate: %d" % crate.cost

func use_crate(p: Player) -> void:
	match crate_node.state:
		CrateNode.State.IDLE:
			var id := crate.buy(p.economy, rng, p.weapon().id)
			if id == "": _deny("Not enough points"); return
			crate_node.start(id); sfx.play_at("crate", crate_node.global_position + Vector3.UP)
		CrateNode.State.READY:
			var w := Weapons.make(crate_node.take())
			p.loadout.give(w); p.apply_reload_perk()
			hud.info("Got %s!" % w.name); sfx.play("buy", -6)

func wall_prompt(p: Player, id: String) -> String:
	if p.loadout.has(id) >= 0: return ""
	return "Buy %s: %d" % [Weapons.make(id).name, Weapons.WALL_PRICES[id]]

func buy_wall(p: Player, id: String) -> void:
	if p.loadout.has(id) >= 0: return
	if not p.economy.spend(Weapons.WALL_PRICES[id]): _deny("Not enough points"); return
	p.loadout.give(Weapons.make(id)); p.apply_reload_perk()
	sfx.play("buy", -4); hud.info("Bought %s" % Weapons.make(id).name)

func buy_armor(p: Player, pack_id: String) -> void:
	if p.armor.is_full(): _deny("Armor full"); return
	if not p.armor.buy(pack_id, p.economy): _deny("Not enough points"); return
	sfx.play("buy", -4); hud.info("%s equipped" % ArmorState.PACKS[pack_id].name)

func restart() -> void: restart_requested.emit()
func to_menu() -> void: exit_to_menu.emit()
