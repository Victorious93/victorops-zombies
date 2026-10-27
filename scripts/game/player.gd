class_name Player
extends CharacterBody3D
## First-person survivor: hitscan guns, recoil, ADS, sprint, reload, use, ability.

const GRAVITY := 18.0
const WALK := 4.2
const MOUSE_SENS := 0.0022
const TOUCH_SENS := 0.006
const HIP_POS := Vector3(0.2, -0.2, -0.42)
const ADS_POS := Vector3(0.0, -0.11, -0.3)

var game
var touch  # TouchControls or null
var char_id := "snoop"
var cdef: Dictionary
var economy := Economy.new()
var armor := ArmorState.new()
var loadout: Loadout
var perks := {}
var max_health := 100.0
var health := 100.0
var low_trigger := LowHealthTrigger.new()
var ability_cd := 0.0
var fire_cd := 0.0
var since_hit := 99.0
var is_downed := false
var ads := false
var sprinting := false
var yaw := 0.0
var pitch := 0.0
var recoil := 0.0
var kick := 0.0
var bob := 0.0
var head: Node3D
var cam: Camera3D
var gun_holder: Node3D
var gun: Node3D
var flash: MeshInstance3D
var flash_light: OmniLight3D
var flash_t := 0.0
var prev_fire := false
var prev_use := false
var use_repeat := 0.0
var shown_weapon := ""

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 8
	cdef = Characters.by_id(char_id)
	max_health = cdef.max_health; health = max_health
	loadout = Loadout.new(Weapons.make(Weapons.STARTER))
	loadout.give(Weapons.make(cdef.start_weapon))
	loadout.current = 0
	var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new(); cap.radius = 0.35; cap.height = 1.8
	cs.shape = cap; cs.position.y = 0.9; add_child(cs)
	head = Node3D.new(); head.position.y = 1.62; add_child(head)
	cam = Camera3D.new(); cam.fov = 75; cam.near = 0.05; cam.far = 120; head.add_child(cam)
	cam.current = true
	var torch := SpotLight3D.new(); torch.light_energy = 1.6; torch.spot_range = 22; torch.spot_angle = 28
	torch.light_color = Color(1.0, 0.95, 0.85); torch.position = Vector3(0.15, -0.1, 0); cam.add_child(torch)
	gun_holder = Node3D.new(); gun_holder.position = HIP_POS; cam.add_child(gun_holder)
	flash = MeshInstance3D.new(); var q := QuadMesh.new(); q.size = Vector2(0.22, 0.22); flash.mesh = q
	var fm := StandardMaterial3D.new(); fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = Color(1.0, 0.8, 0.4); fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; fm.albedo_texture = _flash_tex()
	flash.material_override = fm; flash.visible = false
	flash_light = OmniLight3D.new(); flash_light.light_color = Color(1, 0.75, 0.4); flash_light.omni_range = 6
	flash_light.light_energy = 0.0
	_refresh_gun()

func _flash_tex() -> Texture2D:
	var g := Gradient.new(); g.set_color(0, Color(1, 1, 0.8, 1)); g.set_color(1, Color(1, 0.5, 0.1, 0))
	var gt := GradientTexture2D.new(); gt.gradient = g; gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5); gt.fill_to = Vector2(1.0, 0.5); gt.width = 64; gt.height = 64
	return gt

func weapon() -> WeaponDef: return loadout.weapon()
func ammo() -> Ammo: return loadout.ammo()

func _refresh_gun() -> void:
	var key := "%s:%d:%d" % [weapon().id, weapon().tier, loadout.current]
	if key == shown_weapon: return
	shown_weapon = key
	if gun:
		gun.remove_child(flash); gun.remove_child(flash_light); gun.queue_free()
	gun = GunModel.build(weapon())
	gun_holder.add_child(gun)
	var m: Node3D = gun.get_node("Muzzle")
	gun.add_child(flash); gun.add_child(flash_light)
	flash.position = m.position; flash_light.position = m.position

func _unhandled_input(e: InputEvent) -> void:
	if touch and touch.visible: return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= e.relative.x * MOUSE_SENS * (0.6 if ads else 1.0)
		pitch = clampf(pitch - e.relative.y * MOUSE_SENS * (0.6 if ads else 1.0), -1.45, 1.45)
	elif e is InputEventMouseButton and e.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not game.over:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			swap()
	elif e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_R: reload()
			KEY_Q: use_ability()
			KEY_1, KEY_2, KEY_X: swap()

func swap() -> void:
	if loadout.slots.size() > 1:
		loadout.cycle(); fire_cd = 0.3; kick = 0.6

func reload() -> void:
	if ammo().reload(): game.sfx.play("reload", -4)

func _key(k: Key) -> bool: return Input.is_physical_key_pressed(k)

func _physics_process(dt: float) -> void:
	if game.over or is_downed: return
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
	if touch and touch.visible:
		mv += touch.move
		var look: Vector2 = touch.consume_look()
		yaw -= look.x * TOUCH_SENS * (0.6 if ads else 1.0)
		pitch = clampf(pitch - look.y * TOUCH_SENS * (0.6 if ads else 1.0), -1.45, 1.45)
		fire = fire or touch.fire
		want_ads = want_ads or touch.ads
		use = use or touch.use
		sprint_key = sprint_key or touch.sprint
		if touch.take("reload"): reload()
		if touch.take("swap"): swap()
		if touch.take("skill"): use_ability()
	mv = mv.limit_length(1.0)
	ads = want_ads and not sprinting
	sprinting = sprint_key and mv.y < -0.3 and not ads
	var spd: float = WALK * cdef.speed_mult * (1.15 if perks.has("fleetfoot") else 1.0)
	if sprinting: spd *= 1.7 if perks.has("fleetfoot") else 1.5
	if ads: spd *= 0.6
	var dir := (transform.basis * Vector3(mv.x, 0, mv.y)) * spd
	velocity.x = dir.x; velocity.z = dir.z
	velocity.y = 0.0 if is_on_floor() else velocity.y - GRAVITY * dt
	move_and_slide()
	# look + recoil recovery
	recoil = lerpf(recoil, 0.0, clampf(dt * 8.0, 0, 1))
	rotation.y = yaw
	head.rotation.x = clampf(pitch + recoil, -1.5, 1.5)
	cam.fov = lerpf(cam.fov, 55.0 if ads else (80.0 if sprinting else 75.0), clampf(dt * 12, 0, 1))
	# weapon
	loadout.update(dt)
	fire_cd -= dt
	ability_cd -= dt
	_refresh_gun()
	if fire and not sprinting:
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
	# regen after 4 s without damage (3D rule; health also refills between rounds)
	if since_hit > 4.0 and health < max_health:
		health = minf(max_health, health + 25.0 * dt)
	# viewmodel
	bob += dt * mv.length() * (11.0 if sprinting else 7.0)
	var target: Vector3 = ADS_POS if ads else HIP_POS
	var bob_off := Vector3(sin(bob) * 0.012, absf(cos(bob)) * 0.014, 0) * (0.3 if ads else 1.0)
	if sprinting: target += Vector3(-0.05, -0.05, 0.05)
	kick = lerpf(kick, 0.0, clampf(dt * 14, 0, 1))
	var reload_dip := 0.15 if ammo().reloading() else 0.0
	gun_holder.position = gun_holder.position.lerp(target + bob_off + Vector3(0, -reload_dip, kick * 0.08), clampf(dt * 16, 0, 1))
	gun_holder.rotation.x = lerpf(gun_holder.rotation.x, kick * 0.25 - reload_dip * 3.0 + (-0.35 if sprinting else 0.0), clampf(dt * 14, 0, 1))
	if flash_t > 0.0:
		flash_t -= dt
		if flash_t <= 0.0: flash.visible = false; flash_light.light_energy = 0.0

func try_fire(moving: bool) -> void:
	var a := ammo()
	if fire_cd > 0.0: return
	if not a.can_fire():
		if not a.reloading(): reload()
		return
	var w := weapon()
	fire_cd = w.fire_interval * cdef.fire_interval_mult
	var spread := deg_to_rad(w.spread_deg) * (0.3 if ads else 1.0) * (1.4 if moving else 1.0)
	var origin := cam.global_position
	var fwd := -cam.global_basis.z
	for i in w.pellets:
		var d := fwd.rotated(cam.global_basis.x, randf_range(-spread, spread)).rotated(cam.global_basis.y, randf_range(-spread, spread))
		game.hitscan(self, origin, d.normalized(), w)
	if a.fire():
		game.bark(Barks.RELOAD)
		game.sfx.play("reload", -4)
	recoil += deg_to_rad(w.recoil) * (0.6 if ads else 1.0)
	yaw += deg_to_rad(randf_range(-w.recoil, w.recoil) * 0.2)
	kick = 1.0
	flash.visible = true; flash.rotation.z = randf() * TAU; flash_light.light_energy = 3.0; flash_t = 0.05
	var snd := "shot_light"
	if w.id == "nova" or w.id == "cannon": snd = "shot_energy"
	elif w.pellets > 1: snd = "shot_heavy"
	elif w.automatic: snd = "shot_auto"
	game.sfx.play(snd, -6.0 if w.automatic else -3.0, randf_range(0.95, 1.05) * (0.85 if w.tier > 0 else 1.0))

func use_ability() -> void:
	if ability_cd > 0.0 or game.over: return
	game.use_ability(self)

func take_damage(d: float) -> void:
	if is_downed or game.over: return
	health -= armor.absorb(d)
	since_hit = 0.0
	game.hud.damage_flash()
	game.sfx.play("hurt", -3)
	if low_trigger.check(health, max_health): game.bark(Barks.DANGER)
	if health <= 0.0:
		health = 0.0; is_downed = true
		game.on_player_downed(self)

func set_max_health_from_perks() -> void:
	max_health = cdef.max_health * (2.0 if perks.has("ironhide") else 1.0)
	health = max_health

func apply_reload_perk() -> void:
	for s in loadout.slots: s.reload_mult = 0.5 if perks.has("quickhand") else 1.0
