class_name Tutorial
extends RefCounted
## First-time onboarding (~30 s, skippable): move, shoot, rebuild a barricade, buy a wall gun.
## Pure state machine; the game feeds it events and shows [prompt()] on the HUD.

const STEPS := [
	{"id": "move", "text": "MOVE  ·  left stick / WASD  ·  walk a few steps", "goal": 3.0},
	{"id": "shoot", "text": "SHOOT  ·  aim at the zombie and fire", "goal": 1.0},
	{"id": "rebuild", "text": "REBUILD  ·  hold USE at a broken window to board it up", "goal": 1.0},
	{"id": "buy", "text": "BUY  ·  walk to the chalk outline on the wall and press USE", "goal": 1.0},
]
const STEP_TIMEOUT := 9.0   ## never trap the player: each step auto-advances after this long
const MAX_TIME := 36.0

var step := 0
var progress := 0.0
var step_t := 0.0
var total_t := 0.0
var skipped := false

func done() -> bool:
	return skipped or step >= STEPS.size()

func current() -> String:
	return "" if done() else STEPS[step].id

func prompt() -> String:
	if done(): return ""
	return "%d/%d  %s" % [step + 1, STEPS.size(), STEPS[step].text]

func skip() -> void:
	skipped = true

## Report progress: "move" with metres walked, "shoot"/"rebuild"/"buy" with 1.
func event(id: String, amount := 1.0) -> void:
	if done() or id != current(): return
	progress += amount
	if progress >= float(STEPS[step].goal): _next()

func update(dt: float) -> void:
	if done(): return
	step_t += dt; total_t += dt
	if step_t >= STEP_TIMEOUT: _next()
	if total_t >= MAX_TIME: step = STEPS.size()

func _next() -> void:
	step += 1; progress = 0.0; step_t = 0.0
