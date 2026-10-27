class_name ProgressWatch
extends RefCounted
## Stuck detector for zombie pathing. Feed it the remaining distance to the current goal each tick.
## No real progress (best distance not improved by PROGRESS m) for SIDESTEP s -> "sidestep" (re-path via a
## random nearby point); still none after RESPAWN s -> "respawn" (re-enter from the nearest window).
## Works whether the zombie is pinned against a wall, jittering in place or orbiting a corner.

const PROGRESS := 0.75
const SIDESTEP := 2.5
const RESPAWN := 6.0

var best := INF
var since := 0.0
var sidestepped := false

func reset() -> void:
	best = INF; since = 0.0; sidestepped = false

func update(dist: float, dt: float) -> String:
	if dist < best - PROGRESS:
		best = dist; since = 0.0; sidestepped = false
		return ""
	if best == INF: best = dist
	since += dt
	if since >= RESPAWN:
		reset(); return "respawn"
	if since >= SIDESTEP and not sidestepped:
		sidestepped = true; return "sidestep"
	return ""
