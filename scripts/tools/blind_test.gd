## M3 盲测工具：生成稿里混入 20% 手写稿，看读者分不分得出。
##   第一步 godot --headless -s res://scripts/tools/blind_test.gd -- --brief [--from 20]
##          --from：从哪个种子往上找镇子。每轮换一个起点，读者就是在读一座新镇子；起点记在 round.json，出卷时沿用
##          从一局真实对局里抽 30 篇硬新闻，前 6 篇只写出事实提要（design/blind/briefs_zh.md），等人手写
##   第二步 把手写稿填进 design/blind/handwritten_zh.json：{"b01": {"headline": "...", "body": ["段落", ...]}, ...}
##   第三步 godot --headless -s res://scripts/tools/blind_test.gd -- --packet
##          生成打乱的试卷 design/blind/packet_zh.md 和答案 design/blind/key_zh.json
##   评分   godot --headless -s res://scripts/tools/blind_test.gd -- --score 3,7,12,...
##          读者交上来的「我认为是手写的编号」，对照答案算命中率
extends SceneTree

const World = preload("res://scripts/sim/world.gd")
const Auto = preload("res://scripts/sim/autoplayer.gd")
const TE = preload("res://scripts/text/text_engine.gd")
const Rng = preload("res://scripts/sim/rng.gd")

const TOTAL := 30
const HAND := 6
const DIR := "res://design/blind/"


var seed_from := 1


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	if FileAccess.file_exists(DIR + "round.json"):
		seed_from = int(JSON.parse_string(FileAccess.get_file_as_string(DIR + "round.json")).get("seed_from", 1))
	if "--from" in args:
		seed_from = int(args[args.find("--from") + 1])
	if "--brief" in args:
		_write(DIR + "round.json", JSON.stringify({"seed_from": seed_from}, " "))
		_brief()
	elif "--packet" in args:
		_packet()
	elif "--score" in args:
		_score(args[args.find("--score") + 1])
	else:
		print("用法：--brief | --packet | --score 1,2,3")
	quit()


## 只取一座镇子、一局：试卷里的人名、职业、镇长前后一致，读者不会因为「设定冲突」认出程序稿。
## 从种子 seed_from 往上找，第一个能凑够题量的局就用它。同一类事件最多取 8 篇。
func _collect() -> Array:
	for s in range(seed_from, seed_from + 60):
		var world = World.new(s, {"total_weeks": 104, "lang": "zh"})
		var auto = Auto.new("cautious", s)
		var pool: Array = []
		var per_tid := {}
		while world.game_over == "":
			var issue: Dictionary = auto.play_week(world)
			if issue.is_empty():
				break
			for a in issue.articles:
				var e: Dictionary = world.event_by_id(a.event)
				if e.soft or a.slot == "small":
					continue
				if int(per_tid.get(e.tid, 0)) >= 5:
					continue
				per_tid[e.tid] = int(per_tid.get(e.tid, 0)) + 1
				pool.append(_record(world, e, a, s, "cautious"))
		if pool.size() >= TOTAL:
			print("取材：种子 %d，一局 %d 周，硬新闻 %d 篇" % [s, world.week, pool.size()])
			return pool
	assert(false, "没有一局能凑够 %d 篇" % TOTAL)
	return []


func _record(world, e: Dictionary, a: Dictionary, seed_v: int, st: String) -> Dictionary:
	var roles: Array = []
	for role in e.roles:
		var rid: String = e.roles[role][0]
		var mode: String = a.naming if role == e.target else ("named" if a.naming == "named" else "alias")
		roles.append({"role": role, "name": world.residents[rid].name, "occ": TE.occ_label(world, rid, "zh", e.occ_at.get(rid, "")), "female": world.residents[rid].female, "shown_as": mode, "target": role == e.target})
	var facts: Array = []
	for fid in a.facts:
		var src: Dictionary = TE.best_source(world, fid)
		facts.append({"text": TE.fact_note(world, fid, "zh"), "source": src.kind, "verified": world.is_verified(fid)})
	var target: String = e.roles[e.target][0]
	return {
		"seed": seed_v, "strategy": st, "week": world.week - 1, "event": TE.event_name(world, e, "zh"), "tid": e.tid,
		"tone": a.tone, "naming": a.naming, "evidence": a.evidence, "roles": roles, "facts": facts,
		"pleaded": e.get("plea", "") != "", "season": TE.SEASON_ZH[world.is_season(world.week - 1)],
		"headline": a.headline, "body": a.body,
	}


func _pick(pool: Array) -> Array:
	var rng := Rng.new(19350401)
	return rng.sample(pool, TOTAL)


func _brief() -> void:
	var picked := _pick(_collect())
	var tone_zh := {"calm": "克制", "neutral": "中立", "hot": "煽动"}
	var naming_zh := {"named": "点名", "alias": "化名（写职业，不写名字）", "anon": "完全匿名"}
	var src_zh := {"witness": "本报亲眼所见", "archive": "查到的档案", "interview": "采访", "informer": "线人", "visitor": "有人登门告知", "eavesdrop": "酒馆里听来的", "letter": "匿名信", "public": "公开消息"}
	var md := "# 盲测手写稿提要\n\n每条按提要写一篇报道：一个标题，三到四段。只能写提要里的事实，信源说法要和「来源」一致。写完填进 handwritten_zh.json。\n\n"
	for i in HAND:
		var r: Dictionary = picked[i]
		md += "## b%02d · %s（%s，%s）\n\n" % [i + 1, r.event, r.season, "第 %d 周" % r.week]
		md += "- 语气：%s；署名：%s；%s\n" % [tone_zh[r.tone], naming_zh[r.naming], "附档案影印" if r.evidence else "不附影印"]
		md += "- 当事人是否托人求情：%s\n" % ("是" if r.pleaded else "否")
		for ro in r.roles:
			md += "- %s：%s（%s，%s）%s\n" % [ro.role, ro.name, ro.occ, "女" if ro.female else "男", "，当事人" if ro.target else ""]
		for f in r.facts:
			md += "- 事实：%s（来源：%s%s）\n" % [f.text, src_zh.get(f.source, f.source), "，已交叉验证" if f.verified else ""]
		md += "\n"
	_write(DIR + "briefs_zh.md", md)
	_write(DIR + "pool_zh.json", JSON.stringify(picked, " "))
	print("提要写到 design/blind/briefs_zh.md，共 %d 条；题库 %d 篇" % [HAND, picked.size()])


func _packet() -> void:
	# 出卷前必须通过防污染检查：生成器模板不能和任何一轮手写稿雷同
	var out: Array = []
	var code := OS.execute("python", ["-I", ProjectSettings.globalize_path("res://scripts/tools/check_contamination.py")], out, true)
	if code != 0:
		print("防污染检查没通过，不出卷：")
		for line in out:
			print(line)
		return
	var saved: Array = JSON.parse_string(FileAccess.get_file_as_string(DIR + "pool_zh.json"))
	# 生成稿必须是现在的引擎渲染的，不能用生成提要时存下的旧文字；题目（哪一局、哪一周、哪件事）必须不变
	var picked := _pick(_collect())
	for i in picked.size():
		assert(picked[i].tid == saved[i].tid and int(picked[i].week) == int(saved[i].week), "题库变了，要重新生成提要和手写稿")
	var hand: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "handwritten_zh.json"))
	var items: Array = []
	for i in picked.size():
		var r: Dictionary = picked[i]
		var bid := "b%02d" % (i + 1)
		if i < HAND:
			assert(hand.has(bid), "缺手写稿 " + bid)
			items.append({"headline": hand[bid].headline, "body": hand[bid].body, "hand": true, "src": bid, "week": r.week})
		else:
			items.append({"headline": r.headline, "body": r.body, "hand": false, "src": "%s·种子%d·%s·第%d周" % [r.tid, r.seed, r.strategy, r.week], "week": r.week})
	var rng := Rng.new(int(picked.size()) * 131 + int(str(picked[0].seed)))
	rng.shuffle(items)
	var md := "# 《灰河周报》剪报 " + str(items.size()) + " 篇\n\n这些报道出自同一份小镇周报。其中有一部分是人手写的，其余是程序生成的。请读完后写下你认为是人手写的编号，以及把握有多大。\n\n"
	var key := {}
	for i in items.size():
		var it: Dictionary = items[i]
		md += "## %d. %s\n\n*第 %d 周*\n\n%s\n\n" % [i + 1, it.headline, int(it.week), "\n\n".join(it.body)]
		key[str(i + 1)] = {"hand": it.hand, "src": it.src}
	_write(DIR + "packet_zh.md", md)
	_write(DIR + "key_zh.json", JSON.stringify(key, " "))
	print("试卷写到 design/blind/packet_zh.md，答案在 key_zh.json")


func _score(csv: String) -> void:
	var key: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "key_zh.json"))
	var guesses: Array = []
	for x in csv.split(",", false):
		guesses.append(x.strip_edges())
	var hits := 0
	for g in guesses:
		if key.has(g) and key[g].hand:
			hits += 1
	var n_hand := 0
	for k in key:
		if key[k].hand:
			n_hand += 1
	var expected: float = float(guesses.size()) * n_hand / key.size()
	print("猜了 %d 篇，命中 %d 篇；手写稿共 %d 篇；瞎猜的期望命中 %.1f 篇" % [guesses.size(), hits, n_hand, expected])
	# 30 篇里 6 篇手写、猜 6 篇：瞎猜命中 3 篇的概率约 7%，命中 4 篇及以上不到 1%，所以命中 4 篇就算分得出
	print("判定：%s" % ("分得出（盲测未通过）" if hits >= 4 else "分不出（盲测通过）"))


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
