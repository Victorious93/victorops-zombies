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

## Returns true and saves if [run] beats the stored best.
func submit(run: Dictionary) -> bool:
	load_best()
	if not better(run, best): return false
	for k in best: best[k] = int(run.get(k, 0))
	var cf := ConfigFile.new()
	for k in best: cf.set_value("best", k, best[k])
	cf.save(path)
	return true
