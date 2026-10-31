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
var gadget_cd := 0.0
## v7.14 gear rules (pure, tested in test_v7_14): which gadget to use right now, "" for none.
const AEGIS_HEALTH := 60.0
const SENTRY_CROWD := 2       ## chasers within SENTRY_NEAR
const SENTRY_NEAR := 10.0
const PULSE_CROWD := 2        ## zombies within PULSE_NEAR
const PULSE_NEAR := 6.5      ## = Backpack.PULSE_RADIUS
const PICKUP_RANGE := 14.0    ## walks to a floor drop this close...
const PICKUP_SAFE := 4.0      ## ...only while no zombie is within this
const LOCKER_SPARE := 600     ## keeps this many points after a Tech Locker buy
static func pick_gadget(bag: Dictionary, health: float, near_25: int, within_5: int, chasing_10: int, aegis_up: bool, sentries: int) -> String:
	if bag.get("aegis", 0) > 0 and not aegis_up and ((health < AEGIS_HEALTH and near_25 >= 1) or near_25 >= 2): return "aegis"
	if bag.get("pulse", 0) > 0 and within_5 >= PULSE_CROWD: return "pulse"
	if bag.get("sentry", 0) > 0 and sentries == 0 and chasing_10 >= SENTRY_CROWD: return "sentry"
	return ""
static func want_pickup(drop_dist: float, nearest_zombie: float) -> bool:
	return drop_dist <= PICKUP_RANGE and nearest_zombie > PICKUP_SAFE
static func want_locker(points: int, round_n: int, bag_full: bool) -> bool:
	return round_n >= 3 and not bag_full and points >= Backpack.LOCKER_PRICE + LOCKER_SPARE

func _ready() -> void:
	started_ms = Time.get_ticks_msec()
	game.player.bot_input = {"mv": Vector2.ZERO, "fire": false, "ads": false, "use": false, "sprint": false}
	# VOZ_SIM_GEAR=1 starts the bot with one of each gadget (evidence clips / quick gear checks)
	if OS.has_environment("VOZ_SIM_GEAR"):
		for g in ["sentry", "aegis", "pulse"]: game.player.backpack.add(g)

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
	gadget_cd -= dt
	_gear(p, bd)
	if target == null:
		if game.intermission > 0.0 and game.intermission < 8.0: _shop()
		_go_pickup(p, 1e9)
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
	elif bi.mv == Vector2.ZERO:
		_go_pickup(p, bd)

## v7.14: use a gadget when the rules say so.
func _gear(p: Player, nearest: float) -> void:
	if gadget_cd > 0.0 or p.is_downed: return
	var near_25 := 0; var within_5 := 0; var chasing_10 := 0
	for z in game.zombies:
		if not is_instance_valid(z) or z.state == Zombie.State.DEAD: continue
		var d: float = z.global_position.distance_to(p.global_position)
		if d < 2.5: near_25 += 1
		if d < PULSE_NEAR: within_5 += 1
		if d < SENTRY_NEAR and z.state == Zombie.State.CHASE: chasing_10 += 1
	var bag := {}
	for g in Backpack.GADGETS: bag[g] = p.backpack.count(g)
	var g := pick_gadget(bag, p.health, near_25, within_5, chasing_10, game.aegis.up(), game.sentries.size())
	if g == "": return
	game.use_gadget(p, p.backpack.slot_of(g)); gadget_cd = 1.5
	print("[sim] r%d used %s (hp %.0f, near %d/%d/%d)" % [game.round, g, p.health, near_25, within_5, chasing_10])

## v7.14: walk over to a pak/gadget drop when it's safe (pickup is automatic within 1.2 m).
func _go_pickup(p: Player, nearest: float) -> void:
	var best: Dictionary = {}; var bd := 1e9
	for d in game.gear_drops:
		if not is_instance_valid(d.node): continue
		if d.kind == "gadget" and p.backpack.is_full_for(d.id): continue
		var off: Vector3 = d.node.global_position - p.global_position; off.y = 0
		if off.length() < bd: bd = off.length(); best = d
	if best.is_empty() or not want_pickup(bd, nearest): return
	var go: Vector3 = best.node.global_position - p.global_position; go.y = 0
	var local := go.normalized().rotated(Vector3.UP, -p.yaw)
	p.bot_input.mv = Vector2(local.x, local.z)

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
	if want_locker(p.economy.points, game.round, _bag_full(p)):
		game.use_tech_locker(p); print("[sim] r%d tech locker -> bag %s" % [game.round, str(p.backpack.slots)])
	for perk in ["ironhide", "lazarus"]:
		if game.facility.power_on and not p.perks.has(perk) and p.economy.points >= Perks.ALL[perk].cost + 300:
			game.buy_perk(p, perk); print("[sim] r%d bought %s -> perks %s" % [game.round, perk, str(p.perks.keys())])

func _bag_full(p: Player) -> bool:
	for sl in p.backpack.slots:
		if sl.is_empty(): return false
	return true

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
	lines.append("gear used: %s" % str(game.gear_stats))
	for l in lines: print(l)
	var f := FileAccess.open("user://sim_report.txt", FileAccess.WRITE)
	if f: f.store_string("\n".join(lines))
	get_tree().quit(0 if game.round_times.size() >= max_rounds else 2)
