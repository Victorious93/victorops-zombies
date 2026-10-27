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

func show_menu() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if game: game.queue_free(); game = null
	menu = CanvasLayer.new(); add_child(menu)
	var bg := ColorRect.new(); bg.color = Color(0.03, 0.03, 0.04); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); menu.add_child(bg)
	var box := VBoxContainer.new(); box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER; box.add_theme_constant_override("separation", 14); menu.add_child(box)
	var logo := TextureRect.new(); logo.texture = load(LOGO)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.custom_minimum_size = Vector2(0, 260); box.add_child(logo)
	var pick := HBoxContainer.new(); pick.alignment = BoxContainer.ALIGNMENT_CENTER; pick.add_theme_constant_override("separation", 20)
	box.add_child(pick)
	var desc := Label.new(); desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 22); desc.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	var group := ButtonGroup.new()
	for id in Characters.ALL:
		var b := Button.new(); b.toggle_mode = true; b.button_group = group; b.text = Characters.ALL[id].name
		b.custom_minimum_size = Vector2(280, 64); b.add_theme_font_size_override("font_size", 26)
		b.button_pressed = id == selected
		b.pressed.connect(func(): selected = id; desc.text = Characters.ALL[id].tagline)
		pick.add_child(b)
	desc.text = Characters.ALL[selected].tagline
	box.add_child(desc)
	var play := Button.new(); play.text = "SURVIVE"; play.custom_minimum_size = Vector2(360, 80)
	play.add_theme_font_size_override("font_size", 36); play.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	play.pressed.connect(start_game); box.add_child(play)
	var note := Label.new(); note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.text = "Solo · Co-op (LAN) coming next · WASD/mouse or touch"
	note.add_theme_font_size_override("font_size", 18); note.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	box.add_child(note)

func start_game() -> void:
	if menu: menu.queue_free(); menu = null
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
	await _wait(20); await _snap(dir, "01_menu.png")
	args["touch"] = "1"
	start_game()
	game.auto_rounds = false
	await _wait(30)
	game.round = 3
	var pl := game.player
	pl.yaw = PI * 0.75; pl.pitch = -0.05
	for id in ["w_west", "w_south", "w_west"]: game.spawn_zombie(id)
	await _wait(150)
	await _snap(dir, "02_intake_horde.png")
	game.throw_power(Node3D.new())
	pl.global_position = Vector3(14, 0.1, -3); pl.yaw = 0.3
	game.map.open_door("east")
	await _wait(60)
	await _snap(dir, "03_lab_crate_power.png")
	pl.global_position = Vector3(0, 0.1, 4); pl.yaw = PI; pl.pitch = 0
	pl.ads = true
	await _wait(40); await _snap(dir, "04_ads_window.png")
	get_tree().quit()
