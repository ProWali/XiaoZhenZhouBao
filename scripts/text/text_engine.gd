## 文本引擎：事件模板层 + 语法层 + 润色层。
## 只读世界状态，从不碰 world.rng。所有随机来自 text_rng(world, [...])：种子由局种子和渲染参数决定，
## 所以同一篇报道换语言、重抽标题、重读存档，都不会改变模拟。
##
## 数据在 res://data/text/<lang>/：grammar.json、events.json、letters.json、visitors.json、ui.json
##
## 槽位：
##   {role}          第一次出现写全名（化名写「某工头」），之后写简称（「莫兰先生」「这名工头」）
##   {role.full}     职业 + 全名（「工头莫兰·艾德」）
##   {role.short}    简称
##   {role.occ}      职业
##   {role.yiwei}    「一位镇长」「一名工人」/ "a mayor"
##   {role.ta}       他 / 她；英文 he / she
##   {role.him} {role.his}   英文宾格和所有格；中文都是 他 / 她
##   {x_键}          事件附带的文字（讣告里的死者名、预算的用途）
##   {paper} {season} {loc} {offer} {fact} {event} 以及调用方传进来的其它键
extends RefCounted

const Rng = preload("res://scripts/sim/rng.gd")
const Grammar = preload("res://scripts/text/grammar.gd")
const PolishZh = preload("res://scripts/text/polish_zh.gd")
const PolishEn = preload("res://scripts/text/polish_en.gd")
const T = preload("res://scripts/sim/tables.gd")
const Events = preload("res://scripts/sim/events.gd")

const SEASON_KEYS := ["", "spring", "summer", "autumn", "winter"]
const SEASON_ZH := ["", "春天", "夏天", "秋天", "冬天"]
const SEASON_EN := ["", "spring", "summer", "autumn", "winter"]
const SOURCE_PRIORITY := ["witness", "archive", "public", "interview", "informer", "visitor", "eavesdrop", "letter"]
const FILES := ["grammar", "events", "letters", "visitors", "ui"]

static var _data := {}
static var _re_slot: RegEx


# ================================================================ 数据
static func data(lang: String) -> Dictionary:
	if _data.has(lang):
		return _data[lang]
	var d := {}
	for f in FILES:
		var path := "res://data/text/%s/%s.json" % [lang, f]
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			assert(parsed is Dictionary, "文本数据不是合法 JSON：" + path)
			d[f] = parsed
		else:
			d[f] = {}
	_data[lang] = d
	return d


static func reload() -> void:
	_data.clear()


static func text_rng(world, parts: Array) -> Rng:
	var key := str([world.seed_value] + parts)
	return Rng.new(key.hash())


static func season_key(world) -> String:
	return SEASON_KEYS[world.is_season(world.week)]


static func grammar_for(world, lang: String, rng: Rng, tone: String = "", remember: bool = false) -> Grammar:
	var suf: Array = []
	if tone != "":
		suf.append("@" + tone)
	suf.append("@" + season_key(world))
	var g := Grammar.new(data(lang).grammar, rng, suf)
	if remember:
		if not world.text_memory.has(lang):
			world.text_memory[lang] = {}
		g.memory = world.text_memory[lang]
		g.week = world.week
	return g


static func polish(text: String, lang: String) -> String:
	return PolishEn.polish(text) if lang == "en" else PolishZh.polish(text)


static func lint(text: String, lang: String, names: Array = []) -> Array:
	return PolishEn.lint(text, names) if lang == "en" else PolishZh.lint(text, names)


# ================================================================ 人
static func person_name(world, rid: String, lang: String) -> String:
	if not world.residents.has(rid):
		return "?"
	var r: Dictionary = world.residents[rid]
	return r.get("name_en", r.name) if lang == "en" else r.name


static func surname(world, rid: String, lang: String) -> String:
	var r: Dictionary = world.residents[rid]
	if lang == "en":
		var parts: PackedStringArray = str(r.get("name_en", r.name)).split(" ")
		return parts[parts.size() - 1]
	return str(r.name).split("·")[0]


## 1935 年的报纸称呼：先生、太太、小姐。
static func short_ref(world, rid: String, lang: String, occ_id: String = "") -> String:
	var r: Dictionary = world.residents[rid]
	# 报道里按事发时的职业称呼（当时是牧师，后来当了镇长，这篇里仍是牧师）
	var oc: String = occ_id if occ_id != "" else str(r.occ)
	var married: bool = r.spouse != "" or oc == "widow" or r.get("widowed_week", -99) > -99
	if lang == "en":
		var title := "Mr"
		if r.female:
			title = "Mrs" if married else "Miss"
			if married and r.spouse != "" and world.residents.has(r.spouse) and surname(world, r.spouse, lang) != surname(world, rid, lang):
				return person_name(world, rid, lang)
		if oc == "doctor":
			title = "Dr"
		elif oc == "priest":
			title = "Father"
		elif oc == "mayor":
			title = "Mayor"
		elif oc == "sheriff":
			title = "Sheriff"
		return title + " " + surname(world, rid, lang)
	# 1935 年的报纸称女性「女士」，不论婚否；这样也不会把自己的姓配上「太太」
	var t := "先生"
	if r.female:
		t = "女士"
	if oc == "doctor":
		t = "医生"
	elif oc == "priest":
		t = "牧师"
	elif oc == "mayor":
		t = "镇长"
	elif oc == "sheriff":
		t = "警长"
	return surname(world, rid, lang) + t


static func occ_label(world, rid: String, lang: String, occ_id: String = "") -> String:
	var r: Dictionary = world.residents[rid]
	var oid: String = occ_id if occ_id != "" else str(r.occ)
	if lang == "en":
		return T.occ_en(oid)
	var o := T.occupation_by_id(oid)
	if not o.is_empty():
		return o.name
	return {"homemaker": "家眷", "retired": "赋闲的人"}.get(oid, str(r.occ_name))


## 报名、主编名。玩家没改默认名时按语言显示默认名；改过就照玩家写的印
static func paper_title(world, lang: String) -> String:
	if str(world.paper_name) in ["灰河周报", "The Greyriver Weekly", ""]:
		return "The Greyriver Weekly" if lang == "en" else "灰河周报"
	return str(world.paper_name)


static func editor_title(world, lang: String) -> String:
	if str(world.player_name) in ["主编", "Editor", ""]:
		return "Editor" if lang == "en" else "主编"
	return str(world.player_name)


static func pronoun(world, rid: String, lang: String, form: String) -> String:
	var female: bool = world.residents[rid].female if world.residents.has(rid) else false
	if lang != "en":
		return "她" if female else "他"
	match form:
		"him": return "her" if female else "him"
		"his": return "her" if female else "his"
	return "she" if female else "he"


static func loc_label(world, loc: String, lang: String) -> String:
	if loc.begins_with("home:"):
		var rid := loc.substr(5)
		if lang == "en":
			return "the " + surname(world, rid, lang) + " house"
		return person_name(world, rid, lang) + "家"
	var l := T.location_by_id(loc)
	if l.is_empty():
		return loc
	return l.en if lang == "en" else l.name


# ================================================================ 填槽
## ctx: {roles: {role: rid}, naming: {role: mode}, extras: {k: v}, occ_at: {rid: occ_id}, mentions: {}, vars: {k: v}}
static func fill(world, text: String, ctx: Dictionary, lang: String) -> String:
	if _re_slot == null:
		_re_slot = RegEx.new()
		_re_slot.compile("\\{([A-Za-z0-9_]+)(?:\\.([a-z]+))?\\}")
	var roles: Dictionary = ctx.get("roles", {})
	var extras: Dictionary = ctx.get("extras", {})
	var vars: Dictionary = ctx.get("vars", {})
	if not ctx.has("mentions"):
		ctx["mentions"] = {}
	var out := ""
	var pos := 0
	for m in _re_slot.search_all(text):
		out += text.substr(pos, m.get_start() - pos)
		pos = m.get_end()
		var key := m.get_string(1)
		var field := m.get_string(2)
		if key.begins_with("x_") and extras.has(key.substr(2)):
			var xk := key.substr(2)
			out += str(extras[xk + "_" + lang]) if extras.has(xk + "_" + lang) else str(extras[xk])
		elif roles.has(key):
			out += _person_slot(world, key, field, ctx, lang)
		elif vars.has(key):
			out += str(vars[key])
		else:
			match key:
				"paper": out += paper_title(world, lang)
				"season": out += (SEASON_EN if lang == "en" else SEASON_ZH)[world.is_season(world.week)]
				_: out += m.get_string()  # 留给 lint 抓
	out += text.substr(pos)
	return out


static func _person_slot(world, role: String, field: String, ctx: Dictionary, lang: String) -> String:
	var rid: String = ctx.roles[role]
	if not world.residents.has(rid):
		return "?"
	# {target} 和它指向的那个角色是同一个人：命名方式、提及次数都跟着那个角色走
	if role == "target":
		for r2 in ctx.roles:
			if r2 != "target" and ctx.roles[r2] == rid:
				role = r2
				break
	var mode: String = ctx.get("naming", {}).get(role, "named")
	var occ_id: String = ctx.get("occ_at", {}).get(rid, "")
	var occ := occ_label(world, rid, lang, occ_id)
	var mentions: Dictionary = ctx.mentions
	var oid: String = occ_id if occ_id != "" else str(world.residents[rid].occ)
	var fem: bool = world.residents[rid].female
	match field:
		"occ":
			return occ
		"ta", "he", "him", "his":
			# 匿名报道里，「他」「她」等于告诉读者性别
			if mode == "anon":
				if lang == "en":
					return "this person's" if field == "his" else "this person"
				return "此人"
			return pronoun(world, rid, lang, "he" if field == "ta" else field)
		"yiwei":
			if lang == "en":
				return ("an " if occ.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"] else "a ") + occ
			return ("一位" if occ in PolishZh.RESPECT else "一名") + occ
		"short":
			var c: int = int(mentions.get(role, 0))
			mentions[role] = c + 1
			# 报道是正式文体：头一回提到一个人必须给全名，之后才能叫「莫兰先生」。
			# 镇民说话、写信不讲究这个，直接叫「莫兰先生」。
			if c == 0 and ctx.get("formal", false):
				if mode != "named":
					return _alias_first(occ, oid, fem, mode, lang, false)
				# 头一回提到，带上身份：「警长拉克·汉尔」
				if oid in NO_APPOSITION:
					return person_name(world, rid, lang)
				return _apposition(occ, oid, person_name(world, rid, lang), lang)
			if mode == "named":
				return short_ref(world, rid, lang, occ_id)
			return _alias_later(occ, oid, fem, mode, lang)
		"name":
			var cn: int = int(mentions.get(role, 0))
			mentions[role] = cn + 1
			if mode == "named":
				return person_name(world, rid, lang)
			return _alias_first(occ, oid, fem, mode, lang, false) if cn == 0 else _alias_later(occ, oid, fem, mode, lang)
	# {role} 和 {role.full}
	var n: int = int(mentions.get(role, 0))
	mentions[role] = n + 1
	if mode != "named":
		return _alias_first(occ, oid, fem, mode, lang, field == "full") if n == 0 else _alias_later(occ, oid, fem, mode, lang)
	if n == 2 and field == "":
		return person_name(world, rid, lang)
	if n == 0:
		# 家眷、赋闲的人不算职业，同位语里不写
		if field == "full" and not (oid in NO_APPOSITION):
			return _apposition(occ, oid, person_name(world, rid, lang), lang)
		return person_name(world, rid, lang)
	return short_ref(world, rid, lang, occ_id)


## 「工头莫兰·艾德」。英文里名字前的正式职衔要大写（Mayor, Sheriff），普通职业照常小写（grocer, mill hand）
const EN_TITLES := {"mayor": "Mayor", "sheriff": "Sheriff", "doctor": "Dr.", "priest": "Father"}


static func _apposition(occ: String, oid: String, name: String, lang: String) -> String:
	if lang != "en":
		return occ + name
	return str(EN_TITLES.get(oid, occ)) + " " + name


const NO_APPOSITION := ["homemaker", "retired"]


## 化名第一次出现。in_apposition：模板写的是 {role.full}，前面常有「厂里的」「上游」这类修饰，匿名时只能写「某人」。
static func _alias_first(occ: String, oid: String, female: bool, mode: String, lang: String, in_apposition: bool) -> String:
	if mode == "anon":
		if lang == "en":
			return "someone" if in_apposition else "a resident of the town"
		return "某人" if in_apposition else "镇上某人"
	if lang == "en":
		match oid:
			"homemaker": return "a certain local woman" if female else "a certain local man"
			"retired": return "a certain retired resident"
		return "a certain " + occ
	match oid:
		"homemaker": return "某位太太" if female else "某位先生"
		"retired": return "某位赋闲在家的人"
		"newcomer": return "某位新来的人"
	return ("某位" if occ in PolishZh.RESPECT else "某") + occ


static func _alias_later(occ: String, oid: String, female: bool, mode: String, lang: String) -> String:
	if mode == "anon":
		return "this person" if lang == "en" else "此人"
	if lang == "en":
		match oid:
			"homemaker": return "the woman" if female else "the man"
			"retired": return "the retired resident"
		return "the " + occ
	match oid:
		"homemaker": return "这位太太" if female else "这位先生"
		"retired": return "此人"
		"newcomer": return "这个新来的人"
	return ("这位" if occ in PolishZh.RESPECT else "这名") + occ


## 展开 + 填槽 + 润色，一步到位。
static func render(world, template: String, ctx: Dictionary, lang: String, rng: Rng, tone: String = "") -> String:
	var g := grammar_for(world, lang, rng, tone)
	return polish(fill(world, g.expand(template), ctx, lang), lang)


# ================================================================ 事件与报道
static func event_text(lang: String, tid: String) -> Dictionary:
	return data(lang).events.get(tid, {})


static func event_name(world, e: Dictionary, lang: String) -> String:
	var et := event_text(lang, e.tid)
	return et.get("name", e.name)


static func _naming_map(e: Dictionary, naming: String) -> Dictionary:
	var m := {}
	for role in e.roles:
		if e.soft:
			m[role] = "named"
		elif role == e.target:
			m[role] = naming
		else:
			m[role] = "named" if naming == "named" else "alias"
	return m


static func _ctx_for_event(e: Dictionary, naming: String) -> Dictionary:
	var roles := {}
	for role in e.roles:
		roles[role] = e.roles[role][0]
	# 模板里的 {target} 指当事人；它和当事人的角色共用一份提及计数，见 _person_slot
	roles["target"] = e.roles[e.target][0]
	return {"roles": roles, "naming": _naming_map(e, naming), "extras": e.get("extras", {}), "occ_at": e.get("occ_at", {}), "mentions": {}, "formal": true}


## 选题簿里的一句话：玩家知道的事实，用真名写。
static func fact_note(world, fid: String, lang: String) -> String:
	var f: Dictionary = world.facts[fid]
	var e: Dictionary = world.event_of(fid)
	var et := event_text(lang, e.get("tid", ""))
	var spec: Dictionary = et.get("facts", {}).get(f.key, {})
	var tpl: String = spec.get("note", "")
	if tpl == "":
		if lang == "en":
			return "(untranslated) " + str(f.text)
		return str(f.text)
	var ctx := _ctx_for_event(e, "named")
	return polish(fill(world, tpl, ctx, lang), lang).trim_suffix("。").trim_suffix(".")


## 模板条目可以是字符串，也可以是 {t, needs, needs_all}：报道里登了对应的事实才能用。
##   needs: "key"          要有这条事实
##   needs: ["a", "b"]     有其中任一条即可
##   needs_all: ["a", "b"] 每一条都要有（评论里拿两条证据互相印证时用）
## 报纸不能在标题和细节里写自己没掌握的事。全被筛掉时退回不带条件的条目。
static func eligible(items: Array, fact_keys: Dictionary) -> Array:
	var out: Array = []
	for it in items:
		if it is String:
			out.append(it)
		elif it is Dictionary and needs_ok(it, fact_keys):
			out.append(str(it.t))
	if out.is_empty():
		for it in items:
			out.append(it if it is String else str(it.t))
	return out


## 和 eligible 一样筛，但全被筛掉时就是空的。回应、评论宁可不写，也不能对不上正文。
static func eligible_strict(items: Array, fact_keys: Dictionary) -> Array:
	var out: Array = []
	for it in items:
		if it is String:
			out.append(it)
		elif it is Dictionary and needs_ok(it, fact_keys):
			out.append(str(it.t))
	return out


## 按语气取一组候选，只留对得上登出事实的。这个语气里一条都对不上时，先借别的语气里对得上的，
## 实在没有才退回不加筛选（标题不能空着）。免得只登了「夜里赶车」，标题却写「私酒卖进酒馆」。
static func tone_pool(by_tone: Dictionary, prefer: Array, fact_keys: Dictionary) -> Array:
	var order: Array = []
	for t in prefer + ["neutral", "calm", "hot"]:
		if by_tone.has(t) and not (t in order):
			order.append(t)
	for t in order:
		var strict := eligible_strict(by_tone[t], fact_keys)
		if not strict.is_empty():
			return strict
	for t in order:
		if not by_tone[t].is_empty():
			return eligible(by_tone[t], fact_keys)
	return []


static func needs_ok(it: Dictionary, fact_keys: Dictionary) -> bool:
	if it.has("needs"):
		var nd = it.needs
		if nd is Array:
			var any := false
			for k in nd:
				if fact_keys.has(str(k)):
					any = true
			if not any:
				return false
		elif not fact_keys.has(str(nd)):
			return false
	for k in it.get("needs_all", []):
		if not fact_keys.has(str(k)):
			return false
	# season: ["winter", ...]：只在这些季节用（键 "@winter" 由 article() 放进 fact_keys）
	if it.has("season"):
		var hit := false
		for sv in it.season:
			if fact_keys.has("@" + str(sv)):
				hit = true
		if not hit:
			return false
	return true


static func _has_needs(it) -> bool:
	return it is Dictionary and (it.has("needs") or it.has("needs_all"))


static func _fact_keys(world, facts_list: Array) -> Dictionary:
	var keys := {}
	for fid in facts_list:
		if world.facts.has(fid):
			keys[str(world.facts[fid].key)] = true
	return keys


## 登出来的事实里点到了哪些角色（当事人总算在内）。
static func _roles_in_facts(world, e: Dictionary, facts_list: Array) -> Dictionary:
	var out := {"target": true, str(e.target): true}
	for fid in facts_list:
		if not world.facts.has(fid):
			continue
		var tpl: String = str(world.facts[fid].get("text_tpl", ""))
		for role in e.roles:
			if tpl.find("{" + role + "}") >= 0:
				out[role] = true
		var subj: String = world.facts[fid].subject
		for role in e.roles:
			if subj in e.roles[role]:
				out[role] = true
	return out


static var _re_role: RegEx


## 标题里出现的角色都得在 allowed 里，否则标题会写到正文没提的人。全被筛掉时原样返回。
static func _roles_ok(items: Array, allowed: Dictionary) -> Array:
	if _re_role == null:
		_re_role = RegEx.new()
		_re_role.compile("\\{([a-z_]+)[}.]")
	var out: Array = []
	for t in items:
		var ok := true
		for m in _re_role.search_all(str(t)):
			var r := m.get_string(1)
			if not r.begins_with("x_") and not allowed.has(r):
				ok = false
		if ok:
			out.append(t)
	return out if not out.is_empty() else items


static func headline_candidates(world, e: Dictionary, a: Dictionary, lang: String) -> Array:
	var et := event_text(lang, e.tid)
	var tone: String = a.get("tone", "neutral")
	var naming: String = "named" if e.soft else a.get("naming", "named")
	var pool: Array = _roles_ok(tone_pool(et.get("headlines", {}), [tone], _fact_keys(world, a.get("facts", []))), _roles_in_facts(world, e, a.get("facts", [])))
	var out: Array = []
	if pool.is_empty():
		# 没写文本的事件退回模拟层自带的标题
		for h in world.events_db.headlines(e, tone, naming, world):
			out.append(h)
		return out
	var rng := text_rng(world, [e.id, "hl", tone, naming, int(a.get("reroll", 0))])
	var order: Array = pool.duplicate()
	rng.shuffle(order)
	# 半年内用过的标题模板排到后面（只读，不记；付印时由 article() 记下）
	var mem: Dictionary = world.text_memory.get(lang, {}) if a.get("use_memory", true) else {}
	# 「某某被指某事」是公文腔，一份报纸里见多了就成了套路：排序时当它已经用过两回
	var formula: Array = data(lang).grammar.get("_headline_formula", [])
	var rank := func(t) -> int:
		var r: int = int(mem.get("hln:" + str(t), 0))
		for f in formula:
			if str(t).find(str(f)) >= 0:
				r += 2
		return r
	if not mem.is_empty() or not formula.is_empty():
		var ranked: Array = []
		for i in order.size():
			ranked.append([rank.call(order[i]), i, order[i]])
		ranked.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
		order = []
		for x in ranked:
			order.append(x[2])
	last_headline_templates.clear()
	var tries := 0
	while out.size() < 3 and tries < 12:
		var tpl: String = order[tries % order.size()]
		tries += 1
		var ctx := _ctx_for_event(e, naming)
		var h := grammar_for(world, lang, rng, tone).expand(tpl)
		h = fill(world, h, ctx, lang)
		h = _headline_polish(h, lang)
		if not (h in out):
			out.append(h)
			last_headline_templates.append(tpl)
	return out


## headline_candidates 最近一次返回的标题各自来自哪条模板，给 article() 记忆用
static var last_headline_templates: Array = []


static func _headline_polish(h: String, lang: String) -> String:
	if lang == "en":
		return PolishEn.title_case(PolishEn.polish(h))
	var s := PolishZh.polish(h)
	if s.ends_with("。"):
		s = s.substr(0, s.length() - 1)
	return s


## 一篇报道。a: {slot, facts, tone, naming, evidence, reroll, choice}
## 返回 {headline, paragraphs: [String]}
static func article(world, e: Dictionary, a: Dictionary, lang: String) -> Dictionary:
	var tone: String = a.get("tone", "neutral")
	var naming: String = "named" if e.soft else a.get("naming", "named")
	var cands := headline_candidates(world, e, a, lang)
	var ci := clampi(int(a.get("choice", 0)), 0, cands.size() - 1)
	var headline: String = cands[ci] if not cands.is_empty() else ""
	if a.get("remember", false) and ci < last_headline_templates.size():
		if not world.text_memory.has(lang):
			world.text_memory[lang] = {}
		var hk := "hln:" + str(last_headline_templates[ci])
		world.text_memory[lang][hk] = int(world.text_memory[lang].get(hk, 0)) + 1
	var et := event_text(lang, e.tid)
	var rng := text_rng(world, [e.id, "body", tone, naming, int(a.get("reroll", 0)), a.get("slot", "")])
	var g := grammar_for(world, lang, rng, tone, a.get("remember", false))
	var ctx := _ctx_for_event(e, naming)
	var paras: Array = []
	if et.is_empty():
		for fid in a.facts:
			var f: Dictionary = world.facts[fid]
			var role := _role_of(e, f.subject)
			paras.append(Events.fill_text(f.text_tpl, e.roles, world, naming, role, "occ" if naming != "named" else "named", e.get("extras", {}), e.get("occ_at", {})))
		return {"headline": headline, "paragraphs": paras}
	var small: bool = a.get("slot", "") == "small"
	# 导语
	var keys := _fact_keys(world, a.get("facts", []))
	keys["@" + season_key(world)] = true
	var leads: Dictionary = et.get("lead", {})
	# 人写的导语多从一个具体的场面起头（季节、地方、人在做什么），「本报查了什么」只是备用
	var scenes := _fresh(g, eligible_strict(leads.get("scene", []), keys))
	var lead := ""
	if not scenes.is_empty() and rng.chance(0.4 if tone == "hot" else 0.7):
		lead = g.pick_expand(scenes)
	else:
		lead = g.pick_expand(tone_pool(leads, [tone + "_" + naming, tone], keys))
	if e.soft:
		var body := g.pick_expand(et.get("body", []))
		var text := lead + body
		if not small and not et.get("own_tail", false) and g.has_rule("close_soft") and rng.chance(0.5):
			text += g.expand("#close_soft#")
		paras.append(polish(fill(world, text, ctx, lang), lang))
		return {"headline": headline, "paragraphs": paras}
	paras.append(polish(fill(world, lead, ctx, lang), lang))
	if small:
		return {"headline": headline, "paragraphs": paras}
	var sep := "" if lang != "en" else " "
	var target: String = e.roles[e.target][0]
	var role_rids := {}
	for role in e.roles:
		for rid in e.roles[role]:
			role_rids[rid] = true
	# 事实：按玩家掌握的可靠程度排序。指向别人的说法（counter）放在后面，单独起头。
	var ordered: Array = a.facts.duplicate()
	ordered.sort_custom(func(x, y): return world.verify_score(x) > world.verify_score(y))
	var main_sents: Array = []
	var main_kinds: Array = []
	var counter_sents: Array = []
	var evidence_noted := false
	var detail_used := false
	var hedged := false
	var corroborated := false
	# 一篇报道里交代证据可靠（影印、核对过、另有人看见）最多一处，也不是篇篇都交代：人写稿不会每条证据后面都跟一句保证
	if rng.chance(0.35):
		corroborated = true
	for fid in ordered:
		var f: Dictionary = world.facts[fid]
		var spec: Dictionary = et.get("facts", {}).get(f.key, {})
		var src := best_source(world, fid)
		var prose: Array = _prose_for(spec.get("prose", []), str(src.kind), str(e.get("occ_at", {}).get(target, world.residents[target].occ)))
		var body_tpl: String = g.pick_fresh(prose) if not prose.is_empty() else str(spec.get("note", ""))
		if body_tpl == "":
			continue
		# 以「!」开头的写法自带说话人（「某某告诉本报」），不再加信源前缀
		var own_voice := body_tpl.begins_with("!")
		if own_voice:
			body_tpl = body_tpl.substr(1)
		var vars := {"loc": loc_label(world, f.get("archive", ""), lang) if f.get("archive", "") != "" else "", "src_who": ""}
		# 信源只写职业；但信源本人是事件里的角色，或者和事件里某人同一个职业时，不写，免得「一位警长说，某警长……」
		if src.kind in ["interview", "informer", "visitor", "eavesdrop"] and src.who != "" and world.residents.has(src.who) and not role_rids.has(src.who):
			var lbl := occ_label(world, src.who, lang)
			var clash := false
			for rid in role_rids:
				if occ_label(world, rid, lang, e.get("occ_at", {}).get(rid, "")) == lbl:
					clash = true
			var same := 0
			for oid in world.living_ids():
				if str(world.residents[oid].occ) == str(world.residents[src.who].occ):
					same += 1
			if not clash and same >= 3 and not (str(world.residents[src.who].occ) in NO_APPOSITION):
				vars.src_who = lbl
		ctx["vars"] = vars
		var lead_in := ""
		var sym := "src_" + str(src.kind)
		if vars.src_who != "" and g.has_rule(sym + "_who"):
			sym += "_who"
		var verified: bool = world.is_verified(fid)
		# 核实过的，有一半写进信源说法里（「据两位互不相识的知情人说」），不再在句尾另加一句
		if verified and not own_voice and not corroborated and not evidence_noted and g.has_rule("src_" + str(src.kind) + "_two") and rng.chance(0.5):
			lead_in = g.expand("#src_" + str(src.kind) + "_two#")
			corroborated = true
		elif g.has_rule(sym) and not own_voice:
			lead_in = g.expand("#" + sym + "#")
		var tail := ""
		var tail_n := 0
		# 影印件只能是档案，一篇最多说一次，也不是每次都说
		if a.get("evidence", false) and src.kind == "archive" and not evidence_noted and not corroborated and g.has_rule("evidence_note") and rng.chance(0.4):
			tail += sep + g.expand("#evidence_note#")
			evidence_noted = true
			corroborated = true
			tail_n += 1
		# 消息靠不靠得住，人写报道时会交代一句
		if tail_n == 0 and src.kind == "witness" and not own_voice and g.has_rule("limit_witness") and rng.chance(0.25):
			tail += sep + g.expand("#limit_witness#")
			tail_n += 1
		if tail_n > 0:
			pass
		elif not verified and src.kind in ["interview", "informer", "visitor", "eavesdrop", "letter"] and not hedged and g.has_rule("hedge") and rng.chance(0.5):
			tail += sep + g.expand("#hedge#")
			hedged = true
		elif verified and not corroborated and not (own_voice and src.kind == "archive"):
			var csym := "corroborated"
			if src.kind == "archive":
				csym = "corroborated_archive"
			elif src.kind == "witness":
				csym = "corroborated_witness"
			elif not (src.kind in ["interview", "informer", "visitor"]):
				csym = ""
			if csym != "" and g.has_rule(csym) and rng.chance(0.25):
				tail += sep + g.expand("#" + csym + "#")
				corroborated = true
		var sentence := fill(world, lead_in + g.expand(body_tpl), ctx, lang) + fill(world, tail, ctx, lang)
		var tied: Array = []
		for it in et.get("detail", []):
			if it is Dictionary and str(it.get("needs", "")) == str(f.key) and _unused(g, str(it.t)):
				tied.append(str(it.t))
		if not tied.is_empty() and not detail_used and rng.chance(0.5):
			ctx["vars"] = {}
			sentence += sep + fill(world, g.pick_fresh(tied), ctx, lang)
			detail_used = true
		if spec.get("counter", false) or (f.subject != target and f.get("is_rumor", false) and not spec.get("same_side", false)):
			counter_sents.append(sentence)
		else:
			if main_sents.is_empty():
				sentence = _swap_lead(sentence, data(lang).grammar.get("_lead_swap", {}))
			elif str(main_kinds[-1]) != str(src.kind) and rng.chance(0.5):
				# 换了一种证据（看见的 → 查到的），中间交代一句，读起来才不像两张卡片拼在一起。
				# 先找按这一对证据写的承接（link_witness_archive：看见之后去查了记录），没有再用通用的
				var lsym := "link_%s_%s" % [main_kinds[-1], src.kind]
				if not g.has_rule(lsym):
					lsym = "link"
				if g.has_rule(lsym):
					sentence = g.expand("#" + lsym + "#") + sep + sentence
			main_sents.append(sentence)
			main_kinds.append(src.kind)
	# 段落：一段放一到两句，长短不齐
	var i := 0
	while i < main_sents.size():
		var take := 2 if (i + 1 < main_sents.size() and rng.chance(0.35)) else 1
		var chunk: String = main_sents[i]
		if take == 2:
			chunk += sep + main_sents[i + 1]
		paras.append(polish(chunk, lang))
		i += take
	if not counter_sents.is_empty():
		var cin := g.expand("#counter_in#") if g.has_rule("counter_in") else ""
		ctx["vars"] = {}
		paras.append(polish(fill(world, cin, ctx, lang) + sep.join(counter_sents), lang))
	# 只有这件事才有的细节：有时跟在上一段后面，有时自成一小段，有时不写
	var details: Array = []
	for it in et.get("detail", []):
		var dt: String = it if it is String else str(it.t)
		if (it is String or needs_ok(it, keys)) and _unused(g, dt):
			details.append(dt)
	if not details.is_empty() and not detail_used and rng.chance(0.3):
		ctx["vars"] = {}
		var d := fill(world, g.pick_expand(details), ctx, lang)
		if paras.size() > 1 and rng.chance(0.5):
			paras[-1] = polish(paras[-1] + sep + d, lang)
		else:
			paras.append(polish(d, lang))
	# 编辑的判断：这件事为什么值得读者知道
	var comments: Array = []
	var tied_comments: Array = []
	var occ_comments: Array = []
	var t_occ: String = str(e.get("occ_at", {}).get(target, world.residents[target].occ))
	for it in et.get("comment", {}).get(tone, []) + et.get("comment", {}).get("any", []):
		if it is Dictionary and it.has("occ"):
			if t_occ in it.occ and needs_ok(it, keys):
				occ_comments.append(str(it.t))
		elif it is String or not _has_needs(it):
			comments.append(it if it is String else str(it.t))
		elif needs_ok(it, keys):
			tied_comments.append(str(it.t))
	# 能落到本篇某条证据上的评论，读起来才不像贴上去的。只剩空道理时，多半不写。
	# 评论一局只用一次：同一句判断在两篇报道里一字不差地出现，比不写更糟。
	var fresh_tied := _fresh(g, tied_comments)
	var fresh_plain := _fresh(g, comments)
	# 按职业写的评论会把化名、匿名的人认出来，只在点名时用；它多半是一句道理，排在落到证据上的评论后面
	var fresh_occ: Array = _fresh(g, occ_comments) if naming == "named" else []
	var comment_p := 0.75
	if not fresh_tied.is_empty():
		comments = fresh_occ if (not fresh_occ.is_empty() and rng.chance(0.2)) else fresh_tied
	elif not fresh_occ.is_empty():
		comments = fresh_occ
		comment_p = 0.5
	else:
		comments = fresh_plain
		comment_p = 0.3
	var comment_text := ""
	if not comments.is_empty() and rng.chance(comment_p):
		ctx["vars"] = {}
		comment_text = fill(world, g.pick_expand(comments), ctx, lang)
	# 当事人回应：先用这类事件自己的说法，没有再用通用的
	var resp_kind := "unreached"
	if e.get("plea", "") != "" or e.get("bribed_by", "") != "":
		resp_kind = "pleaded"
	elif _interviewed(world, target):
		resp_kind = "denied"
	elif world.residents[target].get("aware", false):
		resp_kind = "declined"
	# 这类事件自己的说法和通用说法放在一起挑，挑用得最少的；自己的说法只对得上登出的事实才能用
	var resp := ""
	var resp_pool: Array = eligible_strict(et.get("resp", {}).get(resp_kind, []), keys)
	# 「坚称清白」这类说法只配得上被指做了坏事的人；生病、来历、私情这类事件标了 no_charge，不用
	var gsyms: Array = ["resp_" + resp_kind]
	if not et.get("no_charge", false):
		gsyms.append("resp_" + resp_kind + "_charge")
	for gs in gsyms:
		var generic_resp = data(lang).grammar.get(gs, [])
		if generic_resp is Array:
			resp_pool = resp_pool + generic_resp
	if not resp_pool.is_empty():
		resp = g.pick_expand(resp_pool)
	var close := ""
	var ev_close: Array = eligible_strict(et.get("close", {}).get(tone, []), keys)
	# 已经有当事人的回应收尾时，很少再加一句「本报将继续关注」
	if rng.chance(0.15 if resp != "" else 0.35):
		if not ev_close.is_empty() and rng.chance(0.5):
			close = g.pick_expand(ev_close)
		elif g.has_rule("close"):
			close = g.expand("#close#")
	ctx["vars"] = {}
	var intro := ""
	# 化名、匿名的人不介绍（「镇上的警长是某位警长」）
	if naming == "named" and int(ctx.mentions.get(str(e.target), 0)) == 0 and not et.get("intro", []).is_empty():
		intro = fill(world, g.pick_expand(et.intro), ctx, lang)
	# 介绍当事人的话跟着判断走；判断和回应有时分两段
	var judge := _join([intro, comment_text], sep)
	var answer := _join([fill(world, resp, ctx, lang), fill(world, close, ctx, lang)], sep)
	if comment_text != "" and answer != "" and rng.chance(0.5):
		paras.append(polish(judge, lang))
		paras.append(polish(answer, lang))
	elif judge != "" or answer != "":
		paras.append(polish(_join([judge, answer], sep), lang))
	return {"headline": headline, "paragraphs": paras}


static func _fresh(g: Grammar, items: Array) -> Array:
	var out: Array = []
	for t in items:
		if _unused(g, str(t)):
			out.append(t)
	return out


static func _join(pieces: Array, sep: String) -> String:
	var out := ""
	for p in pieces:
		if str(p) != "":
			out += (sep if out != "" else "") + str(p)
	return out


static func _prose_for(items: Array, src_kind: String, t_occ: String = "") -> Array:
	var out: Array = []
	var generic: Array = []
	for it in items:
		if it is String:
			generic.append(it)
		elif it is Dictionary:
			if it.has("occ") and not (t_occ in it.occ):
				continue
			if it.has("not_occ") and t_occ in it.not_occ:
				continue
			if it.has("not_src") and src_kind in it.not_src:
				continue
			if it.has("src"):
				if src_kind in it.src:
					out.append(str(it.t))
			else:
				generic.append(str(it.t))
	# 有专为这个信源写的：目击只用它（通用句前面硬加「本报记者看见，」会把时间地点叠在一起），其它信源优先用它
	if not out.is_empty():
		if src_kind == "witness" or generic.is_empty():
			return out
		return out + out + generic
	return generic


## 句首是「还有人说」这类承接说法、前面却没有别的说法时，换成能单独起头的说法。
static func _swap_lead(sentence: String, swaps: Dictionary) -> String:
	for k in swaps:
		if sentence.begins_with(str(k)):
			return str(swaps[k]) + sentence.substr(str(k).length())
	return sentence


## 这句话本局还没用过（措辞记忆里计数为零）。没有记忆时一律算没用过。
static func _unused(g: Grammar, text: String) -> bool:
	return g.memory == null or int(g.memory.get("n:" + text, 0)) == 0


static func _role_of(e: Dictionary, rid: String) -> String:
	for role in e.roles:
		if rid in e.roles[role]:
			return role
	return ""


static func _interviewed(world, rid: String) -> bool:
	for fid in world.known:
		for s in world.known[fid].sources:
			if s.kind == "interview" and s.who == rid:
				return true
	return false


static func best_source(world, fid: String) -> Dictionary:
	var best := {"kind": "letter", "who": ""}
	var best_rank := 999
	for s in world.known.get(fid, {"sources": []}).sources:
		var rank := SOURCE_PRIORITY.find(s.kind)
		if rank >= 0 and rank < best_rank:
			best_rank = rank
			best = s
	return best


# ================================================================ 信与来访
## L: {kind, roles: {role: rid}, extras: {}, vars: {}, id}
## 返回 {text, from}
static func letter(world, L: Dictionary, lang: String) -> Dictionary:
	var spec: Dictionary = data(lang).letters.get(L.kind, {})
	var items: Array = spec.get("items", [])
	var who: String = L.get("roles", {}).get("who", "")
	var rng := text_rng(world, ["letter", L.get("week", world.week), L.kind, L.get("id", 0)])
	var picked := _pick_conditional(world, items, who, rng)
	if picked == "":
		return {"text": "(%s)" % L.kind, "from": ""}
	var ctx := {"roles": L.get("roles", {}), "naming": {}, "extras": L.get("extras", {}), "vars": L.get("vars", {}), "mentions": {}}
	var text := render(world, picked, ctx, lang, rng)
	var from := ""
	if spec.get("sign", true) and who != "":
		from = person_name(world, who, lang)
	return {"text": text, "from": from}


## item: {who, kind, event, offer, fact, subject}
static func visitor_lines(world, item: Dictionary, lang: String) -> Array:
	var items: Array = data(lang).visitors.get(item.kind, [])
	var rng := text_rng(world, ["visit", world.week, item.who, item.kind, item.get("event", "")])
	var roles := {"who": item.who}
	var e: Dictionary = world.event_by_id(item.get("event", "")) if item.get("event", "") != "" else {}
	var vars := {"offer": str(item.get("offer", 0)), "event": event_name(world, e, lang) if not e.is_empty() else ("that business" if lang == "en" else "那件事")}
	if not e.is_empty():
		var tgt: String = e.roles[e.target][0]
		if tgt != item.who:
			roles["subject"] = tgt
	if item.get("fact", "") != "":
		vars["fact"] = fact_note(world, item.fact, lang)
	if not roles.has("subject"):
		roles["subject"] = item.who
	var chosen = _pick_conditional_obj(world, items, item.who, rng, vars, e)
	if chosen == null:
		return ["(%s)" % item.kind]
	var ctx := {"roles": roles, "naming": {}, "extras": e.get("extras", {}) if not e.is_empty() else {}, "vars": vars, "mentions": {}}
	var out: Array = []
	for line in chosen.lines:
		out.append(render(world, str(line), ctx, lang, rng))
	return out


## 条件：{bucket: [...], female: bool, trait: [...], occ: [...], min_sev: n, has_fact: bool, has_subject: bool}
static func _cond_ok(world, cond: Dictionary, who: String, vars: Dictionary = {}, e: Dictionary = {}) -> bool:
	if cond.is_empty():
		return true
	if who == "" or not world.residents.has(who):
		return not (cond.has("bucket") or cond.has("female") or cond.has("trait") or cond.has("occ"))
	var r: Dictionary = world.residents[who]
	if cond.has("bucket") and not (r.bucket in cond.bucket):
		return false
	if cond.has("female") and bool(r.female) != bool(cond.female):
		return false
	if cond.has("occ") and not (r.occ in cond.occ):
		return false
	if cond.has("trait"):
		var ok := false
		for t in cond.trait:
			if t in r.traits:
				ok = true
		if not ok:
			return false
	if cond.has("min_sev") and (e.is_empty() or int(e.severity) < int(cond.min_sev)):
		return false
	if cond.get("has_fact", false) and not vars.has("fact"):
		return false
	if cond.has("no_fact") and vars.has("fact"):
		return false
	if cond.get("other_subject", false) and (e.is_empty() or e.roles[e.target][0] == who):
		return false
	return true


static func _pick_conditional(world, items: Array, who: String, rng: Rng) -> String:
	var pool: Array = []
	for it in items:
		if it is String:
			pool.append(it)
		elif it is Dictionary and _cond_ok(world, it.get("if", {}), who):
			pool.append(it.t)
	if pool.is_empty():
		return ""
	return str(rng.pick(pool))


static func _pick_conditional_obj(world, items: Array, who: String, rng: Rng, vars: Dictionary, e: Dictionary):
	var specific: Array = []
	var generic: Array = []
	for it in items:
		var cond: Dictionary = it.get("if", {})
		if not _cond_ok(world, cond, who, vars, e):
			continue
		if cond.is_empty():
			generic.append(it)
		else:
			specific.append(it)
	# 有对得上性格的就优先用，八成概率
	if not specific.is_empty() and (generic.is_empty() or rng.chance(0.8)):
		return rng.pick(specific)
	if not generic.is_empty():
		return rng.pick(generic)
	return null


# ================================================================ 界面短句
static func ui(world, key: String, args: Dictionary, lang: String) -> String:
	var spec = data(lang).ui.get(key, null)
	if spec == null:
		if lang != "zh":
			spec = data("zh").ui.get(key, null)
		if spec == null:
			return "〔%s〕" % key
	world.text_counter += 1
	var rng := text_rng(world, ["ui", world.week, world.day, world.text_counter, key])
	var tpl: String = spec if spec is String else str(rng.pick(spec))
	for k in args:
		tpl = tpl.replace("{" + k + "}", str(args[k]))
	var g := grammar_for(world, lang, rng)
	return polish(g.expand(tpl), lang)
