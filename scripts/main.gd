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
	elif args.has("probe"): _probe(args["probe"])
	elif args.has("clip"): _clip(args["clip"])
	elif args.has("views"): _views(args["views"])
	elif args.has("hud"): _hud(args["hud"], args.get("prefix", ""))

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

## Touch HUD captures at 16:9, 19.5:9 and 20:9 (simulated notch + gesture bar on the tall phones),
## near a wall-buy so the contextual USE button shows, plus the Settings > Controls editor.
func _hud(dir: String, prefix: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	args["touch"] = "1"
	start_game()
	game.auto_rounds = false; game.allow_tutorial = false; game.god_mode = true
	var pl := game.player
	pl.bot_input = {"mv": Vector2.ZERO, "fire": false, "ads": false, "use": false, "sprint": false}
	await _wait(40)
	pl.bot_input = null
	pl.global_position = Vector3(-6, 0.1, 6)   # pre-power on purpose: proves the v7.1 lighting fix; pl.yaw = -2.4; pl.pitch = -0.05; pl.velocity = Vector3.ZERO
	for a in [["16x9", Vector2i(1456, 819), 0.0, 0.0], ["19_5x9", Vector2i(1774, 819), 0.052, 0.054], ["20x9", Vector2i(1820, 819), 0.046, 0.044]]:
		get_window().size = a[1]
		await _wait(12)
		var t = game.touch
		if "safe_override" in t:
			var sz: Vector2 = t.size
			t.safe_override = Rect2(Vector2(sz.x * a[2], 0), Vector2(sz.x * (1.0 - 2.0 * a[2]), sz.y * (1.0 - a[3])))
			t.set_use_available(true); t._layout()
		await _wait(8)
		await _snap(dir, "%shud_%s.png" % [prefix, a[0]])
	if ClassDB.class_exists("ControlsEditor") or ResourceLoader.exists("res://scripts/game/controls_editor.gd"):
		var ce = load("res://scripts/game/controls_editor.gd").open(game.hud, game.settings, func(): pass)
		await _wait(10)
		ce.preview.safe_override = game.touch.safe_override; ce.preview._layout()
		await _wait(4)
		await _snap(dir, "%scontrols_editor_20x9.png" % prefix)
	get_tree().quit()

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
	game.round = 3
	game.hud.tally_flip(3)
	game.throw_power(Node3D.new())
	# A: window tear-down + climb-in (0-10 s): walkers rip planks one by one, then haul over the sill
	var win: WindowBarricade = game.map.windows["w_west"]
	var inward := (win.inside_point - win.outside_point); inward.y = 0; inward = inward.normalized()
	var watch := win.inside_point + inward * 6.0; watch.y = 0.1
	pl.global_position = watch; pl.yaw = atan2(inward.x, inward.z); pl.pitch = 0.0
	win.bar.damage(win.bar.plank_hp * maxi(win.bar.planks() - 4, 0)); win.refresh()
	var walkers := []
	for k in 3:
		var z := game.spawn_zombie("w_west", "walker")
		if z:
			z.drop_in = false; z.global_position = win.outside_point + Vector3(randf_range(-0.5, 0.5), 0, 0) - inward * (0.3 + k * 0.9)
			z.state = Zombie.State.TO_WINDOW; z.gait = Gait.Tier.WALK; z.runner = false; walkers.append(z)
	await _wait(1)
	for k in walkers.size():
		var z: Zombie = walkers[k]
		if is_instance_valid(z): z.model.position.y = 0.0; z.model.rotation.x = 0.0; z.global_position = win.outside_point + Vector3(randf_range(-0.4, 0.4), 0, 0) - inward * (0.2 + k * 0.7)
	await _glide(watch, win.center() + Vector3.UP * 0.2, 120)
	await _snap(dir, "01_window_teardown.png")
	await _glide(watch - inward * 0.1, win.center(), 110)
	await _snap(dir, "02_climb_in.png")
	await _glide(watch - inward * 0.1, win.center() - Vector3.UP * 0.3, 60)
	# B: ADS zoom, recoil kick, muzzle flash, hitmarkers, impact sounds (10-17 s)
	pl.bot_input.ads = true
	await _glide(watch - inward * 0.2, win.center(), 25, true)
	await _snap(dir, "03_ads_recoil_muzzle_flash.png")
	await _glide(watch - inward * 0.3, win.center(), 35, true)
	await _snap(dir, "04_hitmarker.png")
	await _glide(watch - inward * 0.4, win.center(), 120, true)
	pl.bot_input.ads = false; pl.bot_input.fire = false
	for z in game.zombies.duplicate():
		if is_instance_valid(z) and z.state != Zombie.State.DEAD: z.take_damage(z.hp + 1, true, pl, "head", inward * 5.0)
	# C: buy a door with points (17-23 s): judder, slide, dust, rumble
	var door: Node3D = game.map.doors["north"]
	var dp := door.global_position; var back := Vector3(0.6, 0, 0.4) - Vector3(dp.x, 0, dp.z)
	back = back.normalized() if back.length() > 0.1 else Vector3(0, 0, 1)
	pl.global_position = Vector3(dp.x, 0.1, dp.z) + back * 3.0
	await _glide(Vector3(dp.x, 0.1, dp.z) + back * 2.6, dp + Vector3.UP * 1.3, 40)
	await _snap(dir, "05_door_price.png")
	game.buy_door(pl, "north")
	await _glide(Vector3(dp.x, 0.1, dp.z) + back * 2.4, dp + Vector3.UP * 1.0, 40)
	await _snap(dir, "06_door_opening.png")
	await _glide(Vector3(dp.x, 0.1, dp.z) + back * 1.5, dp + Vector3.UP * 1.2 - back * 4.0, 90)
	# D: atmospheric round sting + touch HUD (23-30 s)
	game.round = 4
	game.hud.banner("Round 4", 3.0); game.hud.round_flash(); game.hud.tally_flip(4)
	game.sfx.play("round_start_v6", -1); game.duck_music(5.0); pl.add_trauma(0.45)
	await _glide(Vector3(dp.x, 0.1, dp.z) - back * 1.0, dp + Vector3.UP * 1.2 - back * 8.0, 45)
	await _snap(dir, "07_round_sting_touch_hud.png")
	await _wait(60)
	# v7.2 extension (~19 s): reload + weapon switch, then a tour of the per-area mood lighting.
	var cpl = game.player
	cpl.reload(); await _wait(40); await _snap(dir, "08_reload.png")
	await _wait(30); cpl.swap(); await _wait(12); await _snap(dir, "09_weapon_switch.png")
	await _wait(30)
	await _glide(Vector3(-6, 0.1, -12.5), Vector3(-9, 1.2, -15), 140)
	await _snap(dir, "10_generator_mood.png")
	await _glide(Vector3(12, 0.1, 8), Vector3(16, 1.2, 4), 140)
	await _snap(dir, "11_lab_mood.png")
	await _glide(Vector3(32, 0.1, 14), Vector3(30, 1.0, 18), 120, true)
	await _snap(dir, "12_pump_mood.png")
	await _glide(Vector3(36, 0.1, -4), Vector3(40, 1.2, -10), 90)
	await _snap(dir, "13_yard_decals.png")
	await _wait(30)
	# v7.7 (~12 s): a legless zombie_b crawler hauling itself under a lamp's light pool, then a window repair.
	pl.global_position = Vector3(0, 0.1, 5.5)
	var cz: Zombie = game.spawn_zombie("", "walker")
	while cz.variant != "zombie_b": game.zombies.erase(cz); cz.free(); cz = game.spawn_zombie("", "walker")
	cz.drop_in = false; cz.global_position = Vector3(0.4, 0.05, -2.5); cz.state = Zombie.State.CHASE
	cz.model.position.y = 0.0; cz.model.rotation.x = 0.0; cz.make_crawler()
	await _glide(Vector3(0, 0.1, 5.5), Vector3(0.4, 0.2, -1.5), 60)
	await _snap(dir, "14_crawler_light_pool.png")
	await _glide(Vector3(0, 0.1, 5.8), cz.global_position + Vector3.UP * 0.2, 90)
	await _snap(dir, "15_crawler_closer.png")
	await _glide(Vector3(0, 0.1, 6.0), cz.global_position + Vector3.UP * 0.2, 60)
	if is_instance_valid(cz) and cz.state != Zombie.State.DEAD: cz.take_damage(cz.hp + 1, true, pl, "head", Vector3.BACK * 3.0)
	var rw: WindowBarricade = game.map.windows["w_west"]
	var rin := (rw.inside_point - rw.outside_point); rin.y = 0; rin = rin.normalized()
	rw.bar.damage(rw.bar.plank_hp * rw.bar.planks()); rw.refresh()
	pl.global_position = rw.inside_point + rin * 0.6; pl.global_position.y = 0.1
	await _glide(pl.global_position, rw.center() + Vector3.UP * 0.1, 20)
	for k in rw.bar.max_planks:
		game.repair_window(pl, rw)
		await _wait(4)
		if k == 2: await _snap(dir, "16_repair_slam.png")
		await _glide(pl.global_position, rw.center() + Vector3.UP * 0.1, 18)
	await _snap(dir, "17_repaired.png")
	await _wait(20)
	# v7.8 (~12 s): Mystery Crate roll -> beam, pulses, gold reveal; then ADS under a lamp (grip + light pool)
	var cn: CrateNode = game.crate_node
	var cfront := cn.global_position + cn.global_basis.z * 3.4; cfront.y = 0.1
	pl.global_position = cfront
	await _glide(cfront, cn.global_position + Vector3.UP * 1.2, 15)
	cn.move_after = false; cn.start("lmg")
	await _glide(cfront, cn.global_position + Vector3.UP * 1.4, 70)
	await _snap(dir, "18_crate_rolling_beam.png")
	await _glide(cfront, cn.global_position + Vector3.UP * 1.3, int(CrateNode.ROLL_TIME * 30) - 70 + 6)
	await _snap(dir, "19_crate_reveal_flash.png")
	await _glide(cfront, cn.global_position + Vector3.UP * 1.3, 50)
	cn.close()
	pl.global_position = Vector3(0, 0.1, 4.5)
	await _glide(Vector3(0, 0.1, 4.5), Vector3(0, 0.0, -1.5), 40)
	await _snap(dir, "20_light_pool.png")
	pl.bot_input.ads = true
	await _glide(Vector3(0, 0.1, 4.3), Vector3(0, 0.9, -6), 45)
	await _snap(dir, "21_ads_support_grip.png")
	pl.bot_input.ads = false
	await _wait(20)
	# v7.9 (~8 s): perk drink at Iron Hide Tonic, then the power-on wave from the lever in the dark
	pl.global_position = Vector3(-6.2, 0.1, -14.0)
	await _glide(pl.global_position, Vector3(-8.8, 1.3, -14.0), 15)
	pl.perks.erase("ironhide"); game.buy_perk(pl, "ironhide")
	await _glide(pl.global_position, Vector3(-8.8, 1.3, -14.0), 14)
	await _snap(dir, "22_perk_drink_raise.png")
	await _glide(pl.global_position, Vector3(-8.8, 1.3, -14.0), 12)
	await _snap(dir, "23_perk_drink_tip.png")
	await _glide(pl.global_position, Vector3(-8.8, 1.3, -14.0), 40)
	if game.map.find_child("Lever", true, false): game.map.find_child("Lever", true, false).rotation.x = 0.6
	game.facility.power_on = false; game.map.set_power(false); game.env.ambient_light_energy = 0.25
	var lever: Node3D = game.map.find_child("Lever", true, false)
	var lp := lever.global_position if lever else Vector3(-6, 1.5, -12.5)
	pl.global_position = Vector3(lp.x + 3.0, 0.1, lp.z + 6.0)
	await _glide(pl.global_position, lp + Vector3(0, -0.4, 0), 30)
	game.throw_power(lever if lever else Node3D.new())
	await _wait(3)
	await _snap(dir, "24_power_flash.png")
	pl.global_position = Vector3(0, 0.1, 7.0)   # intake: two ceiling lamps in a line catch the wave
	await _glide(pl.global_position, Vector3(0, 2.6, -18), 6)
	await _snap(dir, "25_power_wave.png")
	await _glide(pl.global_position, Vector3(0, 2.4, -18), 60)
	await _snap(dir, "26_power_on.png")
	await _wait(20)
	# v7.10: a zombie claws up out of the floor in front of the camera
	for z0 in game.zombies.duplicate(): if is_instance_valid(z0): z0.queue_free()
	game.zombies.clear()
	pl.global_position = Vector3(0, 0.1, 6.0); await _glide(pl.global_position, Vector3(0, 0.6, 2.5), 12)
	var rz: Zombie = game.spawn_zombie("", "walker")
	rz.drop_in = false; rz.state = Zombie.State.RISE; rz.t = Zombie.RISE_TIME; rz.model.position.y = -1.8
	rz.global_position = Vector3(0, 0.05, 2.5); rz.rotation.y = 0.0
	game.fx.dirt_burst(rz.global_position)
	await _wait(20)
	await _snap(dir, "27_ground_rise.png")
	await _wait(40)
	rz.set_physics_process(false); rz.state = Zombie.State.CHASE; rz.model.position.y = 0.0; rz.model.rotation.x = 0.0
	await _glide(pl.global_position, rz.global_position + Vector3(0, 1.6, 0), 10)
	# headshot: the head bone whips back on top of the animation
	rz.take_damage(1, true, pl, "head", Vector3(0, 0, -6))
	await _wait(3)
	await _snap(dir, "28_head_snap.png")
	await _wait(30)
	rz.take_damage(1, false, pl, "body", Vector3(4, 0, -4))
	await _wait(4)
	await _snap(dir, "29_body_flinch.png")
	await _wait(25)
	# round change: blood-red number slams into the centre with the new sting
	game.hud.round_flash(); game.hud.tally_flip(game.round + 1); game.hud.round_slam(game.round + 1)
	game.sfx.play("round_sting_v10", -2); pl.add_trauma(0.45)
	await _wait(5)
	await _snap(dir, "30_round_slam.png")
	await _wait(25)
	await _snap(dir, "31_round_hold.png")
	await _wait(60)
	# v7.11: a blast tears the legs off (crawler), then a drop grab flash, then the last-zombie cue
	if is_instance_valid(rz): rz.queue_free()
	game.zombies.clear()
	var gz: Zombie = game.spawn_zombie("", "walker")
	gz.state = Zombie.State.CHASE; gz.model.position.y = 0.0; gz.model.rotation.x = 0.0
	gz.global_position = Vector3(0, 0.05, 3.0); gz.set_physics_process(false); gz.max_hp = 100000; gz.hp = 100000
	await _glide(pl.global_position, gz.global_position + Vector3(0, 1.0, 0), 10)
	gz.explosive_hit = true; gz.take_damage(500, false, pl, "body", Vector3(0, 2, -3)); gz.explosive_hit = false
	game.fx.explosion(gz.global_position + Vector3(0, 0.3, 0.4), 1.5)
	await _wait(6)
	await _snap(dir, "32_blast_gib.png")
	await _wait(40)
	await _snap(dir, "33_gib_crawler.png")
	game.collect_power("doublepay")
	await _wait(4)
	await _snap(dir, "34_pickup_flash.png")
	await _wait(60)
	game.to_spawn = 0; game.last_cue_round = -1
	game._last_zombie_cue(gz)
	await _wait(30)
	await _snap(dir, "35_last_zombie.png")
	await _wait(30)
	# v7.12: points pop beside the crosshair (hit, kill, headshot kill)
	game.hud.points_pop(10); await _wait(4); game.hud.points_pop(50); await _wait(4); game.hud.points_pop(100)
	await _wait(5)
	await _snap(dir, "36_points_pops.png")
	await _wait(30)
	# v7.12: a late-round walker that has hunted long enough breaks into a leaning sprint
	if is_instance_valid(gz): gz.queue_free()
	game.zombies.clear()
	pl.global_position = Vector3(0, 0.1, 7.0)
	var sz: Zombie = game.spawn_zombie("", "walker")
	sz.state = Zombie.State.CHASE; sz.model.position.y = 0.0; sz.global_position = Vector3(0, 0.05, -6.0)
	sz.spawn_round = 12; sz.gait = Gait.Tier.WALK; sz.chase_time = 60.0; sz.max_hp = 100000; sz.hp = 100000
	await _glide(pl.global_position, Vector3(0, 1.0, -6.0), 8)
	await _wait(20)
	await _snap(dir, "37_sprint_ramp.png")
	await _wait(25)
	await _snap(dir, "38_sprint_close.png")
	await _wait(20)
	# v7.12: the Sealed Annex - hint, shoot the cracked panel, reveal, Vault Plating, Rift Bench, Hive Reaper
	if is_instance_valid(sz): sz.queue_free()
	game.zombies.clear()
	var cp := HiddenRoom.CRACK_POS
	pl.global_position = Vector3(cp.x + 0.5, 0.1, -21.5)
	for i in 30: _aim_at(cp, 0.3); await get_tree().process_frame
	await _snap(dir, "39_crack_hint.png")
	for i in 50:
		_aim_at(cp + Vector3(sin(i * 0.4) * 0.3, cos(i * 0.3) * 0.3, 0), 0.3)
		pl.bot_input.fire = i % 2 == 0
		if pl.ammo().rounds == 0 and not pl.ammo().reloading(): pl.reload()
		await get_tree().process_frame
	pl.bot_input.fire = false
	if not game.annex.revealed: game.crack_hit(pl, 99999.0, cp)
	await _wait(10)
	await _snap(dir, "40_reveal_dust.png")
	await _wait(50)
	await _glide(Vector3(-6.0, 0.1, -27.0), Vector3(-6.0, 1.3, -32.2), 50)
	await _wait(15)
	await _snap(dir, "41_hidden_room.png")
	pl.economy.points += 40000
	await _glide(HiddenRoom.VAULT_POS + Vector3(1.6, 0.1, 0.4), HiddenRoom.VAULT_POS + Vector3(0, 1.2, 0), 30)
	game.use_vault(pl); await _wait(20); game.use_vault(pl); await _wait(30)
	pl.armor.value -= 140.0; game.sfx.play("armor_hit_v12", -4)
	await _wait(10)
	await _snap(dir, "42_armor_hud.png")
	await _glide(HiddenRoom.RIFT_POS + Vector3(-1.6, 0.1, 0.3), HiddenRoom.RIFT_POS + Vector3(0, 1.0, 0), 30)
	await _wait(10)
	await _snap(dir, "43_rift_bench.png")
	await _glide(HiddenRoom.PEDESTAL_POS + Vector3(0, 0.1, 1.8), HiddenRoom.PEDESTAL_POS + Vector3(0, 1.4, 0), 30)
	await _wait(10)
	await _snap(dir, "44_reaper_pedestal.png")
	game.buy_reaper(pl)
	await _wait(50)
	await _snap(dir, "45_reaper_in_hand.png")
	# out into the generator room and let it spin up on a pack
	await _glide(Vector3(-6.0, 0.1, -24.0), Vector3(-6.0, 1.3, -14.0), 30)
	for i in 5:
		var reaper_z: Zombie = game.spawn_zombie("", "walker")
		reaper_z.state = Zombie.State.CHASE; reaper_z.model.position.y = 0.0; reaper_z.global_position = Vector3(-8.0 + i * 1.2, 0.05, -12.0 - (i % 2) * 1.5)
	await _glide(Vector3(-6.0, 0.1, -23.5), Vector3(-6.0, 1.3, -14.0), 40, true)
	await _snap(dir, "46_reaper_firing.png")
	await _glide(Vector3(-6.0, 0.1, -23.0), Vector3(-6.0, 1.3, -14.0), 60, true)
	await _snap(dir, "47_reaper_heat.png")
	pl.bot_input.fire = false
	pl.armor.value = 5.0; game.god_mode = false
	if pl.has_method("take_damage"): pl.take_damage(30.0, pl.global_position + Vector3(0, 0, 2))
	game.god_mode = true
	await _wait(20)
	await _snap(dir, "48_armor_break.png")
	await _wait(20)
	get_tree().quit()

## Fixed before/after viewpoints: <dir>/scenery/NN_*.png and <dir>/viewmodel/<weapon>_{hip,ads}.png.
const VIEWS := [
	["01_intake", Vector3(-6, 0.1, 6), -2.4, -0.05],
	["02_intake_north", Vector3(0, 0.1, 6), 0.0, 0.02],
	["03_generator", Vector3(-6, 0.1, -12.5), -2.5, 0.0],
	["04_lab", Vector3(12, 0.1, 8), -0.7, 0.0],
	["05_yard", Vector3(30, 0.1, 0), -1.9, 0.02],
	["06_pump", Vector3(32, 0.1, 14), 2.6, 0.05],
	["07_ironhide_close", Vector3(-7.0, 0.1, -14.0), PI / 2, 0.1],
]
func _views(dir: String) -> void:
	var sd := dir.path_join("scenery"); var vd := dir.path_join("viewmodel"); var zd := dir.path_join("zombies")
	DirAccess.make_dir_recursive_absolute(zd)
	DirAccess.make_dir_recursive_absolute(sd); DirAccess.make_dir_recursive_absolute(vd)
	start_game()
	game.auto_rounds = false; game.allow_tutorial = false; game.god_mode = true
	await _wait(30)
	game.throw_power(Node3D.new())
	for d in ["north", "east", "cold", "yard"]: game.map.open_door(d)
	var pl := game.player
	pl.bot_input = {"mv": Vector2.ZERO, "fire": false, "ads": false, "use": false, "sprint": false}
	await _wait(60)
	_debug_toggles(OS.get_environment("VOZ_DBG"))
	var only := OS.get_environment("VOZ_VIEWS")   # optional: "scenery", "zombies", "viewmodel" (comma list)
	var want := func(ph: String) -> bool: return only == "" or ph in only
	var vonly := OS.get_environment("VOZ_VIEW_ONLY")
	for v in (VIEWS if want.call("scenery") else []):
		if vonly != "" and not v[0].begins_with(vonly): continue
		pl.global_position = v[1]; pl.yaw = v[2]; pl.pitch = v[3]; pl.velocity = Vector3.ZERO
		await _wait(45)
		await _snap(sd, v[0] + ".png")
	# zombies: close-up of each type, then a group line-up (intake, facing north)
	pl.global_position = Vector3(0, 0.1, 0.5); pl.yaw = PI; pl.pitch = -0.05   # under the intake lamp, facing south: lit from the front, wall well behind
	for ty in (["walker", "sprinter", "bloater", "brute", "warden", "group", "outfits", "outfits_b"] if want.call("zombies") else []):
		if vonly.begins_with("outfits") and not ty.begins_with("outfits"): continue
		var want_v := "zombie_b" if ty == "outfits_b" else "zombie_a"
		var list := ["walker", "sprinter", "bloater", "brute", "sprinter"] if ty == "group" else (["walker", "walker", "walker", "walker"] if ty.begins_with("outfits") else [ty])
		var zs := []
		for i in list.size():
			var z: Zombie = game.spawn_zombie("", list[i])
			while ty.begins_with("outfits") and z.variant != want_v:   # one line-up per body (fits are per variant)
				game.zombies.erase(z); z.free(); z = game.spawn_zombie("", list[i])
			var x := (i - (list.size() - 1) / 2.0) * 1.6
			z.state = Zombie.State.CHASE; z.model.position.y = 0.0; z.model.rotation.x = 0.0
			z.global_position = Vector3(x, 0.05, 0.5 + (2.8 if ty != "group" else 4.6) + absf(x) * 0.3 + (1.2 if ty == "warden" else 0.0))
			z.set_physics_process(false)   # hold the pose for the portrait: no chasing into the lens
			var d := pl.global_position - z.global_position; z.rotation.y = atan2(-d.x, -d.z)
			z.model.rotation.y = PI; z._locomotion()
			if z.zpose: z.zpose.reach_target = 1.0 if not z.runner else 0.7
			if ty.begins_with("outfits"):   # line-up: worker, lab coat, guard, and a legless crawler
				z.set_outfit(["worker", "labcoat", "guard", "rags"][i])
				if i == 3: z.make_crawler(); z._locomotion()
			zs.append(z)
		await _wait(25)
		await _snap(zd, ("%s_closeup.png" % ty) if not ty in ["group", "outfits", "outfits_b"] else ty + ".png")
		for z in zs:
			if is_instance_valid(z): z.queue_free()
		game.zombies.clear(); await _wait(2)
	pl.global_position = Vector3(0, 0.1, 3); pl.yaw = 0.0; pl.pitch = 0.0
	for id in (Weapons.ALL_IDS if want.call("viewmodel") else []):
		if vonly.begins_with("vm:") and not id in vonly.substr(3).split(","): continue   # VOZ_VIEW_ONLY=vm:rifle,smg
		pl.loadout.give(Weapons.make(id)); pl.apply_reload_perk()
		await _wait(50)
		await _snap(vd, id + "_hip.png")
		pl.bot_input.ads = true
		await _wait(40)
		await _snap(vd, id + "_ads.png")
		pl.bot_input.ads = false
	get_tree().quit()

## Debug probe: pre-power look, then wrist-offset variants on the sidearm (VOZ_PROBE_OFFS="x,y,z;x,y,z").
func _probe(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	start_game()
	game.auto_rounds = false; game.allow_tutorial = false; game.god_mode = true
	var pl := game.player
	pl.bot_input = {"mv": Vector2.ZERO, "fire": false, "ads": false, "use": false, "sprint": false}
	await _wait(30)
	pl.global_position = Vector3(-6, 0.1, 6); pl.yaw = -2.4; pl.pitch = -0.05; pl.velocity = Vector3.ZERO
	await _wait(10); await _snap(dir, "a_prepower.png")
	game.throw_power(Node3D.new())
	pl.global_position = Vector3(0, 0.1, 3); pl.yaw = 0.0; pl.pitch = 0.0
	var ids := OS.get_environment("VOZ_PROBE_IDS").split(",", false)
	if ids.is_empty(): ids = PackedStringArray(["sidearm"])
	var offs := OS.get_environment("VOZ_PROBE_OFFS").split(";", false)
	for id in ids:
		pl.loadout.give(Weapons.make(id)); await _wait(30)
		var k := 0
		for o in offs:
			var v := o.split_floats(",")
			var b := Basis.from_euler(Vector3(v[0], v[1], v[2]))
			pl.fps_arms.hands.wrist_offset = [b, Basis.from_euler(Vector3(v[0], -v[1], -v[2]))]
			await _wait(6); await _snap(dir, "%s_%d.png" % [id, k]); k += 1
			var fa = pl.fps_arms; var sk: Skeleton3D = fa.skel; var cam: Node3D = fa.get_parent()
			for nm in ["bicep.l", "forearm.l", "wrist.l", "bicep.r", "wrist.r"]:
				var gp := sk.global_transform * sk.get_bone_global_pose(sk.find_bone(nm))
				print("PB ", id, " ", nm, " ", cam.to_local(gp.origin))
			print("PB ", id, " tl ", cam.to_local(fa.target_l.global_position), " tr ", cam.to_local(fa.target_r.global_position))
		if offs.is_empty(): await _snap(dir, id + "_hip.png")
	get_tree().quit()

## Render bisect switches for capture debugging (VOZ_DBG="noshadow,noglow,nofog,noflash,nobounce,nodust").
func _debug_toggles(t: String) -> void:
	if t == "": return
	var env: Environment = game.env
	if "noglow" in t: env.glow_enabled = false
	if "nofog" in t: env.fog_enabled = false
	if "noshadow" in t:
		for l in game.map.shadow_lights: if is_instance_valid(l): l.shadow_enabled = false
	if "noflash" in t and game.player.flashlight: game.player.flashlight.visible = false
	if "nobounce" in t:
		for l in game.map.bounce_lights: l.visible = false
	if "nodust" in t:
		for d in game.map.dust: d.visible = false
	if "bakedyn" in t:
		for l in game.map.bounce_lights: l.light_bake_mode = Light3D.BAKE_DYNAMIC
	if "att1" in t:
		for l in game.map.bounce_lights: l.omni_attenuation = 1.0
	if "spec" in t:
		for l in game.map.bounce_lights: l.light_specular = 0.5
	if "nofsh" in t: game.player.flashlight.shadow_enabled = false
	if "noomsh" in t:
		for l in game.map.shadow_lights: if l is OmniLight3D: l.shadow_enabled = false
	if "ovl0" in t: game.player.vm_overlay.vp.positional_shadow_atlas_size = 0
	if "ovl4" in t: game.player.vm_overlay.vp.positional_shadow_atlas_size = 4096
	if "ovloff" in t: game.player.vm_overlay.vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if "fbias" in t: game.player.flashlight.shadow_bias = 0.1; game.player.flashlight.shadow_normal_bias = 1.0
	if "nomoon" in t: game.map.moon_light.visible = false
	if "count" in t:
		var c := Vector3(-6, 1.5, -12.5); var n := 0
		for l in get_tree().root.find_children("*", "Light3D", true, false):
			if l is OmniLight3D and l.is_visible_in_tree() and l.global_position.distance_to(c) < l.omni_range + 4: n += 1; print("LIGHT ", l.get_path(), " ", l.global_position, " r=", l.omni_range, " sh=", l.shadow_enabled)
		print("LIGHTCOUNT ", n)
	print("VOZ_DBG ", t)
