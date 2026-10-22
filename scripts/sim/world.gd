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
const TE = preload("res://scripts/text/text_engine.gd")

## 续报：旧闻带来的发行量涨幅、对当事人的冲击，按首报的这个比例算
const FOLLOWUP_CIRC := 0.6
const FOLLOWUP_SEVERITY := 0.6
## 公信力：登错一条按 (1 - 真实度) × 这个数扣；没登错的一期往 CRED_RECOVER_TO 回差距的 CRED_RECOVER_RATE
const FALSE_PENALTY := 10.0
## 经济：每份纸墨钱；广告费随发行量涨，最多涨到起始的这么多倍（发行量大了钱不再白来）
const PRINT_COST := 0.02
const AD_CIRC_CAP := 2.0
## 好感回落：低于 GRUDGE_BASE 的每周回差距的这个比例
const GRUDGE_BASE := 0.45
const GRUDGE_FADE := 0.02
const GRUDGE_FADE_AD := 0.06
const CRED_RECOVER_TO := 40.0
const CRED_RECOVER_RATE := 0.04
const SLOT_NAMES := ["上午", "下午", "晚上"]
const DAY_NAMES := ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"]
const MAX_NIGHTS := 2  # 一周最多熬夜次数，超过就吃次日上午

var rng: Rng
var seed_value: int = 0
var config := {"total_weeks": 104, "ironman": true, "suicide": false, "lang": "zh"}
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
var letters: Array = []         # 本周一收到的信：{kind, roles, vars, id, week}，显示时由文本引擎渲染
var history: Array = []         # 每周三条主数值
var flags := {"burned_until": 0, "negative_weeks": 0, "lawsuits_lost": 0, "weeks_no_news": 0}
var game_over := ""
var player_name := "主编"
var paper_name := "灰河周报"
var lang := "zh"
var text_counter := 0           # 文本引擎的计数器，只影响措辞，不影响模拟
var text_memory := {}           # 语言 -> {模板原文: 上次用的周}，让报道半年内不重复同一句

var next_event_id := 1
var next_resident_id := 0
var last_spawn := {}   # tid -> 上次触发的周，用于冷却
var next_fact_id := 1
var namegen: NameGen
var campaign := {}              # 选举期间的状态，见 election.gd
var needy: Array = []           # 本周需求长期不满的人，见 needs.gd
var slept_in := 0              # 哪天上午睡过去了（周 × 10 + 天），给画面层提示用
var leads: Array = []           # 线头：交谈落空时对方指给你的人 {who, event, from, week}，见 _maybe_lead
var reluctant := {}             # 知道点什么、但不肯说的人：rid -> {event, why, who, week}，选题簿「按人」里显示
var greeted := {}               # rid -> 哪一周说过见面头一句（_personal_line）
var talked := {}                # rid -> 最近一次当面谈话的周（报道里的回应据此写，见 TE 的 resp_kind）
var actions: Array = []         # 玩家操作日志，存档就是它
var recording := true
var replay_error := ""


# ---------------------------------------------------------------- 生成
func _init(seed_in: int, cfg: Dictionary = {}) -> void:
	seed_value = seed_in
	rng = Rng.new(seed_in)
	for k in cfg:
		config[k] = cfg[k]
	lang = str(config.lang)
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


# ---- 给玩家看的文字：全部走文本引擎，按当前语言
func _nm(rid: String) -> String:
	return TE.person_name(self, rid, lang)


func _note(fid: String) -> String:
	return TE.fact_note(self, fid, lang)


func _ui(key: String, args: Dictionary = {}) -> String:
	return TE.ui(self, key, args, lang)


## 报道的后果。给玩家看的按当前语言；进故事日志的一律用中文，日志和语言无关（测试比对它）。
## args 里 name、who 传 rid，这里按语言换成名字。
func _cons(issue: Dictionary, key: String, args: Dictionary = {}) -> void:
	var shown := args.duplicate()
	var zh := args.duplicate()
	for k in ["name", "who"]:
		if args.has(k):
			shown[k] = TE.person_name(self, args[k], lang)
			zh[k] = TE.person_name(self, args[k], "zh")
	issue.consequences.append(_ui(key, shown))
	var line := str(TE.data("zh").ui.get(key, key))
	for k in zh:
		line = line.replace("{" + k + "}", str(zh[k]))
	issue.cons_log.append(line)


func _letter(kind: String, roles: Dictionary = {}, vars: Dictionary = {}) -> void:
	letters.append({"kind": kind, "roles": roles, "vars": vars, "id": letters.size(), "week": week})


## 本周的信，渲染成文字。
func render_letters(lang_override: String = "") -> Array:
	var lg := lang if lang_override == "" else lang_override
	var out: Array = []
	for L in letters:
		var vars: Dictionary = L.vars.duplicate()
		if vars.has("fact_id"):
			vars["fact"] = TE.fact_note(self, vars.fact_id, lg)
		var Lr: Dictionary = L.duplicate()
		Lr.vars = vars
		var r: Dictionary = TE.letter(self, Lr, lg)
		var text: String = r.text
		if r.from != "":
			text += TE.data(lg).ui.get("letter_sign", "——{from}").replace("{from}", r.from)
		out.append(text)
	return out


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
	# 谣言只靠人嘴传，凑不满三枚（第 2 轮：「三枚算坐实」的事，又有人写信说没发生过）
	if facts[fid].get("is_rumor", false):
		score = minf(score, 2.5)
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
			groups[e.id] = {"event": e, "facts": [], "hints": [], "fresh": []}
		groups[e.id].facts.append(fid)
		if not (fid in e.get("printed_facts", [])):
			groups[e.id].fresh.append(fid)
	var out: Array = []
	for eid in groups:
		var g: Dictionary = groups[eid]
		var e: Dictionary = g.event
		var active: bool = e.week_end > week
		for loc in e.witness:
			if not known.has(e.witness[loc]) and active:
				g.hints.append(_ui("hint_stakeout", {"place": TE.loc_label(self, loc, lang), "days": _nights_text(e, loc)}))
		for fid in e.facts:
			var f: Dictionary = facts[fid]
			if f.archive != "" and not known.get(fid, {"evidence": false}).evidence:
				g.hints.append(_ui("hint_archive", {"place": TE.loc_label(self, f.archive, lang)}))
		# 还有没有人能问：有人知道、肯拿出来说的碎片还剩几条（试玩：玩家拿登完的事问了十几个人，游戏没说「问完了」）
		g["more"] = 0
		if active and not e.soft:
			for fid in e.facts:
				if known.has(fid):
					continue
				for rid in living_ids():
					var refused: bool = reluctant.has(rid) and str(reluctant[rid].event) == str(e.id) and week - int(reluctant[rid].week) <= 1
					if residents[rid].in_town and residents[rid].knows.has(fid) and _can_tell(rid, fid) and not refused:
						g.more += 1
						break
			if g.more > 0:
				g.hints.push_front(_ui("hint_more"))
			else:
				g.hints.push_front(_ui("hint_done") if not g.hints.is_empty() else _ui("hint_all_known"))
		for rid in reluctant:
			var rl: Dictionary = reluctant[rid]
			if rl.event == e.id and week - int(rl.week) <= 3 and residents[rid].alive and residents[rid].in_town:
				g.hints.append(_ui("hint_reluctant", {"name": _nm(rid), "why": _ui("why_" + str(rl.why), {"who": _nm(str(rl.who)) if str(rl.who) != "" else ""})}))
		out.append(g)
	return out


# ---------------------------------------------------------------- 一周的推进
## 气会慢慢消：对报社的好感低于 GRUDGE_BASE 的人，每周回一点。广告主是生意人，回得快些（几个月后多半会回来登广告）
func _fade_grudges() -> void:
	for rid in residents:
		var r: Dictionary = residents[rid]
		var like := float(r.player_rel.like)
		if like < GRUDGE_BASE:
			r.player_rel.like = like + (GRUDGE_BASE - like) * (GRUDGE_FADE_AD if r.get("advertiser", false) else GRUDGE_FADE)


func _start_week(first: bool) -> void:
	day = 1
	nights_used = 0
	letters.clear()
	_apply_pending()
	if not first:
		_fade_grudges()
		Population.tick_week(self)
		needy = Needs.tick_week(self)
		Relations.refresh_lists(self)
		Election.tick_week(self)
	_spawn_events(first)
	_expire_events()
	_expire_leads()
	if first:
		letters.push_front({"kind": "predecessor", "roles": {}, "vars": {}, "id": -1, "week": week})
	_anonymous_letters()
	if not first:
		_rumor_hook()
	_start_day()


## 周一邮差捎一句风声：镇上有件还没登、你一条都不知道的事，就指给你一个知道它的人（附一个线头）。
## 一周最多一条，不说是什么事。M4.2：试玩里没有 ★ 的时候，玩家整天不知道干什么。
func _rumor_hook(with_letter := true) -> void:
	var postman := ""
	for rid in living_ids():
		if residents[rid].occ == "postman" and residents[rid].in_town:
			postman = rid
	if postman == "":
		return
	var led := {}
	for l in leads:
		led[l.event] = true
	for e in events:
		if e.soft or e.printed or e.week_end <= week + 1 or led.has(e.id):
			continue
		var seen := false
		for fid in e.facts:
			if known.has(fid):
				seen = true
		if seen:
			continue
		var cands: Array = []
		for rid in living_ids():
			if rid == postman or not residents[rid].in_town or residents[rid].work == "home" or not _role_of(e, rid).is_empty():
				continue
			for fid in e.facts:
				if residents[rid].knows.has(fid) and _can_tell(rid, fid):
					cands.append(rid)
					break
		if cands.is_empty():
			continue
		var who: String = rng.pick(cands)
		leads.append({"who": who, "event": e.id, "from": postman, "week": week})
		if with_letter:
			_letter("rumor_lead", {"who": postman, "tip": who})
		return


func _start_day() -> void:
	slot = 0
	actions_left = 2
	if morning_lost:
		actions_left = 1
		slot = 1
		morning_lost = false
		slept_in = week * 10 + day
		log.append("第 %d 周 %s：熬夜太多，上午起不来。" % [week, DAY_NAMES[day]])
	_compute_whereabouts()
	_spread_rumors()
	if day >= 2 and day <= 5:
		_midweek_hook()
	_roll_witness_nights()


## 周中：玩家手上既没有找得到人的线头，选题簿里的事也都问完了，就让镇上冒出一件玩家还没摸到的事，邮差路过时指个人。
## M4.2 第 2 轮：一件事两三条料，一两天就挖完，到下周一之前没事可干。
func _midweek_hook() -> void:
	for l in leads:
		var o: Dictionary = residents.get(l.who, {})
		if not o.is_empty() and o.alive and o.in_town and o.work != "home":
			return
	for g in notebook():
		if int(g.get("more", 0)) > 0:
			return
	var fresh := false
	for e in events:
		if e.soft or e.printed or e.week_end <= week + 1:
			continue
		var seen := false
		for fid in e.facts:
			if known.has(fid):
				seen = true
		if not seen:
			fresh = true
	# 只在这周手上没东西可登的时候补生一件，一周最多一件（补多了，挖得快、登得狠的人一周结几个仇，平衡里「敢说」派十局烧掉六局）
	var printable := false
	for e in events:
		if e.soft or e.printed:
			continue
		for fid in e.facts:
			if known.has(fid):
				printable = true
	if not fresh and not printable and int(flags.get("midweek_spawn", 0)) != week:
		flags["midweek_spawn"] = week
		_spawn_one_secret()
	_rumor_hook(false)


## 生一件秘密事件（不管周初掷过的骰）：季节对、没在跑、冷却过了、能凑齐角色的模板里挑一个
func _spawn_one_secret() -> void:
	var tpls: Array = []
	for t in events_db.templates:
		if t.get("manual", false) or t.get("soft", false):
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
		if active or (last_spawn.has(t.id) and week - int(last_spawn[t.id]) < int(t.get("cooldown", 8))):
			continue
		tpls.append(t)
	rng.shuffle(tpls)
	for t in tpls:
		var roles: Dictionary = events_db.cast_roles(t, self)
		if roles.is_empty():
			continue
		spawn_instance(t, roles, {}, "周中")
		return


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
## M4.2：每处一周固定两个晚上（事件生成时定好），不再每晚掷骰；选题簿的蹲守提示写明是哪两晚，蹲守成了推得出来的事
func _roll_witness_nights() -> void:
	for e in events:
		e["tonight"] = {}
		for loc in e.witness:
			if day in e.get("witness_days", {}).get(loc, []):
				e.tonight[loc] = e.witness[loc]


## 「周三、周五」
func _nights_text(e: Dictionary, loc: String) -> String:
	# 直接查表，不走 _ui：_ui 会给每一段补句号
	var ui: Dictionary = TE.data(lang).ui
	var names: Array = []
	for d in e.get("witness_days", {}).get(loc, []):
		names.append(str(ui.get("night_%d" % int(d), str(d))))
	return str(ui.get("nights_join", "、")).join(names)


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
	# 镇上在跑、还没登过的秘密少于两件时一定再生一件，免得玩家一整周无事可查（M4 老板试玩：四周只生出两件）
	var open_secrets := 0
	for e in events:
		if not e.soft and not e.printed and e.week_end > week:
			open_secrets += 1
	var want_secret := first or open_secrets < 2 or rng.chance(0.55 if events.size() < 4 else 0.3)
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
	_letter("anon_tip", {}, {"fact_id": fid})


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
## 先看对方手上有没有你要的，再看他肯不肯说（M4.2：原来先掷「肯不肯」，玩家分不清「不知道」和「不肯说」，推理推不起来）。
## 不知道的人明说不知道；知道不肯说的，说出为什么（是当事人、跟当事人沾亲带故、嘴紧、还在生报社的气），选题簿记下「这人知道点什么」。
func act_interview(rid: String, topic: String = "") -> Dictionary:
	var res := {"ok": false, "lines": [], "gained": []}
	if not can_act_day():
		res.lines.append(_ui("no_action_day"))
		return res
	var r: Dictionary = residents.get(rid, {})
	if r.is_empty() or where_is(rid) == "":
		res.lines.append(_ui("not_found"))
		return res
	_record({"kind": "interview", "rid": rid, "topic": topic})
	talked[rid] = week
	var loc := where_is(rid)
	_spend_day_action()
	res.ok = true
	res.lines.append(_ui("found_at", {"loc": TE.loc_label(self, loc, lang), "name": _nm(rid), "occ": TE.occ_label(self, rid, lang)}))
	if r.avoid_until > week:
		res.lines.append(_ui("avoids", {"name": _nm(rid)}))
		return res
	var greet := _personal_line(rid)
	if greet != "":
		res.lines.append(greet)
	# 顺着线头找来的：「是某某让我来问你的」，对方多半肯说
	var lead_event := ""
	for i in range(leads.size() - 1, -1, -1):
		if leads[i].who == rid:
			lead_event = leads[i].event
			leads.remove_at(i)
	var tfact: Dictionary = facts.get(topic, {})
	if not tfact.is_empty():
		var e := event_of(topic)
		if tfact.subject == rid and tfact.secrecy == "secret":
			r.aware = true
			if rid in e.roles.get(e.target, []):
				_queue_plea_or_threat(rid, e)
		elif not _role_of(e, rid).is_empty():
			r.aware = true
	# 一、他手上有什么
	var offer := ""          # 要说出来的那条
	var key := ""            # 用哪种说法
	var more: Array = []     # 话头对上了，可能顺嘴补的同一件事
	if not tfact.is_empty():
		if r.knows.has(topic):
			offer = topic
			key = "confirms"
			for fid in event_of(topic).facts:
				if fid != topic and _can_tell(rid, fid):
					more.append(fid)
		else:
			# 话头这一句他没听过，可同一件事（或线头上那件事）他知道别的
			var want := lead_event if lead_event != "" else str(tfact.event)
			var pool: Array = []
			for fid in r.knows:
				if facts[fid].event == want and _can_tell(rid, fid):
					pool.append(fid)
			if not pool.is_empty():
				offer = rng.pick(pool)
				key = "lead_redirect" if want != str(tfact.event) else "same_event"
	else:
		var pool: Array = []
		for fid in r.knows:
			if _can_tell(rid, fid):
				pool.append(fid)
		if lead_event != "":
			var on_lead: Array = []
			for fid in pool:
				if facts[fid].event == lead_event:
					on_lead.append(fid)
			if not on_lead.is_empty():
				pool = on_lead
		if not pool.is_empty():
			offer = rng.pick(pool)
			key = "tells"
		else:
			# 没有新料，但对方说起一件你听过的事：多一个来源，选题簿上多盖一枚章
			var echo: Array = []
			for fid in r.knows:
				if not known.has(fid) or facts[fid].secrecy == "public":
					continue
				if facts[fid].subject == rid or not _role_of(event_of(fid), rid).is_empty():
					continue
				var heard := false
				for s in known[fid].sources:
					if s.who == rid:
						heard = true
				if not heard and event_of(fid).week_end > week and not is_verified(fid):
					echo.append(fid)
			if not echo.is_empty():
				offer = rng.pick(echo)
				key = "echo"
	# 手上什么都没有：明说不知道
	if offer == "":
		if not tfact.is_empty():
			res.lines.append(_ui("denies_knowing", {"name": _nm(rid)}))
			# 对方把话头记住了，可能传开
			if rng.chance(0.4):
				r.knows[topic] = true
		elif greet == "":
			res.lines.append(_ui("small_talk", {"name": _nm(rid)}))
		r.player_rel.like = minf(1.0, r.player_rel.like + 0.03)
		_maybe_lead(rid, topic, res)
		return res
	# 二、肯不肯说
	var e: Dictionary = event_of(offer)
	var guard := _guard(rid, e)
	var w := 0.55 + 0.3 * float(r.player_rel.like) + 0.2 * float(r.player_rel.trust) - float(guard.p)
	if lead_event != "": w += 0.3
	if "honest" in r.traits: w += 0.1
	if "gossip" in r.traits: w += 0.15
	if "tight" in r.traits: w -= 0.25
	if stats.credibility < 30: w -= 0.15
	if stats.credibility > 70: w += 0.1
	if key == "echo":
		w += 0.2
	# 第一周的邮差：前任主编的信里说他可靠，开局的提示也让你先找他，不能让他把门关上
	if week == 1 and r.occ == "postman":
		w += 0.5
	if not rng.chance(clampf(w, 0.05, 0.95)):
		# 犯事的一方可能撒谎，把你往别处引
		if guard.why == "self" or guard.why == "kin":
			if ("sly" in r.traits or not ("honest" in r.traits)) and rng.chance(0.5):
				var lie: Array = []
				for rf in e.rumor_facts:
					if not known.has(rf) and facts[rf].subject != rid:
						lie.append(rf)
				if not lie.is_empty():
					var lf: String = rng.pick(lie)
					_learn(lf, "interview", rid)
					res.gained.append(lf)
					res.lines.append(_ui("lie", {"name": _nm(rid), "fact": TE.fact_note_by(self, lf, rid, lang)}))
					return res
		var why: String = guard.why
		if why == "" and float(r.player_rel.like) < 0.3:
			why = "grudge"
		if why == "" and "tight" in r.traits:
			why = "tight"
		if why == "involved" or why == "":
			why = "plain"
		res.lines.append(_ui("refuse_" + why, {"name": _nm(rid), "who": _nm(str(guard.who)) if str(guard.who) != "" else ""}))
		if key != "echo":
			reluctant[rid] = {"event": e.id, "why": why, "who": str(guard.who), "week": week}
		return res
	reluctant.erase(rid)
	_learn(offer, "interview", rid)
	res.gained.append(offer)
	res.lines.append(_ui(_own_key(key, offer, rid), {"name": _nm(rid), "fact": TE.fact_note_by(self, offer, rid, lang)}))
	if not more.is_empty() and rng.chance(0.6):
		var fid2: String = rng.pick(more)
		_learn(fid2, "interview", rid)
		res.gained.append(fid2)
		res.lines.append(_ui(_own_key("adds", fid2, rid), {"name": _nm(rid), "fact": TE.fact_note_by(self, fid2, rid, lang)}))
	return res


## 碎片里说的就是说话人自己（他的车、他诊所的记录）：不用「我听说」的口气，换亲口说的说法（第 2 轮：「我只听说，面粉搬上了我的车」）
func _own_key(key: String, fid: String, rid: String) -> String:
	if TE.fact_note(self, fid, lang).contains(_nm(rid)) and TE.data(lang).ui.has(key + "_own"):
		return key + "_own"
	return key


## 这条碎片他会不会拿出来说：玩家还不知道；不是他自己的秘密；犯事的一方不会自己招认
func _can_tell(rid: String, fid: String) -> bool:
	if known.has(fid):
		return false
	var f: Dictionary = facts[fid]
	if f.subject == rid and f.secrecy != "public":
		return false
	var e := event_of(fid)
	if not e.is_empty() and f.secrecy != "public" and rid in e.roles.get(e.target, []):
		return false
	return true


## 他跟这件事是什么关系：是当事人、当事人的家里人或朋友、牵扯其中。p 是不肯说的程度
func _guard(rid: String, e: Dictionary) -> Dictionary:
	var tgt: Array = e.roles.get(e.target, [])
	if rid in tgt:
		return {"p": 0.7, "why": "self", "who": rid}
	for t in tgt:
		if rid in residents[t].family:
			return {"p": 0.4, "why": "kin", "who": t}
	for t in tgt:
		if rid in residents[t].friends:
			return {"p": 0.3, "why": "friend", "who": t}
	if not _role_of(e, rid).is_empty():
		return {"p": 0.2, "why": "involved", "who": ""}
	return {"p": 0.0, "why": "", "who": ""}


## 见面头一句：这个人最近跟报社、跟报上登的事有什么瓜葛（试玩：写信道谢的新郎，当面只问报纸什么时候涨价）。
## 一个人一周只说一次。不碰随机数。
func _personal_line(rid: String) -> String:
	if int(greeted.get(rid, 0)) == week:
		return ""
	var r: Dictionary = residents[rid]
	var line := ""
	for e in events + archive_events:
		var role := _role_of(e, rid)
		if role == "":
			continue
		if e.printed and week - int(e.printed_week) <= 4:
			if e.soft:
				line = _ui("mem_soft_printed", {"name": _nm(rid)})
			elif role == e.target:
				line = _ui("mem_target_cold", {"name": _nm(rid)}) if float(r.player_rel.like) < 0.4 else _ui("mem_target_polite", {"name": _nm(rid)})
			else:
				line = _ui("mem_side_printed", {"name": _nm(rid)})
			break
		if e.soft and not e.printed and e.week_end > week and e.get("positive", false):
			line = _ui("mem_soft_soon", {"name": _nm(rid)})
			break
	if line == "" and float(r.player_rel.like) < 0.3:
		line = _ui("mem_grudge", {"name": _nm(rid)})
	if line != "":
		greeted[rid] = week
	return line


## 交谈落空时，对方可能给你指个人：一个知道某件你还不知道的事的人。
## 有话头时优先指向同一件事；对方更可能指自己认识的人（家人、朋友、同事）。当事人不会被指来说自己的秘密。
func _maybe_lead(rid: String, topic: String, res: Dictionary) -> void:
	var r: Dictionary = residents[rid]
	var p := 0.35 + 0.4 * float(r.player_rel.like)
	if "gossip" in r.traits: p += 0.15
	if "tight" in r.traits: p -= 0.15
	if not rng.chance(clampf(p, 0.1, 0.9)):
		return
	var want_event: String = facts[topic].event if facts.has(topic) else ""
	var led := {}
	for l in leads:
		led[l.who] = true
	var who_list: Array = []
	var ev_list: Array = []
	var weights: Array = []
	for oid in living_ids():
		if oid == rid or led.has(oid):
			continue
		var o: Dictionary = residents[oid]
		var best_ev := ""
		var best_w := 0.0
		for fid in o.knows:
			if known.has(fid):
				continue
			var f: Dictionary = facts[fid]
			if f.subject == oid and f.secrecy != "public":
				continue
			var e := event_of(fid)
			if e.is_empty() or e.week_end <= week:
				continue
			var wt := 3.0 if e.id == want_event else (1.0 if not e.soft else 0.4)
			if wt > best_w:
				best_w = wt
				best_ev = e.id
		if best_ev == "":
			continue
		if oid in r.family or oid in r.friends or o.work == r.work:
			best_w *= 2.0
		# 指一个整天在家、玩家进不去的人没有用
		var out_today := false
		for sl in [slot, mini(slot + 1, 1)]:
			var place: String = o.today[sl]
			if place != "" and not place.begins_with("home:"):
				out_today = true
		if not out_today:
			continue
		who_list.append(oid)
		ev_list.append(best_ev)
		weights.append(best_w)
	if who_list.is_empty():
		return
	var i := rng.weighted(weights)
	var oid: String = who_list[i]
	leads.append({"who": oid, "event": ev_list[i], "from": rid, "week": week})
	res["lead"] = oid
	var key := "lead_topic" if ev_list[i] == want_event and want_event != "" else "lead"
	res.lines.append(_ui(key, {"name": _nm(rid), "who": _nm(oid), "occ": TE.occ_label(self, oid, lang)}))


## 线头放三周就凉了；人走了、死了的线头作废
func _expire_leads() -> void:
	var keep: Array = []
	for l in leads:
		var o: Dictionary = residents.get(l.who, {})
		if week - int(l.week) <= 3 and not o.is_empty() and o.alive and o.in_town:
			keep.append(l)
	leads = keep


## 酒馆偷听（晚上）。
func act_eavesdrop() -> Dictionary:
	var res := {"ok": false, "lines": [], "gained": []}
	if not can_act_night():
		res.lines.append(_ui("no_action_night"))
		return res
	var present := people_at_night("tavern")
	_record({"kind": "eavesdrop"})
	_spend_night_mark()
	res.ok = true
	res.lines.append(_ui("tavern_count", {"n": present.size()}))
	for rid in rng.sample(present, 3):
		var r: Dictionary = residents[rid]
		if r.knows.is_empty() or not rng.chance(0.5):
			continue
		# 酒客多半说你还没听过的；自己的丑事不会喝着酒说出来（第 2 轮：「火车晚点」一字不差听了四回、老板在自己店里说自己出千）
		var fresh: Array = []
		var old: Array = []
		for k in r.knows:
			if not _can_tell(rid, k) and not known.has(k):
				continue
			if known.has(k):
				if facts[k].secrecy != "public":
					old.append(k)
			else:
				fresh.append(k)
		if fresh.is_empty() and (old.is_empty() or not rng.chance(0.3)):
			continue
		var fid: String = rng.pick(fresh) if not fresh.is_empty() else rng.pick(old)
		var e := event_of(fid)
		# 醉话走样：有概率变成谣言版本
		if not e.is_empty() and not e.rumor_facts.is_empty() and rng.chance(0.15):
			fid = rng.pick(e.rumor_facts)
		_learn(fid, "eavesdrop", rid)
		res.gained.append(fid)
		res.lines.append(_ui("overheard", {"name": _nm(rid), "fact": TE.fact_note_by(self, fid, rid, lang)}))
	if res.gained.is_empty():
		res.lines.append(_ui("tavern_nothing"))
	_spend_night()
	return res


func _spend_night_mark() -> void:
	slot = 2


## 查档案。
func act_archive(loc: String) -> Dictionary:
	var res := {"ok": false, "lines": [], "gained": []}
	if not can_act_day():
		res.lines.append(_ui("no_action_day"))
		return res
	var l := T.location_by_id(loc)
	if not l.get("archive", false):
		res.lines.append(_ui("no_archive"))
		return res
	var keeper := ""
	for rid in living_ids():
		if residents[rid].keeper == loc:
			keeper = rid
	_record({"kind": "archive", "loc": loc})
	_spend_day_action()
	res.ok = true
	if keeper == "":
		res.lines.append(_ui("archive_unattended", {"place": TE.loc_label(self, loc, lang)}))
		return res
	var k: Dictionary = residents[keeper]
	if k.player_rel.trust >= 0.5:
		res.lines.append(_ui("archive_open", {"name": _nm(keeper)}))
	elif stats.cash >= 5:
		stats.cash -= 5
		k.player_rel.like = minf(1.0, k.player_rel.like + (0.1 if "greedy" in k.traits else 0.0))
		res.lines.append(_ui("archive_bribe", {"name": _nm(keeper)}))
	else:
		res.lines.append(_ui("archive_refused", {"name": _nm(keeper)}))
		return res
	var found := 0
	for e in events:
		for fid in e.facts:
			if facts[fid].archive == loc and not known.get(fid, {"evidence": false}).evidence:
				_learn(fid, "archive", keeper)
				known[fid].evidence = true
				res.gained.append(fid)
				res.lines.append(_ui("archive_record", {"fact": _note(fid)}))
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
		res.lines.append(_ui("archive_nothing"))
	return res


## 线人：花钱买关于某人的一条事实。
func act_informer(target: String) -> Dictionary:
	var res := {"ok": false, "lines": [], "gained": []}
	if not can_act_day():
		res.lines.append(_ui("no_action_day"))
		return res
	var informer := ""
	var best := -1.0
	for rid in living_ids():
		var r: Dictionary = residents[rid]
		if r.informer and float(r.player_rel.like) > best:
			best = r.player_rel.like
			informer = rid
	if informer == "":
		res.lines.append(_ui("no_informer"))
		return res
	if stats.cash < 3:
		res.lines.append(_ui("informer_broke"))
		return res
	if not residents.has(target):
		res.lines.append(_ui("no_such_person"))
		return res
	_record({"kind": "informer", "target": target})
	_spend_day_action()
	stats.cash -= 3
	res.ok = true
	var inf: Dictionary = residents[informer]
	var pool: Array = []
	var rumor_pool: Array = []
	# 这人身上的事：碎片说的是他，或者他就是犯事的一方（试玩：偷猎的人被说成「干净得很」，因为碎片的主语是收鹿皮的店）
	var involved := false
	for e in events:
		var his: bool = not e.soft and not _role_of(e, target).is_empty()
		for fid in e.facts:
			if facts[fid].subject == target or his:
				involved = true
				if not known.has(fid):
					pool.append(fid)
		for fid in e.rumor_facts:
			if facts[fid].subject == target and not known.has(fid):
				rumor_pool.append(fid)
	var double_cross: bool = "greedy" in inf.traits and residents[target].power >= 2 and rng.chance(0.4)
	if (double_cross or pool.is_empty()) and not rumor_pool.is_empty():
		var fid: String = rng.pick(rumor_pool)
		_learn(fid, "informer", informer)
		res.gained.append(fid)
		res.lines.append(_ui("informer_says", {"name": _nm(informer), "fact": _note(fid)}))
	elif not pool.is_empty():
		var fid: String = rng.pick(pool)
		_learn(fid, "informer", informer)
		res.gained.append(fid)
		res.lines.append(_ui("informer_says", {"name": _nm(informer), "fact": _note(fid)}))
	elif involved:
		res.lines.append(_ui("informer_known", {"name": _nm(informer)}))
	else:
		res.lines.append(_ui("informer_nothing", {"name": _nm(informer)}))
	return res


## 蹲守（晚上）。
func act_stakeout(loc: String) -> Dictionary:
	var res := {"ok": false, "lines": [], "gained": []}
	if not can_act_night():
		res.lines.append(_ui("no_action_night"))
		return res
	_record({"kind": "stakeout", "loc": loc})
	_spend_night_mark()
	res.ok = true
	for e in events:
		if e.get("tonight", {}).has(loc):
			var fid: String = e.tonight[loc]
			var seen_before := false
			for s in known.get(fid, {"sources": []}).sources:
				if s.kind == "witness":
					seen_before = true
			if seen_before:
				res.lines.append(_ui("witnessed_again", {"fact": _note(fid)}))
				continue
			_learn(fid, "witness", "")
			known[fid].evidence = true
			res.gained.append(fid)
			res.lines.append(_ui("witnessed", {"fact": _note(fid)}))
	if res.gained.is_empty():
		var hinted := ""
		for e in events:
			if e.witness.has(loc) and not e.get("tonight", {}).has(loc) and not known.has(e.witness[loc]):
				for fid in e.facts:
					if known.has(fid):
						hinted = _nights_text(e, loc)
		if hinted != "":
			res.lines.append(_ui("stakeout_wrong_night", {"place": TE.loc_label(self, loc, lang), "days": hinted}))
		elif res.lines.is_empty():
			res.lines.append(_ui("stakeout_nothing", {"place": TE.loc_label(self, loc, lang)}))
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
		var item := {"who": v.who, "kind": v.kind, "event": v.event, "lines": [], "offer": 0, "fact": "", "facts": []}
		# 当事人上过门：报道里不能再写「本人还没有回应」（第 2 轮：前一晚刚上门认错，稿子写没回应）
		if not e.is_empty() and v.who in e.roles.get(e.target, []):
			e["visited"] = true
		if v.has("subject"):
			item["subject"] = v.subject
		match v.kind:
			"plea":
				if not e.is_empty():
					e.plea = v.who
			"threat":
				r.player_rel.fear = minf(1.0, r.player_rel.fear + 0.2)
			"deal":
				item.offer = 6 + r.wealth * 4
			"tip":
				var pool: Array = []
				for fid in r.knows:
					var fs: String = facts[fid].subject
					# 不会把自己和家里人的事说出去
					if not known.has(fid) and fs != v.who and not (fs in r.family):
						pool.append(fid)
				if not pool.is_empty():
					var fid: String = rng.pick(pool)
					_learn(fid, "visitor", v.who)
					item.fact = fid
			"explain":
				r.player_rel.like = minf(1.0, r.player_rel.like + 0.1)
				# 上门解释的人总得说点什么：挑一条他知道、你还不知道、又不往自己身上揽的（第 2 轮：「讲到天黑」，一个字都没给玩家看）
				if not e.is_empty():
					var side: Array = []
					for fid in e.facts:
						if r.knows.has(fid) and _can_tell(v.who, fid):
							side.append(fid)
					if not side.is_empty():
						var fid: String = rng.pick(side)
						_learn(fid, "visitor", v.who)
						item.fact = fid
			"expose":
				for ev in events:
					for fid in ev.facts:
						var subj: String = facts[fid].subject
						if subj != v.who and (subj in r.enemies) and not known.has(fid) and item.facts.size() < 2:
							_learn(fid, "visitor", v.who)
							item.facts.append(fid)
				if not item.facts.is_empty():
					item.fact = item.facts[0]
		item.lines = TE.visitor_lines(self, item, lang)
		for i in range(1, item.facts.size()):
			var more := item.duplicate()
			more.kind = "expose_more"
			more.fact = item.facts[i]
			item.lines.append_array(TE.visitor_lines(self, more, lang))
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
	return TE.headline_candidates(self, e, a, lang)


## 排版台预览：按付印时的顺序生成每篇的候选标题和正文，不改任何状态。
## 付印时前一篇会记下用过的句子，影响后一篇的措辞，所以必须整期一起预览，预览才和印出来的逐字相同。
## 返回 [{candidates: [String], headline, paragraphs}]，和 articles 一一对应。
func preview_issue(articles: Array, headline_choice := {}) -> Array:
	var saved: Dictionary = text_memory.duplicate(true)
	var out: Array = []
	for a0 in articles:
		var a: Dictionary = a0.duplicate(true)
		var e := event_of(a.facts[0])
		if e.soft:
			a.naming = "named"
		a["choice"] = int(headline_choice.get(a.slot, 0))
		a["remember"] = true
		var cands: Array = TE.headline_candidates(self, e, a, lang)
		var art: Dictionary = TE.article(self, e, a, lang)
		out.append({"candidates": cands, "headline": art.headline, "paragraphs": art.paragraphs})
	text_memory = saved
	return out


## 付印并结算。返回 issue 字典。
func print_issue(articles: Array, headline_choice := {}) -> Dictionary:
	assert(day >= 6, "还没到周日")
	_record({"kind": "print", "articles": articles.duplicate(true), "choice": headline_choice.duplicate()})
	var issue := {"week": week, "articles": [], "consequences": [], "cons_log": [], "cred_delta": 0.0, "circ_delta": 0.0, "cash_delta": 0.0}
	var burned: bool = flags.burned_until > week
	if burned:
		_cons(issue, "cons_burned")
		articles = []
	var circ_change := 0.0
	var cred_change := 0.0
	var had_news := false
	var soft_n := 0
	var circ_hot := 0.0
	var printed_false := false
	for a in articles:
		var err := validate_article(a)
		assert(err == "", err)
		var e := event_of(a.facts[0])
		if e.soft:
			a.naming = "named"  # 公开的事没有化名可言
		# 续报：早先登过的事又登新料。旧闻卖得少些，当事人已经挨过一回，这一回的冲击也轻些
		var is_fu: bool = e.printed and int(e.get("printed_week", week)) < week
		var ra: Dictionary = a.duplicate()
		ra["choice"] = int(headline_choice.get(a.slot, 0))
		ra["remember"] = true
		var art: Dictionary = TE.article(self, e, ra, lang)
		var hl: String = art.headline
		var body: Array = art.paragraphs
		# 故事日志只给开发者看，固定用中文，这样换语言不会改变日志
		var rl: Dictionary = ra.duplicate()
		rl["use_memory"] = false
		rl["remember"] = false
		var log_cands: Array = TE.headline_candidates(self, e, rl, "zh")
		var hl_log: String = str(log_cands[clampi(int(ra.choice), 0, log_cands.size() - 1)]) if not log_cands.is_empty() else hl
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
				# 登错了，镇上会记住。没坐实、语气也不煽动的，报上等于标了「尚待查证」，记得轻一半；煽动着登错的记得最重
				var miss: float = (1.0 - f.truth) * FALSE_PENALTY
				if a.tone == "hot":
					miss *= 1.2
				elif not is_verified(fid):
					miss *= 0.5
				cred_change -= miss
				printed_false = true
		avg_truth /= a.facts.size()
		if a.tone == "hot" and not e.soft:
			cred_change -= 1.0
			for fid in a.facts:
				if not is_verified(fid):
					cred_change -= 0.5
		if not e.soft:
			had_news = true
		else:
			soft_n += 1
		var gain: float = T.SLOT_MULT[a.slot] / 3.0 * T.TONE_CIRC[a.tone] * (1.0 + 0.4 * e.severity) * {"named": 1.0, "alias": 0.7, "anon": 0.4}[a.naming] * (FOLLOWUP_CIRC if is_fu else 1.0)
		if a.tone == "hot":
			circ_hot += gain
		else:
			circ_change += gain
		if not e.printed:
			e["first_printed_week"] = week
		# 后续事件（检查员上门之类）首报和续报都能引出：首报没附证据、续报附上了，也该有下文。
		# 每种只掷一次骰子（够条件的那一期掷），和以前「首报掷一次」的概率一样
		var rolled: Array = e.get("followups_rolled", [])
		var tpl: Dictionary = events_db.template_by_id(e.tid)
		for fu in tpl.get("followups", []):
			if fu.tid in rolled:
				continue
			if fu.get("needs_evidence", false) and not a.get("evidence", false):
				continue
			rolled.append(fu.tid)
			if not rng.chance(float(fu.get("chance", 0.6))):
				continue
			var preset := {}
			for new_role in fu.map:
				preset[new_role] = e.roles[fu.map[new_role]]
			pending.append({"week": week + int(fu.get("delay", 2)), "kind": "followup", "who": "", "event": e.id, "tid": fu.tid, "preset": preset})
		e["followups_rolled"] = rolled
		e.printed = true
		e.printed_week = week
		var pf: Array = e.get("printed_facts", [])
		for fid in a.facts:
			if not (fid in pf):
				pf.append(fid)
		e["printed_facts"] = pf
		var rec := {"slot": a.slot, "headline": hl, "body": body, "tone": a.tone, "naming": a.naming, "evidence": a.get("evidence", false), "event": e.id, "avg_truth": avg_truth, "facts": a.facts.duplicate(), "choice": ra.choice, "reroll": int(a.get("reroll", 0)), "followup": is_fu}
		issue.articles.append(rec)
		if not e.soft or a.slot == "head":
			log.append("第 %d 周 %s：%s" % [week, T.SLOT_NAME[a.slot], hl_log])
		var before: int = issue.consequences.size()
		_react_to_article(a, e, rec, exposure, issue)
		for i in range(before, issue.consequences.size()):
			if not e.soft:
				log.append("    → " + issue.cons_log[i])
	# 发行量：涨幅受公信力和镇子规模约束，跌幅不受
	# 克制、中立的报道靠公信力卖；煽动的报道公信力低也卖得动（爱看热闹的人不管真假），代价在官司、砸窗和退订上
	circ_change = circ_change * (0.25 + stats.credibility / 100.0) + circ_hot * (0.6 + stats.credibility / 250.0)
	circ_change *= clampf(1.0 - stats.circulation / 600.0, 0.1, 1.0)
	if not had_news:
		flags.weeks_no_news += 1
		# 只登软新闻也比没报纸强：满满一版婚丧集市的（两条以上），读者掉得最慢；镇上这类事多不多，各局不一样
		if flags.weeks_no_news >= 2:
			circ_change -= 0.03 - 0.01 * mini(2, soft_n)
	else:
		flags.weeks_no_news = 0
	if stats.credibility < 20: circ_change -= 0.02
	if stats.credibility < 10: circ_change -= 0.03
	if stats.credibility > 70: circ_change += 0.01
	if burned: circ_change -= 0.3
	stats.circulation = maxf(40.0, stats.circulation * (1.0 + circ_change))
	# 镇上会慢慢忘：这一期没登错东西，公信力往 CRED_RECOVER_TO 回一点
	if not printed_false and stats.credibility + cred_change < CRED_RECOVER_TO:
		cred_change += (CRED_RECOVER_TO - stats.credibility - cred_change) * CRED_RECOVER_RATE
	stats.credibility = clampf(stats.credibility + cred_change, 0.0, 100.0)
	# 现金
	var income: float = stats.circulation * 0.05
	var ad_income := 0.0
	for rid in ads:
		var r: Dictionary = residents[rid]
		if ads[rid].paused_until <= week and r.in_town and r.player_rel.like >= 0.3:
			ad_income += (2.0 + r.wealth * 1.0 + r.player_rel.like * 2.0) * clampf(stats.circulation / 180.0, 0.3, AD_CIRC_CAP)
	var cost: float = 10.0 + stats.circulation * PRINT_COST
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
			_cons(issue, "cons_pleased", {"name": subj})
			continue
		var s: float = e.severity * naming_mult * (1.3 if a.tone == "hot" else 1.0) * (1.2 if a.get("evidence", false) else 1.0)
		s *= {"head": 1.0, "second": 0.8, "third": 0.6, "small": 0.3}[a.slot]
		if rec.get("followup", false):
			s *= FOLLOWUP_SEVERITY
		# 读到了吗？点名的人几乎一定会被告知
		var p_read := 0.95 if a.naming == "named" else (0.7 if a.naming == "alias" else 0.4)
		if r.get("aware", false) or e.get("visited", false):
			p_read = 1.0
		if not rng.chance(p_read):
			_cons(issue, "cons_unread", {"name": subj})
			continue
		var level := "light"
		if s >= 2.2: level = "heavy"
		elif s >= 1.1: level = "medium"
		if e.bribed_by == subj:
			level = "heavy"
			_cons(issue, "cons_bribe_printed", {"name": subj})
		r.player_rel.like = maxf(0.0, r.player_rel.like - 0.3 * s)
		r.player_rel.trust = maxf(0.0, r.player_rel.trust - 0.2 * s)
		r.player_rel.fear = minf(1.0, r.player_rel.fear + 0.1 * s)
		r.exposed_week = week
		Relations.on_exposed(self, subj, s, e)
		Election.on_article(self, subj, s, false)
		var kind := _reaction(r.bucket, level)
		if level != "light":
			for fam in r.family:
				if residents.has(fam) and residents[fam].in_town and residents[fam].player_rel.like < 0.3 and rng.chance(0.3):
					visitors.append({"who": fam, "kind": "silent", "event": e.id})
					break
		if kind == "suicide" and not config.suicide:
			kind = "leave"
		# 印了假话且对方有点地位：起诉概率
		# 小小提了一句的，多半不值得打官司；登了重话的才常去请律师
		var suing := false
		for l in lawsuits:
			if l.who == subj:
				suing = true
		# 一个人同时只打一场官司
		if not suing and rec.avg_truth < 0.5 and a.naming == "named" and r.power >= 1 and rng.chance({"light": 0.1, "medium": 0.3, "heavy": 0.5}[level]):
			kind = "sue"
		_schedule_reaction(kind, subj, e, issue, s, rec)


## 被曝光的人要动手时，和他走得近、又对报社有好感的人可能会来通风报信。
func _maybe_warning(angry: String, e: Dictionary) -> void:
	var allies: Array = []
	for fr in residents[angry].friends:
		if residents.has(fr) and residents[fr].in_town and residents[fr].player_rel.like >= 0.6:
			allies.append(fr)
	if not allies.is_empty() and rng.chance(0.6):
		visitors.append({"who": rng.pick(allies), "kind": "warning", "event": e.id, "subject": angry})


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
			_cons(issue, "cons_avoid", {"name": rid})
		"leave":
			pending.append({"week": week + 2, "kind": "leave", "who": rid, "event": e.id})
			_cons(issue, "cons_leave", {"name": rid})
		"explain":
			visitors.append({"who": rid, "kind": "explain", "event": e.id})
			_cons(issue, "cons_explain", {"name": rid})
		"deal":
			visitors.append({"who": rid, "kind": "deal", "event": e.id})
			_cons(issue, "cons_deal", {"name": rid})
		"expose":
			visitors.append({"who": rid, "kind": "expose", "event": e.id})
			_cons(issue, "cons_expose", {"name": rid})
		"insult":
			stats.circulation *= 0.98
			for fr in r.friends:
				residents[fr].player_rel.like = maxf(0.0, residents[fr].player_rel.like - 0.1)
			_cons(issue, "cons_insult", {"name": rid})
		"window":
			pending.append({"week": week + 1, "kind": "window", "who": rid, "event": e.id})
			_cons(issue, "cons_loiter")
			_maybe_warning(rid, e)
		"arson":
			_maybe_warning(rid, e)
			if rng.chance(0.5):
				pending.append({"week": week + 1, "kind": "arson", "who": rid, "event": e.id})
				_cons(issue, "cons_kerosene")
			else:
				pending.append({"week": week + 1, "kind": "window", "who": rid, "event": e.id})
				_cons(issue, "cons_loiter")
		"pull_ad":
			if ads.has(rid):
				ads[rid].paused_until = week + 8
				_cons(issue, "cons_pull_ad", {"name": rid})
				pending.append({"week": week + 1, "kind": "letter", "who": rid, "letter": {"kind": "ad_pulled", "roles": {"who": rid}, "vars": {}, "id": 900 + letters.size(), "week": week + 1}})
			else:
				for fr in r.friends:
					if ads.has(fr):
						ads[fr].paused_until = week + 4
						_cons(issue, "cons_pull_ad_friend", {"name": rid, "who": fr})
						break
		"pressure":
			stats.circulation *= 0.92
			var n := 0
			for rid2 in living_ids():
				if residents[rid2].subscribed and (rid2 in r.friends or residents[rid2].work == r.work) and n < 6:
					residents[rid2].subscribed = false
					n += 1
			_cons(issue, "cons_pressure", {"name": rid, "n": n})
			# 连带撤掉的广告要写明是谁让谁撤的（第 2 轮：锯木厂撤了广告，玩家到最后都不知道为什么）
			for fr in r.friends:
				if ads.has(fr) and fr != rid:
					ads[fr].paused_until = week + 6
					_cons(issue, "cons_pull_ad_friend", {"name": rid, "who": fr})
		"sue":
			lawsuits.append({"week": week + 2, "who": rid, "event": e.id, "truth": rec.avg_truth, "evidence": rec.evidence})
			_cons(issue, "cons_sue", {"name": rid})
		"suicide":
			pending.append({"week": week + 2, "kind": "suicide", "who": rid, "event": e.id})
			_cons(issue, "cons_hide", {"name": rid})


func _apply_pending() -> void:
	var keep: Array = []
	for p in pending:
		if p.week > week:
			keep.append(p)
			continue
		if p.kind == "letter":
			letters.append(p.letter)
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
				_letter("left_town", {"who": p.who})
				log.append("第 %d 周：%s离镇。" % [week, r.name])
			"window":
				stats.cash -= 10
				flags["window_week"] = week
				_letter("window")
				log.append("第 %d 周：报社窗户被砸。" % week)
			"arson":
				flags.burned_until = week + 2
				stats.cash -= 60
				_letter("arson")
				log.append("第 %d 周：报社被纵火。" % week)
			"suicide":
				r.alive = false
				_letter("mourning", {"who": p.who})
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
		# 登的是真事：附了档案稳赢，没附也多半赢；半真半假看报纸平日的名声；假的必输
		if l.truth >= 0.8: win = true if l.evidence else rng.chance(0.75)
		elif l.truth < 0.5: win = false
		else: win = rng.chance(0.4 + stats.credibility / 250.0)
		if win:
			stats.credibility = minf(100.0, stats.credibility + 10)
			_letter("lawsuit_won", {"who": l.who})
			r.player_rel.fear = minf(1.0, r.player_rel.fear + 0.3)
		else:
			stats.credibility = maxf(0.0, stats.credibility - 10)
			stats.cash -= 25
			flags.lawsuits_lost += 1
			var lost: Array = flags.get("lawsuit_weeks", [])
			lost.append(week)
			flags["lawsuit_weeks"] = lost
			_letter("lawsuit_lost", {"who": l.who})
		log.append("第 %d 周：官司%s。" % [week, "赢了" if win else "输了"])
	lawsuits = keep_l
	# 读者来信
	_reader_letters()


## 周一的读者来信：对上一期报纸的反应。2 到 4 封，是玩家读「镇民态度」的主要窗口。
## 谁来写信是模拟决定的（走 world.rng），写成什么样是文本引擎决定的。
func _reader_letters() -> void:
	var cands: Array = []   # {kind, roles, vars, w}
	var last: Dictionary = issues[-1] if not issues.is_empty() else {}
	if not last.is_empty() and int(last.week) == week - 1:
		var any_hot := false
		var all_calm := true
		var hard := 0
		for a in last.articles:
			var e: Dictionary = event_by_id(a.event)
			if e.is_empty():
				continue
			if a.tone == "hot":
				any_hot = true
			if a.tone != "calm":
				all_calm = false
			var subj: String = e.roles[e.target][0]
			if not residents.has(subj):
				continue
			var sr: Dictionary = residents[subj]
			if e.soft:
				if sr.in_town and sr.alive and rng.chance(0.5):
					cands.append({"kind": "soft_thanks", "roles": {"who": subj}, "w": 1.0})
				continue
			hard += 1
			var mult: float = {"head": 1.0, "second": 0.8, "third": 0.6, "small": 0.3}[a.slot]
			# 当事人的亲友抱怨
			var near: Array = []
			for oid in sr.family + sr.friends:
				if residents.has(oid) and residents[oid].in_town and residents[oid].alive and oid != subj:
					near.append(oid)
			if not near.is_empty() and rng.chance(0.7 * mult):
				cands.append({"kind": "complaint", "roles": {"who": rng.pick(near), "subject": subj}, "w": 2.0})
			# 仇人叫好
			var foes: Array = []
			for oid in sr.enemies:
				if residents.has(oid) and residents[oid].in_town and residents[oid].alive:
					foes.append(oid)
			if not foes.is_empty() and rng.chance(0.5 * mult):
				var foe: String = rng.pick(foes)
				# 仇人手上还有你不知道的料：信里叫你去找他，线头页记一笔（原来「来找我」的信找上门什么都不说）
				var more := false
				for tf in e.facts:
					if residents[foe].knows.has(tf) and _can_tell(foe, tf):
						more = true
				if more:
					cands.append({"kind": "more_to_tell", "roles": {"who": foe, "subject": subj}, "w": 1.5, "lead": e.id})
				else:
					cands.append({"kind": "praise_exposure", "roles": {"who": foe, "subject": subj}, "w": 1.5})
			# 受害者道谢
			for role in ["victim", "creditor", "wife", "boss"]:
				if e.roles.has(role):
					var vid: String = e.roles[role][0]
					if vid != subj and residents[vid].in_town and not (vid in sr.family) and rng.chance(0.5 * mult):
						cands.append({"kind": "thanks_victim", "roles": {"who": vid, "subject": subj}, "w": 1.5})
						break
			# 印了假话：知道真相的人来更正
			for fid in a.facts:
				if facts[fid].truth < 0.5:
					var knowers: Array = []
					for oid in living_ids():
						if oid == subj:
							continue
						for tf in e.facts:
							if residents[oid].knows.has(tf):
								knowers.append(oid)
								break
					if knowers.is_empty():
						knowers = near
					if not knowers.is_empty() and rng.chance(0.7):
						cands.append({"kind": "correction", "roles": {"who": rng.pick(knowers), "subject": subj}, "vars": {"fact_id": fid}, "w": 3.0})
					break
		var readers: Array = []
		for oid in living_ids():
			if residents[oid].subscribed and residents[oid].literate:
				readers.append(oid)
		if not readers.is_empty():
			if any_hot and rng.chance(0.45):
				cands.append({"kind": "tone_hot", "roles": {"who": rng.pick(readers)}, "w": 1.0})
			elif all_calm and hard > 0 and rng.chance(0.3):
				cands.append({"kind": "tone_calm", "roles": {"who": rng.pick(readers)}, "w": 1.0})
			if hard == 0 and not last.articles.is_empty() and rng.chance(0.5):
				cands.append({"kind": "no_news", "roles": {"who": rng.pick(readers)}, "w": 1.0})
	# 订户的态度：喜欢的写信夸，讨厌的退订
	var pool := living_ids()
	rng.shuffle(pool)
	var head := ""
	if not last.is_empty() and not last.articles.is_empty():
		head = last.articles[0].headline
	var n := 0
	for rid in pool:
		if n >= 2:
			break
		var r: Dictionary = residents[rid]
		if not r.literate or not r.subscribed:
			continue
		if r.player_rel.like > 0.65 and flags.get("last_fan", "") != rid and rng.chance(0.5):
			cands.append({"kind": "fan", "roles": {"who": rid}, "vars": {"headline": head}, "w": 1.0})
			flags.last_fan = rid
			n += 1
		elif r.player_rel.like < 0.25 and int(r.get("praised_week", -9)) < week - 1:
			cands.append({"kind": "unsubscribe", "roles": {"who": rid}, "w": 2.0, "unsub": rid})
			n += 1
	# 挑 2 到 4 封：权重高的优先，同一个人只写一封
	rng.shuffle(cands)
	cands.sort_custom(func(x, y): return float(x.w) > float(y.w))
	var used := {}
	var taken := 0
	for c in cands:
		if taken >= 4:
			break
		var who: String = c.roles.get("who", "")
		if used.has(who):
			continue
		used[who] = true
		_letter(c.kind, c.roles, c.get("vars", {}))
		if c.has("lead"):
			leads.append({"who": who, "event": c.lead, "from": who, "week": week})
		if c.has("unsub"):
			residents[c.unsub].subscribed = false
		taken += 1


func _check_game_over() -> void:
	if flags.negative_weeks >= 4:
		game_over = "破产"
		log.append("第 %d 周：连续四周亏空，报纸停了。" % week)
	elif _recent_losses() >= 3:
		game_over = "停刊"
		log.append("第 %d 周：一年里输了三场官司，报纸被勒令停刊。" % week)
	elif flags.burned_until > week and stats.cash < 0 and flags.negative_weeks >= 2:
		game_over = "报社被毁"
		log.append("第 %d 周：报社烧了，没钱重建。" % week)


## 一年内输掉的官司。一年里输三场才勒令停刊；早年的败诉不一直记着
func _recent_losses() -> int:
	var n := 0
	for w in flags.get("lawsuit_weeks", []):
		if int(w) > week - 52:
			n += 1
	return n


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
