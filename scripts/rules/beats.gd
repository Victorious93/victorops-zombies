class_name Beats
## v7.12 in-round music: three original synthesised hip-hop/trap loops (tools/gen_beats_v12.py).
## A new beat every ROUNDS_PER rounds, cycling grave_shift -> static_ward -> low_tide.

const IDS := ["beat_grave_shift", "beat_static_ward", "beat_low_tide"]
const BPM := {"beat_grave_shift": 88, "beat_static_ward": 92, "beat_low_tide": 86}
const BARS := 16
const ROUNDS_PER := 2
const VOLUME_DB := -3.0   ## under the base music level so SFX stay on top
const FADE := 1.5

static func for_round(r: int) -> String:
	return IDS[(maxi(r, 1) - 1) / ROUNDS_PER % IDS.size()]

## Exact loop length: whole bars of 4/4.
static func loop_seconds(id: String) -> float:
	return BARS * 4 * 60.0 / float(BPM[id])

static func load_loop(id: String) -> AudioStream:
	var s = load("res://audio/%s.ogg" % id)
	if s is AudioStreamOggVorbis:
		s = s.duplicate(); s.loop = true
	return s
