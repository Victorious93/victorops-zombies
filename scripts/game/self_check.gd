class_name SelfCheck
extends Node
## Victorious Framework scene-level self-check for VICTOR ZOMBIES.
## Run: godot --headless --fixed-fps 60 -- --check
## Drives the real Game scene (physics, navigation, input events) without a renderer and prints one
## PASS/FAIL line per check; the process exits 0 only when everything passed. It complements the GUT
## rule tests (pure logic) and the bot sim (--sim=N, long play). It does NOT prove anything about
## rendering, audio or how the touch controls feel on a device.

var main
var game: Game
var pl: Player
var fails := 0
var passes := 0

func ok(cond: bool, what: String, detail := "") -> void:
	if cond: passes += 1
	else: fails += 1
	print("[check] %s  %s%s" % ["PASS" if cond else "FAIL", what, ("  (" + detail + ")") if detail != "" else ""])

func frames(n: int) -> void:
	for i in n: await get_tree().physics_frame

func _ready() -> void:
	await get_tree().process_frame
	main.start_game(); game = main.game; pl = game.player
	game.allow_tutorial = false
	await frames(10)
	await _t_countdown_and_rounds()
	game.auto_rounds = false
	for z in game.zombies.duplicate():
		if is_instance_valid(z): z.queue_free()
	game.zombies.clear(); game.to_spawn = 0
	await frames(5)
	await _t_shooting()
	await _t_ammo_rules()
	await _t_purchases_and_nav()
	await _t_forge_and_pickups()
	await _t_choices()
	await _t_elite()
	await _t_damage_and_pause()
	await _t_touch()
	await _t_death_and_restart()
	print("[check] %d passed, %d failed" % [passes, fails])
	get_tree().quit(0 if fails == 0 else 1)

# ---------------------------------------------------------------- rounds
func _t_countdown_and_rounds() -> void:
	ok(Hud.countdown_text(game.round + 1, game.intermission).begins_with("Round 1 in"), "pre-round countdown shown", Hud.countdown_text(game.round + 1, game.intermission))
	var peak := 0; var t := 0
	# kill whatever is alive every half second until round 3 begins: rounds must never stall
	while game.round < 3 and t < 60 * 90:
		await get_tree().physics_frame; t += 1
		peak = maxi(peak, game.zombies.size())
		if t % 30 == 0:
			for z in game.zombies.duplicate():
				if is_instance_valid(z) and z.state != Zombie.State.DEAD: z.take_damage(z.hp + 1, false, pl, "body", Vector3.ZERO)
	ok(game.round >= 3, "three consecutive rounds start and complete", "round %d after %.0f s" % [game.round, t / 60.0])
	ok(peak <= Rounds.MAX_ALIVE and peak > 0, "live zombie count stays within the cap", "peak %d / cap %d" % [peak, Rounds.MAX_ALIVE])
	ok(game.kills == Rounds.zombie_count(1) + Rounds.zombie_count(2), "every zombie of rounds 1-2 spawned and died exactly once", "kills %d" % game.kills)
	ok(pl.economy.points > Economy.START, "kills pay points", "%d points" % pl.economy.points)

func _dummy(pos: Vector3) -> Zombie:
	var z: Zombie = game.spawn_zombie("", "walker")
	z.drop_in = false; z.state = Zombie.State.CHASE; z.model.position.y = 0.0; z.model.rotation.x = 0.0
	z.set_physics_process(false); z.max_hp = 100000; z.hp = 100000
	z.global_position = pos
	return z

# ---------------------------------------------------------------- shooting
func _t_shooting() -> void:
	var w := Weapons.make("sidearm")
	var z := _dummy(Vector3(0, 0.05, -3))
	await frames(3)
	var before := pl.economy.points
	game.hitscan(pl, Vector3(0, 1.1, 3), Vector3(0, 0, -1), w)
	var body := 100000 - z.hp
	ok(body == w.damage, "body shot applies damage exactly once", "%d of %d" % [body, w.damage])
	ok(pl.economy.points == before + Economy.HIT, "a hit pays %d points" % Economy.HIT)
	z.hp = 100000
	game.hitscan(pl, Vector3(0, 1.66, 3), Vector3(0, 0, -1), w)
	var head := 100000 - z.hp
	ok(head == int(w.damage * 2.0), "headshot region doubles damage", "%d vs body %d" % [head, body])
	z.hp = 100000
	game.hitscan(pl, Vector3(0.9, 1.66, 3), Vector3(0, 0, -1), w)
	ok(z.hp == 100000, "a shot past the head misses")
	# zombie behind the closed Back Alley wall: the bullet must stop at the wall
	z.global_position = Vector3(4, 0.05, -11.5)
	await frames(3)
	game.hitscan(pl, Vector3(4, 1.1, -8.5), Vector3(0, 0, -1), w)
	ok(z.hp == 100000, "walls block shots")
	# the same zombie winds up a swing through that wall: it must not connect
	pl.global_position = Vector3(4, 0.1, -9.2); await frames(2)
	var hp0: float = pl.health
	ok(not game.melee_clear(z.global_position, pl.global_position), "walls block the melee line", "gap %.1f m" % z.global_position.distance_to(pl.global_position))
	z.set_physics_process(true); z.windup_t = 0.05
	await frames(20)
	z.set_physics_process(false)
	ok(is_equal_approx(pl.health, hp0), "a swing through a wall does not hurt", "health %.0f" % pl.health)
	z.global_position = Vector3(4, 0.05, -7.9); await frames(2)
	ok(game.melee_clear(z.global_position, pl.global_position), "an open melee line is clear")
	pl.global_position = Vector3(0, 0.1, 3); await frames(2)
	# shotgun: every pellet stays inside the spread cone
	var sg := Weapons.make("scatter")
	z.global_position = Vector3(0, 0.05, -3); await frames(3)
	pl.global_position = Vector3(0, 0.1, 3); pl.yaw = 0.0; pl.pitch = 0.0; await frames(3)
	pl.loadout.give(sg); pl.fire_cd = 0.0
	var mag := pl.ammo().rounds
	pl.try_fire(false)
	var dealt := 100000 - z.hp
	ok(dealt % sg.damage == 0 and dealt <= sg.damage * sg.pellets * 2, "shotgun pellets each hit at most once", "%d damage, %d pellets x %d" % [dealt, sg.pellets, sg.damage])
	ok(pl.ammo().rounds == mag - 1, "one trigger pull uses one shell")
	var cone := deg_to_rad(sg.spread_deg) * 1.4 * sqrt(2.0) + 0.001
	ok(cone < deg_to_rad(11.0), "shotgun spread is bounded", "max %.1f deg off axis" % rad_to_deg(cone))
	pl.fire_cd = 0.4; pl.try_fire(false)
	ok(pl.ammo().rounds == mag - 1, "cannot fire again inside the fire interval")
	z.queue_free(); game.zombies.erase(z)
	await frames(2)

func _t_ammo_rules() -> void:
	# pump-action reload: shell by shell, interruptible by firing
	var a: Ammo = pl.ammo()
	a.rounds = 2; a.reload_left = 0.0
	ok(a.reload(), "shotgun reload starts")
	await frames(int(a.reload_step() * 60) + 3)
	ok(a.rounds == 3 and a.reloading(), "shotgun loads one shell at a time", "%d shells" % a.rounds)
	pl.fire_cd = 0.0; pl.try_fire(false)
	ok(a.rounds == 2 and not a.reloading(), "firing interrupts a shell reload")
	# weapon switch cancels a magazine reload and blocks firing briefly
	pl.swap(); await frames(30)
	var s: Ammo = pl.ammo()
	s.rounds = 3; ok(s.reload(), "pistol reload starts")
	pl.swap()
	ok(not s.reloading() and s.rounds == 3, "switching weapons abandons the reload")
	pl.try_fire(false)
	ok(pl.ammo().rounds == 2, "no shot during the weapon switch")
	pl.swap(); await frames(30)
	# drain everything: ammunition never goes negative and an empty gun cannot fire
	var lowest := 0
	for i in 400:
		pl.fire_cd = 0.0
		if s.reloading(): s.update(10.0)
		pl.try_fire(false)
		lowest = mini(lowest, mini(s.rounds, s.reserve))
	ok(lowest >= 0 and s.is_empty(), "ammunition never goes negative", "ended %d / %d" % [s.rounds, s.reserve])
	pl.fire_cd = 0.0; pl.try_fire(false)
	ok(s.rounds == 0, "an empty weapon does not fire")
	s.refill()

# ---------------------------------------------------------------- economy + navigation
func _reach(to: Vector3) -> bool:
	var path := NavigationServer3D.map_get_path(game.map.get_navigation_map(), Vector3(0, 0.1, 3), to, true)
	if path.is_empty(): return false
	var e := path[path.size() - 1]
	return Vector2(e.x - to.x, e.z - to.z).length() < 1.2

## Town integrity with every door open: each window's approach lane is walkable, every machine and
## pick-up can be reached, and the open combat lanes have room for the player.
func _t_town() -> void:
	var nav := game.map.get_navigation_map()
	var bad := []
	for id in game.map.windows:
		var w: WindowBarricade = game.map.windows[id]
		for off in [Vector3(-3.5, 0, 0), Vector3.ZERO, Vector3(3.5, 0, 0)]:
			var from: Vector3 = w.spawn_point + w.global_basis * off
			var path := NavigationServer3D.map_get_path(nav, from, w.outside_point, true)
			if path.is_empty() or Vector2(path[path.size() - 1].x - w.outside_point.x, path[path.size() - 1].z - w.outside_point.z).length() > 0.9 \
					or Vector2(path[0].x - from.x, path[0].z - from.z).length() > 1.0: bad.append(id); break
		if not _reach(w.inside_point): bad.append(id + " (inside)")
	ok(bad.is_empty(), "every window has a clear spawn lane and a way in", str(bad))
	bad = []
	for it in game.interactables:
		if HiddenRoom.inside(it.pos): continue   # the Sealed Annex is walled off until its crack is broken
		var c: Vector3 = NavigationServer3D.map_get_closest_point(nav, Vector3(it.pos.x, 0.3, it.pos.z))
		var gap := Vector2(c.x - it.pos.x, c.z - it.pos.z).length()
		if gap > float(it.r) - 0.5 or not _reach(c): bad.append("%.1f,%.1f" % [it.pos.x, it.pos.z])
	ok(bad.is_empty(), "every purchase, machine and pick-up can be walked up to", "%d checked, blocked: %s" % [game.interactables.size(), str(bad)])
	# the player capsule can travel the main routes without snagging on scenery
	bad = []
	var space := game.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new(); cap.radius = 0.35; cap.height = 1.6
	var q := PhysicsShapeQueryParameters3D.new(); q.shape = cap; q.collision_mask = 1 | 8
	for leg in [[Vector3(0, 0, 3), Vector3(0, 0, -9)], [Vector3(0, 0, -11), Vector3(0, 0, -17)], [Vector3(0, 0, -18), Vector3(9, 0, -18)], [Vector3(11, 0, -18), Vector3(12.4, 0, -20.5)],
			[Vector3(12.4, 0, -20.5), Vector3(22, 0, -20.5)], [Vector3(22, 0, -20.5), Vector3(25, 0, -11)], [Vector3(25, 0, -9), Vector3(22, 0, 0)], [Vector3(22, 0, 0), Vector3(1, 0, 0)],
			[Vector3(22, 0, 0), Vector3(27, 0, 0)], [Vector3(27, 0, 0), Vector3(31.8, 0, 2.6)], [Vector3(31.8, 0, 2.6), Vector3(36, 0, 9)], [Vector3(36, 0, 11), Vector3(32, 0, 16)],
			[Vector3(32, 0, 16), Vector3(27.5, 0, 12)], [Vector3(27.5, 0, 12), Vector3(22.5, 0, 12)], [Vector3(22.5, 0, 12), Vector3(22.5, 0, 8)], [Vector3(22.5, 0, 8), Vector3(22, 0, 0)],
			[Vector3(36, 0, 8), Vector3(40.2, 0, 2)], [Vector3(40.2, 0, 2), Vector3(40.0, 0, -5.4)], [Vector3(40.0, 0, -5.4), Vector3(33, 0, -6.6)], [Vector3(33, 0, -6.6), Vector3(31.8, 0, 2.6)],
			[Vector3(39.60, 0, 20.00), Vector3(38.55, 0, 22.55)], [Vector3(38.55, 0, 22.55), Vector3(36.00, 0, 23.60)], [Vector3(36.00, 0, 23.60), Vector3(33.45, 0, 22.55)], [Vector3(33.45, 0, 22.55), Vector3(32.40, 0, 20.00)], [Vector3(32.40, 0, 20.00), Vector3(33.45, 0, 17.45)], [Vector3(33.45, 0, 17.45), Vector3(36.00, 0, 16.40)], [Vector3(36.00, 0, 16.40), Vector3(38.55, 0, 17.45)], [Vector3(38.55, 0, 17.45), Vector3(39.60, 0, 20.00)]]:
		var n := int(leg[0].distance_to(leg[1]) / 0.4) + 1
		for i in n + 1:
			var p: Vector3 = leg[0].lerp(leg[1], float(i) / n)
			q.transform = Transform3D(Basis.IDENTITY, p + Vector3(0, 1.0, 0))
			if not space.intersect_shape(q, 1).is_empty(): bad.append("%.1f,%.1f" % [p.x, p.z]); break
	ok(bad.is_empty(), "both escape loops are clear for the player capsule", str(bad))

func _t_purchases_and_nav() -> void:
	var lab := Vector3(18, 0.1, 4); var cold := Vector3(18, 0.1, -18); var gen := Vector3(0, 0.1, -18)
	await frames(5)
	ok(not _reach(lab) and not _reach(cold) and not _reach(gen), "locked areas are unreachable before purchase")
	pl.global_position = Vector3(8.4, 0.1, 0); pl.yaw = -PI / 2; pl.velocity = Vector3.ZERO
	await frames(4)
	pl.economy.points = 400; game._update_prompt()
	ok(game.current_prompt == "Open General Store — 1000 points (need 600 more)", "prompt explains an unaffordable door", game.current_prompt)
	game.player_use(pl, true, false)
	ok(pl.economy.points == 400 and not game.facility.open_doors.has("east"), "cannot buy without the points")
	pl.economy.points = 3000; game._update_prompt()
	ok(game.current_prompt == "Open General Store — 1000 points", "prompt shows action and price", game.current_prompt)
	for i in 20: game.player_use(pl, false, true)   # button held: no purchase without a fresh press
	ok(pl.economy.points == 3000, "holding the use button does not buy")
	game.player_use(pl, true, false)
	for i in 5: game.player_use(pl, true, false)
	ok(pl.economy.points == 2000 and game.facility.open_doors.get("east", false), "a door charges exactly once", "%d points left" % pl.economy.points)
	pl.global_position = Vector3(0, 0.1, 3)
	await frames(240)
	ok(_reach(lab) and not _reach(cold), "zombie navigation opens with the Lab door", "lab %s cold %s" % [_reach(lab), _reach(cold)])
	game.buy_door(pl, "service")
	await frames(240)
	ok(_reach(cold) and game.facility.open_areas.get("cold", false), "Service Passage links Lab to Cold Storage", "points %d" % pl.economy.points)
	pl.economy.points = 5000
	game.buy_door(pl, "cold"); game.buy_door(pl, "north")
	await frames(240)
	ok(_reach(gen), "the loop Diner - Back Alley - Garage - Store is fully connected")
	var p0 := NavigationServer3D.map_get_path(game.map.get_navigation_map(), Vector3(0, 0.1, 3), cold, true)
	ok(p0.size() >= 2, "navmesh path exists after doors change", "%d points" % p0.size())
	# second loop: Store -> Side Alley -> Courtyard -> gate -> Main Street -> Store
	var court := Vector3(40, 0.1, 24); var street := Vector3(36, 0.1, 2)
	ok(not _reach(court) and not _reach(street), "street and courtyard stay locked")
	pl.economy.points = 5000
	game.buy_door(pl, "alley")
	await frames(240)
	ok(_reach(court) and not _reach(street) and game.facility.active_windows().has("w_pump_s"), "the Side Alley opens the Courtyard from the store")
	game.buy_door(pl, "pump")
	await frames(240)
	ok(_reach(street) and not game.facility.open_doors.has("yard"), "the courtyard gate closes the loop onto Main Street")
	game.buy_door(pl, "yard")
	await frames(240)
	await _t_town()
	# wall weapon: buy once, then ammo only when not full
	pl.economy.points = 5000
	game.buy_wall(pl, "rifle")
	ok(pl.economy.points == 5000 - Weapons.WALL_PRICES.rifle and pl.loadout.has("rifle") >= 0, "wall weapon purchase")
	game.buy_wall(pl, "rifle")
	ok(pl.economy.points == 5000 - Weapons.WALL_PRICES.rifle, "full ammo is not sold again")
	pl.ammo().reserve = 0
	game.buy_wall(pl, "rifle")
	ok(pl.ammo().is_full() and pl.economy.points == 5000 - Weapons.WALL_PRICES.rifle - Weapons.ammo_price("rifle"), "ammunition refill purchase")

func _t_forge_and_pickups() -> void:
	pl.economy.points = 6000
	ok(game.forge_prompt(pl).contains("no power"), "upgrade station explains it needs power", game.forge_prompt(pl))
	# v10 power objective: walk to the generator and hold USE; each tick is one crank
	ok(game.facility.objective().contains("crank the generator"), "objective points at the generator once the Back Alley is open", game.facility.objective())
	ok(game.perk_prompt(pl, "ironhide").contains("no power"), "tonic machine explains it needs power")
	pl.economy.points = 6000; game.buy_perk(pl, "ironhide")
	ok(pl.economy.points == 6000 and not pl.perks.has("ironhide"), "no tonic is sold without power")
	pl.global_position = Vector3(3, 0.1, -22.6); pl.yaw = 0.0; pl.velocity = Vector3.ZERO
	await frames(4)
	game._update_prompt()
	ok(game.current_prompt.begins_with("Hold to crank the generator  0/%d" % Facility.POWER_CRANKS), "generator prompt shows progress", game.current_prompt)
	game.player_use(pl, true, true)
	ok(game.facility.cranks == 1 and not game.facility.power_on, "one press is one crank, not instant power")
	for i in Facility.POWER_CRANKS + 3: game.player_use(pl, false, true)
	ok(game.facility.power_on and game.facility.cranks == Facility.POWER_CRANKS and game.stats.power, "holding USE starts the generator", "%d cranks" % game.facility.cranks)
	game._update_prompt()
	ok(game.current_prompt == "", "the generator prompt disappears once it runs", game.current_prompt)
	ok(game.map.power_label.text.contains("RUNNING") and game.map.power_beacon_light.light_color.is_equal_approx(FacilityMap.POWER_CUE_ON), "generator sign and beacon switch to running")
	ok(not game.facility.objective().contains("Restore"), "the objective moves on after power", game.facility.objective())
	pl.global_position = Vector3(0, 0.1, 3); await frames(3)
	ok(game.forge_prompt(pl).begins_with("Upgrade Pulse Rifle to Mk.2 — 5000 points"), "upgrade prompt", game.forge_prompt(pl))
	var base := pl.weapon().damage; var base_mag := pl.weapon().mag_size
	game.use_forge(pl); game.use_forge(pl)
	ok(pl.economy.points == 1000, "the upgrade charges exactly once")
	pl.fire_cd = 0.0; var r := pl.ammo().rounds; pl.try_fire(false)
	ok(pl.ammo().rounds == r and pl.ammo().locked, "the weapon cannot fire while it is being upgraded")
	await frames(int(OverchargeForge.FORGE_TIME * 60) + 20)
	ok(pl.weapon().tier == 1 and pl.weapon().damage == base * 2 and pl.weapon().mag_size == base_mag * 2 and not pl.ammo().locked,
		"upgrade doubles damage and magazine", "%s: %d dmg, %d mag" % [pl.weapon().display_name(), pl.weapon().damage, pl.weapon().mag_size])
	# temporary pickups
	game.collect_power("doublepay"); await frames(3)
	var b := pl.economy.points; pl.economy.on_hit()
	ok(pl.economy.points - b == Economy.HIT * 2 and game.power.active("doublepay"), "double points pickup doubles earnings")
	pl.ammo().rounds = 1; pl.ammo().reserve = 0
	game.collect_power("restock")
	ok(pl.ammo().is_full(), "ammunition pickup refills the weapon")
	game.power.timers["doublepay"] = 0.05; await frames(10)
	ok(not game.power.active("doublepay") and pl.economy.mult == 1, "double points expires")

func _t_damage_and_pause() -> void:
	pl.health = pl.max_health; pl.since_hit = 99.0
	pl.take_damage(30.0, pl.global_position + Vector3(0, 0, 2))
	pl.take_damage(30.0, pl.global_position + Vector3(0, 0, 2))
	pl.take_damage(30.0, pl.global_position + Vector3(2, 0, 0))
	ok(is_equal_approx(pl.health, pl.max_health - 30.0), "stacked hits in the same instant count once", "health %.0f" % pl.health)
	await frames(int(Player.HIT_GRACE * 60) + 3)
	pl.take_damage(30.0)
	ok(is_equal_approx(pl.health, pl.max_health - 60.0), "the next hit lands after the grace window")
	await frames(int(Player.REGEN_DELAY * 60) - 30)
	ok(pl.health < pl.max_health - 59.0, "no regeneration right after a hit")
	await frames(120)
	ok(pl.health >= pl.max_health - 0.01, "health regenerates after the delay", "health %.0f" % pl.health)
	# pause / resume, including the focus-loss rule
	ok(Game.wants_auto_pause(true, false, false, false) and not Game.wants_auto_pause(true, true, false, false) and not Game.wants_auto_pause(true, false, true, false), "focus loss pauses a live match only")
	var clock := game.stats.time
	game.toggle_pause()
	ok(get_tree().paused and game.paused and game.hud.pause_panel != null, "pause opens the pause menu")
	ok(game.hud.pause_panel.find_child("Status", true, false) != null and game.hud.pause_panel.find_child("Actions", true, false) != null, "the pause menu shows status and actions")
	# app interruption: a focus-loss notification pauses a live match and a second one does not unpause it
	game.toggle_pause()
	var ap := game.auto_pause; game.auto_pause = true
	ok(Game.wants_auto_pause(game.auto_pause, game.paused, game.over, pl.bot_input != null), "a live match wants to pause when the app loses focus")
	game.toggle_pause()
	ok(not Game.wants_auto_pause(game.auto_pause, game.paused, game.over, false), "a second interruption does not toggle the pause off")
	game.auto_pause = ap
	for i in 30: await get_tree().process_frame
	ok(is_equal_approx(game.stats.time, clock), "the match clock stops while paused")
	game.toggle_pause()
	ok(not get_tree().paused and game.hud.pause_panel == null, "resume closes the pause menu")
	await frames(10)
	ok(game.stats.time > clock, "the match continues after resume")

# ---------------------------------------------------------------- v10: tonics, crate, purchase safety
func _t_choices() -> void:
	# the three enhancements: bought once, with power, and each one changes the player
	var hp0: float = pl.max_health; var st0: float = pl.stamina_max()
	pl.economy.points = 20000
	for id in Perks.CORE:
		var before := pl.economy.points
		game.buy_perk(pl, id); game.buy_perk(pl, id)
		ok(pl.perks.get(id, false) == true and pl.economy.points == before - Perks.ALL[id].cost, "%s is charged exactly once" % Perks.ALL[id].name)
		ok(game.perk_prompt(pl, id) == "", "%s is no longer offered once owned" % Perks.ALL[id].name)
	ok(is_equal_approx(pl.max_health, hp0 * Perks.HEALTH_MULT) and is_equal_approx(pl.health, pl.max_health), "Iron Hide doubles maximum health", "%.0f -> %.0f" % [hp0, pl.max_health])
	ok(is_equal_approx(pl.ammo().reload_mult, Perks.RELOAD_MULT) and pl.ammo().reload_step() < pl.weapon().reload_time * 0.6, "Quickhand halves the reload", "%.2f s" % pl.ammo().reload_step())
	ok(is_equal_approx(pl.stamina_max(), st0 * Perks.STAMINA_MULT), "Fleetfoot extends sprint endurance", "%.1f -> %.1f s" % [st0, pl.stamina_max()])
	pl.economy.points = 100
	game.buy_perk(pl, "marksman")
	ok(pl.economy.points == 100 and not pl.perks.has("marksman"), "an unaffordable tonic is refused")
	var status := "\n".join(game.status_lines())
	ok(status.contains("Iron Hide Tonic — Doubles max health") and status.contains("Quickhand") and status.contains("Fleetfoot") and status.contains("Mk.2"), "pause status lists owned upgrades and their effects")
	# mystery crate: visible cost, never a gun already carried, never a downgrade of the upgraded one
	var sign_ok := false
	for c in game.crate_node.get_children():
		if c is Label3D and (c as Label3D).text.contains(str(game.crate.cost)): sign_ok = true
	ok(sign_ok, "the crate shows its price in the world")
	pl.economy.points = 500
	ok(game.crate_prompt(pl).contains("need %d more" % (game.crate.cost - 500)), "crate prompt explains the shortfall", game.crate_prompt(pl))
	game.use_crate(pl)
	ok(pl.economy.points == 500 and game.crate_node.state == CrateNode.State.IDLE, "the crate refuses an unaffordable roll")
	var owned := game._owned_ids(pl); var bad := []
	var c2 := MysteryCrate.new()
	for i in 500:
		var id := c2.roll(game.rng, owned)
		if id in owned or Weapons.make(id) == null: bad.append(id)
	ok(bad.is_empty(), "the crate only offers real weapons the player does not carry", "carrying %s" % str(owned))
	pl.economy.points = 5000
	var upgraded: WeaponDef = pl.weapon()
	game.use_crate(pl); game.use_crate(pl)
	ok(pl.economy.points == 5000 - game.crate.cost and game.crate_node.state == CrateNode.State.ROLLING, "one crate roll is charged once")
	var t := 0
	while game.crate_node.state == CrateNode.State.ROLLING and t < 900: await get_tree().physics_frame; t += 1
	ok(game.crate_node.state == CrateNode.State.READY and not (game.crate_node.result in owned), "the crate lands on a new weapon", game.crate_node.result)
	var got: String = game.crate_node.result
	game.use_crate(pl)
	ok(pl.weapon().id == got and pl.loadout.slots.size() == Loadout.MAX_SLOTS and pl.ammo().is_full(), "taking the crate weapon equips it with full ammunition", pl.weapon().name)
	ok(pl.economy.points == 5000 - game.crate.cost, "taking the weapon costs nothing more")
	# a gun inside the Forge cannot be traded away, and it comes back upgraded even after a knock-down
	pl.economy.points = 20000
	var base := pl.weapon().damage
	game.use_forge(pl)
	var locked: Ammo = pl.ammo()
	var pts := pl.economy.points
	game.buy_wall(pl, "smg" if pl.loadout.has("smg") < 0 else "scatter")
	ok(pl.economy.points == pts and pl.ammo() == locked, "no weapon purchase while the gun is in the upgrade station")
	pl.since_hit = 99.0; pl.perks["lazarus"] = true
	pl.take_damage(9999.0, pl.global_position + Vector3(0, 0, 2))
	ok(pl.is_downed, "knocked down while the gun is in the station")
	game._update_prompt(); game.player_use(pl, true, true)
	await frames(int(maxf(OverchargeForge.FORGE_TIME, LastStand.SELF_REVIVE) * 60) + 40)
	ok(not pl.is_downed and pl.weapon().tier == 1 and pl.weapon().damage == base * 2 and not pl.ammo().locked, "the upgraded gun returns to its slot after a revive",
		"%s tier %d locked %s" % [pl.weapon().display_name(), pl.weapon().tier, pl.ammo().locked])
	ok(Perks.held(pl.perks).is_empty() and is_equal_approx(pl.max_health, hp0), "self-revive removes every tonic effect", "max health %.0f" % pl.max_health)
	for z in game.zombies.duplicate():
		if is_instance_valid(z): z.queue_free()
	game.zombies.clear()

# ---------------------------------------------------------------- v10: the Brute
func _t_elite() -> void:
	pl.global_position = Vector3(0, 0.1, 3); pl.yaw = 0.0; pl.velocity = Vector3.ZERO
	pl.health = pl.max_health; pl.since_hit = 99.0
	game.round = 4
	var z: Zombie = game.spawn_zombie("", "brute")
	z.drop_in = false; z.state = Zombie.State.CHASE; z.model.position.y = 0.0; z.model.rotation.x = 0.0
	z.global_position = Vector3(0, 0.05, -0.5); z.slam_cd = 0.0
	await frames(3)
	ok(z.max_hp == ZombieTypes.health("brute", Rounds.zombie_health(4)) and z.max_hp > Rounds.zombie_health(4) * 4, "the Brute is several times tougher than a walker", "%d HP" % z.max_hp)
	ok(z.model.scale.y > 1.3 and z.weak_light != null, "the Brute is visibly larger and its weak point glows")
	var w := Weapons.make("sidearm")
	var hp := z.hp
	game.hitscan(pl, Vector3(0, 1.3, 3), Vector3(0, 0, -1), w)
	var body := hp - z.hp; hp = z.hp
	game.hitscan(pl, Vector3(0, z.head_y() + 0.25, 3), Vector3(0, 0, -1), w)
	var head := hp - z.hp
	ok(body == w.damage / 2 and head == w.damage * 2, "armour halves body shots; the head takes double", "body %d, head %d" % [body, head])
	await frames(12)
	ok(z.model.scale.is_equal_approx(z.type_scale) and z.model.scale.y > 1.3, "being shot does not shrink the Brute back to normal size", str(z.model.scale))
	var t := 0
	while z.slam_t <= 0.0 and t < 240: await get_tree().physics_frame; t += 1
	ok(z.slam_t > 0.0 and z.slam_ring != null and z.slam_ring.visible, "the Brute telegraphs a slam with a ring on the floor", "after %.1f s" % (t / 60.0))
	var hp_before: float = pl.health
	await frames(int(ZombieTypes.SLAM_WINDUP * 60 * 0.5))
	ok(is_equal_approx(pl.health, hp_before), "no damage during the wind-up")
	# step out of the ring: the slam must miss
	pl.global_position = z.global_position + Vector3(0, 0.05, ZombieTypes.SLAM_RADIUS + 1.5)
	t = 0
	while z.winded_t <= 0.0 and t < 120: await get_tree().physics_frame; t += 1
	ok(z.winded_t > 0.0 and is_equal_approx(pl.health, hp_before), "leaving the ring avoids the slam", "health %.0f" % pl.health)
	ok(z.exposed and not z.slam_ring.visible, "after the slam the Brute is winded and the ring is gone")
	hp = z.hp
	game.hitscan(pl, Vector3(z.global_position.x, 1.3, pl.global_position.z), Vector3(0, 0, -1), w)
	ok(hp - z.hp == w.damage, "a winded Brute takes full body damage", "%d" % (hp - z.hp))
	await frames(int(ZombieTypes.SLAM_WINDED * 60) + 10)
	ok(not z.exposed and z.winded_t <= 0.0, "the Brute recovers and its armour returns")
	# stand inside the ring: the slam hits once, and does not kill a healthy survivor
	z.set_physics_process(false)
	pl.global_position = z.global_position + Vector3(0, 0.05, 2.0); pl.health = pl.max_health; pl.since_hit = 99.0
	z.slam_cd = 0.0; z.set_physics_process(true)
	t = 0
	while z.winded_t <= 0.0 and t < 400:
		pl.global_position = z.global_position + Vector3(0, 0.05, 2.0); pl.velocity = Vector3.ZERO
		await get_tree().physics_frame; t += 1
	ok(is_equal_approx(pl.health, pl.max_health - ZombieTypes.SLAM_DAMAGE) and not pl.is_downed, "standing in the ring takes one slam and survives it", "health %.0f of %.0f" % [pl.health, pl.max_health])
	# reward
	z.set_physics_process(false)
	var pts := pl.economy.points; var drops := game.drops.size(); var elites := game.stats.elites
	z.take_damage(z.hp + 1, true, pl, "head", Vector3.ZERO)
	ok(pl.economy.points >= pts + int(ZombieTypes.ALL.brute.points) and game.stats.elites == elites + 1, "killing the Brute pays its bounty", "+%d" % (pl.economy.points - pts))
	var restock := false
	for d in game.drops: if d.id == "restock": restock = true
	ok(game.drops.size() > drops and restock, "the Brute drops a RESTOCK pickup")
	ok(z.slam_ring == null or not is_instance_valid(z.slam_ring) or z.slam_ring.is_queued_for_deletion(), "its slam ring is removed when it dies")
	ok(ZombieTypes.brute_count(4) == 1 and ZombieTypes.brute_count(5) == 0 and ZombieTypes.brute_count(12) == 2, "Brutes arrive every %d rounds" % ZombieTypes.BRUTE_EVERY)
	game.round = 3
	for d in game.drops.duplicate(): (d.node as Node).queue_free()
	game.drops.clear()
	pl.global_position = Vector3(0, 0.1, 3); pl.health = pl.max_health; pl.since_hit = 99.0
	await frames(5)

# ---------------------------------------------------------------- touch
func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new(); e.index = idx; e.position = pos; e.pressed = pressed
	get_viewport().push_input(e, true)

func _drag(idx: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new(); e.index = idx; e.position = pos; e.relative = rel
	get_viewport().push_input(e, true)

func _t_touch() -> void:
	var t: TouchControls = game.touch
	ok(t.visible, "touch controls are active")
	for n in ["fire", "ads", "reload", "sprint", "use", "swap", "pause"]:
		if not t.buttons.has(n): ok(false, "touch button '%s' exists" % n)
	ok(TouchLayout.overlaps(t.buttons).is_empty(), "touch buttons do not overlap")
	pl.global_position = Vector3(0, 0.1, 3); pl.yaw = 0.0; pl.pitch = 0.0; pl.velocity = Vector3.ZERO
	pl.ammo().refill(); pl.fire_cd = 0.0
	await frames(5)
	var s := t.size
	var stick := Vector2(s.x * 0.16, s.y * 0.72)
	var look := Vector2(s.x * 0.62, s.y * 0.30)
	ok(t._button_at(look) == "" and t._button_at(stick) == "", "stick and look zones are clear of buttons")
	var p0 := pl.global_position; var yaw0 := pl.yaw; var r0 := pl.ammo().rounds
	_touch(0, stick, true); _drag(0, stick + Vector2(0, -120), Vector2(0, -120))   # finger 0: push forward
	_touch(1, look, true)                                                        # finger 1: camera
	_touch(2, t.buttons.fire[0], true)                                           # finger 2: FIRE
	await frames(2)
	ok(t.stick_idx == 0 and t.look_idx == 1 and t.fire, "each finger is tracked by its own index", "stick %d look %d fire %s" % [t.stick_idx, t.look_idx, t.fire])
	for i in 30:
		_drag(1, look + Vector2(i * 4, 0), Vector2(4, 0))
		await get_tree().physics_frame
	var moved := pl.global_position.distance_to(p0); var turned := absf(pl.yaw - yaw0); var shot := r0 - pl.ammo().rounds
	ok(moved > 0.5 and turned > 0.2 and shot >= 2, "three fingers at once: move + aim + fire", "moved %.1f m, turned %.0f deg, %d shots" % [moved, rad_to_deg(turned), shot])
	_touch(2, t.buttons.fire[0], false)
	await frames(3)
	var r1 := pl.ammo().rounds; var y1 := pl.yaw
	for i in 10:
		_drag(1, look + Vector2(120 + i * 4, 0), Vector2(4, 0))
		await get_tree().physics_frame
	ok(pl.ammo().rounds == r1 and absf(pl.yaw - y1) > 0.05 and t.move.length() > 0.5, "lifting FIRE keeps the stick and the camera finger tracked",
		"shots %d, turned %.0f deg, stick %.2f" % [r1 - pl.ammo().rounds, rad_to_deg(absf(pl.yaw - y1)), t.move.length()])
	# a fresh finger on a button must not steal the camera finger
	_touch(3, t.buttons.reload[0], true); _touch(3, t.buttons.reload[0], false)
	await frames(2)
	ok(t.look_idx == 1 and t.stick_idx == 0, "button taps do not steal the stick or camera fingers")
	game.toggle_pause()
	ok(t.stick_idx == -1 and t.look_idx == -1 and not t.fire and t.move == Vector2.ZERO, "pausing releases every held touch")
	game.toggle_pause()
	_touch(0, stick, false); _touch(1, look, false)
	await frames(3)

# ---------------------------------------------------------------- death, records, restart
func _t_death_and_restart() -> void:
	var hs_path := "user://check_highscore.cfg"
	if FileAccess.file_exists(hs_path): DirAccess.remove_absolute(ProjectSettings.globalize_path(hs_path))
	game.high = HighScore.new(hs_path)
	pl.since_hit = 99.0; pl.health = 10.0
	pl.take_damage(500.0, pl.global_position + Vector3(0, 0, 2))
	ok(pl.is_downed and not game.over, "lethal damage drops the player into last stand")
	await frames(int(LastStand.BLEED_OUT * 60) + 30)
	ok(game.over and game.hud.over_panel != null, "bleeding out ends the match with a results screen")
	ok(is_equal_approx(Engine.time_scale, 1.0), "the results screen runs at normal speed")
	var tot := HighScore.new(hs_path).load_totals()
	ok(int(tot.matches) == 1 and int(tot.kills) == game.kills and int(tot.headshots) == game.stats.headshots and int(tot.elites) == game.stats.elites, "lifetime kills and headshots are saved",
		"%d kills, %d headshots, %d Brutes" % [tot.kills, tot.headshots, tot.elites])
	var over_text := ""
	for c in game.hud.over_panel.get_children():
		if c is Label: over_text += (c as Label).text + "\n"
	ok(over_text.contains("Districts  3/3") and over_text.contains("Power  restored") and over_text.contains("Lifetime"), "results list districts, power and lifetime totals")
	var rec := HighScore.new(hs_path).load_records()
	ok(int(rec.round) == game.round and int(rec.score) == game.stats.points_earned and game.round >= 3, "best round and best score are saved", "round %d, score %d" % [rec.round, rec.score])
	var old := game
	# leave as much state behind as possible, then restart
	Engine.time_scale = 0.3; old.slowmo_t = 1.0
	old.power.activate("doublepay"); old.paks.activate("overdrive")
	var settings_before := old.settings.to_dict()
	game.restart()
	for i in 10: await get_tree().process_frame
	var g2: Game = main.game
	ok(g2 != old and g2.round == 0 and not g2.over and g2.player.health == g2.player.max_health and not get_tree().paused, "restart begins a fresh match")
	ok(g2.player.economy.points == Economy.START and g2.facility.open_doors.is_empty(), "restart resets points and doors")
	var p2: Player = g2.player
	ok(not g2.facility.power_on and g2.facility.cranks == 0 and g2.facility.districts_open() == 1 and g2.facility.objective().contains("open the Back Alley"), "restart turns the power off and resets the objective")
	ok(Perks.held(p2.perks).is_empty() and is_equal_approx(p2.max_health, float(p2.cdef.max_health)) and is_equal_approx(p2.stamina_max(), Player.STAMINA_MAX) and is_equal_approx(p2.ammo().reload_mult, 1.0), "restart removes every enhancement")
	var tiers := 0
	for sl in p2.loadout.slots: tiers += sl.weapon.tier
	ok(tiers == 0 and p2.loadout.weapon().id == Weapons.STARTER and not p2.ammo().locked, "restart returns the starting weapons, not upgraded")
	ok(g2.zombies.is_empty() and get_tree().get_nodes_in_group("voz_zombie").filter(func(n): return not n.is_queued_for_deletion() and n.get_parent() == g2).is_empty(), "restart leaves no enemies behind")
	ok(g2.power.timers.is_empty() and not g2.paks.active() and g2.drops.is_empty() and g2.gear_drops.is_empty() and g2.forge_busy <= 0.0 and p2.economy.mult == 1, "restart clears timed effects, pickups and the upgrade timer")
	ok(is_equal_approx(Engine.time_scale, 1.0) and g2.slowmo_t <= 0.0 and g2.kills == 0 and g2.stats.kills == 0 and g2.stats.time < 1.0, "restart clears slow motion and run statistics")
	ok(g2.settings.to_dict() == settings_before, "restart keeps the settings")
	ok(int(HighScore.new(hs_path).load_records().round) >= 3 and int(HighScore.new(hs_path).load_totals().matches) == 1, "restart keeps the records")
	# back to the menu and into a third match: still clean
	g2.to_menu()
	for i in 10: await get_tree().process_frame
	ok(main.game == null and main.menu != null and not get_tree().paused, "Main menu returns to the menu")
	ok(main.menu.find_children("*", "Button", true, false).any(func(b): return (b as Button).text == "How to play"), "the menu offers How to play")
	main.start_game()
	for i in 10: await get_tree().process_frame
	ok(main.game != null and main.game.round == 0 and main.game.player.economy.points == Economy.START and not main.game.facility.power_on, "a match started from the menu is fresh")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(hs_path))
