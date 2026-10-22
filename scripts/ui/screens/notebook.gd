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
	var te := K.button(Game.t("notebook.tab_events"), func(): _tab = "events"; _sel = ""; _build())
	te.disabled = _tab == "events"
	tabs.add_child(te)
	var tp := K.button(Game.t("notebook.tab_people"), func(): _tab = "people"; _sel = ""; _build())
	tp.disabled = _tab == "people"
	tabs.add_child(tp)
	var nl: int = Game.world.leads.size()
	var tl := K.button(Game.t("notebook.tab_leads_n", {"n": nl}) if nl > 0 else Game.t("notebook.tab_leads"), func(): _tab = "leads"; _sel = ""; _build())
	tl.disabled = _tab == "leads"
	tabs.add_child(tl)
	var close := K.button(Game.t("notebook.close"), func(): Game.close_overlay(), 50)
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
		sl[1].add_child(K.para(Game.t("notebook.events_empty"), 270, "hand", 11, P.PENCIL))
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
		var tag: String = (Game.t("notebook.tag_printed_fresh") if not g.fresh.is_empty() else Game.t("notebook.tag_printed")) if e.printed else (Game.t("notebook.tag_soft") if e.soft else "")
		var txt := Game.t("notebook.event_row", {"name": TE.event_name(w, e, Game.lang), "tag": tag, "n": g.facts.size(), "ok": n_ok})
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
	var title := K.para(TE.event_name(w, e, Game.lang), 270, "hand", 14, P.PRINT_INK)
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
		v.add_child(K.para(TE.fact_note(w, fid, Game.lang), 230, "hand", 11, P.PENCIL, 1))
		var srcs: Array = []
		var times := {}
		for s in w.known[fid].sources:
			var key: String = Game.t("notebook.source_" + str(s.kind)) + ("" if s.who == "" else "·" + Game.name_of(s.who))
			if not times.has(key):
				srcs.append(key)
			times[key] = int(times.get(key, 0)) + 1
		var shown: Array = []
		for key in srcs:
			shown.append(key + (Game.t("notebook.source_times", {"n": times[key]}) if times[key] > 1 else ""))
		var meta := Game.t("notebook.sources") + Game.t("notebook.source_sep").join(shown)
		if w.known[fid].evidence:
			meta += Game.t("notebook.has_evidence")
		v.add_child(K.para(meta, 230, "pixel", 12, P.WARM_GREY, 0))
		hb.add_child(v)
		sl[1].add_child(hb)
	if not g.hints.is_empty() and not e.printed:
		sl[1].add_child(K.label(Game.t("notebook.where_else"), "pixel", 12, P.STAMP_RED))
		var seen := {}
		for h in g.hints:
			if not seen.has(h):
				seen[h] = true
				sl[1].add_child(K.para("· " + h, 260, "hand", 10, P.PENCIL, 0))
	var legend := K.label(Game.t("notebook.legend"), "pixel", 12, P.WARM_GREY)
	legend.position = Vector2(12, 304)
	_right.add_child(legend)


# ------------------------------------------------------------ 线头
func _leads() -> void:
	var w = Game.world
	var sl: Array = K.scroll_list(Vector2(8, 34), Vector2(284, 286), 6)
	_left.add_child(sl[0])
	if w.leads.is_empty():
		sl[1].add_child(K.para(Game.t("notebook.leads_empty"), 270, "hand", 11, P.PENCIL))
	for l in w.leads:
		var who: String = l.who
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		hb.add_child(K.image(Portrait.face(w, who)))
		var where: String = w.where_is(who)
		var at: String = Game.t("notebook.lead_at", {"where": Game.place(where)}) if where != "" and not where.begins_with("home:") and w.slot <= 1 else Game.t("notebook.lead_not_out")
		var txt := Game.t("notebook.lead_row", {"who": Game.name_of(who), "occ": Game.occ(who), "from": Game.name_of(str(l.from)), "week": int(l.week), "at": at})
		hb.add_child(K.para(txt, 236, "hand", 11, P.PENCIL, 1))
		sl[1].add_child(hb)
	var t := K.para(Game.t("notebook.tab_leads"), 270, "hand", 14, P.PRINT_INK)
	t.position = Vector2(12, 10)
	_right.add_child(t)
	var help := K.para(Game.t("notebook.leads_help"), 266, "hand", 11, P.PENCIL, 3)
	help.position = Vector2(14, 44)
	_right.add_child(help)


# ------------------------------------------------------------ 按人
func _people() -> void:
	var w = Game.world
	var people := _people_of_interest()
	var sl: Array = K.scroll_list(Vector2(8, 34), Vector2(284, 286), 2)
	_left.add_child(sl[0])
	if people.is_empty():
		sl[1].add_child(K.para(Game.t("notebook.people_empty"), 270, "hand", 11, P.PENCIL))
		return
	if _sel == "" or not (_sel in people):
		_sel = people[0]
	for rid in people:
		var r: Dictionary = w.residents[rid]
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		hb.add_child(K.image(Portrait.face(w, rid)))
		var who: String = rid
		var b := K.row(Game.t("notebook.person_row", {"name": Game.name_of(rid), "occ": Game.occ(rid)}), func(): _sel = who; _build(), 236)
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
	var nm := K.label(Game.name_of(rid), "hand", 16, P.PRINT_INK)
	nm.position = Vector2(84, 14)
	_right.add_child(nm)
	var sub := Game.t("notebook.occ_age", {"occ": Game.occ(rid), "age": int(r.age)})
	if not r.in_town:
		sub += Game.t("notebook.left_town")
	elif not r.alive:
		sub += Game.t("notebook.deceased")
	var s := K.label(sub, "hand", 11, P.PENCIL)
	s.position = Vector2(84, 38)
	_right.add_child(s)
	var where: String = w.where_is(rid)
	if where != "" and w.day <= 6 and w.slot <= 1:
		var wl := K.label(Game.t("notebook.now_at", {"where": Game.place(where)}), "pixel", 12, P.WARM_GREY)
		wl.position = Vector2(84, 56)
		_right.add_child(wl)
	var sl: Array = K.scroll_list(Vector2(8, 82), Vector2(284, 212), 4)
	_right.add_child(sl[0])
	var fam: Array = []
	if r.spouse != "" and w.residents.has(r.spouse):
		fam.append(Game.t("notebook.spouse", {"name": Game.name_of(r.spouse)}))
	for f in r.family:
		if f != r.spouse and w.residents.has(f):
			fam.append(Game.name_of(f))
	sl[1].add_child(K.para(Game.t("notebook.family") + (Game.t("notebook.family_sep").join(fam) if not fam.is_empty() else Game.t("notebook.family_none")), 270, "hand", 11, P.PENCIL))
	var about: Array = []
	var told: Array = []
	for fid in w.known:
		if w.facts[fid].subject == rid:
			about.append(fid)
		for src in w.known[fid].sources:
			if src.who == rid and not (fid in told):
				told.append(fid)
	if not about.is_empty():
		sl[1].add_child(K.label(Game.t("notebook.about_him") if not r.female else Game.t("notebook.about_her"), "pixel", 12, P.STAMP_RED))
		for fid in about:
			sl[1].add_child(K.para("· " + TE.fact_note(w, fid, Game.lang), 266, "hand", 10, P.PENCIL, 0))
	if not told.is_empty():
		sl[1].add_child(K.label(Game.t("notebook.told_by"), "pixel", 12, P.WARM_GREY))
		for fid in told:
			sl[1].add_child(K.para("· " + TE.fact_note(w, fid, Game.lang), 266, "hand", 10, P.PENCIL, 0))


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
