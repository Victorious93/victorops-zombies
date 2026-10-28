class_name Game
extends Node3D
## One solo match: map, player, round director, machines, HUD. Rules come from scripts/rules.

signal exit_to_menu
signal restart_requested

var character_id := Characters.DEFAULT
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
var brute_pending := false
var gas_clouds: Array = []   ## {node, pos, life}
var slowmo_t := 0.0
var type_counts := {}        ## sim/test stats: spawned per zombie type
var zombies: Array = []
var pickups: Array = []
var over := false
var kills := 0
var interactables: Array = []
var current_prompt := ""
var current_target = null
var env: Environment
var auto_rounds := true
var fx: Fx
var settings := GameSettings.new()
var music: AudioStreamPlayer
var resonance := Resonance.new()
var crate_mover: CrateMover
var crate_it: Dictionary
var grenades: Array = []
var tint := 0.0
var paused := false
var power := PowerUps.new()
var drops: Array = []        ## power-up pickups on the floor
var tutorial: Tutorial
var allow_tutorial := true     ## scripted clips/shots turn this off
var _tut_frames := 0
var _tut_last := Vector3.INF
var god_mode := false        ## screenshots only
var forge_busy := 0.0
var groan_t := 6.0
var round_times := {}        ## round -> seconds (sim report)
var round_clock := 0.0
var downs := 0
## v7 side content
var quest := WonderQuest.new()
var pact := PactStone.new()
var stats := RunStats.new()
var high := HighScore.new()
var quest_nodes: QuestNodes
var alt_last := {}            ## weapon id -> time of the last alt-ammo proc
var boss_pending := false
var boss: Zombie = null
var stuck_respawns := 0

func on_zombie_stuck(_z) -> void: stuck_respawns += 1
const SETTINGS_PATH := "user://settings.cfg"
const BASE_FOG := Color(0.06, 0.07, 0.09)

func _ready() -> void:
	rng.randomize()
	load_settings(settings)
	sfx = Sfx.new(); add_child(sfx)
	fx = Fx.new(); fx.game = self; add_child(fx)
	_build_env()
	map = FacilityMap.new(); add_child(map); map.build(self); map.build_sky()
	quest.pick_spots(rng)
	quest_nodes = QuestNodes.new(); map.add_child(quest_nodes); quest_nodes.build(self, map)
	map.bake_navigation_mesh(false)
	player = Player.new(); player.game = self; player.char_id = character_id
	player.position = Vector3(0, 0.1, 3); add_child(player)
	hud = Hud.new(); hud.game = self; hud.process_mode = Node.PROCESS_MODE_ALWAYS; add_child(hud)
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	touch = TouchControls.new()
	touch.visible = force_touch or DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	hud.add_child(touch)
	player.touch = touch
	sfx.start_ambient()
	_start_music()
	apply_settings()
	hud.banner("Hold the line", 3.0)
	crate_mover = CrateMover.new(map.crate_spots, rng)
	if not touch.visible and not OS.has_feature("headless"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _build_env() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.012, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.26, 0.3, 0.42)
	env.ambient_light_energy = 0.2
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.06, 0.07, 0.09)
	env.fog_density = 0.055
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.adjustment_enabled = true
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)

static func load_settings(s: GameSettings) -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		s.from_dict(cf.get_value("voz", "settings", {}))
	else:
		s.set_preset(GameSettings.default_preset(OS.has_feature("mobile")))

static func save_settings(s: GameSettings) -> void:
	var cf := ConfigFile.new(); cf.set_value("voz", "settings", s.to_dict()); cf.save(SETTINGS_PATH)

func settings_shadows() -> bool: return settings.data().shadows

func apply_settings() -> void:
	var d := settings.data()
	get_viewport().scaling_3d_scale = d.scale
	get_viewport().msaa_3d = Viewport.MSAA_2X if d.msaa >= 2 else Viewport.MSAA_DISABLED
	env.glow_enabled = d.glow
	env.fog_enabled = d.fog
	fx.particle_scale = d.particles
	if map: map.apply_quality(d)
	if music: music.volume_db = GameSettings.linear_to_db_safe(settings.music) - 10.0
	AudioServer.set_bus_volume_db(0, GameSettings.linear_to_db_safe(settings.sfx))
	if player:
		player.sens = settings.sensitivity; player.aim_assist = settings.aim_assist
		player.auto_fire = settings.auto_fire; player.gyro_mode = settings.gyro; player.look_curve = settings.look_curve
		if player.flashlight: player.flashlight.shadow_enabled = d.shadows
	if touch:
		touch.floating = settings.joystick != "fixed"; touch.fire_scale = settings.fire_size; touch._layout()

## Pull the background loop down while a round sting plays, then bring it back.
func duck_music(sec: float) -> void:
	if music == null: return
	var base := GameSettings.linear_to_db_safe(settings.music) - 10.0
	var tw := create_tween()
	tw.tween_property(music, "volume_db", base - 14.0, 0.4)
	tw.tween_interval(sec)
	tw.tween_property(music, "volume_db", base, 1.5)

func _start_music() -> void:
	var s := sfx.stream("music") as AudioStreamWAV
	if s == null: return
	s = s.duplicate(); s.loop_mode = AudioStreamWAV.LOOP_FORWARD; s.loop_begin = 0
	s.loop_end = int(s.get_length() * s.mix_rate)
	music = AudioStreamPlayer.new(); music.stream = s; add_child(music); music.play()

func toggle_pause() -> void:
	if over: return
	paused = not paused
	hud.show_pause(paused)
	if not touch.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	get_tree().paused = paused

func add_interactable(pos: Vector3, radius: float, prompt: Callable, use: Callable, hold := false) -> Dictionary:
	var it := {pos = pos, r = radius, prompt = prompt, use = use, hold = hold}
	interactables.append(it)
	return it

# ---------------------------------------------------------------- loop
func _process(dt: float) -> void:
	if over or player == null or paused: return
	_update_prompt()
	_update_rounds(dt)
	_update_pickups(dt)
	_update_grenades(dt)
	_update_drops(dt)
	_update_gas(dt)
	_update_slowmo(dt)
	_update_tutorial(dt)
	for id in power.update(dt):
		hud.info("%s wore off" % PowerUps.ALL[id].name); sfx.play("pu_end", -6)
	player.economy.mult = 2 if power.active("doublepay") else 1
	round_clock += dt
	stats.time += dt
	if boss and (not is_instance_valid(boss) or boss.state == Zombie.State.DEAD): boss = null
	hud.boss_bar(boss)
	# distant groans from outside the walls
	groan_t -= dt
	if groan_t <= 0.0:
		groan_t = rng.randf_range(7.0, 16.0)
		var a := rng.randf() * TAU
		sfx.play_at("groan%d" % (rng.randi() % 3 + 1), player.global_position + Vector3(cos(a), 0.5, sin(a)) * 22.0, -10, rng.randf_range(0.7, 0.85))
	tint = move_toward(tint, 0.0, dt * 0.35)
	env.adjustment_saturation = 1.0 - tint * 0.3
	env.fog_light_color = BASE_FOG.lerp(Color(0.35, 0.03, 0.02), tint) if not Rounds.is_special(round) else Color(0.2, 0.03, 0.02)

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
			round_clock = 0.0
			player.economy.on_round_start(); power.on_round_start()
			to_spawn = Rounds.zombie_count(round)
			spawn_cd = 1.0
			pact.on_round_start(round)
			boss_pending = Rounds.is_boss(round)
			if boss_pending:
				to_spawn = Rounds.boss_escort(round)
				hud.banner("Round %d · THE WARDEN" % round, 4.0)
				announce("ann_boss_v7"); sfx.play("boss_roar_v7", 0)
			elif Rounds.is_special(round):
				hud.banner("Round %d · FRENZY" % round, 3.5)
			else:
				hud.banner("Round %d" % round, 3.0)
			sfx.play("sting", -6)
			sfx.play("round_start_v6", -1)
			if not boss_pending: announce("ann_round_v7", 1.4)
			duck_music(5.0)
			sfx.play("rumble", -3); player.add_trauma(0.45)
			brute_pending = ZombieTypes.is_brute_round(round)
			if brute_pending: hud.banner("Round %d · BRUTE" % round, 3.5)
			tint = 1.0
			hud.round_flash(); hud.tally_flip(round)
			if round > 1:
				player.equipment.on_round_start()
	elif to_spawn > 0:
		spawn_cd -= dt
		if spawn_cd <= 0.0 and zombies.size() < Rounds.MAX_ALIVE:
			var ty := "brute" if brute_pending and to_spawn <= Rounds.zombie_count(round) / 2 else ZombieTypes.pick(round, rng.randf())
			if ty == "brute": brute_pending = false
			if boss_pending and to_spawn <= Rounds.boss_escort(round) - 2: ty = "warden"; boss_pending = false
			var nz := spawn_zombie("", ty)
			if ty == "warden": boss = nz
			to_spawn -= 1
			spawn_cd = Rounds.spawn_interval(round)
	elif zombies.size() == 1 and zombies[0].state != Zombie.State.DEAD and not zombies[0].crawler:
		zombies[0].make_crawler()   ## the last one of the round drags itself along: time to train/rebuy
	if to_spawn == 0 and zombies.is_empty() and intermission <= 0.0:
		round_times[round] = round_clock
		intermission = Rounds.INTERMISSION
		hud.banner("Round %d survived" % round, 3.0)
		sfx.play("round_end", -7)
		sfx.play("round_end_v6", -1)
		if pact.on_round_end(round): _seal_pact()
		duck_music(4.0)
		tint = 0.6
		player.health = player.max_health

## Window a stuck zombie should re-enter from: the one nearest the player.
func respawn_window_for(z: Zombie) -> WindowBarricade:
	var best: WindowBarricade = z.window; var bd := 1e9
	for id in facility.active_windows():
		var w: WindowBarricade = map.windows[id]
		var d := w.inside_point.distance_to(player.global_position)
		if d < bd: bd = d; best = w
	return best

func spawn_zombie(win_id := "", ztype := "walker") -> Zombie:
	var ids := facility.active_windows()
	if win_id == "": win_id = ids[rng.randi() % ids.size()]
	var w: WindowBarricade = map.windows[win_id]
	var z := Zombie.new()
	z.setup(self, w, maxi(round, 1), ztype)
	type_counts[ztype] = type_counts.get(ztype, 0) + 1
	if ztype == "warden": sfx.play_at("boss_roar_v7", w.spawn_point + Vector3.UP * 2, 6)
	if ztype == "brute": sfx.play_at("brute_roar", w.spawn_point + Vector3.UP * 2, 4)
	z.position = w.spawn_point + Vector3(rng.randf_range(-1.5, 1.5), 0, rng.randf_range(-1.5, 1.5))
	add_child(z)
	zombies.append(z)
	return z

# ---------------------------------------------------------------- combat
func _part_of(z: Zombie, y: float) -> String:
	var rel := y - z.global_position.y
	if z.crawler: return "head" if rel > 0.55 else "body"
	if rel > z.head_y(): return "head"
	if rel < Zombie.LEG_Y: return "legs"
	return "body"

func _pay(p: Player, at: Vector3, before: int) -> void:
	var gain := p.economy.points - before
	if gain > 0: fx.popup(at, "+%d" % gain); stats.points_earned += gain

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
			var part := _part_of(z, r.position.y)
			var head := part == "head"
			var dmg := int(w.damage * (Perks.head_mult(p.perks) if head else 1.0))
			var before := p.economy.points
			p.economy.on_hit()
			var was_alive := z.state != Zombie.State.DEAD
			z.take_damage(dmg, head, p, part, dir * (3.0 + w.damage * 0.02) * w.kick_mult())
			var killed := was_alive and z.state == Zombie.State.DEAD
			_pay(p, r.position + Vector3.UP * 0.3, before)
			var armored := ZombieTypes.is_heavy(z.ztype) and not head
			hud.hitmarker(killed, head, armored)
			sfx.play("hitmarker", -10, 1.25 if head else 1.0)
			sfx.play("hit_tick_v6", -8 if killed else -12, 0.8 if killed else (1.2 if head else 1.0))
			sfx.play_at(GunFeel.impact_sound(true, armored, false), r.position, -3, randf_range(0.9, 1.1))
			sfx.play_at("thwack", r.position, -6, randf_range(0.9, 1.1))
			if head: sfx.play("headshot_pop", -4 if killed else -9, randf_range(0.95, 1.08))
			if killed: sfx.play("kill_confirm", -10)
			if killed: sfx.play("gore", -8, randf_range(0.9, 1.1))
			fx.blood_hit(r.position, dir)
			if w.splash > 0.0: _splash(p, r.position, w, z)
			_alt_ammo(p, z, w, dmg, killed)
			if pierce > 0:
				pierce -= 1; exclude.append(z.get_rid()); from = r.position; continue
			break
		else:
			var col: Object = r.collider
			if col and col.has_meta("fuse"):
				_shoot_fuse(p, col)
			var n: Vector3 = r.normal
			fx.bullet_hole(r.position, n, w.weight >= 1.2)
			if randf() < 0.6: sfx.play_at(GunFeel.impact_sound(false, false, col is StaticBody3D and n.y < 0.5), r.position, -8, randf_range(0.85, 1.15))
			if w.splash > 0.0: _splash(p, r.position, w, null)
			break
	var m: Node3D = p.vm.muzzle if p.vm and p.vm.muzzle else null
	_tracer(m.global_position if m else origin, end_point, w)

func _shoot_fuse(p: Player, col: Object) -> void:
	var id: String = col.get_meta("fuse")
	var res := resonance.shoot(id, facility.power_on)
	if res == "":
		if not facility.power_on: hud.info("Something hums... it needs power")
		return
	map.fuse_lit(id)
	sfx.play("egg_fuse", -2)
	hud.info("Resonance fuse %d / %d" % [resonance.found(), Resonance.FUSES.size()])
	if res == "complete":
		sfx.play("egg_complete")
		hud.banner("THE BLACKWATER SIGNAL", 4.0)
		p.economy.points += Resonance.REWARD_POINTS
		fx.popup(p.global_position + Vector3.UP * 2.0 - p.global_basis.z * 2.0, "+%d" % Resonance.REWARD_POINTS, Color(0.6, 0.9, 1.0))
		if not p.weapon().is_maxed():
			var up := p.weapon().upgraded_version()
			if up: p.loadout.replace_current(up); p.apply_reload_perk(); hud.info("Free overcharge: %s" % up.display_name())

func knife_target(p: Player, reach: float) -> Zombie:
	var best: Zombie = null; var bd := reach
	var fwd := -p.cam.global_basis.z; fwd.y = 0; fwd = fwd.normalized()
	for z in zombies:
		if not is_instance_valid(z) or z.state == Zombie.State.DEAD: continue
		var off: Vector3 = z.global_position - p.global_position; off.y = 0
		var d := off.length()
		if d < bd and (d < 0.6 or fwd.dot(off / d) > 0.5):
			bd = d; best = z
	return best

func melee(p: Player) -> void:
	var fwd := -p.cam.global_basis.z; fwd.y = 0; fwd = fwd.normalized()
	var best := knife_target(p, Equipment.KNIFE_RANGE_M + 0.4)
	if best == null: return
	var before := p.economy.points
	p.economy.on_hit()
	var was_alive := best.state != Zombie.State.DEAD
	best.take_damage(Equipment.KNIFE_DAMAGE, false, p, "body", fwd * 3.0, true)
	_pay(p, best.global_position + Vector3.UP * 1.6, before)
	hud.hitmarker(was_alive and best.state == Zombie.State.DEAD)
	sfx.play("knife_hit", -2, randf_range(0.9, 1.1))
	fx.blood_hit(best.global_position + Vector3.UP * 1.2, fwd)
	p.add_trauma(0.12)

func throw_grenade(p: Player, from: Vector3, vel: Vector3) -> void:
	var b := RigidBody3D.new()
	b.collision_layer = 0; b.collision_mask = 1
	b.mass = 0.4; b.continuous_cd = true
	var pm := PhysicsMaterial.new(); pm.bounce = 0.35; pm.friction = 0.8; b.physics_material_override = pm
	var cs := CollisionShape3D.new(); var sh := SphereShape3D.new(); sh.radius = 0.07; cs.shape = sh; b.add_child(cs)
	b.add_child(ModelLib.prop("grenade", 0.13, false, false))
	b.contact_monitor = true; b.max_contacts_reported = 1
	b.body_entered.connect(func(_n): if b.linear_velocity.length() > 2.0: sfx.play_at("grenade_bounce", b.global_position, -6))
	add_child(b); b.global_position = from; b.linear_velocity = vel
	b.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
	grenades.append({body = b, t = Equipment.GRENADE_FUSE, owner = p})

func _update_grenades(dt: float) -> void:
	for g in grenades.duplicate():
		g.t -= dt
		if g.t > 0.0: continue
		grenades.erase(g)
		var b: RigidBody3D = g.body
		var at := b.global_position
		b.queue_free()
		explode(g.owner, at, Equipment.GRENADE_RADIUS_M, Equipment.grenade_damage(maxi(round, 1)))

func explode(p: Player, at: Vector3, radius: float, dmg: int) -> void:
	fx.explosion(at, radius)
	sfx.play_at("explosion", at, 2)
	for z in zombies.duplicate():
		if not is_instance_valid(z) or z.state == Zombie.State.DEAD: continue
		var d: float = (z.global_position + Vector3.UP * 0.9).distance_to(at)
		if d > radius: continue
		var before := p.economy.points
		var dirv: Vector3 = (z.global_position - at); dirv.y = 0
		z.explosive_hit = true
		z.take_damage(int(dmg * Equipment.grenade_falloff(d / radius * Equipment.GRENADE_RADIUS_M)), false, p, "legs" if d < radius * 0.5 else "body", dirv.normalized() * 8.0 + Vector3.UP * 4.0)
		if is_instance_valid(z) and z.state != Zombie.State.DEAD: z.explosive_hit = false
		_pay(p, z.global_position + Vector3.UP * 1.8, before)
	var pd := player.global_position.distance_to(at)
	player.add_trauma(clampf(1.2 - pd / (radius * 3.0), 0.0, 0.9))

func _splash(p: Player, at: Vector3, w: WeaponDef, skip) -> void:
	var r := w.splash_m()
	for z in zombies.duplicate():
		if z == skip or not is_instance_valid(z) or z.state == Zombie.State.DEAD: continue
		if (z.global_position + Vector3.UP).distance_to(at) < r + 0.5:
			z.take_damage(w.damage / 2, false, p)
	var sp := _fx_sphere(at, r, Color(0.3, 1.0, 0.8, 0.5)); sp.scale = Vector3.ONE * 0.2

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

func on_zombie_killed(z: Zombie, p: Player, headshot: bool, knife := false) -> void:
	zombies.erase(z)
	kills += 1
	stats.kills = kills
	if headshot: stats.headshots += 1
	if z.ztype == "warden":
		stats.bosses += 1; hud.banner("THE WARDEN FALLS", 3.5); announce("ann_sealed_v7")
	if pact.on_kill(z.global_position.distance_to(WonderQuest.STONE)):
		hud.banner("The Pact Stone is sated", 2.5); sfx.play_at("pact_step_v7", WonderQuest.STONE, 0); announce("ann_pact_v7")
		quest_nodes.stone_step(pact.step, false)
	var pu := power.roll(rng)
	var forced := ZombieTypes.guaranteed_drop(z.ztype)
	if forced != "": _spawn_drop(forced, z.global_position)
	elif pu != "" and z.window and not _outside_map(z): _spawn_drop(pu, z.global_position)
	if ZombieTypes.ALL[z.ztype].points > 0 and p:
		p.economy.points += ZombieTypes.ALL[z.ztype].points * p.economy.mult
		stats.points_earned += ZombieTypes.ALL[z.ztype].points * p.economy.mult
	# last kill of the round: brief slow-motion
	if to_spawn == 0 and zombies.is_empty() and round >= 1 and not headless_sim():
		slowmo_t = 1.1; Engine.time_scale = 0.3; sfx.play("slowmo", -2)
	if p:
		var before := p.economy.points
		p.economy.on_kill(headshot, knife)
		_pay(p, z.global_position + Vector3.UP * 2.0, before)
		hud.kill_feed(headshot)
	if rng.randf() < ArmorState.DROP_CHANCE:
		_drop_armor(z.global_position)

func headless_sim() -> bool:
	return DisplayServer.get_name() == "headless"

func _update_slowmo(dt: float) -> void:
	if slowmo_t <= 0.0: return
	slowmo_t -= dt / maxf(Engine.time_scale, 0.05)   # real seconds
	Engine.time_scale = 1.0 if slowmo_t <= 0.0 else lerpf(1.0, 0.3, clampf(slowmo_t / 0.6, 0.0, 1.0))

## Bloater gas: a lingering green cloud that hurts while the player stands in it.
func gas_cloud(at: Vector3) -> void:
	var root := Node3D.new(); add_child(root); root.global_position = Vector3(at.x, maxf(at.y, 0.0) + 0.7, at.z)
	var p := CPUParticles3D.new(); p.amount = maxi(6, int(30 * fx.particle_scale)); p.lifetime = 2.5
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE; p.emission_sphere_radius = ZombieTypes.BLOATER_RADIUS * 0.6
	p.gravity = Vector3(0, 0.15, 0); p.initial_velocity_max = 0.3; p.scale_amount_min = 2.0; p.scale_amount_max = 3.4
	var qm := QuadMesh.new(); qm.size = Vector2.ONE
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_texture = fx._soft_tex; m.albedo_color = Color(0.45, 0.8, 0.15, 0.34); m.vertex_color_use_as_albedo = true
	qm.material = m; p.mesh = qm
	var g := Gradient.new(); g.set_color(0, Color(1, 1, 1, 0)); g.add_point(0.3, Color(1, 1, 1, 1)); g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	p.color_ramp = g
	root.add_child(p)
	var l := OmniLight3D.new(); l.light_color = Color(0.5, 1.0, 0.2); l.light_energy = 1.1; l.omni_range = 5.0; l.position.y = 0.4
	root.add_child(l)
	gas_clouds.append({node = root, pos = root.global_position, life = ZombieTypes.GAS_TIME, tick = 0.0})

func _update_gas(dt: float) -> void:
	for g in gas_clouds.duplicate():
		g.life -= dt
		if g.life <= 0.0:
			(g.node as Node3D).queue_free(); gas_clouds.erase(g); continue
		if g.life < 1.0: ((g.node as Node3D).get_child(0) as CPUParticles3D).emitting = false
		var off: Vector3 = player.global_position - g.pos; off.y = 0
		if off.length() < ZombieTypes.BLOATER_RADIUS * 0.85:
			g.tick -= dt
			if g.tick <= 0.0:
				g.tick = 0.5
				player.take_damage(int(ZombieTypes.GAS_DPS * 0.5), g.pos)
				hud.gas_flash()

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

func _outside_map(z: Zombie) -> bool:
	return z.state == Zombie.State.RISE or z.state == Zombie.State.TO_WINDOW or z.state == Zombie.State.TEAR

# ---------------------------------------------------------------- power-ups
func _spawn_drop(id: String, at: Vector3) -> void:
	var d: Dictionary = PowerUps.ALL[id]
	var root := Node3D.new(); add_child(root); root.global_position = at + Vector3.UP * 0.9
	var mi := MeshInstance3D.new(); var tm := TorusMesh.new(); tm.inner_radius = 0.22; tm.outer_radius = 0.32
	var m := StandardMaterial3D.new(); m.albedo_color = d.color; m.emission_enabled = true; m.emission = d.color
	m.emission_energy_multiplier = 3.0; mi.mesh = tm; mi.material_override = m; mi.rotation.x = PI / 2; root.add_child(mi)
	var icon := Label3D.new(); icon.text = PowerUps.ICONS[id]; icon.font_size = 96; icon.pixel_size = 0.004
	icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED; icon.modulate = d.color; icon.outline_size = 18; root.add_child(icon)
	var gl := OmniLight3D.new(); gl.light_color = d.color; gl.light_energy = 1.5; gl.omni_range = 3.0; root.add_child(gl)
	drops.append({node = root, id = id, life = PowerUps.PICKUP_LIFE})
	sfx.play_at("pu_spawn", root.global_position, -2)

func _update_drops(dt: float) -> void:
	for d in drops.duplicate():
		d.life -= dt
		var n: Node3D = d.node
		n.rotation.y += dt * 2.5
		n.position.y += sin(Time.get_ticks_msec() * 0.004) * dt * 0.15
		n.visible = d.life > 6.0 or fmod(d.life, 0.4) > 0.15   # blink before it vanishes
		if d.life <= 0.0: n.queue_free(); drops.erase(d); continue
		var off := n.global_position - player.global_position; off.y = 0
		if off.length() < 1.2 and not player.is_downed:
			n.queue_free(); drops.erase(d); collect_power(d.id)

func collect_power(id: String) -> void:
	var d: Dictionary = PowerUps.ALL[id]
	power.activate(id)
	hud.banner(d.name, 2.5); hud.info(d.desc)
	sfx.play("pu_" + id, 2)
	tint = maxf(tint, 0.3)
	match id:
		"restock":
			for s in player.loadout.slots: s.refill()
			player.equipment.grenades = Equipment.GRENADE_MAX
		"blackout":
			for z in zombies.duplicate():
				if is_instance_valid(z) and z.state != Zombie.State.DEAD:
					z.take_damage(z.hp + 1, false, null, "body", Vector3.UP * 3.0)
			player.economy.earn(PowerUps.BLACKOUT_POINTS)
			player.add_trauma(0.6); fx.explosion(player.global_position + Vector3.UP * 3.0, 2.0)
		"handyman":
			for w in map.windows.values(): w.bar.repair_all(); w.refresh()
			player.economy.earn(PowerUps.HANDYMAN_POINTS)
			sfx.play("plank_place")

# ---------------------------------------------------------------- last stand
func on_player_downed(p: Player) -> void:
	downs += 1
	stats.downs = downs
	pact.on_down()
	announce("ann_laststand_v7", 0.6)
	sfx.play("downed", 0)
	tint = 1.0
	if p.last_stand.will_revive:
		hud.banner("DOWN · Lazarus Fizz kicking in", 3.0)
	else:
		hud.banner("LAST STAND · bleeding out", 3.0)

func on_player_revived(p: Player) -> void:
	hud.banner("Back on your feet", 2.0); sfx.play("perk", -4)
	# clear space so you're not swarmed the instant you rise
	for z in zombies:
		if is_instance_valid(z) and z.global_position.distance_to(p.global_position) < 3.0:
			z.push((z.global_position - p.global_position).normalized() * 12.0)

func on_player_bled_out(p: Player) -> void:
	over = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.banner("", 0)
	stats.parts = quest.count(); stats.pact = pact.done
	var run := {"round": round, "kills": kills, "points": stats.points_earned, "headshots": stats.headshots}
	var prev := high.load_best().duplicate()
	var is_best := high.submit(run)
	hud.show_game_over(round, kills, stats, prev, is_best)
	announce("ann_gameover_v7", 0.4)
	if is_best: announce("ann_highscore_v7", 2.6)
	sfx.play("round_end", 0, 0.7)

## Voice-like announcer sting (synthesised) with the music ducked under it.
func announce(id: String, delay := 0.0) -> void:
	if delay <= 0.0:
		sfx.play(id, 0); duck_music(2.5); return
	get_tree().create_timer(delay, true, false, true).timeout.connect(func(): sfx.play(id, 0); duck_music(2.5))

## Forge alternate ammo: chance per hit to burn, arc or freeze.
func _alt_ammo(p: Player, z: Zombie, w: WeaponDef, dmg: int, killed: bool) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not AltAmmo.procs(w.alt_ammo, rng.randf(), now - float(alt_last.get(w.id, -99.0))): return
	alt_last[w.id] = now
	var at := z.global_position + Vector3.UP * 1.2
	match w.alt_ammo:
		AltAmmo.FIRE:
			sfx.play_at("alt_fire_v7", at, -2)
			if not killed: z.apply_status(AltAmmo.FIRE, dmg, p)
			fx.sparks(at, Vector3.UP, AltAmmo.COLORS[AltAmmo.FIRE], 16, 0.5, 3.0)
		AltAmmo.FREEZE:
			sfx.play_at("alt_freeze_v7", at, -2)
			if not killed: z.apply_status(AltAmmo.FREEZE, dmg, p)
			fx.sparks(at, Vector3.UP, AltAmmo.COLORS[AltAmmo.FREEZE], 14, 0.5, 2.0)
		AltAmmo.SHOCK:
			sfx.play_at("alt_shock_v7", at, -1)
			var n := 0
			for o in zombies.duplicate():
				if n >= AltAmmo.CHAIN_TARGETS: break
				if o == z or not is_instance_valid(o) or o.state == Zombie.State.DEAD: continue
				if o.global_position.distance_to(z.global_position) > AltAmmo.CHAIN_RANGE: continue
				var to: Vector3 = o.global_position + Vector3.UP * 1.2
				_arc(at, to)
				o.apply_status(AltAmmo.SHOCK, dmg, p)
				o.take_damage(AltAmmo.chain_damage(dmg), false, p)
				n += 1
			if not killed: z.apply_status(AltAmmo.SHOCK, dmg, p)
			fx.sparks(at, Vector3.UP, AltAmmo.COLORS[AltAmmo.SHOCK], 12, 0.3, 4.0)

func _arc(a: Vector3, b: Vector3) -> void:
	var mi := MeshInstance3D.new(); var im := ImmediateMesh.new(); mi.mesh = im
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.albedo_color = AltAmmo.COLORS[AltAmmo.SHOCK]
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, m)
	for i in 9:
		var f := i / 8.0
		var j := Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25)) if i > 0 and i < 8 else Vector3.ZERO
		im.surface_add_vertex(a.lerp(b, f) + j)
	im.surface_end(); add_child(mi)
	get_tree().create_timer(0.12).timeout.connect(mi.queue_free)

# ---------------------------------------------------------------- wonder weapon quest + Pact Stone
func collect_part(p: Player, part: String) -> void:
	if not quest.collect(part): return
	quest_nodes.part_taken(part)
	sfx.play("part_pickup_v7", -2); announce("ann_part_v7", 0.3)
	hud.banner("%s found  ·  %d / 3" % [WonderQuest.PART_NAMES[part], quest.count()], 2.5)

func use_bench(p: Player) -> void:
	if quest.build():
		quest_nodes.bench_built(); sfx.play_at("wonder_build_v7", WonderQuest.BENCH + Vector3.UP, 0)
		announce("ann_built_v7", 1.2); hud.banner("The Gloam Harp is assembled", 3.0); p.add_trauma(0.3)
	elif quest.take():
		quest_nodes.bench_taken()
		var w := Weapons.make(Weapons.QUEST_WONDER)
		p.loadout.give(w); p.apply_reload_perk(); sfx.play("buy", -4); hud.info("Got the Gloam Harp!")
	elif not quest.has_all():
		_deny("Find the missing parts")

func use_pact(p: Player) -> void:
	var step := pact.current()
	if step == "awaken" or step == "tithe":
		if not pact.pay(p.economy): _deny("Not enough points"); return
		sfx.play_at("pact_step_v7", WonderQuest.STONE, 0); announce("ann_pact_v7", 0.5)
		hud.banner("Pact Stone: %s" % PactStone.STEP_TEXT[pact.current()], 2.5)
		quest_nodes.stone_step(pact.step, false); p.add_trauma(0.25)
	elif step != "":
		hud.info(pact.prompt())

func _seal_pact() -> void:
	quest_nodes.stone_step(pact.step, true)
	hud.banner("PACT SEALED", 4.0); announce("ann_sealed_v7", 0.8)
	player.economy.points += PactStone.REWARD_POINTS
	for s in player.loadout.slots: s.refill()
	for id in ["ironhide", "quickhand", "marksman", "lazarus"]:
		if not player.perks.has(id) and Perks.ALL.has(id):
			player.perks[id] = true; player.set_max_health_from_perks(); player.apply_reload_perk()
			hud.info("The stone grants %s" % Perks.ALL[id].name); break

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
				z.take_damage(dmg, false, p, "body", off.normalized() * 6.0)
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
	p.add_trauma(0.4)

# ---------------------------------------------------------------- interactions
func _deny(msg: String) -> void:
	hud.info(msg); sfx.play("deny", -6)

func _update_tutorial(dt: float) -> void:
	_tut_frames += 1
	if _tut_frames == 3 and allow_tutorial and not settings.tutorial_done and DisplayServer.get_name() != "headless":
		tutorial = Tutorial.new(); hud.show_tutorial(true)
	if tutorial == null: return
	var pos := player.global_position
	if _tut_last != Vector3.INF: tutorial.event("move", Vector2(pos.x - _tut_last.x, pos.z - _tut_last.z).length())
	_tut_last = pos
	tutorial.update(dt)
	hud.set_tutorial(tutorial.prompt())
	if tutorial.done(): end_tutorial()

func end_tutorial() -> void:
	if tutorial: tutorial.skip()
	tutorial = null
	hud.show_tutorial(false)
	if not settings.tutorial_done:
		settings.tutorial_done = true; save_settings(settings)

func repair_window(p: Player, w: WindowBarricade) -> void:
	var n := w.bar.repair_planks(p.cdef.repair_planks_per_use)
	if n > 0 and tutorial: tutorial.event("rebuild")
	if n > 0:
		if p.economy.on_repair(n, p.cdef.repair_points_mult) == 0 and p.economy.repair_earned >= Economy.REPAIR_CAP_PER_ROUND:
			hud.info("Repair points maxed this round")
		w.refresh(); sfx.play_at("plank_place", w.center(), -2)

func buy_door(p: Player, id: String) -> void:
	var err := facility.buy_door(id, p.economy)
	if err != "": _deny(err); return
	sfx.play("door"); sfx.play("buy", -6)
	sfx.play("door_open_v6", -2)
	player.add_trauma(0.25)
	map.open_door(id)
	hud.info("%s opened" % Facility.DOORS[id].label)

func throw_power(lever: Node3D) -> void:
	if not facility.throw_power(): return
	lever.rotation.x = -0.6
	map.set_power(true)
	sfx.play("power_on")
	hud.banner("Power restored", 3.0)
	env.ambient_light_energy = 0.5
	player.add_trauma(0.3)

func perk_prompt(p: Player, id: String) -> String:
	var d: Dictionary = Perks.ALL[id]
	if not facility.power_on: return "%s: power required" % d.name
	if p.perks.get(id, false) == true: return ""
	if id == "lazarus" and int(p.perks.get("_lazarus_buys", 0)) >= Perks.LAZARUS_MAX: return "%s: sold out" % d.name
	return "%s (%s): %d" % [d.name, d.desc, d.cost]

func buy_perk(p: Player, id: String) -> void:
	var err := Perks.buy(id, p.perks, p.economy, facility.power_on)
	if err != "": _deny(err); return
	sfx.play("perk")
	if id == "ironhide": p.set_max_health_from_perks()
	if id == "quickhand": p.apply_reload_perk()
	hud.info("%s active" % Perks.ALL[id].name)

func forge_prompt(p: Player) -> String:
	if forge_busy > 0.0: return ""
	if not facility.power_on: return "%s: power required" % OverchargeForge.NAME
	var c := forge.cost_for(p.weapon())
	if c < 0: return "%s: weapon maxed" % OverchargeForge.NAME
	return "%s -> Mk.%d: %d" % [OverchargeForge.NAME, p.weapon().tier + 2, c]

func use_forge(p: Player) -> void:
	if not facility.power_on: _deny("Power required"); return
	if forge_busy > 0.0: return
	var slot := p.loadout.current
	var up := forge.upgrade(p.weapon(), p.economy)
	if up == null:
		_deny("Already maxed" if p.weapon().is_maxed() else "Not enough points"); return
	# the forge swallows the gun for ~5 s, then hands back the overcharged version
	forge_busy = OverchargeForge.FORGE_TIME
	var held: Ammo = p.loadout.slots[slot]
	held.reload_left = OverchargeForge.FORGE_TIME   # can't fire it while it's in the machine
	sfx.play("forge"); sfx.play("forge_jingle", -5); announce("ann_forge_v7", 0.4); hud.info("%s working..." % OverchargeForge.NAME)
	map.forge_working(OverchargeForge.FORGE_TIME)
	var tw := create_tween(); tw.tween_property(self, "forge_busy", 0.0, OverchargeForge.FORGE_TIME)
	tw.tween_callback(func():
		if p.loadout.slots.size() > slot and p.loadout.slots[slot] == held: held.swap(up)
		else: p.loadout.give(up)
		p.apply_reload_perk()
		sfx.play("forge_done", 0)
		hud.banner(up.display_name() + ("  ·  " + AltAmmo.NAMES[up.alt_ammo] if up.alt_ammo != "" else ""), 2.5))

func crate_prompt(p: Player) -> String:
	match crate_node.state:
		CrateNode.State.ROLLING: return ""
		CrateNode.State.READY: return "Take %s (%ds)" % [Weapons.make(crate_node.result).name, ceili(crate_node.t)]
	return "Mystery Crate: %d" % crate.cost

func use_crate(p: Player) -> void:
	match crate_node.state:
		CrateNode.State.IDLE:
			var id := crate.buy(p.economy, rng, p.weapon().id)
			if id == "": _deny("Not enough points"); return
			crate_node.start(id); sfx.play_at("crate", crate_node.global_position + Vector3.UP)
			sfx.play_at("crate_jingle", crate_node.global_position + Vector3.UP, -4)
			if crate_mover.on_roll(rng): crate_node.move_after = true
		CrateNode.State.READY:
			var w := Weapons.make(crate_node.take())
			p.loadout.give(w); p.apply_reload_perk()
			hud.info("Got %s!" % w.name); sfx.play("buy", -6)

func wall_prompt(p: Player, id: String) -> String:
	var i := p.loadout.has(id)
	if i >= 0:
		if p.loadout.slots[i].is_full(): return ""
		return "%s ammo: %d" % [p.loadout.slots[i].weapon.display_name(), Weapons.ammo_price(id) * (5 if p.loadout.slots[i].weapon.tier > 0 else 1)]
	return "Buy %s: %d" % [Weapons.make(id).name, Weapons.WALL_PRICES[id]]

func buy_wall(p: Player, id: String) -> void:
	var i := p.loadout.has(id)
	if i >= 0:
		var a: Ammo = p.loadout.slots[i]
		if a.is_full(): return
		if not p.economy.spend(Weapons.ammo_price(id) * (5 if a.weapon.tier > 0 else 1)): _deny("Not enough points"); return
		a.refill(); sfx.play("buy", -4); hud.info("Ammo refilled"); return
	if not p.economy.spend(Weapons.WALL_PRICES[id]): _deny("Not enough points"); return
	p.loadout.give(Weapons.make(id)); p.apply_reload_perk()
	if tutorial: tutorial.event("buy")
	sfx.play("buy", -4); hud.info("Bought %s" % Weapons.make(id).name)

func buy_armor(p: Player, pack_id: String) -> void:
	if p.armor.is_full(): _deny("Armor full"); return
	if not p.armor.buy(pack_id, p.economy): _deny("Not enough points"); return
	sfx.play("buy", -4); hud.info("%s equipped" % ArmorState.PACKS[pack_id].name)

## Called by the crate once its "overloaded" animation finishes.
func relocate_crate() -> void:
	var i := crate_mover.relocate(rng)
	var spot: Array = map.crate_spots[i]
	map.move_crate(spot[0], spot[1])
	crate_it.pos = spot[0] + Vector3(0, 1.0, 0) + Vector3(sin(spot[1]), 0, cos(spot[1])) * 1.0
	sfx.play_at("crate_move", spot[0] + Vector3.UP, 0)
	hud.info("The Mystery Crate moved: %s" % spot[2])

func restart() -> void: get_tree().paused = false; restart_requested.emit()
func to_menu() -> void: get_tree().paused = false; exit_to_menu.emit()
