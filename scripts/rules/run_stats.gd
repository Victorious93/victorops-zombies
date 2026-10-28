class_name RunStats
## Per-game stats for the game-over screen.

var kills := 0
var headshots := 0
var points_earned := 0
var downs := 0
var time := 0.0
var parts := 0
var pact := false
var bosses := 0

static func fmt_time(sec: float) -> String:
	var s := int(sec)
	return "%d:%02d" % [s / 60, s % 60]

func accuracy_text(shots: int, hits: int) -> String:
	return "%d%%" % (0 if shots <= 0 else int(round(100.0 * hits / shots)))

func lines(round: int) -> Array:
	return [
		"Rounds survived  %d" % round,
		"Kills  %d   ·   Headshots  %d" % [kills, headshots],
		"Points earned  %d" % points_earned,
		"Downs  %d   ·   Time  %s" % [downs, fmt_time(time)],
		"Harp parts  %d/3   ·   Pact  %s   ·   Wardens slain  %d" % [parts, "sealed" if pact else "unsealed", bosses],
	]
