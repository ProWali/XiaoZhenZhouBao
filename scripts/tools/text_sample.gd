## 文本抽检工具。不开游戏，批量跑局、批量生成文字，查机械痕迹。
##   godot --headless -s res://scripts/tools/text_sample.gd -- --lang zh --seeds 10 --weeks 52 --out sample_zh.md
## 产出：
##   一、每局真实印出来的报道、信、来访，全部过 lint
##   二、对每个登过报的事件，穷举 语气 × 署名 × 重抽 五次的候选标题，统计总数与重复率
##   三、问题按类型计数，每类列几个例子
##   四、--out 写一份抽样（随机 40 篇报道 + 40 封信 + 40 段来访），给人读
extends SceneTree

const World = preload("res://scripts/sim/world.gd")
const Auto = preload("res://scripts/sim/autoplayer.gd")
const TE = preload("res://scripts/text/text_engine.gd")
const Rng = preload("res://scripts/sim/rng.gd")

var opts := {"lang": "zh", "seeds": 10, "weeks": 52, "out": ""}
var issues := {}      # 问题类型 -> 次数
var examples := {}    # 问题类型 -> [例句]
var counts := {"articles": 0, "paragraphs": 0, "letters": 0, "visitor_lines": 0, "headlines": 0, "ui_lines": 0}
var headline_set := {}
var sample_articles: Array = []
var sample_letters: Array = []
var sample_visits: Array = []


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var nxt: String = args[i + 1] if i + 1 < args.size() else ""
		match args[i]:
			"--lang": opts.lang = nxt; i += 1
			"--seeds": opts.seeds = int(nxt); i += 1
			"--weeks": opts.weeks = int(nxt); i += 1
			"--out": opts.out = nxt; i += 1
		i += 1
	for s in range(1, int(opts.seeds) + 1):
		for st in ["cautious", "sensational", "random"]:
			_run(s, st)
	_report()
	quit(0 if _total_issues() == 0 else 1)


func _names(world) -> Array:
	var out: Array = []
	for rid in world.residents:
		out.append(TE.person_name(world, rid, opts.lang))
	return out


func _check(text: String, where: String, names: Array) -> void:
	for problem in TE.lint(text, opts.lang, names):
		var key: String = str(problem).split("：")[0].split(":")[0]
		issues[key] = int(issues.get(key, 0)) + 1
		if not examples.has(key):
			examples[key] = []
		if examples[key].size() < 6:
			examples[key].append("[%s] %s  ← %s" % [where, text, problem])


func _run(seed_v: int, strategy: String) -> void:
	var world = World.new(seed_v, {"total_weeks": int(opts.weeks), "lang": opts.lang})
	var auto = Auto.new(strategy, seed_v)
	var names := _names(world)
	var printed_events := {}
	var pick := Rng.new(seed_v * 31 + strategy.length())
	while world.game_over == "":
		var issue: Dictionary = auto.play_week(world)
		names = _names(world)
		for l in auto.last_letters:
			counts.letters += 1
			_check(l, "信", names)
			if pick.chance(0.08):
				sample_letters.append(l)
		for v in auto.last_visitors:
			for line in v.lines:
				counts.visitor_lines += 1
				_check(line, "来访·" + v.kind, names)
			if pick.chance(0.15):
				sample_visits.append("\n".join(v.lines))
		for line in auto.transcript:
			if line.begins_with("  ") and not line.begins_with("    "):
				counts.ui_lines += 1
				_check(line.strip_edges(), "采访", names)
		if issue.is_empty():
			break
		for a in issue.articles:
			counts.articles += 1
			_check(a.headline, "标题", names)
			for para in a.body:
				counts.paragraphs += 1
				_check(para, "正文", names)
			printed_events[a.event] = a
			if pick.chance(0.1):
				sample_articles.append("**%s**（%s · %s）\n\n%s" % [a.headline, a.tone, a.naming, "\n\n".join(a.body)])
	# 候选标题穷举
	for eid in printed_events:
		var e: Dictionary = world.event_by_id(eid)
		var a: Dictionary = printed_events[eid]
		for tone in ["calm", "neutral", "hot"]:
			for naming in ["named", "alias", "anon"]:
				for reroll in 5:
					var q := {"facts": a.facts, "tone": tone, "naming": naming, "reroll": reroll, "slot": a.slot}
					for h in TE.headline_candidates(world, e, q, opts.lang):
						counts.headlines += 1
						headline_set[h] = true
						_check(h, "候选标题", names)


func _total_issues() -> int:
	var n := 0
	for k in issues:
		n += int(issues[k])
	return n


func _report() -> void:
	print("文本抽检 · 语言 %s · %d 种子 × 3 策略 × %d 周" % [opts.lang, opts.seeds, opts.weeks])
	print("报道 %d 篇（段落 %d）  信 %d 封  来访台词 %d 句  采访反馈 %d 句" % [counts.articles, counts.paragraphs, counts.letters, counts.visitor_lines, counts.ui_lines])
	var uniq: int = headline_set.size()
	print("候选标题 %d 条，不重复 %d 条（%.1f%%）" % [counts.headlines, uniq, 100.0 * uniq / maxf(1.0, counts.headlines)])
	if issues.is_empty():
		print("lint：0 个问题")
	else:
		print("lint：%d 个问题" % _total_issues())
		for k in issues:
			print("  %s × %d" % [k, issues[k]])
			for ex in examples[k]:
				print("      " + ex)
	if opts.out != "":
		var f := FileAccess.open(opts.out, FileAccess.WRITE)
		var pick := Rng.new(12345)
		f.store_string("# 文本抽样（%s）\n\n## 报道\n\n" % opts.lang)
		for x in pick.sample(sample_articles, 40):
			f.store_string(x + "\n\n---\n\n")
		f.store_string("## 信\n\n")
		for x in pick.sample(sample_letters, 40):
			f.store_string("- " + x + "\n")
		f.store_string("\n## 来访\n\n")
		for x in pick.sample(sample_visits, 40):
			f.store_string(x.replace("\n", "  \n") + "\n\n")
		f.close()
		print("抽样写到 " + opts.out)
