## 模拟层自动测试。无头运行：
##   godot --headless -s res://scripts/tools/run_tests.gd
## 失败时退出码非 0。
extends SceneTree

const World = preload("res://scripts/sim/world.gd")
const Auto = preload("res://scripts/sim/autoplayer.gd")
const Save = preload("res://scripts/sim/save.gd")
const TE = preload("res://scripts/text/text_engine.gd")

var failures: Array = []


func _init() -> void:
	_test_determinism()
	_test_replay()
	_test_robustness()
	_test_templates_reachable()
	_test_fact_text()
	_test_unattended()
	_test_language_independent()
	_test_text_lint()
	if failures.is_empty():
		print("全部通过")
		quit(0)
	else:
		for f in failures:
			print("失败：" + f)
		quit(1)


func _fail(msg: String) -> void:
	failures.append(msg)


func _play(seed_v: int, strategy: String, weeks: int, lang: String = "zh") -> Dictionary:
	var world = World.new(seed_v, {"total_weeks": weeks, "lang": lang})
	var auto = Auto.new(strategy, seed_v)
	while world.game_over == "":
		var issue: Dictionary = auto.play_week(world)
		if issue.is_empty():
			break
	return {"world": world}


## 同种子两次跑出逐字相同的日志和数值。
func _test_determinism() -> void:
	var a = _play(7, "cautious", 16).world
	var b = _play(7, "cautious", 16).world
	if JSON.stringify(a.log) != JSON.stringify(b.log):
		_fail("同种子日志不一致")
	if JSON.stringify(a.history) != JSON.stringify(b.history):
		_fail("同种子数值不一致")
	var c = _play(8, "cautious", 16).world
	if JSON.stringify(a.log) == JSON.stringify(c.log):
		_fail("不同种子日志居然一样")


## 存档 = 种子 + 操作日志；重放后状态逐字一致。
func _test_replay() -> void:
	for st in ["cautious", "sensational"]:
		var a = _play(5, st, 20).world
		var data: Dictionary = Save.to_dict(a)
		# 走一遍 JSON，模拟真的写盘读盘
		var round_trip = JSON.parse_string(JSON.stringify(data))
		var b = Save.from_dict(round_trip)
		if b.replay_error != "":
			_fail("重放出错（%s）：%s" % [st, b.replay_error])
		if JSON.stringify(a.history) != JSON.stringify(b.history):
			_fail("重放后数值不一致（%s）" % st)
		if JSON.stringify(a.log) != JSON.stringify(b.log):
			_fail("重放后日志不一致（%s）" % st)
		if a.actions.size() == 0:
			_fail("没有记录到任何操作（%s）" % st)
		if JSON.stringify(a.actions) != JSON.stringify(b.actions):
			_fail("重放后操作日志不一致（%s）" % st)


## 20 个种子 × 4 种策略 × 52 周不崩、无 NaN、人口不归零。
func _test_robustness() -> void:
	for st in ["cautious", "sensational", "soft", "random"]:
		for s in range(1, 21):
			var w = _play(s, st, 52).world
			for k in w.stats:
				if is_nan(float(w.stats[k])) or is_inf(float(w.stats[k])):
					_fail("种子 %d 策略 %s：%s 出现 NaN" % [s, st, k])
			if w.living_ids().size() < 25:
				_fail("种子 %d 策略 %s：人口只剩 %d" % [s, st, w.living_ids().size()])
			if w.game_over == "":
				_fail("种子 %d 策略 %s：52 周后没有结局" % [s, st])


## 每个非手动事件模板在 40 个种子里至少触发一次；手动模板至少在某局出现。
func _test_templates_reachable() -> void:
	var seen := {}
	var all_tids: Array = []
	var manual: Dictionary = {}
	for s in range(1, 41):
		var w = _play(s, "random", 52).world
		if all_tids.is_empty():
			for t in w.events_db.templates:
				all_tids.append(t.id)
				manual[t.id] = t.get("manual", false)
		for e in w.events + w.archive_events:
			seen[e.tid] = true
	for tid in all_tids:
		if not seen.has(tid) and not manual[tid]:
			_fail("模板从未触发：" + tid)
	for tid in ["obituary", "arrival", "fired", "inspector", "budget", "election", "candidacy"]:
		if not seen.has(tid):
			_fail("手动模板从未出现：" + tid)


## 事实文本没有未填的槽位。
func _test_fact_text() -> void:
	for s in range(1, 11):
		var w = _play(s, "random", 52).world
		for fid in w.facts:
			if "{" in w.facts[fid].text:
				_fail("种子 %d 事实 %s 有未填槽位：%s" % [s, fid, w.facts[fid].text])
		for iss in w.issues:
			for a in iss.articles:
				if "{" in a.headline:
					_fail("种子 %d 标题有未填槽位：%s" % [s, a.headline])
				for b in a.body:
					if "{" in b:
						_fail("种子 %d 正文有未填槽位：%s" % [s, b])


## 104 周无人干预（只印软新闻）：镇子自己要生出故事。
## 衡量：10 局里，需求驱动事件总数、后续事件总数、选举都要有。
func _test_unattended() -> void:
	var driven := 0
	var followups := 0
	var elections := 0
	var deaths := 0
	for s in range(1, 11):
		var w = _play(s, "cautious", 104).world
		for l in w.log:
			if "已经紧了" in l:
				driven += 1
			if "镇长选举" in l:
				elections += 1
			if "去世" in l:
				deaths += 1
		for e in w.events + w.archive_events:
			if e.tid in ["fired", "inspector", "separation", "resign"]:
				followups += 1
		var pop: int = w.living_ids().size()
		if pop < 30 or pop > 110:
			_fail("种子 %d 104 周后人口 %d，失控" % [s, pop])
	if driven < 20:
		_fail("10 局 104 周需求驱动事件只有 %d 起" % driven)
	if followups < 5:
		_fail("10 局 104 周后续事件只有 %d 起" % followups)
	if elections < 3:
		_fail("10 局里只有 %d 局办了选举（局中途结束的除外）" % elections)
	print("无人跑：需求驱动 %d，后续 %d，选举 %d，死亡 %d" % [driven, followups, elections, deaths])


## 文本层不能碰模拟：同一种子中文局和英文局，故事日志和数值逐字相同。
func _test_language_independent() -> void:
	for st in ["cautious", "sensational"]:
		var a = _play(4, st, 30, "zh").world
		var b = _play(4, st, 30, "en").world
		if JSON.stringify(a.history) != JSON.stringify(b.history):
			_fail("换语言后数值变了（%s）" % st)
		if JSON.stringify(a.log) != JSON.stringify(b.log):
			_fail("换语言后故事日志变了（%s）" % st)


## 实际印出来的文字（报道、信、来访、采访反馈）过 lint。每种已有数据的语言都查。
func _test_text_lint() -> void:
	for lang in ["zh", "en"]:
		if not FileAccess.file_exists("res://data/text/%s/events.json" % lang):
			continue
		var bad := 0
		var first := ""
		for s in range(1, 4):
			var world = World.new(s, {"total_weeks": 26, "lang": lang})
			var auto = Auto.new("random", s)
			while world.game_over == "":
				var issue: Dictionary = auto.play_week(world)
				var texts: Array = auto.last_letters.duplicate()
				for v in auto.last_visitors:
					texts.append_array(v.lines)
				if not issue.is_empty():
					for a in issue.articles:
						texts.append(a.headline)
						texts.append_array(a.body)
				for t in texts:
					var probs: Array = TE.lint(str(t), lang)
					if not probs.is_empty():
						bad += 1
						if first == "":
							first = "%s ← %s" % [t, probs]
				if issue.is_empty():
					break
		if bad > 0:
			_fail("%s 文本 lint 有 %d 处问题，例如：%s" % [lang, bad, first])
