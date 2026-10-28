extends Node
## Main menu + match host. Cmdline (after --): --shots=<dir> renders screenshots then quits; --touch forces touch UI.

const LOGO := "res://assets/victorops-zombies-logo.jpg"
var game: Game
var menu: CanvasLayer
var selected := Characters.DEFAULT
var args := {}

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	show_menu()
	if args.has("shots"): _shots(args["shots"])
	elif args.has("sim"): _sim(int(args["sim"]))
	elif args.has("clip"): _clip(args["clip"])

var diorama: Node3D
var settings := GameSettings.new()

## 3D menu backdrop: a foggy loading bay with shambling zombies, the crate glow and a slow camera drift.
func _build_diorama() -> void:
	diorama = Node3D.new(); add_child(diorama)
	var env := Environment.new(); env.background_mode = Environment.BG_COLOR; env.background_color = Color(0.01, 0.012, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color = Color(0.25, 0.28, 0.4); env.ambient_light_energy = 0.4
	env.fog_enabled = true; env.fog_density = 0.07; env.fog_light_color = Color(0.12, 0.05, 0.06)
	env.glow_enabled = true; env.glow_intensity = 0.8; env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = env; diorama.add_child(we)
	var floor := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(60, 60); floor.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_texture = load("res://assets/textures/concrete034_albedo.jpg")
	fm.normal_enabled = true; fm.normal_texture = load("res://assets/textures/concrete034_normal.jpg")
	fm.uv1_scale = Vector3(14, 14, 1); fm.albedo_color = Color(0.5, 0.5, 0.5); floor.material_override = fm; diorama.add_child(floor)
	for i in 5:
		var v := "zombie_b" if i % 2 == 1 else "zombie_a"
		var c := ModelLib.character(v, 1.8)
		var z: Node3D = c[0]; var ap: AnimationPlayer = c[1]
		z.position = Vector3(-3.2 + i * 1.6 + randf_range(-0.3, 0.3), 0, -4.0 - (i % 3) * 1.4)
		z.rotation.y = randf_range(-0.3, 0.3)
		diorama.add_child(z)
		var an := ModelLib.anim_name(ap, ["Walk", "Idle"])
		if an != "":
			ap.get_animation(an).loop_mode = Animation.LOOP_LINEAR
			ap.play(an); ap.seek(randf() * 1.5, true); ap.speed_scale = randf_range(0.5, 0.75)
	var crate := ModelLib.prop("chest", 1.0); crate.position = Vector3(3.2, 0, -2.2); crate.rotation.y = -0.6; diorama.add_child(crate)
	var cl := OmniLight3D.new(); cl.light_color = Color(0.3, 0.8, 1.0); cl.light_energy = 3.0; cl.omni_range = 4.0; cl.position = Vector3(3.2, 1.2, -2.0); diorama.add_child(cl)
	var car := ModelLib.prop("police_car", 4.5); car.position = Vector3(-4.5, 0, -8.5); car.rotation.y = 0.9; diorama.add_child(car)
	var rl := OmniLight3D.new(); rl.light_color = Color(1.0, 0.1, 0.05); rl.light_energy = 3.0; rl.omni_range = 8.0; rl.position = Vector3(-4.5, 2.0, -7.5); diorama.add_child(rl)
	rl.set_script(load("res://scripts/game/flicker_light.gd"))
	var key := SpotLight3D.new(); key.light_color = Color(0.7, 0.8, 1.0); key.light_energy = 4.0; key.spot_range = 20; key.spot_angle = 35
	key.position = Vector3(2, 6, 2); key.look_at_from_position(key.position, Vector3(0, 0.5, -5)); diorama.add_child(key)
	var cam := Camera3D.new(); cam.name = "Cam"; cam.position = Vector3(0, 1.5, 3.2); cam.fov = 60; diorama.add_child(cam)
	cam.look_at(Vector3(0, 1.2, -4)); cam.current = true

func _process(dt: float) -> void:
	if diorama and is_instance_valid(diorama):
		var cam: Camera3D = diorama.get_node("Cam")
		var t := Time.get_ticks_msec() / 1000.0
		cam.position = Vector3(sin(t * 0.15) * 0.8, 1.5 + sin(t * 0.3) * 0.08, 3.2)
		cam.look_at(Vector3(0, 1.2, -4))

func _menu_btn(text: String, size: int, w: float, h: float) -> Button:
	var b := Button.new(); b.text = text; b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", size); b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b

func show_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false
	if game: game.queue_free(); game = null
	Game.load_settings(settings)
	_build_diorama()
	menu = CanvasLayer.new(); add_child(menu)
	var shade := ColorRect.new(); shade.color = Color(0, 0, 0, 0.35); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE; menu.add_child(shade)
	var box := VBoxContainer.new(); box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER; box.add_theme_constant_override("separation", 14); menu.add_child(box)
	var logo := TextureRect.new(); logo.texture = load(LOGO)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0, 220); box.add_child(logo)
	var pick := HBoxContainer.new(); pick.alignment = BoxContainer.ALIGNMENT_CENTER; pick.add_theme_constant_override("separation", 20)
	box.add_child(pick)
	var desc := Label.new(); desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 22); desc.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	desc.add_theme_color_override("font_outline_color", Color.BLACK); desc.add_theme_constant_override("outline_size", 6)
	var group := ButtonGroup.new()
	for id in Characters.ALL:
		var c: Dictionary = Characters.ALL[id]
		var b := _menu_btn("%s\n%s" % [c.name, c.role], 22, 300, 78); b.toggle_mode = true; b.button_group = group
		b.button_pressed = id == selected
		b.pressed.connect(func(): selected = id; desc.text = c.tagline)
		pick.add_child(b)
	desc.text = Characters.ALL[selected].tagline
	box.add_child(desc)
	var play := _menu_btn("SURVIVE", 36, 360, 80); play.pressed.connect(start_game); box.add_child(play)
	var sb := _menu_btn("Settings", 24, 240, 56); box.add_child(sb)
	sb.pressed.connect(func():
		var panel := SettingsPanel.make(settings, func(): Game.save_settings(settings), [])
		var close := _menu_btn("Back", 28, 320, 64)
		panel.get_child(0).add_child(close)
		close.pressed.connect(panel.queue_free)
		menu.add_child(panel))
	var ab := _menu_btn("Armory", 24, 240, 56); box.add_child(ab)
	ab.pressed.connect(_show_armory)
	var note := Label.new(); note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.text = "Solo · Co-op coming next · WASD/mouse, V knife, G grenade, Q ability · or touch"
	note.add_theme_font_size_override("font_size", 18); note.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	box.add_child(note)

## Armory: pick which wall gun hangs in the spawn room (price unchanged; the others move deeper in).
func _show_armory() -> void:
	var panel := PanelContainer.new(); panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new(); sb.bg_color = Color(0.01, 0.01, 0.04, 0.9); panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new(); v.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_theme_constant_override("separation", 18); panel.add_child(v)
	var t := Label.new(); t.text = "ARMORY  ·  choose your spawn-room wall gun"; t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 34); t.add_theme_color_override("font_color", Color(0.3, 0.95, 1.0)); v.add_child(t)
	var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER; row.add_theme_constant_override("separation", 20); v.add_child(row)
	var group := ButtonGroup.new()
	for id in GameSettings.STARTER_GUNS:
		var w := Weapons.make(id)
		var b := _menu_btn("%s\n%d pts · %d dmg · %d mag" % [w.name, Weapons.WALL_PRICES[id], w.damage, w.mag_size], 22, 300, 96)
		b.toggle_mode = true; b.button_group = group; b.button_pressed = settings.starter_gun == id
		var gid: String = id
		b.pressed.connect(func(): settings.starter_gun = gid; Game.save_settings(settings))
		row.add_child(b)
	var close := _menu_btn("Back", 28, 320, 64); close.pressed.connect(panel.queue_free); v.add_child(close)
	var tut := _menu_btn("Replay tutorial", 22, 320, 56); v.add_child(tut)
	tut.pressed.connect(func(): settings.tutorial_done = false; Game.save_settings(settings); tut.text = "Tutorial on next run")
	menu.add_child(panel)

func start_game() -> void:
	if menu: menu.queue_free(); menu = null
	if diorama: diorama.queue_free(); diorama = null
	if game: game.queue_free()
	game = Game.new(); game.character_id = selected; game.force_touch = args.has("touch")
	game.exit_to_menu.connect(func(): call_deferred("show_menu"))
	game.restart_requested.connect(func(): call_deferred("start_game"))
	add_child(game)

func _snap(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(dir.path_join(name))
	print("saved ", dir.path_join(name))

func _wait(n: int) -> void:
	for i in n: await get_tree().process_frame

func _shots(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	await _wait(40); await _snap(dir, "01_menu.png")
	args["touch"] = "1"
	start_game()
	game.auto_rounds = false
	game.allow_tutorial = false
	await _wait(30)
	game.round = 3
	var pl := game.player
	game.god_mode = true  # screenshot run only: keep the camera alive under slow software rendering
	# 02: intake horde through the west window, hip-fire with blood
	pl.global_position = Vector3(-4, 0.1, 2); pl.yaw = PI / 2 + 0.25; pl.pitch = -0.05
	for id in ["w_west", "w_west", "w_south", "w_west"]: game.spawn_zombie(id)
	await _wait(200)
	for i in 6:
		pl.try_fire(false); await _wait(6)
	await _wait(2)
	await _snap(dir, "02_intake_horde.png")
	# 03: power on, lab with neon perk + catwalk + crate
	game.throw_power(Node3D.new())
	for z in game.zombies.duplicate(): z.queue_free()
	game.zombies.clear()
	game.map.open_door("east")
	pl.global_position = Vector3(12.5, 0.1, 4.5); pl.yaw = -0.9; pl.pitch = 0.08
	game.crate_node.start("nova"); 
	await _wait(240)
	await _snap(dir, "03_lab_power_crate.png")
	# 04: ADS sight picture with the upgraded wonder weapon in the yard
	game.map.open_door("yard")
	pl.loadout.give(Weapons.make("rifle")); pl.apply_reload_perk()
	pl.global_position = Vector3(30, 0.1, 4); pl.yaw = -PI / 2 + 0.25; pl.pitch = 0.0
	game.spawn_zombie("w_yard_s"); game.spawn_zombie("w_yard_n")
	pl.touch.ads = true
	await _wait(220)
	await _snap(dir, "04_yard_ads.png")
	pl.touch.ads = false
	for z in game.zombies.duplicate(): z.queue_free()
	game.zombies.clear()
	# 05: cold storage Overcharge Forge animated
	game.map.open_door("cold")
	pl.global_position = Vector3(18, 0.1, -19.5); pl.yaw = 0.0; pl.pitch = 0.12
	await _wait(90)
	await _snap(dir, "05_forge.png")
	# 06: grenade + round change tint
	pl.global_position = Vector3(-2, 0.1, 4); pl.yaw = PI / 2; pl.pitch = -0.1
	game.spawn_zombie("w_west"); game.spawn_zombie("w_west")
	await _wait(160)
	game.explode(pl, Vector3(-7, 0.5, 4), 4.5, 50)
	game.tint = 1.0; game.hud.round_flash(); game.hud.banner("Round 4", 3.0)
	await _wait(8)
	await _snap(dir, "06_explosion_round.png")
	# 07: power-up drop + active timers on the HUD
	for z in game.zombies.duplicate(): z.queue_free()
	game.zombies.clear()
	pl.global_position = Vector3(-1, 0.1, 4); pl.yaw = PI / 2; pl.pitch = -0.25
	game._spawn_drop("onetouch", Vector3(-4, 0.4, 4))
	game.collect_power("doublepay")
	await _wait(60)
	await _snap(dir, "07_powerup.png")
	# 08: crate rolling / Phantom bust
	pl.global_position = Vector3(12.5, 0.1, 4.5); pl.yaw = -0.9; pl.pitch = 0.08
	game.crate_node.move_after = true; game.crate_node.start("nova"); game.crate_node.t = 0.05
	pl.global_position = game.crate_node.global_position + Vector3(0, 0.1, 3.2); pl.yaw = 0.0; pl.pitch = 0.15
	await _wait(14)
	await _snap(dir, "08_crate.png")
	# 09: last stand
	game.god_mode = false
	pl.global_position = Vector3(-1, 0.1, 4); pl.yaw = PI / 2; pl.pitch = 0.0
	pl.health = 1.0; pl.take_damage(50.0)
	await _wait(6)
	await _snap(dir, "09_last_stand.png")
	get_tree().quit()

## Headless playtest: `godot --headless --fixed-fps 60 -- --sim=10` (bot plays rounds 1..N, prints a report).
func _sim(n: int) -> void:
	await _wait(5)
	start_game()
	await _wait(5)
	if args.has("simround"):   # clip mode: jump in at a busier round
		game.round = int(args["simround"]) - 1; game.intermission = 1.0
		game.player.economy.points = 1500
	var b := BotDriver.new(); b.game = game; b.max_rounds = n
	game.add_child(b)
	if args.has("simquit"):   # movie/clip mode: stop after N seconds of game time
		await get_tree().create_timer(float(args["simquit"]), true, true).timeout
		get_tree().quit()

# ------------------------------------------------------------------ scripted 30 s trailer route
## --clip=<dir>: a directed camera route through the action (run with --fixed-fps 30 --write-movie).
## Horde at the west window (round 6 alarms) -> Mystery Crate -> Overcharge Forge -> power-up.
## Also saves six stills into <dir>. God mode keeps the camera alive; everything else is live gameplay.
var _clip_pl: Player

func _aim_at(p: Vector3, k: float) -> void:
	var v := p - _clip_pl.cam.global_position
	var ty := atan2(-v.x, -v.z); var tp := atan2(v.y, Vector2(v.x, v.z).length())
	_clip_pl.yaw = lerp_angle(_clip_pl.yaw, ty, k); _clip_pl.pitch = lerpf(_clip_pl.pitch, tp, k)

func _nearest_zombie() -> Zombie:
	var best: Zombie = null; var bd := 1e9
	for z in game.zombies:
		if not is_instance_valid(z) or z.state == Zombie.State.DEAD or z.state == Zombie.State.RISE: continue
		var d: float = z.global_position.distance_to(_clip_pl.global_position)
		if d < bd: bd = d; best = z
	return best

## Move the player along a straight line over n frames while looking at [look] (or fighting).
func _glide(to: Vector3, look: Vector3, n: int, fight := false) -> void:
	var from := _clip_pl.global_position
	for i in n:
		var t := smoothstep(0.0, 1.0, float(i + 1) / n)
		_clip_pl.global_position = from.lerp(to, t)
		var z := _nearest_zombie() if fight else null
		if z:
			_aim_at(z.global_position + Vector3.UP * (Zombie.HEAD_Y - 0.05 if not z.crawler else 0.35), 0.16)
			_clip_pl.bot_input.fire = _clip_pl.ammo().rounds > 0 and Engine.get_process_frames() % 2 == 0
			if _clip_pl.ammo().rounds == 0 and not _clip_pl.ammo().reloading(): _clip_pl.reload()
		else:
			_aim_at(look, 0.08)
			_clip_pl.bot_input.fire = false
		await get_tree().process_frame

func _clip(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	args["touch"] = "1"
	start_game()
	game.auto_rounds = false
	game.allow_tutorial = false
	game.god_mode = true
	await _wait(5)
	var pl := game.player; _clip_pl = pl
	pl.bot_input = {mv = Vector2.ZERO, fire = false, ads = false, use = false, sprint = false}
	pl.economy.points = 12000
	pl.loadout.give(Weapons.make("rifle")); pl.apply_reload_perk()
	game.round = 8   # brute round: alarm beacons + painted tally gate
	game.hud.tally_flip(8)
	game.throw_power(Node3D.new())
	game.map.open_door("east"); game.map.open_door("yard")
	# A: brute + sprinters through the west window (0-8 s)
	pl.global_position = Vector3(-3.0, 0.1, 3.2); pl.yaw = PI / 2 + 0.2; pl.pitch = -0.05
	game.spawn_zombie("w_west", "brute")
	for id in ["w_west", "w_south"]: game.spawn_zombie(id, "sprinter")
	game.spawn_zombie("w_west", "walker")
	await _glide(Vector3(-3.0, 0.1, 3.2), Vector3(-10, 1.4, 2), 50)
	for z in game.zombies: if z.window: z.window.bar.damage(999); z.window.refresh()
	await _glide(Vector3(-2.5, 0.1, 3.0), Vector3(-8, 1.4, 2.5), 110)
	await _snap(dir, "01_brute_sprinters.png")
	await _glide(Vector3(-2.0, 0.1, 3.0), Vector3(-7, 1.5, 3.0), 40, true)
	await _glide(Vector3(-1.0, 0.1, 3.4), Vector3(-10, 1.4, 2), 90, true)
	# C: ragdolls - body-shot kills with force (8-12 s)
	for z in game.zombies.duplicate():
		if is_instance_valid(z) and z.state != Zombie.State.DEAD and z.ztype != "brute":
			z.take_damage(z.hp + 1, false, pl, "body", (z.global_position - pl.global_position).normalized() * 9.0)
	await _glide(Vector3(-1.0, 0.1, 3.4), Vector3(-6, 0.4, 2.8), 45)
	await _snap(dir, "02_ragdolls.png")
	await _glide(Vector3(-1.0, 0.1, 3.4), Vector3(-7, 0.4, 2.5), 40, true)
	for z in game.zombies.duplicate():
		if is_instance_valid(z) and z.state != Zombie.State.DEAD: z.take_damage(z.hp + 1, true, pl, "head", Vector3(-6, 0, 0))
	# B: bloater + gas cloud in the yard (12-18 s)
	pl.global_position = Vector3(31, 0.1, 4); pl.yaw = -PI / 2
	game.map.open_door("pump")
	var bl := game.spawn_zombie("w_yard_s", "bloater")
	game.spawn_zombie("w_yard_n", "walker"); game.spawn_zombie("w_yard_n", "walker")
	for z in game.zombies: if z.window: z.window.bar.damage(999); z.window.refresh()
	await _wait(4)
	if is_instance_valid(bl): bl.global_position = Vector3(38, 0.1, 5.5)
	await _glide(Vector3(31.5, 0.1, 4.5), Vector3(38, 1.3, 5.5), 75)
	await _snap(dir, "03_bloater.png")
	await _glide(Vector3(31.5, 0.1, 4.5), Vector3(38, 1.3, 5.5), 40, true)
	if is_instance_valid(bl) and bl.state != Zombie.State.DEAD: bl.take_damage(bl.hp + 1, false, pl, "body", Vector3(4, 0, 0))
	await _glide(Vector3(31.5, 0.1, 4.5), Vector3(38, 1.0, 5.5), 60)
	await _snap(dir, "04_gas_cloud.png")
	# D: explosive kill -> gibs (18-22 s)
	var live := []
	for z in game.zombies: if is_instance_valid(z) and z.state != Zombie.State.DEAD: live.append(z)
	for z in live: z.global_position = Vector3(36 + randf_range(-1, 1), 0.1, -4 + randf_range(-1, 1))
	await _glide(Vector3(31, 0.1, -1), Vector3(36, 1.0, -4), 20)
	game.explode(pl, Vector3(36, 0.4, -4), 5.0, 5000)
	await _glide(Vector3(31.5, 0.1, -1.2), Vector3(36, 0.8, -4), 60)
	# E: Pump Station + Marksman Mist (22-26 s)
	pl.global_position = Vector3(36, 0.1, 8); pl.yaw = PI
	await _glide(Vector3(36, 0.1, 13), Vector3(44, 1.2, 22), 70)
	await _snap(dir, "05_pump_station.png")
	await _glide(Vector3(38, 0.1, 17), Vector3(44.8, 1.3, 22), 40)
	# F: last kill slow-mo + points tick + painted tally (26-30 s)
	var last := game.spawn_zombie("w_pump_e", "sprinter")
	if last: last.global_position = Vector3(42, 0.1, 22)
	await _glide(Vector3(38, 0.1, 18), Vector3(42, 1.4, 22), 25)
	game.to_spawn = 0
	for z in game.zombies.duplicate(): if is_instance_valid(z) and z != last: game.zombies.erase(z); z.queue_free()
	if is_instance_valid(last): last.take_damage(last.hp + 1, true, pl, "head", Vector3(5, 1, 3))
	await _glide(Vector3(38, 0.1, 18), Vector3(42, 0.8, 22), 30)
	await _snap(dir, "06_hud_slowmo_tally.png")
	await _wait(100)
	get_tree().quit()
