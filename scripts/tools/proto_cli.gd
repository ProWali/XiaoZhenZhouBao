## M1 纸上原型的命令行入口。无画面，纯文本。
## 用法（在项目根目录）：
##   godot --headless -s res://scripts/tools/proto_cli.gd -- --auto cautious --seed 1 --weeks 12 --verbose
##   godot --headless -s res://scripts/tools/proto_cli.gd -- --batch 10 --weeks 52
##   godot --headless -s res://scripts/tools/proto_cli.gd -- --play --seed 3
extends SceneTree

const World = preload("res://scripts/sim/world.gd")
const Auto = preload("res://scripts/sim/autoplayer.gd")
const T = preload("res://scripts/sim/tables.gd")
const Save = preload("res://scripts/sim/save.gd")

var opts := {"seed": 1, "weeks": 12, "auto": "", "verbose": false, "batch": 0, "play": false, "story": false, "save": "", "load": ""}


func _init() -> void:
	_parse_args()
	if opts.load != "":
		_run_load()
	elif opts.batch > 0:
		_run_batch()
	elif opts.play:
		_run_interactive()
	else:
		_run_auto(opts.auto if opts.auto != "" else "cautious", opts.seed, opts.weeks, true)
	quit()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var a: String = args[i]
		var next: String = args[i + 1] if i + 1 < args.size() else ""
		match a:
			"--seed": opts.seed = int(next); i += 1
			"--weeks": opts.weeks = int(next); i += 1
			"--auto": opts.auto = next; i += 1
			"--batch": opts.batch = int(next); i += 1
			"--verbose": opts.verbose = true
			"--story": opts.story = true
			"--play": opts.play = true
			"--save": opts.save = next; i += 1
			"--load": opts.load = next; i += 1
		i += 1


# ------------------------------------------------------------ 自动
func _run_auto(strategy: String, seed_v: int, weeks: int, show: bool) -> Dictionary:
	var world = World.new(seed_v, {"total_weeks": weeks})
	var auto = Auto.new(strategy, seed_v)
	var false_printed := 0
	var articles := 0
	var reactions := {}
	while world.game_over == "":
		var issue: Dictionary = auto.play_week(world)
		if show and opts.verbose:
			for l in auto.transcript:
				print(l)
			print("")
		if issue.is_empty():
			break
		for a in issue.articles:
			articles += 1
			if a.avg_truth < 0.5:
				false_printed += 1
		for c in issue.consequences:
			reactions[c.substr(0, 2)] = reactions.get(c.substr(0, 2), 0) + 1
	var summary := {
		"strategy": strategy, "seed": seed_v, "weeks": world.week if world.game_over == "任期结束" else world.week,
		"end": world.game_over, "cred": world.stats.credibility, "circ": world.stats.circulation, "cash": world.stats.cash,
		"articles": articles, "false": false_printed, "left": _count_left(world), "dead": _count_dead(world),
	}
	if show and opts.save != "":
		print("存档写到 %s：%s" % [opts.save, "成功" if Save.save(world, opts.save) else "失败"])
	if show:
		print("=== 结局：%s · 第 %d 周 ===" % [world.game_over, world.week])
		print("公信力 %.0f  发行量 %.0f  现金 %.1f  报道 %d 篇（其中假的 %d）  离镇 %d 人  去世 %d 人" % [world.stats.credibility, world.stats.circulation, world.stats.cash, articles, false_printed, summary.left, summary.dead])
		if opts.story or opts.verbose:
			print("\n--- 故事日志 ---")
			for l in world.log:
				print(l)
			print("\n--- 年度回顾 ---")
			for l in world.retrospective():
				print(l)
	return summary


## 读档重放，打印摘要。
func _run_load() -> void:
	var world = Save.load_path(opts.load)
	if world == null:
		print("读不了存档：" + opts.load)
		return
	if world.replay_error != "":
		print("重放中断：" + world.replay_error)
	print("重放完成：第 %d 周 %s · 公信力 %.0f 发行量 %.0f 现金 %.1f · 操作 %d 步 · 结局「%s」" % [world.week, world.DAY_NAMES[world.day], world.stats.credibility, world.stats.circulation, world.stats.cash, world.actions.size(), world.game_over])
	for l in world.retrospective():
		print(l)


func _count_left(world) -> int:
	var n := 0
	for rid in world.residents:
		if not world.residents[rid].in_town:
			n += 1
	return n


func _count_dead(world) -> int:
	var n := 0
	for rid in world.residents:
		if not world.residents[rid].alive:
			n += 1
	return n


func _run_batch() -> void:
	var strategies := ["cautious", "sensational", "soft", "random"]
	print("策略        局数  平均周数  破产  停刊  被毁  任期满  公信力  发行量   现金  报道  假报道")
	for st in strategies:
		var rows: Array = []
		for s in range(1, opts.batch + 1):
			rows.append(_run_auto(st, s, opts.weeks, false))
		var ends := {"破产": 0, "停刊": 0, "报社被毁": 0, "任期结束": 0}
		var sum := {"weeks": 0.0, "cred": 0.0, "circ": 0.0, "cash": 0.0, "articles": 0.0, "false": 0.0}
		for r in rows:
			ends[r.end] = ends.get(r.end, 0) + 1
			for k in sum:
				sum[k] += float(r[k])
		var n := float(rows.size())
		print("%-11s %4d  %7.1f  %4d  %4d  %4d  %6d  %6.1f  %6.0f  %6.1f  %4.1f  %5.1f" % [
			st, rows.size(), sum.weeks / n, ends["破产"], ends["停刊"], ends["报社被毁"], ends["任期结束"],
			sum.cred / n, sum.circ / n, sum.cash / n, sum.articles / n, sum["false"] / n])


# ------------------------------------------------------------ 交互
func _read_line() -> String:
	var s := OS.read_string_from_stdin()
	return s.strip_edges()


func _ask_int(prompt: String, lo: int, hi: int) -> int:
	while true:
		print(prompt)
		var s := _read_line()
		if s == "":
			return -1
		if s.is_valid_int():
			var v := int(s)
			if v >= lo and v <= hi:
				return v
	return -1


func _run_interactive() -> void:
	var world = World.new(opts.seed, {"total_weeks": opts.weeks})
	print("《%s》 · 灰河镇 · 种子 %d · %d 周" % [world.paper_name, world.seed_value, opts.weeks])
	while world.game_over == "":
		print("\n======== 第 %d 周 · %s ========" % [world.week, world.season_name()])
		for l in world.letters:
			print("信：" + l)
		while world.day <= 6:
			_interactive_day(world)
		var visitors: Array = world.saturday_visitors()
		print("\n—— 周六夜 ——")
		if visitors.is_empty():
			print("没有人来。")
		for v in visitors:
			for l in v.lines:
				print(l)
			if v.kind == "deal":
				var c := _ask_int("收下这笔钱？ 1 收  2 不收", 1, 2)
				if c == 1:
					world.accept_deal(v)
		_interactive_layout(world)
	print("\n=== 结局：%s ===" % world.game_over)
	for l in world.retrospective():
		print(l)


func _interactive_day(world) -> void:
	while world.day <= 6:
		var status := "第 %d 周 %s %s · 行动点 %d · 熬夜 %d/2 · 公信力 %.0f 发行量 %.0f 现金 %.1f" % [
			world.week, world.DAY_NAMES[world.day], world.SLOT_NAMES[world.slot], world.actions_left, world.nights_used, world.stats.credibility, world.stats.circulation, world.stats.cash]
		print("\n" + status)
		var menu := "1 采访  2 查档案  3 线人  4 选题簿  5 结束今天"
		if world.slot == 2 or not world.can_act_day():
			menu = "4 选题簿  5 结束今天  6 酒馆偷听（熬夜）  7 蹲守（熬夜）"
		var c := _ask_int(menu, 1, 7)
		match c:
			1:
				if not world.can_act_day():
					continue
				_interactive_interview(world)
			2:
				if not world.can_act_day():
					continue
				var locs := ["post", "hall", "clinic", "store"]
				var k := _ask_int("去哪？ 1 邮局  2 镇公所  3 诊所  4 杂货店", 1, 4)
				if k > 0:
					_print_lines(world.act_archive(locs[k - 1]))
			3:
				if not world.can_act_day():
					continue
				var ids: Array = world.living_ids()
				for i in ids.size():
					print("%3d %s（%s）" % [i + 1, world.residents[ids[i]].name, world.residents[ids[i]].occ_name])
				var k := _ask_int("买谁的料？", 1, ids.size())
				if k > 0:
					_print_lines(world.act_informer(ids[k - 1]))
			4:
				_print_notebook(world)
			5:
				world.end_day()
				return
			6:
				if world.can_act_night():
					_print_lines(world.act_eavesdrop())
					return
			7:
				var locs := ["river", "bridge", "woods", "mill", "tavern"]
				var k := _ask_int("蹲哪？ 1 河边  2 桥头  3 树林  4 锯木厂  5 酒馆", 1, 5)
				if k > 0 and world.can_act_night():
					_print_lines(world.act_stakeout(locs[k - 1]))
					return
			_:
				world.end_day()
				return


func _interactive_interview(world) -> void:
	var present: Array = []
	for rid in world.living_ids():
		var loc: String = world.where_is(rid)
		if loc != "" and not loc.begins_with("home:"):
			present.append(rid)
	present.sort_custom(func(a, b): return world.where_is(a) < world.where_is(b))
	for i in present.size():
		var r: Dictionary = world.residents[present[i]]
		print("%3d %-8s %s（%s）" % [i + 1, world.loc_name(world.where_is(present[i])), r.name, r.occ_name])
	var k := _ask_int("找谁？（回车取消）", 1, present.size())
	if k <= 0:
		return
	var topics: Array = world.known.keys()
	print("  0 泛泛打听")
	for i in topics.size():
		print("%3d %s" % [i + 1, world.facts[topics[i]].text])
	var t := _ask_int("话头？", 0, topics.size())
	if t < 0:
		return
	_print_lines(world.act_interview(present[k - 1], "" if t == 0 else topics[t - 1]))


func _print_lines(res: Dictionary) -> void:
	for l in res.lines:
		print("  " + l)


func _print_notebook(world) -> void:
	print("\n—— 选题簿 ——")
	var groups: Array = world.notebook()
	if groups.is_empty():
		print("（空）")
	for g in groups:
		var e: Dictionary = g.event
		print("· %s%s" % [e.name, "（已登）" if e.printed else ""])
		for fid in g.facts:
			var f: Dictionary = world.facts[fid]
			var stamps := ""
			for i in mini(3, int(world.verify_score(fid))):
				stamps += "印"
			var srcs: Array = []
			for s in world.known[fid].sources:
				srcs.append(T.SOURCE_NAME[s.kind] + ("" if s.who == "" else "·" + world.res_name(s.who)))
			print("    [%s] %s  ← %s%s" % [stamps.rpad(3, "　"), f.text, "，".join(srcs), "  ✔证据" if world.known[fid].evidence else ""])
		for h in g.hints:
			print("    提示：" + h)


func _interactive_layout(world) -> void:
	print("\n—— 周日排版 ——")
	var groups: Array = world.notebook()
	var articles: Array = []
	var slots := ["head", "second", "third", "small"]
	for slot in slots:
		var avail: Array = []
		for g in groups:
			if not g.event.printed:
				var used := false
				for a in articles:
					if world.event_of(a.facts[0]).id == g.event.id:
						used = true
				if not used:
					avail.append(g)
		if avail.is_empty():
			break
		print("%s：" % T.SLOT_NAME[slot])
		for i in avail.size():
			var e: Dictionary = avail[i].event
			print("%3d %s（%d 条碎片）" % [i + 1, e.name, avail[i].facts.size()])
		var k := _ask_int("登哪件事？（回车留空）", 1, avail.size())
		if k <= 0:
			break
		var g: Dictionary = avail[k - 1]
		var tones := ["calm", "neutral", "hot"]
		var tone := _ask_int("语气？ 1 克制  2 中立  3 煽动", 1, 3)
		var namings := ["named", "alias", "anon"]
		var naming := _ask_int("署名？ 1 点名  2 化名  3 匿名", 1, 3)
		var has_ev := false
		for fid in g.facts:
			if world.known[fid].evidence:
				has_ev = true
		var ev := false
		if has_ev:
			ev = _ask_int("附档案影印？ 1 附  2 不附", 1, 2) == 1
		var a := {"slot": slot, "facts": g.facts, "tone": tones[maxi(tone, 1) - 1], "naming": namings[maxi(naming, 1) - 1], "evidence": ev}
		var cands: Array = world.headline_candidates(a)
		for i in cands.size():
			print("  标题 %d：%s" % [i + 1, cands[i]])
		articles.append(a)
	print("付印……（印刷机的声音）")
	var issue: Dictionary = world.print_issue(articles)
	for a in issue.articles:
		print("【%s】%s" % [T.SLOT_NAME[a.slot], a.headline])
	for c in issue.consequences:
		print("后果：" + c)
	print("公信力 %+.0f  发行量 %+.1f%%  现金 %+.1f" % [issue.cred_delta, issue.circ_delta * 100, issue.cash_delta])
