## 把一份存档逐步重放，打印每一步玩家看到的文字。读真人试玩用。
## 用法：godot --headless -s res://scripts/tools/replay_report.gd -- --save <slot1.json> [--out report.md]
extends SceneTree

const World = preload("res://scripts/sim/world.gd")
const TE = preload("res://scripts/text/text_engine.gd")
const T = preload("res://scripts/sim/tables.gd")

var _out: Array = []


func _p(s: String) -> void:
	_out.append(s)


func _init() -> void:
	var path := ""
	var out_path := ""
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--save": path = args[i + 1]
		if args[i] == "--out": out_path = args[i + 1]
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data.has("save"):
		data = data.save
	var cfg := {}
	for k in data.get("config", {}):
		var v = data.config[k]
		cfg[k] = int(v) if (v is float and k == "total_weeks") else v
	var w = World.new(int(data.seed), cfg)
	_p("# 重放：种子 %d，%d 步" % [int(data.seed), data.actions.size()])
	var week := 0
	for act in data.actions:
		if w.week != week:
			week = w.week
			_p("\n## 第 %d 周" % week)
			for l in w.render_letters():
				_p("- 信：" + l)
		var k: String = act.kind
		var head := "**%s%s**" % [w.DAY_NAMES[mini(w.day, 7)], w.SLOT_NAMES[mini(w.slot, 2)]]
		match k:
			"interview":
				var rid: String = act.rid
				var topic: String = str(act.get("topic", ""))
				var r: Dictionary = w.residents[rid]
				var knows_n := 0
				for fid in r.knows:
					if not w.known.has(fid):
						knows_n += 1
				var res: Dictionary = w.act_interview(rid, topic)
				_p("%s 采访 %s（%s，在%s），话头：%s ｜ 对方知道 %d 条你不知道的" % [head, r.name, r.occ_name, w.loc_name(w.where_is(rid)) if w.where_is(rid) != "" else "?", ("「" + TE.fact_note(w, topic, "zh") + "」") if topic != "" else "随便聊", knows_n])
				for l in res.lines.slice(1):
					_p("    > " + l)
			"archive":
				var res: Dictionary = w.act_archive(str(act.loc))
				_p("%s 查档案 %s" % [head, w.loc_name(str(act.loc))])
				for l in res.lines:
					_p("    > " + l)
			"informer":
				var res: Dictionary = w.act_informer(str(act.target))
				_p("%s 线人 %s" % [head, w.res_name(str(act.target))])
				for l in res.lines:
					_p("    > " + l)
			"eavesdrop", "stakeout":
				var res: Dictionary = w.act_eavesdrop() if k == "eavesdrop" else w.act_stakeout(str(act.loc))
				_p("%s %s %s" % [head, "偷听" if k == "eavesdrop" else "蹲守", str(act.get("loc", "酒馆"))])
				for l in res.lines:
					_p("    > " + l)
			"end_day":
				_p("%s 收工（剩 %d 行动点）" % [head, w.actions_left if w.slot <= 1 else 0])
				w.end_day()
			"saturday":
				var vs: Array = w.saturday_visitors()
				_p("**周六夜** 来访 %d 人" % vs.size())
				for v in vs:
					for l in v.lines:
						_p("    > " + l)
			"deal":
				w.accept_deal({"who": str(act.who), "event": str(act.event), "offer": int(act.offer)})
				_p("收钱")
			"print":
				_p("\n**周日选题簿：**")
				for g in w.notebook():
					var e: Dictionary = g.event
					var vs: Array = []
					for fid in g.facts:
						vs.append("%s[%d章%s]" % [TE.fact_note(w, fid, "zh"), mini(3, int(w.verify_score(fid))), "·档" if w.known[fid].evidence else ""])
					_p("- %s%s%s：%s" % [TE.event_name(w, e, "zh"), "（软）" if e.soft else "", "（已登）" if e.printed else "", "；".join(vs)])
				var choice := {}
				for c in act.get("choice", {}):
					choice[c] = int(act.choice[c])
				var issue: Dictionary = w.print_issue(act.articles, choice)
				_p("\n**付印：**")
				for a in issue.articles:
					_p("- 【%s · %s · %s%s】%s（真实度 %.2f）" % [T.SLOT_NAME[a.slot], T.TONE_NAME[a.tone], T.NAMING_NAME[a.naming], " · 附档案" if a.evidence else "", a.headline, a.avg_truth])
				for c in issue.consequences:
					_p("    后果：" + c)
				_p("公信力 %.1f（%+.1f） 发行 %.0f 现金 %.1f" % [w.stats.credibility, issue.cred_delta, w.stats.circulation, w.stats.cash])
	_p("\n## 故事日志（模拟层，玩家看不到）")
	for l in w.log:
		_p("- " + l)
	var text := "\n".join(_out)
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		f.store_string(text)
		f.close()
	else:
		print(text)
	quit()
