class_name HighScore
## Best run, saved locally (ConfigFile in user://). Ranked by round, then kills, then points.

const PATH := "user://highscore.cfg"
var path := PATH
var best := {"round": 0, "kills": 0, "points": 0, "headshots": 0}

func _init(p_path := PATH) -> void: path = p_path

static func better(a: Dictionary, b: Dictionary) -> bool:
	for k in ["round", "kills", "points"]:
		if int(a.get(k, 0)) != int(b.get(k, 0)): return int(a.get(k, 0)) > int(b.get(k, 0))
	return false

func load_best() -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		for k in best: best[k] = int(cf.get_value("best", k, 0))
	return best

## v8: best round and best score are also kept on their own (a high-scoring run that died early still counts).
var records := {"round": 0, "score": 0}
var new_round := false
var new_score := false

func load_records() -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		records.round = maxi(int(cf.get_value("records", "round", 0)), int(cf.get_value("best", "round", 0)))
		records.score = maxi(int(cf.get_value("records", "score", 0)), int(cf.get_value("best", "points", 0)))
	return records

## v10 lifetime totals across every finished match on this device.
var totals := {"matches": 0, "kills": 0, "headshots": 0, "rounds": 0, "elites": 0}

func load_totals() -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(path) == OK:
		for k in totals: totals[k] = int(cf.get_value("totals", k, 0))
	return totals

static func totals_text(t: Dictionary) -> String:
	var k := int(t.get("kills", 0)); var h := int(t.get("headshots", 0))
	var m := int(t.get("matches", 0))
	return "Lifetime  ·  %d %s  ·  %d kills  ·  %d headshots (%d%%)  ·  %d Brutes" % [m, "match" if m == 1 else "matches", k, h, (0 if k <= 0 else int(round(100.0 * h / k))), int(t.get("elites", 0))]

## Returns true if [run] beats the stored best run; always updates the separate round/score records
## and the lifetime totals.
func submit(run: Dictionary) -> bool:
	load_best(); load_records(); load_totals()
	new_round = int(run.get("round", 0)) > int(records.round)
	new_score = int(run.get("points", 0)) > int(records.score)
	totals.matches += 1
	totals.kills += maxi(int(run.get("kills", 0)), 0); totals.headshots += maxi(int(run.get("headshots", 0)), 0)
	totals.rounds += maxi(int(run.get("round", 0)), 0); totals.elites += maxi(int(run.get("elites", 0)), 0)
	var is_best := better(run, best)
	if is_best:
		for k in best: best[k] = int(run.get(k, 0))
	if new_round: records.round = int(run.get("round", 0))
	if new_score: records.score = int(run.get("points", 0))
	var cf := ConfigFile.new()
	for k in best: cf.set_value("best", k, best[k])
	for k in records: cf.set_value("records", k, records[k])
	for k in totals: cf.set_value("totals", k, totals[k])
	cf.save(path)
	return is_best
