class_name PactStone
## The Pact Stone: a points-based easter-egg chain (original). Each step must be finished in order.
##  0 Awaken  - pay the stone to wake it
##  1 Feed    - kill zombies close to the stone so it drinks their souls
##  2 Tithe   - pay a heavier offering
##  3 Endure  - survive one full round after the tithe without going down
## Reward: a free perk, a full restock and bonus points.

const STEPS := ["awaken", "feed", "tithe", "endure"]
const STEP_TEXT := {"awaken": "Awaken the Pact Stone", "feed": "Feed it souls", "tithe": "Offer a tithe", "endure": "Endure one round unbroken"}
const AWAKEN_COST := 750
const TITHE_COST := 1500
const SOULS := 12
const FEED_RADIUS := 8.0
const REWARD_POINTS := 2500

var step := 0
var souls := 0
var endure_round := -1    ## round that must be survived for the last step
var done := false

func current() -> String: return "" if done else STEPS[step]

func cost() -> int:
	match current():
		"awaken": return AWAKEN_COST
		"tithe": return TITHE_COST
	return -1

## Pay at the stone. Returns true on progress.
func pay(economy: Economy) -> bool:
	var c := cost()
	if c < 0 or not economy.spend(c): return false
	step += 1
	return true

## A kill at [dist] metres from the stone. Returns true when this kill completes the feeding.
func on_kill(dist: float) -> bool:
	if current() != "feed" or dist > FEED_RADIUS: return false
	souls += 1
	if souls < SOULS: return false
	step += 1
	return true

## Called when [round] starts; arms the endure step on the round after the tithe.
func on_round_start(round: int) -> void:
	if current() == "endure" and endure_round < 0: endure_round = round

## The player went down: the endure step resets to the next round.
func on_down() -> void:
	if current() == "endure": endure_round = -1

## Called when [round] ends. Returns true when the pact is sealed.
func on_round_end(round: int) -> bool:
	if current() != "endure" or endure_round != round: return false
	done = true
	return true

func prompt() -> String:
	if done: return ""
	match current():
		"awaken": return "Pact Stone: awaken (%d)" % AWAKEN_COST
		"feed": return "Pact Stone hungers: %d / %d souls" % [souls, SOULS]
		"tithe": return "Pact Stone: tithe (%d)" % TITHE_COST
		"endure": return "Pact Stone: endure a round unbroken"
	return ""
