## 模拟世界：镇子、居民、事实、玩家知识、报纸结算。纯数据，可无头运行。
## 一切随机都走 self.rng；同一个种子 + 同一串玩家操作 = 同一局。
extends RefCounted

const Rng = preload("res://scripts/sim/rng.gd")
const NameGen = preload("res://scripts/sim/namegen.gd")
const T = preload("res://scripts/sim/tables.gd")
const Events = preload("res://scripts/sim/events.gd")
const TownGen = preload("res://scripts/sim/town_gen.gd")
const Relations = preload("res://scripts/sim/relations.gd")
const Needs = preload("res://scripts/sim/needs.gd")
const Population = preload("res://scripts/sim/population.gd")
const Election = preload("res://scripts/sim/election.gd")

const SLOT_NAMES := ["上午", "下午", "晚上"]
const DAY_NAMES := ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
const MAX_NIGHTS := 2  # 一周最多熬夜次数，超过就吃次日上午

var rng: Rng
var seed_value: int = 0
var config := {"total_weeks": 104, "ironman": true, "suicide": false}
var events_db: Events

var week := 1
var day := 1    # 1..7
var slot := 0   # 0 上午 1 下午 2 晚上
var actions_left := 2
var nights_used := 0
var morning_lost := false

var residents := {}
var facts := {}
var events: Array = []          # 活动中的事件实例
var archive_events: Array = []  # 已结束的事件实例
var known := {}                 # fid -> {sources, evidence, first_week}
var stats := {"credibility": 50.0, "circulation": 180.0, "cash": 30.0}
var ads := {}                   # rid -> {"paused_until": week}
var visitors: Array = []        # 周六夜来访队列
var pending: Array = []         # 延迟生效的反应 {week, kind, who, event}
var lawsuits: Array = []
var log: Array = []             # 故事日志（给人读）
var issues: Array = []          # 已印报纸
var letters: Array = []         # 本周一收到的信
var history: Array = []         # 每周三条主数值
var flags := {"burned_until": 0, "negative_weeks": 0, "lawsuits_lost": 0, "weeks_no_news": 0}
var game_over := ""
var player_name := "主编"
var paper_name := "灰河周报"

var next_event_id := 1
var next_resident_id := 0
var last_spawn := {}   # tid -> 上次触发的周，用于冷却
var next_fact_id := 1
var namegen: NameGen
var campaign := {}              # 选举期间的状态，见 election.gd
var needy: Array = []           # 本周需求长期不满的人，见 needs.gd
var actions: Array = []         # 玩家操作日志，存档就是它
var recording := true
var replay_error := ""


# ---------------------------------------------------------------- 生成
func _init(seed_in: int, cfg: Dictionary = {}) -> void:
	seed_value = seed_in
	rng = Rng.new(seed_in)
	for k in cfg:
		config[k] = cfg[k]
	namegen = NameGen.new(rng)
	events_db = Events.new()
	events_db.load_all()
	TownGen.generate(self)
	_start_week(true)


# ---------------------------------------------------------------- 查询
func living_ids() -> Array:
	var out: Array = []
	for rid in residents:
		var r: Dictionary = residents[rid]
		if r.alive and r.in_town:
			out.append(rid)
	return out


func res_name(rid: String) -> String:
	return residents[rid].name if residents.has(rid) else "？"


func event_of(fid: String) -> Dictionary:
	return event_by_id(facts[fid].event)


func event_by_id(eid: String) -> Dictionary:
	for e in events:
		if e.id == eid:
			return e
	for e in archive_events:
		if e.id == eid:
			return e
	return {}


func is_season(w: int) -> int:
	## 1 春 2 夏 3 秋 4 冬，一年 52 周，开局是春天
	return int(((w - 1) % 52) / 13.0) + 1


func season_name() -> String:
	return ["", "春", "夏", "秋", "冬"][is_season(week)]


func loc_name(loc: String) -> String:
	if loc.begins_with("home:"):
		return res_name(loc.substr(5)) + "家"
	var l := T.location_by_id(loc)
	return l.get("name", loc)


func people_at(loc: String) -> Array:
	var out: Array = []
	for rid in living_ids():
		if residents[rid].today[slot] == loc:
			out.append(rid)
	return out


func public_locations() -> Array:
	var out: Array = []
	for l in T.LOCATIONS:
		if l.id != "office":
			out.append(l.id)
	return out


## 玩家对一条事实的「验证分」：档案 2，亲眼 3，采访/来访/线人各 1（按人去重），偷听 0.5，匿名信 0，公开事实直接 3。
func verify_score(fid: String) -> float:
	if not known.has(fid):
		return 0.0
	var k: Dictionary = known[fid]
	var score := 0.0
	var seen := {}
	for s in k.sources:
		var key: String = s.kind + ":" + s.who
		if seen.has(key):
			continue
		seen[key] = true
		match s.kind:
			"witness": score += 3.0
			"archive": score += 2.0
			"public": score += 3.0
			"eavesdrop": score += 0.5
			"letter": score += 0.0
			_: score += 1.0
	return score


func is_verified(fid: String) -> bool:
	return verify_score(fid) >= 3.0


func visible_cred(fid: String) -> float:
	var best := 0.0
	for s in known.get(fid, {"sources": []}).sources:
		best = maxf(best, float(T.SOURCE_CRED[s.kind]))
	return best


## 选题簿：按事件分组的已知碎片，附提示。
func notebook() -> Array:
	var groups := {}
	for fid in known:
		var e := event_of(fid)
		if e.is_empty():
			continue
		if not groups.has(e.id):
			groups[e.id] = {"event": e, "facts": [], "hints": []}
		groups[e.id].facts.append(fid)
	var out: Array = []
	for eid in groups:
		var g: Dictionary = groups[eid]
		var e: Dictionary = g.event
		var active: bool = e.week_end > week
		for loc in e.witness:
			if not known.has(e.witness[loc]) and active:
				g.hints.append("晚上蹲守%s也许有发现" % loc_name(loc))
		for fid in e.facts:
			var f: Dictionary = facts[fid]
			if f.archive != "" and not known.get(fid, {"evidence": false}).evidence:
				g.hints.append("%s的档案里也许有记录" % loc_name(f.archive))
		out.append(g)
	return out


# ---------------------------------------------------------------- 一周的推进
func _start_week(first: bool) -> void:
	day = 1
	nights_used = 0
	letters.clear()
	_apply_pending()
	if not first:
		Population.tick_week(self)
		needy = Needs.tick_week(self)
		Relations.refresh_lists(self)
		Election.tick_week(self)
	_spawn_events(first)
	_expire_events()
	if first:
		letters.push_front("前任主编留下的信：邮差是朋友，有事先问他。锯木厂的广告别断，那是半个月的纸钱。酒馆晚上去听听，别信全部。头条空着，你自己填。")
	_anonymous_letters()
	_start_day()


func _start_day() -> void:
	slot = 0
	actions_left = 2
	if morning_lost:
		actions_left = 1
		slot = 1
		morning_lost = false
		log.append("第 %d 周 %s：熬夜太多，上午起不来。" % [week, DAY_NAMES[day]])
	_compute_whereabouts()
	_spread_rumors()
	_roll_witness_nights()


func _compute_whereabouts() -> void:
	var sunday := day == 7
	for rid in living_ids():
		var r: Dictionary = residents[rid]
		var home: String = "home:" + rid
		var work: String = r.work
		if work == "home":
			work = home
		var day_loc := work
		if sunday:
			day_loc = "church" if rng.chance(0.95 if "pious" in r.traits else 0.65) else home
		elif rng.chance(0.12):
			day_loc = home
		var afternoon: String = day_loc if sunday == false else home
		if r.occ in ["barkeep", "stationmaster", "grocer", "postman"] and not sunday:
			afternoon = work
		var night_p := 0.15
		if "drinker" in r.traits: night_p = 0.75
		elif "gossip" in r.traits: night_p = 0.45
		elif r.occ in ["veteran", "worker", "fisher", "drifter"]: night_p = 0.45
		if r.female and r.occ != "newcomer":
			night_p *= 0.35
		if r.occ == "barkeep":
			night_p = 1.0
		if sunday:
			night_p *= 0.5
		var night: String = "tavern" if rng.chance(night_p) else home
		r.today = [day_loc, afternoon, night]


## 流言传播：每天每人有概率把自己知道的一条事实讲给朋友或家人。
func _spread_rumors() -> void:
	for rid in living_ids():
		var r: Dictionary = residents[rid]
		if r.knows.is_empty():
			continue
		var p := 0.12
		if "gossip" in r.traits: p += 0.25
		if "tight" in r.traits: p -= 0.1
		if r.today[2] == "tavern": p += 0.15
		if not rng.chance(p):
			continue
		var fid: String = rng.pick(r.knows.keys())
		var f: Dictionary = facts[fid]
		# 自己的秘密不说，除非多嘴
		if f.subject == rid and f.secrecy == "secret" and not ("gossip" in r.traits):
			continue
		var pool: Array = r.friends + r.family
		if r.today[2] == "tavern":
			pool.append_array(people_at_night("tavern"))
		var pool2: Array = []
		for oid in pool:
			if oid != rid and residents.has(oid) and residents[oid].in_town:
				pool2.append(oid)
		if pool2.is_empty():
			continue
		residents[rng.pick(pool2)].knows[fid] = true


func people_at_night(loc: String) -> Array:
	var out: Array = []
	for rid in living_ids():
		if residents[rid].today[2] == loc:
			out.append(rid)
	return out


## 每天决定有目击碎片的事件今晚在不在现场发生。
func _roll_witness_nights() -> void:
	for e in events:
		e["tonight"] = {}
		for loc in e.witness:
			if rng.chance(0.45):
				e.tonight[loc] = e.witness[loc]


func _spawn_events(first: bool) -> void:
	var secret_tpls: Array = []
	var soft_tpls: Array = []
	for t in events_db.templates:
		if t.get("manual", false):
			continue
		if t.has("season"):
			var ok_season := false
			for sv in t.season:
				if int(sv) == is_season(week):
					ok_season = true
			if not ok_season:
				continue
		var active := false
		for e in events:
			if e.tid == t.id:
				active = true
		if active:
			continue
		var cooldown: int = int(t.get("cooldown", 4 if t.get("soft", false) else 8))
		if last_spawn.has(t.id) and week - int(last_spawn[t.id]) < cooldown:
			continue
		if t.get("soft", false):
			soft_tpls.append(t)
		else:
			secret_tpls.append(t)
	rng.shuffle(secret_tpls)
	rng.shuffle(soft_tpls)
	var want_secret := first or rng.chance(0.55 if events.size() < 4 else 0.3)
	var want_soft := first or rng.chance(0.6)
	# 需求驱动：谁的日子过不下去了，谁就铤而走险
	if not first and not needy.is_empty() and rng.chance(0.65):
		var tries := 0
		for item in needy:
			if tries >= 6:
				break
			tries += 1
			if residents[item.rid].busy_until > week:
				continue
			for t in secret_tpls:
				if not (item.need in t.get("driven_by", [])):
					continue
				var preset := {t.target: [item.rid]}
				var roles: Dictionary = events_db.cast_roles(t, self, preset)
				if roles.is_empty():
					continue
				spawn_instance(t, roles, {}, "%s的%s已经紧了 %d 周" % [res_name(item.rid), Needs.NEED_NAME[item.need], item.weeks])
				want_secret = false
				break
			if not want_secret:
				break
	if first:
		# 首周保底：挑一个严重度不超过 2 的秘密事件，并让邮差知道它的半公开碎片
		secret_tpls.sort_custom(func(a, b): return int(a.severity) < int(b.severity))
	if want_secret:
		for t in secret_tpls:
			if first and int(t.severity) > 2:
				continue
			var roles: Dictionary = events_db.cast_roles(t, self)
			if roles.is_empty():
				continue
			var inst: Dictionary = spawn_instance(t, roles)
			if first:
				for fid in inst.facts:
					if facts[fid].secrecy == "semi":
						for rid in living_ids():
							if residents[rid].occ == "postman":
								residents[rid].knows[fid] = true
			break
	if want_soft:
		for t in soft_tpls:
			var roles: Dictionary = events_db.cast_roles(t, self)
			if roles.is_empty():
				continue
			spawn_instance(t, roles)
			break


## 实例化一个事件并登记：软事件直接公开，秘密事件只记日志。reason 写进日志。
func spawn_instance(tpl: Dictionary, roles: Dictionary, extras: Dictionary = {}, reason: String = "") -> Dictionary:
	var inst: Dictionary = events_db.instantiate(tpl, roles, self, extras)
	events.append(inst)
	last_spawn[tpl.id] = week
	_apply_effects(tpl, inst)
	if inst.soft:
		for fid in inst.facts:
			_learn(fid, "public", "")
		log.append("第 %d 周：%s。" % [week, facts[inst.facts[0]].text])
	else:
		var why := "" if reason == "" else "%s，" % reason
		log.append("第 %d 周：%s镇上悄悄发生了「%s」（%s）。" % [week, why, inst.name, res_name(roles[inst.target][0])])
	return inst


## 模板的 effects：对 target 角色的即时后果。
func _apply_effects(tpl: Dictionary, inst: Dictionary) -> void:
	var fx: Dictionary = tpl.get("effects", {})
	if fx.is_empty():
		return
	var target: String = inst.roles[inst.target][0]
	var r: Dictionary = residents[target]
	if fx.has("wealth"):
		r.wealth = clampi(int(r.wealth) + int(fx.wealth), 0, 2)
	if fx.has("job"):
		if r.occ == "mayor":
			flags["mayor_vacant"] = true
		TownGen.change_job(self, target, str(fx.job))
	if fx.has("move"):
		var who: String = inst.roles[str(fx.move)][0]
		pending.append({"week": week + 2, "kind": "leave", "who": who, "event": inst.id})


func _expire_events() -> void:
	var keep: Array = []
	for e in events:
		if e.week_end <= week:
			archive_events.append(e)
			for role in e.roles:
				for rid in e.roles[role]:
					if residents[rid].busy_until <= e.week_end:
						residents[rid].busy_until = 0
		else:
			keep.append(e)
	events = keep


func _anonymous_letters() -> void:
	var p := 0.25
	if stats.credibility > 70:
		p += 0.2
	if not rng.chance(p):
		return
	# 偏向有仇的人写的信：从仇人知道的事实里挑
	var candidates: Array = []
	for e in events:
		for fid in e.facts + e.rumor_facts:
			if not known.has(fid):
				candidates.append(fid)
	if candidates.is_empty():
		return
	var fid: String = rng.pick(candidates)
	_learn(fid, "letter", "")
	letters.append("一封没有署名的信：「%s」" % facts[fid].text)


# ---------------------------------------------------------------- 玩家行动
func can_act_day() -> bool:
	return day <= 6 and slot <= 1 and actions_left > 0 and game_over == ""


func can_act_night() -> bool:
	return day <= 6 and game_over == "" and slot <= 2


func _spend_day_action() -> void:
	actions_left -= 1
	slot = 1 if actions_left == 1 else 2


## 结束今天（跳过晚上）。玩家操作，会记录。
func end_day() -> void:
	_record({"kind": "end_day"})
	_advance_day()


func _advance_day() -> void:
	if day >= 6:
		day = 7
		return
	day += 1
	_start_day()


func _spend_night() -> void:
	nights_used += 1
	if nights_used > MAX_NIGHTS:
		morning_lost = true
	_advance_day()


func _record(act: Dictionary) -> void:
	if recording:
		actions.append(act)


## 重放一条操作。返回是否成功。
func apply_action(act: Dictionary) -> bool:
	match str(act.get("kind", "")):
		"interview": return act_interview(str(act.rid), str(act.get("topic", ""))).ok
		"eavesdrop": return act_eavesdrop().ok
		"archive": return act_archive(str(act.loc)).ok
		"informer": return act_informer(str(act.target)).ok
		"stakeout": return act_stakeout(str(act.loc)).ok
		"end_day":
			end_day()
			return true
		"saturday":
			saturday_visitors()
			return true
		"deal":
			accept_deal({"who": str(act.who), "event": str(act.event), "offer": int(act.offer)})
			return true
		"print":
			var choice := {}
			for k in act.get("choice", {}):
				choice[k] = int(act.choice[k])
			for a in act.articles:
				if validate_article(a) != "":
					return false
			print_issue(act.articles, choice)
			return true
		"leave":
			leave_town()
			return true
	return false


## 当前时段某居民在哪（玩家可去）。
func where_is(rid: String) -> String:
	var r: Dictionary = residents[rid]
	if not r.alive or not r.in_town:
		return ""
	return r.today[mini(slot, 2)]


## 采访。topic 为空表示泛泛打听。返回 {ok, lines, gained}
func act_interview(rid: String, topic: String = "") -> Dictionary:
	var res := {"ok": false, "lines": [], "gained": []}
	if not can_act_day():
		res.lines.append("今天没有行动点了。")
		return res
	var r: Dictionary = residents.get(rid, {})
	if r.is_empty() or where_is(rid) == "":
		res.lines.append("找不到这个人。")
		return res
	_record({"kind": "interview", "rid": rid, "topic": topic})
	_spend_day_action()
	res.ok = true
	var loc := where_is(rid)
	res.lines.append("你在%s找到了%s（%s）。" % [loc_name(loc), r.name, r.occ_name])
	if r.avoid_until > week:
		res.lines.append("%s看见你就转身走了。" % r.name)
		return res
	var w := 0.3 + 0.45 * float(r.player_rel.like) + 0.25 * float(r.player_rel.trust)
	if "honest" in r.traits: w += 0.1
	if "tight" in r.traits: w -= 0.2
	if "gossip" in r.traits: w += 0.15
	var involved := false
	var tfact: Dictionary = facts.get(topic, {})
	if not tfact.is_empty():
		var e := event_of(topic)
		for role in e.roles:
			if rid in e.roles[role]:
				involved = true
		if tfact.subject == rid and tfact.secrecy == "secret":
			w -= 0.6
			r.aware = true
			_queue_plea_or_threat(rid, e)
		elif involved:
			w -= 0.25
			r.aware = true
	if stats.credibility < 30: w -= 0.15
	if stats.credibility > 70: w += 0.1
	if not rng.chance(clampf(w, 0.05, 0.95)):
		if involved and ("sly" in r.traits or not ("honest" in r.traits)) and rng.chance(0.5):
			var e := event_of(topic)
			var lie: Array = []
			for rf in e.rumor_facts:
				if not known.has(rf):
					lie.append(rf)
			if not lie.is_empty():
				var fid: String = rng.pick(lie)
				_learn(fid, "interview", rid)
				res.gained.append(fid)
				res.lines.append("%s压低声音：「你该去查查别的。%s。」" % [r.name, facts[fid].text])
				return res
		res.lines.append("%s含糊了几句，什么都没说。" % r.name)
		return res
	if tfact.is_empty():
		# 泛泛打听：给一条玩家不知道的、不是自己秘密的事实
		var pool: Array = []
		for fid in r.knows:
			if known.has(fid):
				continue
			var f: Dictionary = facts[fid]
			if f.subject == rid and f.secrecy != "public":
				continue
			pool.append(fid)
		if pool.is_empty():
			res.lines.append("%s聊了聊天气和河水，没什么新鲜事。" % r.name)
			r.player_rel.like = minf(1.0, r.player_rel.like + 0.03)
			return res
		var fid: String = rng.pick(pool)
		_learn(fid, "interview", rid)
		res.gained.append(fid)
		res.lines.append("%s说：「%s。」" % [r.name, facts[fid].text])
		return res
	# 有话头
	if r.knows.has(topic):
		_learn(topic, "interview", rid)
		res.gained.append(topic)
		res.lines.append("%s点头：「这事我也听说了。%s。」" % [r.name, tfact.text])
		var e := event_of(topic)
		var more: Array = []
		for fid in e.facts:
			if fid != topic and r.knows.has(fid) and not known.has(fid):
				more.append(fid)
		if not more.is_empty() and rng.chance(0.6):
			var fid2: String = rng.pick(more)
			_learn(fid2, "interview", rid)
			res.gained.append(fid2)
			res.lines.append("%s又补了一句：「%s。」" % [r.name, facts[fid2].text])
	else:
		res.lines.append("%s摇头：「这个我真不知道。」" % r.name)
		# 对方把话头记住了，可能传开
		if rng.chance(0.4):
			r.knows[topic] = true
	return res


## 酒馆偷听（晚上）。
func act_eavesdrop() -> Dictionary:
	var res := {"ok": false, "lines": [], "gained": []}
	if not can_act_night():
		res.lines.append("今晚不能行动。")
		return res
	var present := people_at_night("tavern")
	_record({"kind": "eavesdrop"})
	_spend_night_mark()
	res.ok = true
	res.lines.append("酒馆里有 %d 个人。" % present.size())
	for rid in rng.sample(present, 3):
		var r: Dictionary = residents[rid]
		if r.knows.is_empty() or not rng.chance(0.5):
			continue
		var fid: String = rng.pick(r.knows.keys())
		var e := event_of(fid)
		# 醉话走样：有概率变成谣言版本
		if not e.is_empty() and not e.rumor_facts.is_empty() and rng.chance(0.25):
			fid = rng.pick(e.rumor_facts)
		_learn(fid, "eavesdrop", rid)
		res.gained.append(fid)
		res.lines.append("隔壁桌%s在说：「%s。」" % [r.name, facts[fid].text])
	if res.gained.is_empty():
		res.lines.append("今晚只听到了牌桌上的争吵。")
	_spend_night()
	return res


func _spend_night_mark() -> void:
	slot = 2


## 查档案。
func act_archive(loc: String) -> Dictionary:
	var res := {"ok": false, "lines": [], "gained": []}
	if not can_act_day():
		res.lines.append("今天没有行动点了。")
		return res
	var l := T.location_by_id(loc)
	if not l.get("archive", false):
		res.lines.append("这里没有档案可查。")
		return res
	var keeper := ""
	for rid in living_ids():
		if residents[rid].keeper == loc:
			keeper = rid
	_record({"kind": "archive", "loc": loc})
	_spend_day_action()
	res.ok = true
	if keeper == "":
		res.lines.append("%s今天没人看门，你翻了一会儿什么也没找到。" % l.name)
		return res
	var k: Dictionary = residents[keeper]
	if k.player_rel.trust >= 0.5:
		res.lines.append("%s让你在后屋随便看。" % k.name)
	elif stats.cash >= 5:
		stats.cash -= 5
		k.player_rel.like = minf(1.0, k.player_rel.like + (0.1 if "greedy" in k.traits else 0.0))
		res.lines.append("你塞给%s五块钱，门开了。" % k.name)
	else:
		res.lines.append("%s说档案不外借，你也没钱打点。" % k.name)
		return res
	var found := 0
	for e in events:
		for fid in e.facts:
			if facts[fid].archive == loc and not known.get(fid, {"evidence": false}).evidence:
				_learn(fid, "archive", keeper)
				known[fid].evidence = true
				res.gained.append(fid)
				res.lines.append("记录：%s。" % facts[fid].text)
				found += 1
				# 看门人可能走漏风声
				if rng.chance(0.35):
					var subj: String = facts[fid].subject
					if subj in k.friends or subj in k.family:
						residents[subj].aware = true
						_queue_plea_or_threat(subj, e)
				if found >= 2:
					break
		if found >= 2:
			break
	if found == 0:
		res.lines.append("翻了一下午，没有和你在查的事有关的记录。")
	return res


## 线人：花钱买关于某人的一条事实。
func act_informer(target: String) -> Dictionary:
	var res := {"ok": false, "lines": [], "gained": []}
	if not can_act_day():
		res.lines.append("今天没有行动点了。")
		return res
	var informer := ""
	var best := -1.0
	for rid in living_ids():
		var r: Dictionary = residents[rid]
		if r.informer and float(r.player_rel.like) > best:
			best = r.player_rel.like
			informer = rid
	if informer == "":
		res.lines.append("镇上没有肯做线人的人。")
		return res
	if stats.cash < 3:
		res.lines.append("线人要三块钱，你拿不出来。")
		return res
	if not residents.has(target):
		res.lines.append("没有这个人。")
		return res
	_record({"kind": "informer", "target": target})
	_spend_day_action()
	stats.cash -= 3
	res.ok = true
	var inf: Dictionary = residents[informer]
	var pool: Array = []
	var rumor_pool: Array = []
	for e in events:
		for fid in e.facts:
			if facts[fid].subject == target and not known.has(fid):
				pool.append(fid)
		for fid in e.rumor_facts:
			if facts[fid].subject == target and not known.has(fid):
				rumor_pool.append(fid)
	var double_cross: bool = "greedy" in inf.traits and residents[target].power >= 2 and rng.chance(0.4)
	if (double_cross or pool.is_empty()) and not rumor_pool.is_empty():
		var fid: String = rng.pick(rumor_pool)
		_learn(fid, "informer", informer)
		res.gained.append(fid)
		res.lines.append("%s收了钱，说：「%s。」" % [inf.name, facts[fid].text])
	elif not pool.is_empty():
		var fid: String = rng.pick(pool)
		_learn(fid, "informer", informer)
		res.gained.append(fid)
		res.lines.append("%s收了钱，说：「%s。」" % [inf.name, facts[fid].text])
	else:
		res.lines.append("%s收了钱，想了半天：「这人干净得很。」" % inf.name)
	return res


## 蹲守（晚上）。
func act_stakeout(loc: String) -> Dictionary:
	var res := {"ok": false, "lines": [], "gained": []}
	if not can_act_night():
		res.lines.append("今晚不能行动。")
		return res
	_record({"kind": "stakeout", "loc": loc})
	_spend_night_mark()
	res.ok = true
	for e in events:
		if e.get("tonight", {}).has(loc):
			var fid: String = e.tonight[loc]
			_learn(fid, "witness", "")
			known[fid].evidence = true
			res.gained.append(fid)
			res.lines.append("你亲眼看见：%s。" % facts[fid].text)
	if res.gained.is_empty():
		res.lines.append("你在%s蹲到后半夜，只有风。" % loc_name(loc))
	_spend_night()
	return res


func _learn(fid: String, kind: String, who: String) -> void:
	if not known.has(fid):
		known[fid] = {"sources": [], "evidence": false, "first_week": week}
	known[fid].sources.append({"kind": kind, "who": who, "week": week})


func _queue_plea_or_threat(rid: String, e: Dictionary) -> void:
	for v in visitors:
		if v.who == rid:
			return
	var r: Dictionary = residents[rid]
	var kind := "plea"
	if r.bucket == "powerful" or r.bucket == "hot":
		kind = "threat"
	if r.bucket == "practical" and r.wealth >= 1:
		kind = "deal"
	visitors.append({"who": rid, "kind": kind, "event": e.id})


# ---------------------------------------------------------------- 周六夜来访
## 跳到周六晚上（若还在白天，放弃剩余行动点）。返回来访者列表，每项 {who, kind, event, lines, offer}
func saturday_visitors() -> Array:
	_record({"kind": "saturday"})
	while day < 6:
		_advance_day()
	day = 6
	slot = 2
	# 感激的人、广告主
	for rid in living_ids():
		var r: Dictionary = residents[rid]
		if r.advertiser and ads.has(rid) and ads[rid].paused_until <= week and ads[rid].paused_until > 0 and r.player_rel.like > 0.5:
			visitors.append({"who": rid, "kind": "ad", "event": ""})
			ads[rid].paused_until = 0
	var out: Array = []
	for v in visitors:
		var r: Dictionary = residents[v.who]
		if not r.in_town or not r.alive:
			continue
		var e := {}
		for ev in events + archive_events:
			if ev.id == v.event:
				e = ev
		var item := {"who": v.who, "kind": v.kind, "event": v.event, "lines": [], "offer": 0}
		match v.kind:
			"plea":
				item.lines.append("%s站在门口，帽子攥在手里：「我知道你在打听%s的事。求你，别登。」" % [r.name, e.get("name", "我")])
				if not e.is_empty():
					e.plea = v.who
			"threat":
				item.lines.append("%s没进门：「有些事登了，报社的窗户就不好修了。」" % r.name)
				r.player_rel.fear = minf(1.0, r.player_rel.fear + 0.2)
			"deal":
				item.offer = 6 + r.wealth * 4
				item.lines.append("%s放下一个信封，%d 块钱：「这周别写我，下周也别。」" % [r.name, item.offer])
			"tip":
				var pool: Array = []
				for fid in r.knows:
					if not known.has(fid):
						pool.append(fid)
				if pool.is_empty():
					item.lines.append("%s来道谢，带了一篮鸡蛋。" % r.name)
				else:
					var fid: String = rng.pick(pool)
					_learn(fid, "visitor", v.who)
					item.lines.append("%s来道谢，临走压低声音：「%s。」" % [r.name, facts[fid].text])
			"explain":
				item.lines.append("%s登门解释了半个钟头，说报上写的不全是那么回事。" % r.name)
				r.player_rel.like = minf(1.0, r.player_rel.like + 0.1)
			"expose":
				var given := 0
				for ev in events:
					for fid in ev.facts:
						var subj: String = facts[fid].subject
						if subj != v.who and (subj in r.enemies) and not known.has(fid) and given < 2:
							_learn(fid, "visitor", v.who)
							item.lines.append("%s咬着牙：「要写就写全。%s。」" % [r.name, facts[fid].text])
							given += 1
				if given == 0:
					item.lines.append("%s来了，想爆别人的料，却没什么可说的。" % r.name)
			"ad":
				item.lines.append("%s想在下期登个广告。" % r.name)
		out.append(item)
	visitors.clear()
	return out


## 接受私下交易。
func accept_deal(item: Dictionary) -> void:
	_record({"kind": "deal", "who": item.who, "event": item.event, "offer": item.offer})
	stats.cash += item.offer
	for e in events:
		if e.id == item.event:
			e.suppressed = true
			e.bribed_by = item.who
	log.append("第 %d 周：你收了%s的 %d 块钱。" % [week, res_name(item.who), item.offer])


# ---------------------------------------------------------------- 排版与结算
## articles: [{slot, facts:[fid], tone, naming, evidence}]
func validate_article(a: Dictionary) -> String:
	if a.facts.is_empty():
		return "没有碎片"
	var eid := ""
	for fid in a.facts:
		if not known.has(fid):
			return "你不知道这条碎片"
		var e := event_of(fid)
		if eid == "":
			eid = e.id
		elif eid != e.id:
			return "一条报道只能写一件事"
	if a.get("evidence", false):
		var has := false
		for fid in a.facts:
			if known[fid].evidence:
				has = true
		if not has:
			return "没有可附的证据"
	return ""


func headline_candidates(a: Dictionary) -> Array:
	var e := event_of(a.facts[0])
	return events_db.headlines(e, a.tone, a.naming, self)


## 付印并结算。返回 issue 字典。
func print_issue(articles: Array, headline_choice := {}) -> Dictionary:
	assert(day >= 6, "还没到周日")
	_record({"kind": "print", "articles": articles.duplicate(true), "choice": headline_choice.duplicate()})
	var issue := {"week": week, "articles": [], "consequences": [], "cred_delta": 0.0, "circ_delta": 0.0, "cash_delta": 0.0}
	var burned: bool = flags.burned_until > week
	if burned:
		issue.consequences.append("报社还是一片焦黑，这周没有报纸。")
		articles = []
	var circ_change := 0.0
	var cred_change := 0.0
	var had_news := false
	for a in articles:
		var err := validate_article(a)
		assert(err == "", err)
		var e := event_of(a.facts[0])
		if e.soft:
			a.naming = "named"  # 公开的事没有化名可言
		var cands := headline_candidates(a)
		var hl: String = cands[mini(headline_choice.get(a.slot, 0), cands.size() - 1)]
		var body: Array = []
		for fid in a.facts:
			var f: Dictionary = facts[fid]
			var role := _role_of(e, f.subject)
			body.append(Events.fill_text(f.text_tpl, e.roles, self, a.naming, role, "occ" if a.naming != "named" else "named", e.get("extras", {}), e.get("occ_at", {})))
		var exposure: float = T.SLOT_MULT[a.slot] * T.TONE_MULT[a.tone]
		var avg_truth := 0.0
		var gain_scale: float = (1.0 - stats.credibility / 150.0) * {"named": 1.0, "alias": 0.7, "anon": 0.4}[a.naming]
		for fid in a.facts:
			var f: Dictionary = facts[fid]
			avg_truth += f.truth
			var with_ev: bool = a.get("evidence", false) and known[fid].evidence
			if e.soft:
				pass  # 软新闻不证明什么，也不伤什么
			elif f.truth >= 0.8:
				cred_change += (4.0 if with_ev else (2.0 if is_verified(fid) else 1.0)) * gain_scale
			elif f.truth >= 0.5:
				cred_change += (1.0 if with_ev else 0.0) * gain_scale
			else:
				cred_change -= (1.0 - f.truth) * 10.0
		avg_truth /= a.facts.size()
		if a.tone == "hot" and not e.soft:
			cred_change -= 1.0
			for fid in a.facts:
				if not is_verified(fid):
					cred_change -= 0.5
		if not e.soft:
			had_news = true
		circ_change += T.SLOT_MULT[a.slot] / 3.0 * T.TONE_CIRC[a.tone] * (1.0 + 0.4 * e.severity) * {"named": 1.0, "alias": 0.7, "anon": 0.4}[a.naming]
		if not e.printed:
			var tpl: Dictionary = events_db.template_by_id(e.tid)
			for fu in tpl.get("followups", []):
				if fu.get("needs_evidence", false) and not a.get("evidence", false):
					continue
				if not rng.chance(float(fu.get("chance", 0.6))):
					continue
				var preset := {}
				for new_role in fu.map:
					preset[new_role] = e.roles[fu.map[new_role]]
				pending.append({"week": week + int(fu.get("delay", 2)), "kind": "followup", "who": "", "event": e.id, "tid": fu.tid, "preset": preset})
		e.printed = true
		e.printed_week = week
		var rec := {"slot": a.slot, "headline": hl, "body": body, "tone": a.tone, "naming": a.naming, "evidence": a.get("evidence", false), "event": e.id, "avg_truth": avg_truth, "facts": a.facts.duplicate()}
		issue.articles.append(rec)
		if not e.soft or a.slot == "head":
			log.append("第 %d 周 %s：%s" % [week, T.SLOT_NAME[a.slot], hl])
		var before: int = issue.consequences.size()
		_react_to_article(a, e, rec, exposure, issue)
		for i in range(before, issue.consequences.size()):
			if not e.soft:
				log.append("    → " + issue.consequences[i])
	# 发行量：涨幅受公信力和镇子规模约束，跌幅不受
	circ_change *= (0.25 + stats.credibility / 100.0)
	circ_change *= clampf(1.0 - stats.circulation / 600.0, 0.1, 1.0)
	if not had_news:
		flags.weeks_no_news += 1
		if flags.weeks_no_news >= 2:
			circ_change -= 0.03
	else:
		flags.weeks_no_news = 0
	if stats.credibility < 20: circ_change -= 0.02
	if stats.credibility < 10: circ_change -= 0.03
	if stats.credibility > 70: circ_change += 0.01
	if burned: circ_change -= 0.3
	stats.circulation = maxf(40.0, stats.circulation * (1.0 + circ_change))
	stats.credibility = clampf(stats.credibility + cred_change, 0.0, 100.0)
	# 现金
	var income: float = stats.circulation * 0.05
	var ad_income := 0.0
	for rid in ads:
		var r: Dictionary = residents[rid]
		if ads[rid].paused_until <= week and r.in_town and r.player_rel.like >= 0.3:
			ad_income += (2.0 + r.wealth * 1.0 + r.player_rel.like * 2.0) * clampf(stats.circulation / 180.0, 0.3, 2.0)
	var cost: float = 10.0 + stats.circulation * 0.02
	var cash_delta := (0.0 if burned else income + ad_income) - cost
	stats.cash += cash_delta
	issue.cred_delta = cred_change
	issue.circ_delta = circ_change
	issue.cash_delta = cash_delta
	issue["ad_income"] = ad_income
	issues.append(issue)
	# 社会扩散：主数值记录
	history.append({"week": week, "cred": stats.credibility, "circ": stats.circulation, "cash": stats.cash})
	# 破产线
	if stats.cash < 0:
		flags.negative_weeks += 1
	else:
		flags.negative_weeks = 0
	_check_game_over()
	if game_over == "":
		week += 1
		if week > config.total_weeks:
			game_over = "任期结束"
			log.append("第 %d 周：两年到了。你把钥匙留在桌上。" % (week - 1))
		else:
			_start_week(false)
	return issue


func _role_of(e: Dictionary, rid: String) -> String:
	for role in e.roles:
		if rid in e.roles[role]:
			return role
	return ""


func _react_to_article(a: Dictionary, e: Dictionary, rec: Dictionary, exposure: float, issue: Dictionary) -> void:
	var subjects := {}
	for fid in a.facts:
		subjects[facts[fid].subject] = true
	var naming_mult: float = T.NAMING_MULT[a.naming]
	for subj in subjects:
		var r: Dictionary = residents[subj]
		if not r.alive or not r.in_town:
			continue
		if e.positive or e.soft:
			# 被夸的人
			r.praised_week = week
			Election.on_article(self, subj, 0.0, true)
			r.player_rel.like = minf(1.0, r.player_rel.like + 0.2)
			r.player_rel.trust = minf(1.0, r.player_rel.trust + 0.1)
			if rng.chance(0.4):
				visitors.append({"who": subj, "kind": "tip", "event": e.id})
			if r.advertiser and ads.has(subj) and ads[subj].paused_until > week:
				ads[subj].paused_until = week
			issue.consequences.append("%s对报道很满意。" % r.name)
			continue
		var s: float = e.severity * naming_mult * (1.3 if a.tone == "hot" else 1.0) * (1.2 if a.get("evidence", false) else 1.0)
		s *= {"head": 1.0, "second": 0.8, "third": 0.6, "small": 0.3}[a.slot]
		# 读到了吗？点名的人几乎一定会被告知
		var p_read := 0.95 if a.naming == "named" else (0.7 if a.naming == "alias" else 0.4)
		if not rng.chance(p_read):
			issue.consequences.append("%s好像还没读到那篇报道。" % r.name)
			continue
		var level := "light"
		if s >= 2.2: level = "heavy"
		elif s >= 1.1: level = "medium"
		if e.bribed_by == subj:
			level = "heavy"
			issue.consequences.append("%s的钱你收了，报纸也印了。" % r.name)
		r.player_rel.like = maxf(0.0, r.player_rel.like - 0.3 * s)
		r.player_rel.trust = maxf(0.0, r.player_rel.trust - 0.2 * s)
		r.player_rel.fear = minf(1.0, r.player_rel.fear + 0.1 * s)
		r.exposed_week = week
		Relations.on_exposed(self, subj, s, e)
		Election.on_article(self, subj, s, false)
		var kind := _reaction(r.bucket, level)
		if kind == "suicide" and not config.suicide:
			kind = "leave"
		# 印了假话且对方有点地位：起诉概率
		if rec.avg_truth < 0.5 and a.naming == "named" and r.power >= 1 and rng.chance(0.7):
			kind = "sue"
		_schedule_reaction(kind, subj, e, issue, s, rec)


func _reaction(bucket: String, level: String) -> String:
	const TABLE := {
		"timid": {"light": "avoid", "medium": "leave", "heavy": "suicide"},
		"practical": {"light": "explain", "medium": "deal", "heavy": "expose"},
		"hot": {"light": "insult", "medium": "window", "heavy": "arson"},
		"powerful": {"light": "pull_ad", "medium": "pressure", "heavy": "sue"},
	}
	return TABLE[bucket][level]


func _schedule_reaction(kind: String, rid: String, e: Dictionary, issue: Dictionary, s: float, rec: Dictionary) -> void:
	var r: Dictionary = residents[rid]
	match kind:
		"avoid":
			r.avoid_until = week + 4
			issue.consequences.append("%s不会再跟你说话了，至少这个月。" % r.name)
		"leave":
			pending.append({"week": week + 2, "kind": "leave", "who": rid, "event": e.id})
			issue.consequences.append("%s开始打听火车时刻。" % r.name)
		"explain":
			visitors.append({"who": rid, "kind": "explain", "event": e.id})
			issue.consequences.append("%s说要来报社当面谈谈。" % r.name)
		"deal":
			visitors.append({"who": rid, "kind": "deal", "event": e.id})
			issue.consequences.append("%s托人带话，想「私下解决」。" % r.name)
		"expose":
			visitors.append({"who": rid, "kind": "expose", "event": e.id})
			issue.consequences.append("%s咬牙说：既然要写，那就都写出来。" % r.name)
		"insult":
			stats.circulation *= 0.98
			for fr in r.friends:
				residents[fr].player_rel.like = maxf(0.0, residents[fr].player_rel.like - 0.1)
			issue.consequences.append("%s在酒馆骂了你一晚上。" % r.name)
		"window":
			pending.append({"week": week + 1, "kind": "window", "who": rid, "event": e.id})
			issue.consequences.append("夜里有人在报社门口站了很久。")
		"arson":
			if rng.chance(0.5):
				pending.append({"week": week + 1, "kind": "arson", "who": rid, "event": e.id})
				issue.consequences.append("有人在报社后巷闻到了煤油味。")
			else:
				pending.append({"week": week + 1, "kind": "window", "who": rid, "event": e.id})
				issue.consequences.append("夜里有人在报社门口站了很久。")
		"pull_ad":
			if ads.has(rid):
				ads[rid].paused_until = week + 8
				issue.consequences.append("%s撤了广告。" % r.name)
			else:
				for fr in r.friends:
					if ads.has(fr):
						ads[fr].paused_until = week + 4
						issue.consequences.append("%s让%s撤了广告。" % [r.name, residents[fr].name])
						break
		"pressure":
			stats.circulation *= 0.92
			var n := 0
			for rid2 in living_ids():
				if residents[rid2].subscribed and (rid2 in r.friends or residents[rid2].work == r.work) and n < 6:
					residents[rid2].subscribed = false
					n += 1
			for fr in r.friends:
				if ads.has(fr):
					ads[fr].paused_until = week + 6
			issue.consequences.append("%s施压，退订单来了 %d 张。" % [r.name, n])
		"sue":
			lawsuits.append({"week": week + 3, "who": rid, "event": e.id, "truth": rec.avg_truth, "evidence": rec.evidence})
			issue.consequences.append("%s请了律师，传票三周后到。" % r.name)
		"suicide":
			pending.append({"week": week + 2, "kind": "suicide", "who": rid, "event": e.id})
			issue.consequences.append("%s这几天谁也不见。" % r.name)


func _apply_pending() -> void:
	var keep: Array = []
	for p in pending:
		if p.week > week:
			keep.append(p)
			continue
		if p.kind == "followup":
			var tpl: Dictionary = events_db.template_by_id(p.tid)
			var roles: Dictionary = events_db.cast_roles(tpl, self, p.preset) if not tpl.is_empty() else {}
			if not roles.is_empty():
				spawn_instance(tpl, roles)
			continue
		var r: Dictionary = residents[p.who]
		match p.kind:
			"leave":
				if not r.in_town:
					continue
				r.in_town = false
				if r.spouse != "":
					residents[r.spouse].spouse = ""
					residents[r.spouse]["widowed_week"] = week
					r.spouse = ""
				letters.append("%s坐上了南去的火车，没跟谁告别。" % r.name)
				log.append("第 %d 周：%s离镇。" % [week, r.name])
			"window":
				stats.cash -= 10
				letters.append("周一早上报社的玻璃碎了一地，修窗十块钱。")
				log.append("第 %d 周：报社窗户被砸。" % week)
			"arson":
				flags.burned_until = week + 2
				stats.cash -= 60
				letters.append("报社烧了。火是后半夜起的，印刷机还在，屋顶没了。重建要六十块钱，两周内印不了报。")
				log.append("第 %d 周：报社被纵火。" % week)
			"suicide":
				r.alive = false
				letters.append("讣告：%s。教堂周四办事。没有人提报纸。" % r.name)
				log.append("第 %d 周：%s去世。" % [week, r.name])
	pending = keep
	# 官司
	var keep_l: Array = []
	for l in lawsuits:
		if l.week > week:
			keep_l.append(l)
			continue
		var r: Dictionary = residents[l.who]
		var win: bool
		if l.evidence and l.truth >= 0.8: win = true
		elif l.truth < 0.5: win = false
		else: win = rng.chance(stats.credibility / 100.0)
		if win:
			stats.credibility = minf(100.0, stats.credibility + 10)
			letters.append("法院判了：%s告你诽谤，败诉。镇上都在传。" % r.name)
			r.player_rel.fear = minf(1.0, r.player_rel.fear + 0.3)
		else:
			stats.credibility = maxf(0.0, stats.credibility - 10)
			stats.cash -= 25
			flags.lawsuits_lost += 1
			letters.append("法院判了：你输给了%s，赔二十五块钱，登报道歉。" % r.name)
		log.append("第 %d 周：官司%s。" % [week, "赢了" if win else "输了"])
	lawsuits = keep_l
	# 读者来信
	_reader_letters()


func _reader_letters() -> void:
	var pool := living_ids()
	rng.shuffle(pool)
	var n := 0
	for rid in pool:
		if n >= 2:
			break
		var r: Dictionary = residents[rid]
		if not r.literate or not r.subscribed:
			continue
		if r.player_rel.like > 0.65 and flags.get("last_fan", "") != rid and rng.chance(0.5):
			letters.append("%s来信：报纸我每期都读，这周的还行。" % r.name)
			flags.last_fan = rid
			n += 1
		elif r.player_rel.like < 0.25:
			letters.append("%s来信：退订。别再往我家送了。" % r.name)
			r.subscribed = false
			n += 1


func _check_game_over() -> void:
	if flags.negative_weeks >= 4:
		game_over = "破产"
		log.append("第 %d 周：连续四周亏空，报纸停了。" % week)
	elif flags.lawsuits_lost >= 3:
		game_over = "停刊"
		log.append("第 %d 周：第三场官司输了，报纸被勒令停刊。" % week)
	elif flags.burned_until > week and stats.cash < 0 and flags.negative_weeks >= 2:
		game_over = "报社被毁"
		log.append("第 %d 周：报社烧了，没钱重建。" % week)


## 玩家主动离开。
func leave_town() -> void:
	_record({"kind": "leave"})
	game_over = "登上火车"
	log.append("第 %d 周：你登上了南去的火车。" % week)


## 年度回顾：所有头条按时间排。
func retrospective() -> Array:
	var out: Array = []
	for iss in issues:
		for a in iss.articles:
			if a.slot == "head":
				out.append("第 %d 周 · %s" % [iss.week, a.headline])
	return out
