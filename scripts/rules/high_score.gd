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

## Returns true if [run] beats the stored best run; always updates the separate round/score records.
func submit(run: Dictionary) -> bool:
	load_best(); load_records()
	new_round = int(run.get("round", 0)) > int(records.round)
	new_score = int(run.get("points", 0)) > int(records.score)
	var is_best := better(run, best)
	if not (is_best or new_round or new_score): return false
	if is_best:
		for k in best: best[k] = int(run.get(k, 0))
	if new_round: records.round = int(run.get("round", 0))
	if new_score: records.score = int(run.get("points", 0))
	var cf := ConfigFile.new()
	for k in best: cf.set_value("best", k, best[k])
	for k in records: cf.set_value("records", k, records[k])
	cf.save(path)
	return is_best
