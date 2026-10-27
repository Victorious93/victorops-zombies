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

func setup(p_game, p_window: WindowBarricade, round: int) -> void:
	game = p_game; window = p_window
	max_hp = Rounds.zombie_health(round); hp = max_hp
	speed = Rounds.zombie_speed(round) * randf_range(0.9, 1.15)
	runner = speed > 1.9
	variant = "zombie_b" if randf() < 0.35 else "zombie_a"

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
	ModelLib.set_shadows(model, game == null or game.settings_shadows())
	if ap:
		for k in ["Walk", "Run", "Crawl", "Idle"]:
			if anims.has(k): ap.get_animation(anims[k]).loop_mode = Animation.LOOP_LINEAR
		ap.speed_scale = randf_range(0.9, 1.1)
	t = 0.9; groan_cd = randf_range(1, 6)
	model.position.y = -1.8
	_play("Idle")

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
func take_damage(dmg: int, headshot: bool, player, part := "body", force := Vector3.ZERO) -> void:
	if state == State.DEAD: return
	hp -= dmg
	flash_t = 0.07
	if part == "leg" and not crawler:
		leg_damage += dmg
		if leg_damage > max_hp * 0.45 and anims.has("Crawl") and hp > 0 and randf() < 0.6:
			_become_crawler()
	if hp <= 0:
		die(player, headshot, force, dmg)
	elif dmg > max_hp * 0.2 and state == State.CHASE and cur_anim != "Punch" and not crawler:
		_play("HitReact", 0.05); cur_anim = "HitReact"; attack_anim_t = 0.35

func _become_crawler() -> void:
	crawler = true; speed *= 0.5
	(shape.shape as CapsuleShape3D).height = 0.9; shape.position.y = 0.45
	if game: game.fx.gibs(global_position + Vector3.UP * 0.4, 3, self)

func die(player, headshot: bool, force := Vector3.ZERO, dmg := 0) -> void:
	state = State.DEAD; t = 4.0
	collision_layer = 0
	velocity = Vector3.ZERO
	if anims.has("Death"):
		cur_anim = ""; _play("Death", 0.08)
	if game:
		var gore := headshot or dmg >= max_hp * 2 or force.length() > 4.0
		game.fx.blood_pool(global_position)
		if gore: game.fx.gibs(global_position + Vector3.UP * (1.5 if headshot else 1.0), 6 if headshot else 9, self, force)
		game.on_zombie_killed(self, player, headshot)
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
			if t < 1.2: model.position.y -= dt * 0.5
			if t <= 0.0: queue_free()
			return
		State.RISE:
			t -= dt
			model.position.y = lerpf(model.position.y, 0.0, dt * 4)
			if t <= 0.0:
				model.position.y = 0; state = State.TO_WINDOW; agent.target_position = window.outside_point
		State.TO_WINDOW:
			if _flat_dist(window.outside_point) < 0.7:
				state = State.TEAR; t = 1.0
			else:
				_nav_move(window.outside_point, dt)
		State.TEAR:
			_face(window.center()); velocity = Vector3.ZERO
			if window.bar.is_broken():
				state = State.VAULT; t = 0.0; vault_from = global_position
				_play("Run" if anims.has("Run") else "Walk", 0.1)
			else:
				_play("Punch", 0.2, 0.8)
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
				state = State.CHASE; repath = 0.0
		State.CHASE:
			var pl = game.player
			if pl == null: return
			var d := _flat_dist(pl.global_position)
			var dy: float = absf(pl.global_position.y - global_position.y)
			if d < (1.0 if crawler else 1.35) and dy < 1.6 and not pl.is_downed:
				velocity = Vector3.ZERO; _face(pl.global_position)
				attack_cd -= dt
				if attack_cd <= 0.0:
					attack_cd = 1.0
					cur_anim = ""; _play("Punch", 0.1, 1.3); attack_anim_t = 0.6
					pl.take_damage(20.0 if crawler else 30.0, global_position)
					game.sfx.play_at("zombie_attack", global_position + Vector3.UP, -2)
			else:
				attack_cd = minf(attack_cd, 0.4)
				repath -= dt
				if repath <= 0.0:
					repath = 0.3; agent.target_position = pl.global_position
				_nav_move(pl.global_position, dt, false)
	groan_cd -= dt
	if groan_cd <= 0.0:
		groan_cd = randf_range(4, 10)
		game.sfx.play_at("groan%d" % (randi() % 3 + 1), global_position + Vector3.UP * 1.5, -4, randf_range(0.85, 1.15) * (0.85 if variant == "zombie_b" else 1.0))

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
	var slow := 0.35 if attack_anim_t > 0.0 else 1.0
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
