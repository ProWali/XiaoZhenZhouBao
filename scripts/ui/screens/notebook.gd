## 选题簿（叠层）：一本可翻页的笔记本（策划案九版决策 4）。
## 「按事」：每件事一页，列已知碎片、谁说的、盖了几枚章（三枚即交叉验证）、还能去哪查。
## 「按人」：每人一页，列他的家人和跟他有关的碎片。
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")
const Portrait = preload("res://scripts/ui/portrait.gd")
const TE = preload("res://scripts/text/text_engine.gd")
const T = preload("res://scripts/sim/tables.gd")

var params := {}
var _tab := "events"
var _sel := ""
var _left: Control
var _right: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(K.rect(Color(P.INK, 0.6), Vector2.ZERO, Vector2(640, 360)))
	# 摊开的本子：两页
	add_child(K.rect(P.DARK_BROWN, Vector2(14, 12), Vector2(612, 338)))
	_left = K.paper(Vector2(22, 18), Vector2(296, 326), P.NOTE_PAPER)
	_right = K.paper(Vector2(322, 18), Vector2(296, 326), P.NOTE_PAPER)
	add_child(_left)
	add_child(_right)
	add_child(K.rect(Color(P.INK, 0.25), Vector2(318, 18), Vector2(4, 326)))
	Game.sfx("page_turn")
	_build()


func _build() -> void:
	for page in [_left, _right]:
		for i in range(2, page.get_child_count()):
			page.get_child(i).queue_free()
	var tabs := HBoxContainer.new()
	tabs.position = Vector2(10, 8)
	tabs.add_theme_constant_override("separation", 4)
	_left.add_child(tabs)
	var te := K.button("按事", func(): _tab = "events"; _sel = ""; _build())
	te.disabled = _tab == "events"
	tabs.add_child(te)
	var tp := K.button("按人", func(): _tab = "people"; _sel = ""; _build())
	tp.disabled = _tab == "people"
	tabs.add_child(tp)
	var nl: int = Game.world.leads.size()
	var tl := K.button("线头 %d" % nl if nl > 0 else "线头", func(): _tab = "leads"; _sel = ""; _build())
	tl.disabled = _tab == "leads"
	tabs.add_child(tl)
	var close := K.button("合上", func(): Game.close_overlay(), 50)
	close.position = Vector2(238, 300)
	_right.add_child(close)
	if _tab == "events":
		_events()
	elif _tab == "leads":
		_leads()
	else:
		_people()


# ------------------------------------------------------------ 按事
func _events() -> void:
	var w = Game.world
	var groups: Array = w.notebook()
	var sl: Array = K.scroll_list(Vector2(8, 34), Vector2(284, 286), 3)
	_left.add_child(sl[0])
	if groups.is_empty():
		sl[1].add_child(K.para("还是空的。出门找人聊聊，听到的事会记在这里。", 270, "hand", 11, P.PENCIL))
		return
	# 没登过的在前，登过的在后
	groups.sort_custom(func(a, b): return int(a.event.printed and a.fresh.is_empty()) < int(b.event.printed and b.fresh.is_empty()))
	if _sel == "":
		_sel = groups[0].event.id
	for g in groups:
		var e: Dictionary = g.event
		var n_ok := 0
		for fid in g.facts:
			if w.is_verified(fid):
				n_ok += 1
		var tag: String = ("（已登，有新料）" if not g.fresh.is_empty() else "（已登）") if e.printed else ("（软新闻）" if e.soft else "")
		var txt := "%s%s\n%d 条碎片，%d 条坐实" % [TE.event_name(w, e, "zh"), tag, g.facts.size(), n_ok]
		var eid: String = e.id
		var b := K.row(txt, func(): _sel = eid; _build(), 270, "hand", 11)
		if eid == _sel:
			b.add_theme_stylebox_override("normal", K.box(P.LAMP, P.INK, 1, 4))
		sl[1].add_child(b)
	for g in groups:
		if g.event.id == _sel:
			_event_page(g)


func _event_page(g: Dictionary) -> void:
	var w = Game.world
	var e: Dictionary = g.event
	var title := K.para(TE.event_name(w, e, "zh"), 270, "hand", 14, P.PRINT_INK)
	title.position = Vector2(12, 10)
	_right.add_child(title)
	var sl: Array = K.scroll_list(Vector2(8, 38), Vector2(284, 256), 6)
	_right.add_child(sl[0])
	for fid in g.facts:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 5)
		hb.add_child(K.stamps(mini(3, int(w.verify_score(fid)))))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.add_child(K.para(TE.fact_note(w, fid, "zh"), 230, "hand", 11, P.PENCIL, 1))
		var srcs: Array = []
		var times := {}
		for s in w.known[fid].sources:
			var key: String = T.SOURCE_NAME[s.kind] + ("" if s.who == "" else "·" + w.res_name(s.who))
			if not times.has(key):
				srcs.append(key)
			times[key] = int(times.get(key, 0)) + 1
		var shown: Array = []
		for key in srcs:
			shown.append(key + ("（%d 次，只算一个来源）" % times[key] if times[key] > 1 else ""))
		var meta := "来源：" + "，".join(shown)
		if w.known[fid].evidence:
			meta += "  · 有档案可附"
		v.add_child(K.para(meta, 230, "pixel", 12, P.WARM_GREY, 0))
		hb.add_child(v)
		sl[1].add_child(hb)
	if not g.hints.is_empty() and not e.printed:
		sl[1].add_child(K.label("还能去哪查：", "pixel", 12, P.STAMP_RED))
		var seen := {}
		for h in g.hints:
			if not seen.has(h):
				seen[h] = true
				sl[1].add_child(K.para("· " + h, 260, "hand", 10, P.PENCIL, 0))
	var legend := K.label("一枚章＝一个来源。三枚算坐实。", "pixel", 12, P.WARM_GREY)
	legend.position = Vector2(12, 304)
	_right.add_child(legend)


# ------------------------------------------------------------ 线头
func _leads() -> void:
	var w = Game.world
	var sl: Array = K.scroll_list(Vector2(8, 34), Vector2(284, 286), 6)
	_left.add_child(sl[0])
	if w.leads.is_empty():
		sl[1].add_child(K.para("还没有。找人聊天问不出东西时，对方有时会给你指个人，记在这里。", 270, "hand", 11, P.PENCIL))
	for l in w.leads:
		var who: String = l.who
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		hb.add_child(K.image(Portrait.face(w, who)))
		var where: String = w.where_is(who)
		var at: String = "这会儿在" + w.loc_name(where) if where != "" and not where.begins_with("home:") and w.slot <= 1 else "这会儿不在外面"
		var txt := "★ %s（%s）\n%s指的，第 %d 周。%s" % [w.res_name(who), TE.occ_label(w, who, "zh"), w.res_name(str(l.from)), int(l.week), at]
		hb.add_child(K.para(txt, 236, "hand", 11, P.PENCIL, 1))
		sl[1].add_child(hb)
	var t := K.para("线头", 270, "hand", 14, P.PRINT_INK)
	t.position = Vector2(12, 10)
	_right.add_child(t)
	var help := K.para("有人说「你去问问某某」，就记在左边。\n\n去找那个人，随便聊聊就行：说是谁让你来的，对方多半肯开口，说的也多半是同一件事。\n\n地图名牌和地点里有 ★ 的地方，就是线头上的人这会儿在的地方。\n\n线头放三周就凉了。", 266, "hand", 11, P.PENCIL, 3)
	help.position = Vector2(14, 44)
	_right.add_child(help)


# ------------------------------------------------------------ 按人
func _people() -> void:
	var w = Game.world
	var people := _people_of_interest()
	var sl: Array = K.scroll_list(Vector2(8, 34), Vector2(284, 286), 2)
	_left.add_child(sl[0])
	if people.is_empty():
		sl[1].add_child(K.para("还没跟谁打过交道。", 270, "hand", 11, P.PENCIL))
		return
	if _sel == "" or not (_sel in people):
		_sel = people[0]
	for rid in people:
		var r: Dictionary = w.residents[rid]
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		hb.add_child(K.image(Portrait.face(w, rid)))
		var who: String = rid
		var b := K.row("%s（%s）" % [r.name, TE.occ_label(w, rid, "zh")], func(): _sel = who; _build(), 236)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if rid == _sel:
			b.add_theme_stylebox_override("normal", K.box(P.LAMP, P.INK, 1, 4))
		hb.add_child(b)
		sl[1].add_child(hb)
	_person_page(_sel)


func _person_page(rid: String) -> void:
	var w = Game.world
	var r: Dictionary = w.residents[rid]
	var face := K.image(Portrait.face(w, rid), Vector2(12, 12))
	face.scale = Vector2(2, 2)
	_right.add_child(face)
	var nm := K.label(r.name, "hand", 16, P.PRINT_INK)
	nm.position = Vector2(84, 14)
	_right.add_child(nm)
	var sub := "%s，%d 岁" % [TE.occ_label(w, rid, "zh"), int(r.age)]
	if not r.in_town:
		sub += "，已离镇"
	elif not r.alive:
		sub += "，已故"
	var s := K.label(sub, "hand", 11, P.PENCIL)
	s.position = Vector2(84, 38)
	_right.add_child(s)
	var where: String = w.where_is(rid)
	if where != "" and w.day <= 6 and w.slot <= 1:
		var wl := K.label("这会儿在：" + (w.loc_name(where)), "pixel", 12, P.WARM_GREY)
		wl.position = Vector2(84, 56)
		_right.add_child(wl)
	var sl: Array = K.scroll_list(Vector2(8, 82), Vector2(284, 212), 4)
	_right.add_child(sl[0])
	var fam: Array = []
	if r.spouse != "" and w.residents.has(r.spouse):
		fam.append("配偶 " + w.res_name(r.spouse))
	for f in r.family:
		if f != r.spouse and w.residents.has(f):
			fam.append(w.res_name(f))
	sl[1].add_child(K.para("家里人：" + ("、".join(fam) if not fam.is_empty() else "没听说"), 270, "hand", 11, P.PENCIL))
	var about: Array = []
	var told: Array = []
	for fid in w.known:
		if w.facts[fid].subject == rid:
			about.append(fid)
		for src in w.known[fid].sources:
			if src.who == rid and not (fid in told):
				told.append(fid)
	if not about.is_empty():
		sl[1].add_child(K.label("关于他的事：" if not r.female else "关于她的事：", "pixel", 12, P.STAMP_RED))
		for fid in about:
			sl[1].add_child(K.para("· " + TE.fact_note(w, fid, "zh"), 266, "hand", 10, P.PENCIL, 0))
	if not told.is_empty():
		sl[1].add_child(K.label("从这里听来的：", "pixel", 12, P.WARM_GREY))
		for fid in told:
			sl[1].add_child(K.para("· " + TE.fact_note(w, fid, "zh"), 266, "hand", 10, P.PENCIL, 0))


func _people_of_interest() -> Array:
	var w = Game.world
	var seen := {}
	for fid in w.known:
		seen[w.facts[fid].subject] = true
		for s in w.known[fid].sources:
			if s.who != "":
				seen[s.who] = true
	for a in w.actions:
		if a.get("kind", "") == "interview":
			seen[str(a.rid)] = true
	var out: Array = []
	for rid in w.residents:
		if seen.has(rid):
			out.append(rid)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Game.close_overlay()
