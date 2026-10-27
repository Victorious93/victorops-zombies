class_name Zombie
extends CharacterBody3D
## Stylised original low-poly zombie (built from primitives) with procedural shamble animation.
## States: rise outside -> walk to its window -> tear planks -> vault in -> chase on the navmesh.

enum State { RISE, TO_WINDOW, TEAR, VAULT, CHASE, DEAD }
const HEAD_Y := 1.45

var game
var window: WindowBarricade
var state := State.RISE
var hp := 100
var max_hp := 100
var speed := 1.1
var t := 0.0
var anim_t := 0.0
var attack_cd := 0.0
var groan_cd := 0.0
var repath := 0.0
var agent: NavigationAgent3D
var model: Node3D
var legs: Array = []
var arms: Array = []
var skin_mat: StandardMaterial3D
var flash_t := 0.0
var vault_from: Vector3
var knock := Vector3.ZERO

func setup(p_game, p_window: WindowBarricade, round: int) -> void:
	game = p_game; window = p_window
	max_hp = Rounds.zombie_health(round); hp = max_hp
	speed = Rounds.zombie_speed(round) * randf_range(0.9, 1.15)
	if Rounds.is_special(round): speed *= 1.0

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new()
	cap.radius = 0.32; cap.height = 1.8; cs.shape = cap; cs.position.y = 0.9
	add_child(cs)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.6; agent.target_desired_distance = 0.5
	agent.radius = 0.4; agent.height = 1.8
	add_child(agent)
	_build_model()
	t = 0.9; groan_cd = randf_range(1, 6)
	model.position.y = -1.8

func _mat(c: Color, emit := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = c; m.roughness = 0.95
	if emit:
		m.emission_enabled = true; m.emission = c; m.emission_energy_multiplier = 4.0
	return m

func _part(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm; mi.position = pos; mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi); return mi

func _build_model() -> void:
	model = Node3D.new(); add_child(model)
	skin_mat = _mat(Color(0.42, 0.5, 0.38).lerp(Color(0.5, 0.45, 0.4), randf()))
	var shirt := _mat([Color(0.2, 0.22, 0.28), Color(0.35, 0.3, 0.22), Color(0.3, 0.12, 0.1), Color(0.25, 0.28, 0.25)][randi() % 4])
	var pants := _mat(Color(0.12, 0.12, 0.14).lerp(Color(0.2, 0.17, 0.12), randf()))
	var eye := _mat(Color(1.0, 0.55, 0.1), true)
	var torso := Node3D.new(); torso.position.y = 0.95; torso.rotation.x = 0.18; model.add_child(torso)
	_part(torso, Vector3(0.5, 0.62, 0.28), Vector3(0, 0.3, 0), shirt)
	var head := _part(torso, Vector3(0.3, 0.32, 0.3), Vector3(0, 0.78, 0.02), skin_mat)
	head.rotation.z = randf_range(-0.25, 0.25)
	_part(head, Vector3(0.06, 0.04, 0.02), Vector3(-0.07, 0.03, -0.155), eye)
	_part(head, Vector3(0.06, 0.04, 0.02), Vector3(0.07, 0.03, -0.155), eye)
	_part(head, Vector3(0.14, 0.05, 0.02), Vector3(0, -0.09, -0.155), _mat(Color(0.15, 0.02, 0.02)))
	for side in [-1, 1]:
		var arm := Node3D.new(); arm.position = Vector3(0.32 * side, 0.55, 0); torso.add_child(arm)
		_part(arm, Vector3(0.13, 0.13, 0.62), Vector3(0, 0, -0.3), shirt if randf() < 0.6 else skin_mat)
		_part(arm, Vector3(0.12, 0.12, 0.14), Vector3(0, 0, -0.66), skin_mat)
		arm.rotation.x = -0.15; arms.append(arm)
		var leg := Node3D.new(); leg.position = Vector3(0.13 * side, 0.92, 0); model.add_child(leg)
		_part(leg, Vector3(0.18, 0.9, 0.2), Vector3(0, -0.46, 0), pants)
		legs.append(leg)

func take_damage(dmg: int, headshot: bool, player) -> void:
	if state == State.DEAD: return
	hp -= dmg
	flash_t = 0.08
	if hp <= 0:
		die(player, headshot)

func die(player, headshot: bool) -> void:
	state = State.DEAD; t = 2.2
	collision_layer = 0
	game.on_zombie_killed(self, player, headshot)

func push(v: Vector3) -> void:
	knock += v

func _physics_process(dt: float) -> void:
	anim_t += dt
	if flash_t > 0.0:
		flash_t -= dt
		skin_mat.emission_enabled = flash_t > 0.0
		skin_mat.emission = Color(1, 0.2, 0.1)
	match state:
		State.DEAD:
			t -= dt
			model.rotation.x = lerpf(model.rotation.x, -PI / 2, dt * 6)
			if t < 1.0: model.position.y -= dt * 0.8
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
			else:
				t -= dt
				for i in arms.size():
					arms[i].rotation.x = -0.3 + sin(anim_t * 8 + i * PI) * 0.6
				if t <= 0.0:
					t = randf_range(0.9, 1.4)
					window.bar.damage(window.bar.plank_hp); window.refresh()
					game.sfx.play_at("plank_rip", window.center(), -4, randf_range(0.9, 1.1))
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
			if d < 1.35 and not pl.is_downed:
				velocity = Vector3.ZERO; _face(pl.global_position)
				attack_cd -= dt
				for i in arms.size():
					arms[i].rotation.x = -0.2 + sin(anim_t * 10) * 0.5
				if attack_cd <= 0.0:
					attack_cd = 1.0
					pl.take_damage(30.0)
					game.sfx.play_at("zombie_attack", global_position, -2)
			else:
				attack_cd = minf(attack_cd, 0.4)
				repath -= dt
				if repath <= 0.0:
					repath = 0.3; agent.target_position = pl.global_position
				_nav_move(pl.global_position, dt, false)
	groan_cd -= dt
	if groan_cd <= 0.0:
		groan_cd = randf_range(4, 10)
		game.sfx.play_at("groan%d" % (randi() % 3 + 1), global_position + Vector3.UP * 1.5, -6, randf_range(0.85, 1.15))

func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length()

func _face(p: Vector3) -> void:
	var dir := p - global_position; dir.y = 0
	if dir.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-dir.x, -dir.z), 0.2)

func _nav_move(target: Vector3, dt: float, set_target := true) -> void:
	if set_target and agent.target_position.distance_to(target) > 0.5:
		agent.target_position = target
	var next := agent.get_next_path_position()
	var dir := next - global_position; dir.y = 0
	if dir.length() < 0.05:
		dir = target - global_position; dir.y = 0
	dir = dir.normalized()
	# light separation from neighbours so the horde does not stack
	var sep := Vector3.ZERO
	for z in game.zombies:
		if z == self or not is_instance_valid(z): continue
		var off: Vector3 = global_position - z.global_position; off.y = 0
		var l := off.length()
		if l < 0.7 and l > 0.001: sep += off / l * (0.7 - l)
	var v := (dir + sep * 1.5).normalized() * speed + knock
	knock = knock.move_toward(Vector3.ZERO, dt * 12)
	velocity.x = v.x; velocity.z = v.z
	velocity.y = -4.0 if not is_on_floor() else 0.0
	move_and_slide()
	_face(global_position + dir)
	var ph := anim_t * speed * 4.2
	legs[0].rotation.x = sin(ph) * 0.55; legs[1].rotation.x = -sin(ph) * 0.55
	for i in arms.size():
		arms[i].rotation.x = -0.15 + sin(ph + i) * 0.12
	model.rotation.z = sin(ph * 0.5) * 0.08
