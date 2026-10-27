class_name Player
extends CharacterBody3D
## First-person survivor: hitscan guns with a full viewmodel, ADS red-dot, sway/bob, recoil,
## camera shake, shell ejection, knife, grenades, touch aim assist, sprint, reload, use, ability.

const GRAVITY := 18.0
const WALK := 4.2
const MOUSE_SENS := 0.0022
const TOUCH_SENS := 0.006
const SHOT_SOUND := {pistol = "shot_pistol", smg = "shot_smg", shotgun = "shot_shotgun", rifle = "shot_rifle", lmg = "shot_lmg", launcher = "shot_launcher", raygun = "shot_nova"}

var game
var touch  # TouchControls or null
var char_id := Characters.DEFAULT
var cdef: Dictionary
var economy := Economy.new()
var armor := ArmorState.new()
var equipment := Equipment.new()
var loadout: Loadout
var perks := {}
var max_health := 100.0
var health := 100.0
var low_trigger := LowHealthTrigger.new()
var ability_cd := 0.0
var fire_cd := 0.0
var knife_cd := 0.0
var since_hit := 99.0
var is_downed := false
var ads := false
var sprinting := false
var yaw := 0.0
var pitch := 0.0
var recoil := 0.0
var trauma := 0.0
var shake_t := 0.0
var head: Node3D
var cam: Camera3D
var vm: Viewmodel
var gun: Node3D:  # kept for Game.hitscan (muzzle lookup)
	get: return vm.gun if vm else null
var prev_fire := false
var prev_use := false
var use_repeat := 0.0
var step_t := 0.0
var reload_beats := {}
var sens := 1.0
var aim_assist := true
## Feel: stamina sprint, slide, per-gun recoil pattern, ADS ramp, knife lunge, last stand.
const STAMINA_MAX := 4.0       ## seconds of sprint
const STAMINA_REGEN := 1.2     ## seconds of rest before it refills
const SLIDE_TIME := 0.55
const SLIDE_SPEED := 8.5
const LUNGE_RANGE := 3.2
const REGEN_DELAY := 4.0
const REGEN_RATE := 60.0
var stamina := STAMINA_MAX
var stamina_rest := 0.0
var slide_t := 0.0
var slide_dir := Vector3.ZERO
var ads01 := 0.0
var pattern_i := 0
var pattern_reset := 0.0
var lunge_t := 0.0
var lunge_vel := Vector3.ZERO
var last_stand := LastStand.new()
var stand_loadout: Loadout = null
var saved_loadout: Loadout = null
var crouch_key_prev := false
## Bot/sim driver: when set, {mv: Vector2, fire, ads, use, sprint: bool} replaces device input.
var bot_input = null

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 8
	cdef = Characters.by_id(char_id)
	max_health = cdef.max_health; health = max_health
	loadout = Loadout.new(Weapons.make(Weapons.STARTER))
	loadout.give(Weapons.make(cdef.start_weapon))
	loadout.current = 0
	if game and game.settings:
		sens = game.settings.sensitivity; aim_assist = game.settings.aim_assist
	var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.35; cap.height = 1.8
	cs.shape = cap; cs.position.y = 0.9; add_child(cs)
	head = Node3D.new(); head.position.y = 1.62; add_child(head)
	cam = Camera3D.new(); cam.fov = 75; cam.near = 0.03; cam.far = 140; head.add_child(cam)
	cam.current = true
	var torch := SpotLight3D.new(); torch.light_energy = 1.6; torch.spot_range = 22; torch.spot_angle = 28
	torch.light_color = Color(1.0, 0.95, 0.85); torch.position = Vector3(0.15, -0.1, 0); cam.add_child(torch)
	vm = Viewmodel.new(); vm.setup(cdef.get("color", Color(0.4, 0.4, 0.45))); cam.add_child(vm)
	cam.add_child(vm.knife); cam.add_child(vm.grenade_hand)
	vm.set_weapon(weapon())

func weapon() -> WeaponDef: return loadout.weapon()
func ammo() -> Ammo: return loadout.ammo()

func _look(d: Vector2, base: float) -> void:
	var k := base * sens * (0.6 if ads else 1.0)
	yaw -= d.x * k
	pitch = clampf(pitch - d.y * k, -1.45, 1.45)
	vm.add_sway(Vector2(d.x, -d.y) * k)

func _unhandled_input(e: InputEvent) -> void:
	if touch and touch.visible: return
	if game.paused:
		if e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE: game.toggle_pause()
		return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look(e.relative, MOUSE_SENS)
	elif e is InputEventMouseButton and e.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not game.over and not game.paused:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			swap()
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_ESCAPE: game.toggle_pause()
			KEY_R: reload()
			KEY_Q: use_ability()
			KEY_V: melee()
			KEY_G: throw_grenade()
			KEY_1, KEY_2, KEY_X: swap()

func swap() -> void:
	if loadout.slots.size() > 1:
		loadout.cycle(); fire_cd = 0.35
		game.sfx.play("bolt", -10)

func reload() -> void:
	if ammo().reload(): _start_reload_sfx()

func _start_reload_sfx() -> void:
	reload_beats = {out = false, ins = false, bolt = false}
	game.sfx.play("mag_out", -6)
	reload_beats.out = true

func reload01() -> float:
	var a := ammo()
	if not a.reloading(): return -1.0
	var total := a.weapon.reload_time * a.reload_mult
	return 1.0 - a.reload_left / maxf(total, 0.01)

func _key(k: Key) -> bool: return Input.is_physical_key_pressed(k)

func add_trauma(a: float) -> void:
	trauma = clampf(trauma + a, 0.0, 1.0)

func _physics_process(dt: float) -> void:
	if game.paused and touch and touch.visible and touch.take("pause"): game.toggle_pause()
	if game.over or game.paused: return
	if is_downed: _downed_tick(dt)
	since_hit += dt
	var mv := Vector2.ZERO
	if _key(KEY_W): mv.y -= 1
	if _key(KEY_S): mv.y += 1
	if _key(KEY_A): mv.x -= 1
	if _key(KEY_D): mv.x += 1
	var fire := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var want_ads := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var use := _key(KEY_E) or _key(KEY_F)
	var sprint_key := _key(KEY_SHIFT)
	var crouch := _key(KEY_C) or _key(KEY_CTRL)
	var on_touch: bool = touch != null and touch.visible
	if bot_input != null:
		mv = bot_input.mv; fire = bot_input.fire; want_ads = bot_input.ads; use = bot_input.use; sprint_key = bot_input.sprint
	elif on_touch:
		mv += touch.move
		_look(touch.consume_look(), TOUCH_SENS)
		fire = fire or touch.fire
		want_ads = want_ads or touch.ads
		use = use or touch.use
		sprint_key = sprint_key or touch.sprint
		if touch.take("reload"): reload()
		if touch.take("swap"): swap()
		if touch.take("skill"): use_ability()
		if touch.take("knife"): melee()
		if touch.take("grenade"): throw_grenade()
		if touch.take("pause"): game.toggle_pause(); return
	mv = mv.limit_length(1.0)
	if is_downed:
		sprint_key = false; crouch = false
	ads = want_ads and not sprinting
	ads01 = move_toward(ads01, 1.0 if ads else 0.0, dt / maxf(weapon().ads_time, 0.05))
	var stam_max := STAMINA_MAX * (1.6 if perks.has("fleetfoot") else 1.0)
	sprinting = sprint_key and mv.y < -0.3 and not ads and stamina > 0.0
	if sprinting:
		stamina = maxf(0.0, stamina - dt); stamina_rest = STAMINA_REGEN
	else:
		stamina_rest -= dt
		if stamina_rest <= 0.0: stamina = minf(stam_max, stamina + dt * 1.5)
	# slide: crouch while sprinting
	if crouch and not crouch_key_prev and sprinting and slide_t <= 0.0 and is_on_floor():
		slide_t = SLIDE_TIME; slide_dir = (transform.basis * Vector3(mv.x, 0, mv.y)).normalized()
		game.sfx.play("slide", -6, randf_range(0.95, 1.05)); add_trauma(0.1)
	crouch_key_prev = crouch
	var spd: float = WALK * cdef.speed_mult * (1.15 if perks.has("fleetfoot") else 1.0)
	if is_downed: spd *= 0.25
	if sprinting: spd *= 1.7 if perks.has("fleetfoot") else 1.5
	spd *= lerpf(1.0, 0.6, ads01)
	var dir := (transform.basis * Vector3(mv.x, 0, mv.y)) * spd
	if slide_t > 0.0:
		slide_t -= dt
		dir = slide_dir * SLIDE_SPEED * clampf(slide_t / SLIDE_TIME + 0.3, 0.0, 1.0) + dir * 0.3
	if lunge_t > 0.0:
		lunge_t -= dt; dir = lunge_vel
	velocity.x = dir.x; velocity.z = dir.z
	velocity.y = -0.5 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	# footsteps
	if is_on_floor() and mv.length() > 0.2:
		step_t -= dt * spd / WALK
		if step_t <= 0.0:
			step_t = 0.42
			game.sfx.play("step%d" % (randi() % 3 + 1), -16 if not sprinting else -12, randf_range(1.1, 1.3))
	# aim assist (touch, or when enabled): slow pull toward the nearest zombie in a small cone
	if aim_assist and on_touch and (ads or fire):
		var targets: Array = []
		for z in game.zombies:
			if is_instance_valid(z) and z.state != Zombie.State.DEAD:
				targets.append(z.global_position + Vector3.UP * (0.5 if z.crawler else 1.25))
		var fwd := -cam.global_basis.z
		var i := AimAssist.pick(cam.global_position, fwd, targets)
		if i >= 0:
			var n := AimAssist.nudge(cam.global_position, fwd, targets[i], dt)
			yaw += n.x; pitch = clampf(pitch + n.y, -1.45, 1.45)
	# look + recoil recovery + shake
	recoil = lerpf(recoil, 0.0, clampf(dt * 8.0, 0, 1))
	trauma = move_toward(trauma, 0.0, dt * 1.6)
	shake_t += dt * 30.0
	var sh := trauma * trauma
	rotation.y = yaw
	head.rotation.x = clampf(pitch + recoil, -1.5, 1.5) + sin(shake_t * 1.3) * sh * 0.05
	head.rotation.z = sin(shake_t * 0.9 + 1.7) * sh * 0.06
	var base_fov := 82.0 if sprinting or slide_t > 0.0 else 75.0
	cam.fov = lerpf(base_fov, 55.0, ads01)
	var head_y := 0.55 if is_downed else (1.0 if slide_t > 0.0 else 1.62)
	head.position.y = lerpf(head.position.y, head_y, clampf(dt * 10.0, 0, 1))
	pattern_reset -= dt
	if pattern_reset <= 0.0: pattern_i = 0
	# weapon
	loadout.update(dt)
	fire_cd -= dt
	knife_cd -= dt
	ability_cd -= dt
	vm.set_weapon(weapon())
	var r01 := reload01()
	if r01 >= 0.0:
		if not reload_beats.get("out", false): _start_reload_sfx()
		if r01 > 0.55 and not reload_beats.ins: reload_beats.ins = true; game.sfx.play("mag_in", -5)
		if r01 > 0.85 and not reload_beats.bolt: reload_beats.bolt = true; game.sfx.play("bolt", -6)
	else:
		reload_beats = {}
	if fire and not sprinting and vm.knife_t <= 0.0 and vm.throw_t <= 0.0:
		if weapon().automatic or not prev_fire:
			try_fire(mv.length() > 0.1)
	prev_fire = fire
	# use / hold-to-repair
	use_repeat -= dt
	if use:
		game.player_use(self, not prev_use, use_repeat <= 0.0)
		if use_repeat <= 0.0: use_repeat = 0.45
	else:
		use_repeat = 0.0
	prev_use = use
	if since_hit > REGEN_DELAY and health < max_health and not is_downed:
		health = minf(max_health, health + REGEN_RATE * dt)
	vm.tick(dt, ads, mv.length(), sprinting, r01)

func try_fire(moving: bool) -> void:
	var a := ammo()
	if fire_cd > 0.0: return
	if not a.can_fire():
		if not a.reloading(): reload()
		else: return
		game.sfx.play("deny", -18, 2.0)
		return
	var w := weapon()
	fire_cd = w.fire_interval * cdef.fire_interval_mult
	var spread := deg_to_rad(w.spread_deg) * lerpf(1.0, 0.3, ads01) * (1.4 if moving else 1.0) * (1.6 if slide_t > 0.0 else 1.0)
	var origin := cam.global_position
	var fwd := -cam.global_basis.z
	for i in w.pellets:
		var d := fwd.rotated(cam.global_basis.x, randf_range(-spread, spread)).rotated(cam.global_basis.y, randf_range(-spread, spread))
		game.hitscan(self, origin, d.normalized(), w)
	if a.fire():
		game.bark(Barks.RELOAD)
		_start_reload_sfx()
	# learnable per-gun recoil pattern (resets after a short pause in fire), plus a little noise
	var kick: Vector2 = w.recoil_pattern[pattern_i % w.recoil_pattern.size()]
	pattern_i += 1; pattern_reset = w.fire_interval * 2.5 + 0.15
	var k := lerpf(1.0, 0.6, ads01)
	recoil += deg_to_rad(w.recoil * kick.x) * k
	yaw -= deg_to_rad(w.recoil * kick.y * 0.35 + randf_range(-0.05, 0.05) * w.recoil) * k
	vm.fire(0.5 + w.recoil * 0.15)
	add_trauma(0.06 + w.recoil * 0.025 * (0.5 if ads else 1.0))
	var model: String = vm.model_name
	game.sfx.play(SHOT_SOUND.get(model, "shot_pistol"), -7.0 if w.automatic else -4.0, randf_range(0.95, 1.05) * (0.88 if w.tier > 0 else 1.0))
	if w.tier > 0: game.sfx.play("shot_energy", -16, 1.6)
	if model != "raygun" and model != "launcher":
		var b := cam.global_basis
		game.fx.shell(vm.gun.global_position + b.x * 0.03 + b.y * 0.03, b.x, b.y, model == "shotgun")

func melee() -> void:
	if knife_cd > 0.0 or game.over: return
	knife_cd = Equipment.KNIFE_COOLDOWN
	vm.knife_t = 1.0
	game.sfx.play("knife_swing", -4, randf_range(0.9, 1.1))
	# lunge: snap toward a zombie in front within LUNGE_RANGE before the stab lands
	var tgt = game.knife_target(self, LUNGE_RANGE)
	if tgt and not is_downed:
		var off: Vector3 = tgt.global_position - global_position; off.y = 0
		if off.length() > Equipment.KNIFE_RANGE_M * 0.7:
			lunge_t = 0.12; lunge_vel = off.normalized() * (off.length() - 0.8) / 0.12
			get_tree().create_timer(0.12, true, true).timeout.connect(func(): game.melee(self))
			return
	game.melee(self)

func throw_grenade() -> void:
	if vm.throw_t > 0.0 or game.over: return
	if not equipment.throw_one():
		game.hud.info("No grenades"); return
	vm.throw_t = 1.0
	var dir := (-cam.global_basis.z + Vector3.UP * 0.25).normalized()
	game.throw_grenade(self, cam.global_position + dir * 0.5, dir * 14.0 + velocity * 0.5)

func use_ability() -> void:
	if ability_cd > 0.0 or game.over: return
	game.use_ability(self)

func take_damage(d: float, from := Vector3.INF) -> void:
	if is_downed or game.over: return
	if game.god_mode: d = 0.0
	health -= armor.absorb(d)
	since_hit = 0.0
	add_trauma(0.35)
	game.hud.damage_flash(_dir_angle(from))
	game.sfx.play("hurt", -3)
	if low_trigger.check(health, max_health): game.bark(Barks.DANGER)
	if health <= 0.0:
		health = 0.0
		go_down()

## Last stand: drop to the floor with a sidearm; Lazarus Fizz gets you back up, otherwise bleed out.
func go_down() -> void:
	is_downed = true; slide_t = 0.0; ads = false
	var has_laz: bool = perks.get("lazarus", false)
	last_stand.start(has_laz)
	saved_loadout = loadout
	var i := loadout.has("sidearm")
	var pistol: WeaponDef = loadout.slots[i].weapon if i >= 0 else Weapons.make("sidearm")
	stand_loadout = Loadout.new(pistol); loadout = stand_loadout
	apply_reload_perk()
	game.on_player_downed(self)

func _downed_tick(dt: float) -> void:
	match last_stand.update(dt):
		"revive": revive()
		"dead": game.on_player_bled_out(self)

func revive() -> void:
	is_downed = false
	loadout = saved_loadout
	var keep_buys = perks.get("_lazarus_buys", 0)
	perks = {"_lazarus_buys": keep_buys}  # self-revive costs every perk
	set_max_health_from_perks(); apply_reload_perk()
	health = max_health; since_hit = 99.0
	game.on_player_revived(self)

## Screen-space angle (radians, 0 = ahead, +right) of a world position, or NAN.
func _dir_angle(from: Vector3) -> float:
	if from == Vector3.INF: return NAN
	var off := to_local(from); off.y = 0
	if off.length() < 0.01: return NAN
	return atan2(off.x, -off.z)

func set_max_health_from_perks() -> void:
	max_health = cdef.max_health * (2.0 if perks.has("ironhide") else 1.0)
	health = max_health

func apply_reload_perk() -> void:
	for s in loadout.slots: s.reload_mult = 0.5 if perks.has("quickhand") else 1.0
