class_name BotDriver
extends Node
## Headless playtest bot (sim only, `-- --sim=10`). Stays in the start room like a round-1 player:
## aims at the nearest zombie's head, fires, knifes anything in reach, backs off when crowded,
## reloads, and between rounds spends points on wall guns / ammo / perks. Prints a per-round report.

var game: Game
var max_rounds := 10
var started_ms := 0
var log_lines: Array[String] = []
var last_round := 0
var hits_taken := 0
var prev_health := 100.0
var t := 0.0

func _ready() -> void:
	started_ms = Time.get_ticks_msec()
	game.player.bot_input = {"mv": Vector2.ZERO, "fire": false, "ads": false, "use": false, "sprint": false}

func _physics_process(dt: float) -> void:
	var p := game.player
	t += dt
	if p.health < prev_health - 1.0: hits_taken += 1
	prev_health = p.health
	if game.round != last_round:
		if last_round > 0: print("[sim] round %d done in %.1fs · downs %d · kills %d" % [last_round, game.round_times.get(last_round, -1.0), game.downs, game.kills])
		_shop(); last_round = game.round
	if game.over or game.round > max_rounds or t > 60.0 * 40:
		_finish(); return
	var bi: Dictionary = p.bot_input
	if OS.has_environment("VOZ_SIM_DEBUG") and Engine.get_physics_frames() % 300 == 0 and game.to_spawn == 0:
		var zs := []
		for z in game.zombies: zs.append("%s@%s hp%d" % [Zombie.State.keys()[z.state], str(z.global_position.snapped(Vector3.ONE * 0.1)), z.hp])
		print("[dbg] ammo %d/%d " % [p.ammo().rounds, p.ammo().reserve] + "r%d t%.0f hp%.0f downed=%s player@%s zombies=%s" % [game.round, t, p.health, p.is_downed, str(p.global_position.snapped(Vector3.ONE * 0.1)), zs])
	bi.fire = false; bi.mv = Vector2.ZERO; bi.ads = false; bi.sprint = false
	# v7.13: prefer the nearest zombie a bullet can actually reach (same mask as hitscan); the old bot
	# emptied its sidearm into walls and the gas-tank cage at zombies still outside the windows.
	var target: Zombie = null; var bd := 1e9; var clear := false
	var eye0 := p.cam.global_position
	for z in game.zombies:
		if not is_instance_valid(z) or z.state == Zombie.State.DEAD: continue
		var d: float = z.global_position.distance_to(p.global_position)
		var c := OS.has_environment("VOZ_SIM_NOLOS") or game.shot_clear(p, eye0, z.global_position + Vector3(0, z.head_y() if not z.crawler else 0.35, 0), z)
		if (c and not clear) or (c == clear and d < bd): bd = d; target = z; clear = c
	if target == null:
		if game.intermission > 0.0 and game.intermission < 8.0: _shop()
		return
	var aim := target.global_position + Vector3(0, target.head_y() if not target.crawler else 0.35, 0)
	var eye := p.cam.global_position
	var v := aim - eye
	p.yaw = atan2(-v.x, -v.z)
	p.pitch = atan2(v.y, Vector2(v.x, v.z).length())
	var tearing := target.state != Zombie.State.CHASE
	if bd < 2.2 and p.knife_cd <= 0.0 and not tearing:
		p.melee()
	elif p.ammo().rounds > 0 and clear:
		bi.fire = Engine.get_physics_frames() % 2 == 0 or p.weapon().automatic
		bi.ads = bd > 6.0
	elif p.ammo().rounds > 0:
		pass   # no clear shot: hold fire
	elif not p.ammo().is_empty():
		p.reload()
	else:
		_shop()
	# crowded: back away from the nearest one toward the room centre
	var crowd := 0
	for z in game.zombies:
		if is_instance_valid(z) and z.state == Zombie.State.CHASE and z.global_position.distance_to(p.global_position) < 3.0: crowd += 1
	if crowd >= 2 or (bd < 3.2 and not tearing and p.health < 70.0) or (bd < 1.6 and p.knife_cd > 0.0) or (tearing and bd < 3.0):
		var away := (p.global_position - target.global_position); away.y = 0
		var home := (Vector3(0, 0, 3) - p.global_position); home.y = 0
		var go := (away.normalized() + home.normalized() * 0.6).normalized()
		var local := go.rotated(Vector3.UP, -p.yaw)
		bi.mv = Vector2(local.x, local.z)
		bi.sprint = crowd >= 3

func _shop() -> void:
	var p := game.player
	if p.is_downed: return
	# a typical first game: open the lab around round 4 and throw the power for perks
	if game.round >= 4 and not game.facility.power_on and p.economy.points >= 1300:
		if not game.facility.open_doors.has("east"):
			game.buy_door(p, "east")
		game.throw_power(Node3D.new()); print("[sim] r%d power on" % game.round)
	# v7.13 balance probe: VOZ_SIM_REAPER=<round> hands the bot the Hive Reaper from that round on
	var rr := int(OS.get_environment("VOZ_SIM_REAPER")) if OS.has_environment("VOZ_SIM_REAPER") else 0
	if rr > 0 and game.round >= rr and p.loadout.has(Weapons.ALIEN) < 0:
		p.loadout.give(Weapons.make(Weapons.ALIEN)); print("[sim] r%d given reaper" % game.round)
	for id in ["rifle"]:
		var i := p.loadout.has(id)
		if i < 0 and p.economy.points >= Weapons.WALL_PRICES[id] + 200 and (game.round >= 2):
			game.buy_wall(p, id); print("[sim] r%d bought %s" % [game.round, id]); return
		if i >= 0 and p.loadout.slots[i].reserve < p.loadout.slots[i].max_reserve() / 3 and p.economy.points >= Weapons.ammo_price(id):
			game.buy_wall(p, id)
	for i in p.loadout.slots.size():
		if p.loadout.slots[i].weapon.id != "sidearm" and p.loadout.current != i:
			p.swap()
	for perk in ["ironhide", "lazarus"]:
		if game.facility.power_on and not p.perks.has(perk) and p.economy.points >= Perks.ALL[perk].cost + 300:
			game.buy_perk(p, perk); print("[sim] r%d bought %s -> perks %s" % [game.round, perk, str(p.perks.keys())])

func _finish() -> void:
	set_physics_process(false)
	var lines: Array[String] = ["VictorOps Zombies bot sim · %d rounds requested" % max_rounds]
	lines.append("round | seconds | zombies | zombie HP")
	var total := 0.0
	for r in game.round_times:
		total += game.round_times[r]
		lines.append("%5d | %7.1f | %7d | %d" % [r, game.round_times[r], Rounds.zombie_count(r), Rounds.zombie_health(r)])
	lines.append("reached round %d · kills %d · downs %d · stuck respawns %d · hits taken %d · game over %s · points %d · sim time %.0f s (+%d s breaks) · wall clock %.1f s" % [
		game.round, game.kills, game.downs, game.stuck_respawns, hits_taken, str(game.over), game.player.economy.points, total, int(Rounds.INTERMISSION) * game.round_times.size(), (Time.get_ticks_msec() - started_ms) / 1000.0])
	lines.append("zombie types spawned: %s" % str(game.type_counts))
	for l in lines: print(l)
	var f := FileAccess.open("user://sim_report.txt", FileAccess.WRITE)
	if f: f.store_string("\n".join(lines))
	get_tree().quit(0 if game.round_times.size() >= max_rounds else 2)
