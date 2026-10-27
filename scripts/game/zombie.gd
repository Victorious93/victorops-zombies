class_name Zombie
extends CharacterBody3D
## Rigged CC0 zombie (Quaternius, see ASSETS.md) driven by its own AnimationPlayer:
## walk / run / attack / hit-react / death / crawl. Leg damage can turn a walker into a crawler.
## States: rise outside -> walk to its window -> tear planks -> vault in -> chase on the navmesh.

enum State { RISE, TO_WINDOW, TEAR, VAULT, CHASE, DEAD }
const HEAD_Y := 1.45
const LEG_Y := 0.62
const HEIGHT := 1.8

var game
var window: WindowBarricade
var state := State.RISE
var hp := 100
var max_hp := 100
var speed := 1.1
var runner := false
var crawler := false
var leg_damage := 0
var t := 0.0
var attack_cd := 0.0
var attack_anim_t := 0.0
var groan_cd := 0.0
var step_cd := 0.0
var repath := 0.0
var agent: NavigationAgent3D
var model: Node3D
var ap: AnimationPlayer
var variant := "zombie_a"
var anims := {}
var cur_anim := ""
var shape: CollisionShape3D
var vault_from: Vector3
var knock := Vector3.ZERO
var flash_t := 0.0
var meshes: Array = []
var eye_light: OmniLight3D
var voice := 1           ## which groan this zombie uses (each has its own voice)
var voice_pitch := 1.0
var stagger_t := 0.0
var lunge_cd := 1.5
var lunge_t := 0.0
var windup_t := -1.0     ## >0: an attack is winding up and lands when it reaches 0
var drop_in := false     ## spawned on top of the perimeter wall and drops down
var drop_v := 0.0
var skel: Skeleton3D
var head_popped := false
var death_fling := Vector3.ZERO
var death_tilt := Vector3.ZERO
const LUNGE_RANGE := 2.9
const LUNGE_SPEED := 5.5
const WINDUP := 0.22

func setup(p_game, p_window: WindowBarricade, round: int) -> void:
	game = p_game; window = p_window
	max_hp = Rounds.zombie_health(round); hp = max_hp
	# shamblers until round 5, then a growing share of sprinters (Frenzy rounds: everyone runs)
	var rc := 1.0 if Rounds.is_special(round) else Rounds.runner_chance(round)
	runner = randf() < rc
	speed = (Rounds.RUN_SPEED if runner else Rounds.WALK_SPEED) * randf_range(0.9, 1.12)
	variant = "zombie_b" if randf() < 0.35 else "zombie_a"
	voice = randi() % 5 + 1
	voice_pitch = randf_range(0.78, 1.22) * (0.88 if variant == "zombie_b" else 1.0)
	drop_in = randf() < 0.35

func _ready() -> void:
	add_to_group("voz_zombie")
	collision_layer = 2
	collision_mask = 1
	shape = CollisionShape3D.new(); var cap := CapsuleShape3D.new()
	cap.radius = 0.32; cap.height = HEIGHT; shape.shape = cap; shape.position.y = HEIGHT / 2
	add_child(shape)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.6; agent.target_desired_distance = 0.5
	agent.radius = 0.4; agent.height = 1.8
	add_child(agent)
	var c := ModelLib.character(variant, HEIGHT * randf_range(0.94, 1.06))
	model = c[0]; ap = c[1]
	model.rotation.y = PI  # model faces +Z; gameplay forward is -Z
	add_child(model)
	for key in ["Walk", "Run", "Punch", "Attack", "Death", "Crawl", "HitReact", "HitRecieve", "Idle", "Idle_Attack", "Run_Attack"]:
		var n := ModelLib.anim_name(ap, [key])
		if n != "": anims[key] = n
	if anims.has("HitRecieve") and not anims.has("HitReact"): anims.HitReact = anims.HitRecieve
	if anims.has("Attack") and not anims.has("Punch"): anims.Punch = anims.Attack
	_collect_meshes(model)
	for mi in meshes:
		(mi as GeometryInstance3D).visibility_range_end = 48.0
		for si in (mi as MeshInstance3D).mesh.get_surface_count():
			var m := (mi as MeshInstance3D).mesh.surface_get_material(si)
			if m is StandardMaterial3D: (mi as MeshInstance3D).set_surface_override_material(si, _rim_mat(m))
	ModelLib.set_shadows(model, game == null or game.settings_shadows())
	if ap:
		for k in ["Walk", "Run", "Crawl", "Idle"]:
			if anims.has(k): ap.get_animation(anims[k]).loop_mode = Animation.LOOP_LINEAR
		ap.speed_scale = randf_range(0.9, 1.1)
	var sks := model.find_children("*", "Skeleton3D", true, false)
	if not sks.is_empty(): skel = sks[0]
	t = 0.9; groan_cd = randf_range(1, 6)
	if drop_in:
		# climbs over the yard wall: appears on top, drops down with a thud
		model.position.y = 2.6; t = 0.9
		if anims.has("Run"): _play("Run", 0.1, 0.5)
	else:
		model.position.y = -1.8
		_play("Idle")
		if game and game.fx: game.fx.dirt_burst(global_position)
		if game and game.sfx: game.sfx.play_at("dirt_rise", global_position, -6, randf_range(0.85, 1.1))

## Cold blue-green rim so zombies read as silhouettes in the dark. Shared per source material (batches).
static var _rim_cache := {}
static func _rim_mat(src: StandardMaterial3D) -> StandardMaterial3D:
	if not _rim_cache.has(src):
		var m := src.duplicate() as StandardMaterial3D
		m.rim_enabled = true; m.rim = 0.7; m.rim_tint = 0.15
		_rim_cache[src] = m
	return _rim_cache[src]

func _collect_meshes(n: Node) -> void:
	if n is MeshInstance3D: meshes.append(n)
	for c in n.get_children(): _collect_meshes(c)

func _play(key: String, blend := 0.2, spd := 1.0) -> void:
	if ap == null or not anims.has(key): return
	if cur_anim == key and ap.is_playing(): return
	cur_anim = key
	ap.play(anims[key], blend, spd)

func _locomotion() -> void:
	if crawler and anims.has("Crawl"): _play("Crawl", 0.3, 1.0)
	elif runner and anims.has("Run"): _play("Run", 0.25, speed / 3.2)
	else: _play("Walk", 0.25, clampf(speed / 1.1, 0.7, 1.6))

## part: "head", "leg" or "body" (from the hit height).
const SWIPE_DAMAGE := 45.0     ## 100 HP player: down on the third hit (2 with chip damage)
const CRAWLER_DAMAGE := 30.0
const SWIPE_REACH := 1.7        ## reach-through-the-window range
var knifed := false
var stuck_t := 0.0
var last_pos := Vector3.ZERO
var swipe_cd := 1.0

func take_damage(dmg: int, headshot: bool, player, part := "body", force := Vector3.ZERO, knife := false) -> void:
	if state == State.DEAD: return
	if game and game.power.active("onetouch"): dmg = maxi(dmg, hp)
	knifed = knife
	hp -= dmg
	flash_t = 0.07
	if part == "legs" and not crawler:
		leg_damage += dmg
		if leg_damage > max_hp * 0.45 and anims.has("Crawl") and hp > 0 and randf() < 0.6:
			_become_crawler()
	if hp <= 0:
		die(player, headshot, force, dmg)
		return
	# stagger: knocked back, slowed, interrupts a wind-up on big hits
	var heavy := float(dmg) / max_hp
	if state == State.CHASE and not crawler:
		var f := force; f.y = 0
		knock += f.limit_length(6.0) * clampf(heavy * 2.5, 0.15, 1.0)
		stagger_t = maxf(stagger_t, clampf(0.12 + heavy * 0.8, 0.12, 0.6))
		if heavy > 0.2: windup_t = -1.0; lunge_t = 0.0
		if heavy > 0.12 or headshot:
			cur_anim = ""; _play("HitReact", 0.04, 1.4); attack_anim_t = stagger_t
	model.rotation.x = clampf(-heavy * 0.9, -0.35, 0.0)  # flinch, recovers in _physics_process

func make_crawler() -> void:
	if not crawler and state != State.DEAD and anims.has("Crawl"): _become_crawler()

func _become_crawler() -> void:
	crawler = true; runner = false; speed *= 0.5
	(shape.shape as CapsuleShape3D).height = 0.9; shape.position.y = 0.45
	_pop_bone("LowerLeg.L" if randf() < 0.5 else "LowerLeg.R")
	if game:
		game.fx.gibs(global_position + Vector3.UP * 0.4, 4, self)
		game.fx.blood_burst(global_position + Vector3.UP * 0.4, Vector3.UP, false)
		game.sfx.play_at("gore", global_position, -6, randf_range(0.9, 1.1))

## Limb/head pop: collapse the bone (and its children) to nothing so the mesh tears off there.
func _pop_bone(bone: String) -> void:
	if skel == null: return
	var i := skel.find_bone(bone)
	if i < 0: return
	skel.set_bone_pose_scale(i, Vector3.ONE * 0.001)
	set_meta("popped_" + bone, i)

func die(player, headshot: bool, force := Vector3.ZERO, dmg := 0) -> void:
	state = State.DEAD; t = 4.0
	collision_layer = 0
	velocity = Vector3.ZERO
	if anims.has("Death"):
		cur_anim = ""; _play("Death", 0.05, randf_range(1.1, 1.5))
	# fake ragdoll: the body is flung along the hit and topples that way while the death anim plays
	var f := force; f.y = 0
	death_fling = f.limit_length(7.0) * 0.55 + f.normalized() * 0.6
	death_tilt = Vector3(clampf(f.length() * 0.12, 0.15, 0.9), 0, randf_range(-0.35, 0.35))
	if game:
		var gore := headshot or dmg >= max_hp * 2 or force.length() > 4.0
		game.fx.blood_pool(global_position)
		if headshot and (dmg >= max_hp * 0.5 or randf() < 0.6):
			head_popped = true; _pop_bone("Head")
			game.fx.blood_burst(global_position + Vector3.UP * HEAD_Y, force.normalized())
		if gore: game.fx.gibs(global_position + Vector3.UP * (1.5 if headshot else 1.0), 6 if headshot else 9, self, force)
		game.on_zombie_killed(self, player, headshot, knifed)
		if eye_light: eye_light.queue_free()

func push(v: Vector3) -> void:
	knock += v

func _physics_process(dt: float) -> void:
	if flash_t > 0.0:
		flash_t -= dt
		var on := flash_t > 0.0
		model.scale = Vector3.ONE * (1.03 if on else 1.0)
	attack_anim_t -= dt
	match state:
		State.DEAD:
			t -= dt
			if death_fling.length() > 0.05:
				global_position += death_fling * dt
				death_fling = death_fling.move_toward(Vector3.ZERO, dt * 9.0)
			# topple in the direction of the fling (relative to our own facing)
			model.rotation.x = lerpf(model.rotation.x, -death_tilt.x * 0.6, dt * 6)
			model.rotation.z = lerpf(model.rotation.z, death_tilt.z, dt * 6)
			if t < 1.2: model.position.y -= dt * 0.5
			if t <= 0.0: queue_free()
			return
		State.RISE:
			t -= dt
			if drop_in:
				drop_v -= 18.0 * dt
				model.position.y = maxf(0.0, model.position.y + drop_v * dt)
				if model.position.y <= 0.0 and drop_v < -1.0:
					drop_v = 0.0; game.fx.dirt_burst(global_position)
					game.sfx.play_at("land_thud", global_position, -6, randf_range(0.8, 1.0))
					_play("Idle", 0.1)
			else:
				model.position.y = lerpf(model.position.y, 0.0, dt * 4)
				model.rotation.x = sin(t * 9.0) * 0.12 * t  # claws and lurches up out of the dirt
			if t <= 0.0:
				model.rotation.x = 0
				model.position.y = 0; state = State.TO_WINDOW; agent.target_position = window.outside_point
		State.TO_WINDOW:
			if _flat_dist(window.outside_point) < 0.7:
				state = State.TEAR; t = 1.0; watch.reset()
			else:
				_nav_move(window.outside_point, dt)
				_unstick(dt, window.outside_point)
		State.TEAR:
			_face(window.center()); velocity = Vector3.ZERO
			if window.bar.is_broken():
				state = State.VAULT; t = 0.0; vault_from = global_position
				_play("Run" if anims.has("Run") else "Walk", 0.1)
			else:
				_play("Punch", 0.2, 0.8)
				# reach through the gap and swipe anyone standing at the window
				swipe_cd -= dt
				var pl = game.player
				if pl and swipe_cd <= 0.0 and window.bar.planks() < window.bar.max_planks and not pl.is_downed \
						and _flat_dist(pl.global_position) < SWIPE_REACH + 0.6 and pl.global_position.distance_to(window.inside_point) < SWIPE_REACH:
					swipe_cd = 1.3
					pl.take_damage(SWIPE_DAMAGE, global_position)
					game.sfx.play_at("zombie_attack", window.center(), -2)
				t -= dt
				if t <= 0.0:
					t = randf_range(0.9, 1.4)
					if ap and anims.has("Punch"): ap.seek(0.0)
					window.bar.damage(window.bar.plank_hp); window.refresh()
					game.sfx.play_at("plank_rip", window.center(), -4, randf_range(0.9, 1.1))
					game.fx.splinters(window.center())
		State.VAULT:
			t += dt / 0.8
			var p := vault_from.lerp(window.inside_point, clampf(t, 0, 1))
			p.y += sin(clampf(t, 0, 1) * PI) * 1.1
			global_position = p
			if t >= 1.0:
				state = State.CHASE; repath = 0.0; watch.reset()
		State.CHASE:
			var pl = game.player
			if pl == null: return
			var d := _flat_dist(pl.global_position)
			var dy: float = absf(pl.global_position.y - global_position.y)
			lunge_cd -= dt
			if windup_t > 0.0:
				# committed swing: keep facing, land it if still in reach
				windup_t -= dt; _face(pl.global_position); velocity = Vector3.ZERO
				if windup_t <= 0.0:
					windup_t = -1.0
					if d < (1.25 if crawler else 1.75) and dy < 1.6 and not pl.is_downed:
						pl.take_damage(CRAWLER_DAMAGE if crawler else SWIPE_DAMAGE, global_position)
						game.sfx.play_at("zombie_attack", global_position + Vector3.UP, -2, voice_pitch)
					else:
						game.sfx.play_at("swipe_miss", global_position + Vector3.UP, -8, randf_range(0.9, 1.1))
			elif lunge_t > 0.0:
				# lunge: a short burst straight at the player, ending in a swing
				lunge_t -= dt
				var dir: Vector3 = pl.global_position - global_position; dir.y = 0; dir = dir.normalized()
				velocity.x = dir.x * LUNGE_SPEED; velocity.z = dir.z * LUNGE_SPEED; velocity.y = -0.5
				move_and_slide(); _face(pl.global_position)
				if lunge_t <= 0.0 or d < 1.2: lunge_t = 0.0; _start_swing()
			elif d < (1.0 if crawler else 1.35) and dy < 1.6 and not pl.is_downed:
				velocity = Vector3.ZERO; _face(pl.global_position)
				attack_cd -= dt
				if attack_cd <= 0.0 and stagger_t <= 0.0:
					attack_cd = 0.95
					_start_swing()
			elif not crawler and stagger_t <= 0.0 and lunge_cd <= 0.0 and d < LUNGE_RANGE and d > 1.5 and dy < 1.0 and not pl.is_downed:
				lunge_cd = randf_range(2.2, 3.5); lunge_t = 0.28
				cur_anim = ""; _play("Run_Attack" if anims.has("Run_Attack") else "Run", 0.05, 1.6)
				game.sfx.play_at("screech", global_position + Vector3.UP * 1.5, -5, voice_pitch * randf_range(0.95, 1.05))
			else:
				attack_cd = minf(attack_cd, 0.4)
				repath -= dt
				if repath <= 0.0:
					repath = 0.3; agent.target_position = pl.global_position
				_nav_move(pl.global_position, dt, false)
				_unstick(dt, pl.global_position)
	stagger_t -= dt
	model.rotation.x = lerpf(model.rotation.x, 0.0, dt * 8.0) if state != State.RISE else model.rotation.x
	groan_cd -= dt
	if groan_cd <= 0.0:
		groan_cd = randf_range(3.5, 9) if not runner else randf_range(2.5, 6)
		game.sfx.play_at("groan%d" % voice, global_position + Vector3.UP * 1.5, -4, voice_pitch * randf_range(0.96, 1.04))

func _start_swing() -> void:
	windup_t = WINDUP
	cur_anim = ""; _play("Punch", 0.06, 1.7); attack_anim_t = 0.5

## Re-path when blocked: no progress toward the goal -> sidestep, then re-enter from the window nearest
## the closest player (out of sight if possible). Runs in TO_WINDOW and CHASE.
var watch := ProgressWatch.new()
func _unstick(dt: float, goal: Vector3) -> void:
	# chasing a player who is moving around isn't "stuck" just because distance doesn't shrink:
	# measure progress toward the goal, but count actual movement as progress too.
	var moved := global_position.distance_to(last_pos)
	last_pos = global_position
	var d := _flat_dist(goal)
	if state == State.CHASE and moved > speed * dt * 0.6 and watch.since < ProgressWatch.SIDESTEP: watch.since = maxf(0.0, watch.since - dt)
	match watch.update(d, dt):
		"sidestep":
			agent.target_position = global_position + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
			repath = 1.0
		"respawn":
			if game.has_method("on_zombie_stuck"): game.on_zombie_stuck(self)
			window = game.respawn_window_for(self)
			global_position = window.spawn_point + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1))
			velocity = Vector3.ZERO; knock = Vector3.ZERO
			state = State.TO_WINDOW; agent.target_position = window.outside_point
			watch.reset()

func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()

func _face(p: Vector3) -> void:
	var dir := p - global_position; dir.y = 0
	if dir.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 0.2)

func _nav_move(target: Vector3, dt: float, set_target := true) -> void:
	if attack_anim_t <= 0.0: _locomotion()
	if set_target and agent.target_position.distance_to(target) > 0.5:
		agent.target_position = target
	var next := agent.get_next_path_position()
	var dir := next - global_position; dir.y = 0
	if dir.length() < 0.05:
		dir = target - global_position; dir.y = 0
	dir = dir.normalized()
	var sep := Vector3.ZERO
	for z in game.zombies:
		if z == self or not is_instance_valid(z): continue
		var off: Vector3 = global_position - z.global_position; off.y = 0
		var l := off.length()
		if l < 0.7 and l > 0.001: sep += off / l * (0.7 - l)
	var slow := 0.15 if stagger_t > 0.0 else (0.35 if attack_anim_t > 0.0 else 1.0)
	var v := (dir + sep * 1.5).normalized() * speed * slow + knock
	knock = knock.move_toward(Vector3.ZERO, dt * 12)
	velocity.x = v.x; velocity.z = v.z
	velocity.y = velocity.y - 18.0 * dt if not is_on_floor() else -0.5
	move_and_slide()
	_face(global_position + dir)
	step_cd -= dt * speed
	if step_cd <= 0.0:
		step_cd = 0.55 if not crawler else 0.8
		if game.player and global_position.distance_to(game.player.global_position) < 14.0:
			game.sfx.play_at("drag" if crawler else "step%d" % (randi() % 3 + 1), global_position, -12, randf_range(0.8, 1.0))
