## 一局存档的取料统计：交谈 / 问出新料、蹲守 / 看到新东西、顺线头、熬夜丢掉的上午、没用完行动点就收工。
## 和 M4.1 外部试玩分析里那张表同口径，真人和子 Agent 的局放在一起比。
## 用法：godot --headless -s res://scripts/tools/action_stats.gd -- <存档.json>...
extends SceneTree

const World = preload("res://scripts/sim/world.gd")


func _init() -> void:
	print("| 局 | 交谈/问出新料 | 顺线头/问出新料 | 蹲守/看到新东西 | 偷听/听到新料 | 查档案/有料 | 线人/有料 | 丢掉的上午 | 提前收工 |")
	print("|---|---|---|---|---|---|---|---|---|")
	for path in OS.get_cmdline_user_args():
		_one(path)
	quit()


func _one(path: String) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data.has("save"):
		data = data.save
	var cfg := {}
	for k in data.get("config", {}):
		var v = data.config[k]
		cfg[k] = int(v) if (v is float and k == "total_weeks") else v
	var w = World.new(int(data.seed), cfg)
	w.recording = false
	var n := {}
	for k in ["talk", "talk_new", "lead", "lead_new", "stake", "stake_new", "ears", "ears_new", "arch", "arch_new", "inf", "inf_new", "lost", "quit"]:
		n[k] = 0
	var lost_seen := {}
	for act in data.actions:
		var before: int = w.known.size()
		var k: String = act.kind
		var on_lead := false
		if k == "interview":
			for l in w.leads:
				if l.who == str(act.rid):
					on_lead = true
		if k == "end_day" and w.slot <= 1 and w.actions_left > 0:
			n.quit += 1
		w.apply_action(act)
		var got: bool = w.known.size() > before
		match k:
			"interview":
				n.talk += 1
				n.talk_new += int(got)
				if on_lead:
					n.lead += 1
					n.lead_new += int(got)
			"stakeout":
				n.stake += 1
				n.stake_new += int(got)
			"eavesdrop":
				n.ears += 1
				n.ears_new += int(got)
			"archive":
				n.arch += 1
				n.arch_new += int(got)
			"informer":
				n.inf += 1
				n.inf_new += int(got)
		if w.slept_in != 0:
			lost_seen[w.slept_in] = true
		if w.week > 4:
			break
	n.lost = lost_seen.size()
	print("| %s | %d/%d | %d/%d | %d/%d | %d/%d | %d/%d | %d/%d | %d | %d |" % [path.get_base_dir().get_file() + "/" + path.get_file(), n.talk, n.talk_new, n.lead, n.lead_new, n.stake, n.stake_new, n.ears, n.ears_new, n.arch, n.arch_new, n.inf, n.inf_new, n.lost, n.quit])
