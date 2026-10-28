class_name Sfx
extends Node
## Tiny audio helper. All sounds are synthesised by tools/gen_audio.py (original).

var cache := {}
var ambient: AudioStreamPlayer

func stream(sound: String) -> AudioStream:
	if not cache.has(sound):
		cache[sound] = load("res://audio/%s.wav" % sound)
	return cache[sound]

const MAX_VOICES := 4      ## per sound: a horde or an LMG burst no longer stacks into clipping
var voices := {}           ## sound -> live player count

static func ensure_limiter() -> void:
	## A hard limiter on Master keeps big moments (explosions + horde + music) from distorting on phones.
	for i in AudioServer.get_bus_effect_count(0):
		if AudioServer.get_bus_effect(0, i) is AudioEffectHardLimiter: return
	var lim := AudioEffectHardLimiter.new(); lim.ceiling_db = -0.5; lim.pre_gain_db = 0.0
	AudioServer.add_bus_effect(0, lim)

func _ready() -> void: ensure_limiter()

func _claim(sound: String) -> bool:
	if int(voices.get(sound, 0)) >= MAX_VOICES: return false
	voices[sound] = int(voices.get(sound, 0)) + 1
	return true

func _release(sound: String) -> void: voices[sound] = maxi(0, int(voices.get(sound, 0)) - 1)

## Small random pitch spread so repeated shots/groans don't phase into one buzzy tone.
static func vary(pitch: float, sound: String) -> float:
	return pitch if sound in ["music", "ambient"] else pitch * randf_range(0.96, 1.04)

func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	if not _claim(sound): return
	pitch = vary(pitch, sound)
	var p := AudioStreamPlayer.new()
	p.stream = stream(sound); p.volume_db = volume_db; p.pitch_scale = pitch
	add_child(p); p.play()
	p.finished.connect(func(): _release(sound); p.queue_free())

func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if not _claim(sound): return
	pitch = vary(pitch, sound)
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(sound); p.volume_db = volume_db; p.pitch_scale = pitch
	p.unit_size = 6.0; p.max_distance = 40.0
	add_child(p); p.global_position = pos; p.play()
	p.finished.connect(func(): _release(sound); p.queue_free())

func start_ambient() -> void:
	var s := stream("ambient") as AudioStreamWAV
	if s:
		s = s.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	ambient = AudioStreamPlayer.new(); ambient.stream = s; ambient.volume_db = -8.0
	add_child(ambient); ambient.play()

## v7.3: per-area ambient beds, crossfaded by the player's position (original synthesised loops).
const AREA_BEDS := [
	[Rect2(-9, -25, 18, 14), "bed_generator"],
	[Rect2(11, -9, 14, 18), "bed_lab"],
	[Rect2(11, -25, 14, 14), "bed_damp"],
	[Rect2(27, 11, 18, 18), "bed_damp"],
	[Rect2(27, -15, 18, 24), "bed_wind"],
]
var beds := {}
static func bed_for(pos: Vector3) -> String:
	for b in AREA_BEDS:
		if (b[0] as Rect2).grow(1.0).has_point(Vector2(pos.x, pos.z)): return b[1]
	return ""
func update_beds(pos: Vector3, dt: float) -> void:
	var want := bed_for(pos)
	if want != "" and not beds.has(want):
		var s := stream(want) as AudioStreamWAV
		if s == null: return
		s = s.duplicate(); s.loop_mode = AudioStreamWAV.LOOP_FORWARD; s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
		var p := AudioStreamPlayer.new(); p.stream = s; p.volume_db = -60.0
		add_child(p); p.play(); beds[want] = p
	for k in beds:
		var p: AudioStreamPlayer = beds[k]
		var target := -10.0 if k == want else -60.0
		p.volume_db = move_toward(p.volume_db, target, dt * 25.0)
