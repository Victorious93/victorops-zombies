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
	var note := Label.new(); note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.text = "Solo · Co-op coming next · WASD/mouse, V knife, G grenade, Q ability · or touch"
	note.add_theme_font_size_override("font_size", 18); note.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
	box.add_child(note)

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
	await _wait(30)
	game.round = 3
	var pl := game.player
	pl.max_health = 1e9; pl.health = 1e9  # screenshot run only: keep the camera alive under slow software rendering
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
	get_tree().quit()
