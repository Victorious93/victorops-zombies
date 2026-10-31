class_name CueQueue
extends RefCounted
## v7.12 audio priority for big 2D cues so a drop call-out, its stinger and the round sting don't pile up.
## Each cue has a priority; while a higher-or-equal priority cue is playing:
##  - a VOICE cue (announcer) is delayed until the slot is free (never talks over another voice/sting);
##  - any other cue plays now but ducked by DUCK_DB.
enum Prio { STINGER = 1, VOICE = 2, ROUND = 3 }
const DUCK_DB := -9.0
const GAP := 0.15   ## breath between queued voice lines

var active: Array = []   ## [{prio, end}]

func _prune(now: float) -> void:
	active = active.filter(func(a): return a.end > now)

## Returns {delay, db_offset} and books the cue's slot.
func request(prio: int, now: float, dur: float, voice := false) -> Dictionary:
	_prune(now)
	var delay := 0.0
	var db := 0.0
	var block_end := now
	for a in active:
		if a.prio >= prio: block_end = maxf(block_end, a.end)
	if block_end > now:
		if voice: delay = block_end - now + GAP
		else: db = DUCK_DB
	active.append({"prio": prio, "end": now + delay + dur})
	return {"delay": delay, "db_offset": db}
