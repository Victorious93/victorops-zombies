class_name Sfx
extends Node
## Tiny audio helper. All sounds are synthesised by tools/gen_audio.py (original).

var cache := {}
var ambient: AudioStreamPlayer

func stream(sound: String) -> AudioStream:
	if not cache.has(sound):
		cache[sound] = load("res://audio/%s.wav" % sound)
	return cache[sound]

func play(sound: String, volume_db := 0.0, pitch := 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream(sound); p.volume_db = volume_db; p.pitch_scale = pitch
	add_child(p); p.play()
	p.finished.connect(p.queue_free)

func play_at(sound: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = stream(sound); p.volume_db = volume_db; p.pitch_scale = pitch
	p.unit_size = 6.0; p.max_distance = 40.0
	add_child(p); p.global_position = pos; p.play()
	p.finished.connect(p.queue_free)

func start_ambient() -> void:
	var s := stream("ambient") as AudioStreamWAV
	if s:
		s = s.duplicate()
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
	ambient = AudioStreamPlayer.new(); ambient.stream = s; ambient.volume_db = -8.0
	add_child(ambient); ambient.play()
