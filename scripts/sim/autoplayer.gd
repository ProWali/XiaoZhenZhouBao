## 自动玩家：四种策略，用来跑批量测试和读故事日志。
## cautious 谨慎：只印交叉验证过的；sensational 煽动：什么都印，点名煽动；
## soft 软新闻：只印公开事件；random 随机；
## bold 敢说：取料和谨慎一样，登两枚章以上的，一律点名、煽动（看煽动语气本身站不站得住）。
extends RefCounted

const T = preload("res://scripts/sim/tables.gd")
const Rng = preload("res://scripts/sim/rng.gd")

var strategy := "cautious"
var rng: Rng     # 自动玩家自己的随机源，和世界的分开，避免策略改变世界种子序列
var transcript: Array = []  # 可读的行动记录
var last_letters: Array = []   # 本周渲染出来的信，抽检工具用
var last_visitors: Array = []  # 本周的来访，抽检工具用
var _world


func _init(strategy_in: String, seed_in: int) -> void:
	strategy = strategy_in
	rng = Rng.new(seed_in * 7919 + 17)


func play_week(world) -> Dictionary:
	_world = world
	transcript.clear()
	transcript.append("—— 第 %d 周（%s）——" % [world.week, world.season_name()])
	last_letters = world.render_letters()
	for l in last_letters:
		transcript.append("信：" + l)
	while world.day <= 6 and world.game_over == "":
		if world.can_act_day():
			_day_action(world)
		elif _want_night(world):
			_night_action(world)
		else:
			world.end_day()
	if world.game_over != "":
		return {}
	var visitors: Array = world.saturday_visitors()
	last_visitors = visitors
	for v in visitors:
		for l in v.lines:
			transcript.append("来访：" + l)
		if v.kind == "deal":
			var accept := false
			match strategy:
				"sensational": accept = true
				"soft": accept = true
				"random": accept = rng.chance(0.5)
			if accept:
				world.accept_deal(v)
				transcript.append("你收下了钱。")
	var articles: Array = _compose(world)
	var issue: Dictionary = world.print_issue(articles)
	for a in issue.articles:
		transcript.append("【%s】%s" % [T.SLOT_NAME[a.slot], a.headline])
		for b in a.body:
			transcript.append("    " + b)
	for c in issue.consequences:
		transcript.append("后果：" + c)
	transcript.append("公信力 %.0f（%+.0f） 发行量 %.0f 现金 %.1f（%+.1f）" % [world.stats.credibility, issue.cred_delta, world.stats.circulation, world.stats.cash, issue.cash_delta])
	return issue


func _log(res: Dictionary) -> void:
	for l in res.lines:
		transcript.append("  " + l)


# ------------------------------------------------------------ 白天
func _day_action(world) -> void:
	match strategy:
		"soft":
			_interview_random(world, "")
		"random":
			# 随手乱来，但抽屉快空了还是看得见的：钱少于 15 块不花钱查档案、找线人
			var roll := rng.randi_range(0, 3)
			if roll == 0 and world.stats.cash > 15:
				_archive_any(world)
			elif roll == 1 and world.stats.cash > 15:
				_informer_random(world)
			else:
				_interview_random(world, _random_known_fact(world))
		"sensational":
			if world.stats.cash > 12 and rng.chance(0.3):
				_informer_random(world)
			else:
				_interview_random(world, _random_known_fact(world))
		_:
			_cautious_day(world)


func _cautious_day(world) -> void:
	# 1. 有档案提示就去查
	for g in world.notebook():
		var e: Dictionary = g.event
		if e.soft or e.week_end <= world.week:
			continue
		for fid in e.facts:
			var f: Dictionary = world.facts[fid]
			if f.archive != "" and not world.known.get(fid, {"evidence": false}).evidence:
				var keeper_ok: bool = world.stats.cash >= 5
				for rid in world.living_ids():
					if world.residents[rid].keeper == f.archive and world.residents[rid].player_rel.trust >= 0.5:
						keeper_ok = true
				if keeper_ok:
					_log(world.act_archive(f.archive))
					return
	# 2. 有没验证的碎片就找人核实
	var unverified: Array = []
	for fid in world.known:
		if not world.is_verified(fid) and not world.event_of(fid).soft and world.event_of(fid).week_end > world.week:
			unverified.append(fid)
	if not unverified.is_empty():
		var fid: String = rng.pick(unverified)
		var subj: String = world.facts[fid].subject
		# 优先问当事人的朋友和同事
		var pool: Array = []
		for rid in world.living_ids():
			if rid == subj:
				continue
			var r: Dictionary = world.residents[rid]
			if subj in r.friends or subj in r.family or r.work == world.residents[subj].work:
				if world.where_is(rid) != "" and r.avoid_until <= world.week:
					pool.append(rid)
		if pool.is_empty():
			pool = _reachable(world)
		if not pool.is_empty():
			_log(world.act_interview(rng.pick(pool), fid))
			return
	# 3. 泛泛打听，优先邮差和多嘴的人
	_interview_random(world, "", true)


func _reachable(world) -> Array:
	var out: Array = []
	for rid in world.living_ids():
		var r: Dictionary = world.residents[rid]
		if world.where_is(rid) != "" and r.avoid_until <= world.week:
			out.append(rid)
	return out


func _interview_random(world, topic: String, prefer_gossip := false) -> void:
	var pool: Array = _reachable(world)
	if pool.is_empty():
		world.end_day()
		return
	if prefer_gossip:
		var g: Array = []
		for rid in pool:
			var r: Dictionary = world.residents[rid]
			if r.occ == "postman" or "gossip" in r.traits or r.occ == "barkeep":
				g.append(rid)
		if not g.is_empty() and rng.chance(0.7):
			pool = g
	_log(world.act_interview(rng.pick(pool), topic))


func _random_known_fact(world) -> String:
	var pool: Array = []
	for fid in world.known:
		var e: Dictionary = world.event_of(fid)
		if not e.soft and e.week_end > world.week:
			pool.append(fid)
	if pool.is_empty() or rng.chance(0.3):
		return ""
	return rng.pick(pool)


func _archive_any(world) -> void:
	var locs := ["post", "hall", "clinic", "store"]
	_log(world.act_archive(rng.pick(locs)))


func _informer_random(world) -> void:
	var pool: Array = world.living_ids()
	_log(world.act_informer(rng.pick(pool)))


# ------------------------------------------------------------ 晚上
func _want_night(world) -> bool:
	if world.nights_used >= world.MAX_NIGHTS:
		return false
	match strategy:
		"soft": return false
		"sensational": return true
		"random": return rng.chance(0.4)
		_:
			# 谨慎：有蹲守提示就去；否则每周听一次
			return _stakeout_target(world) != "" or world.nights_used == 0


func _stakeout_target(world) -> String:
	for g in world.notebook():
		var e: Dictionary = g.event
		if e.week_end <= world.week:
			continue
		for loc in e.witness:
			if not world.known.has(e.witness[loc]):
				return loc
	return ""


func _night_action(world) -> void:
	var loc: String = _stakeout_target(world)
	if loc != "" and (strategy == "cautious" or rng.chance(0.5)):
		_log(world.act_stakeout(loc))
	else:
		_log(world.act_eavesdrop())


# ------------------------------------------------------------ 排版
func _compose(world) -> Array:
	var candidates: Array = []
	for g in world.notebook():
		var e: Dictionary = g.event
		# 登过的事有了新料可以登续报（M4.1 起玩家能这么做），只登新料
		if e.printed and (e.soft or g.fresh.is_empty()):
			continue
		# 收了钱的事，煽动派和软新闻派就不登了（收钱照登是两头得罪，真人不会这么干）；随机派照样乱来
		if e.get("bribed_by", "") != "" and strategy in ["sensational", "soft"]:
			continue
		var fids: Array = []
		var all_verified := true
		var any_evidence := false
		for fid in (g.fresh if e.printed else g.facts):
			fids.append(fid)
			if not world.is_verified(fid):
				all_verified = false
			if world.known[fid].evidence:
				any_evidence = true
		candidates.append({"event": e, "facts": fids, "verified": all_verified, "evidence": any_evidence})
	var picked: Array = []
	match strategy:
		"cautious":
			for c in candidates:
				if c.event.soft:
					picked.append(_article(c, "calm", "named", false))
				else:
					var ok_facts: Array = []
					for fid in c.facts:
						if world.is_verified(fid):
							ok_facts.append(fid)
					if ok_facts.is_empty():
						continue
					c.facts = ok_facts
					picked.append(_article(c, "neutral", "named" if c.evidence else "alias", c.evidence))
		"sensational":
			for c in candidates:
				picked.append(_article(c, "hot", "named", c.evidence))
		"soft":
			for c in candidates:
				if c.event.soft:
					picked.append(_article(c, "calm", "named", false))
		"bold":
			for c in candidates:
				if c.event.soft:
					picked.append(_article(c, "neutral", "named", false))
					continue
				var two: Array = []
				for fid in c.facts:
					if world.known[fid].sources.size() >= 2:
						two.append(fid)
				if two.is_empty():
					continue
				c.facts = two
				picked.append(_article(c, "hot", "named", c.evidence))
		_:
			for c in candidates:
				if rng.chance(0.6):
					picked.append(_article(c, rng.pick(["calm", "neutral", "hot"]), rng.pick(["named", "alias", "anon"]), c.evidence and rng.chance(0.5)))
	# 按严重度排版位
	picked.sort_custom(func(a, b): return a.severity > b.severity)
	var slots := ["head", "second", "third", "small"]
	var out: Array = []
	for i in mini(picked.size(), 4):
		var a: Dictionary = picked[i]
		a.slot = slots[i]
		a.erase("severity")
		out.append(a)
	return out


func _article(c: Dictionary, tone: String, naming: String, evidence: bool) -> Dictionary:
	# 证据必须来自真正入选的碎片
	var has_ev := false
	for fid in c.facts:
		if _world.known[fid].evidence:
			has_ev = true
	return {"facts": c.facts, "tone": tone, "naming": naming, "evidence": evidence and has_ev, "severity": c.event.severity + (0.5 if c.verified else 0.0)}
