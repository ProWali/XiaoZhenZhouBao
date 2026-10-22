## 周日排版台：左边从选题簿挑事、做四个决定（碎片、语气、署名、证据）、在三个候选标题里选一个；
## 右边是一张真实版式的报纸，改什么都立刻重排。玩家不手写文字（策划案九版决策 2）。
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")
const TE = preload("res://scripts/text/text_engine.gd")

const SLOTS := ["head", "second", "third", "small"]
## 选项的文字在 layout 表里：tone_calm / tone_calm_tip 这样按「组_值」取
const TONES := ["calm", "neutral", "hot"]
const NAMINGS := ["named", "alias", "anon"]
## 版面上各栏的位置（相对报纸）
const AREA := {"head": Rect2(8, 50, 296, 124), "second": Rect2(8, 180, 146, 114), "third": Rect2(158, 180, 146, 114), "small": Rect2(8, 298, 146, 38)}

var params := {}
var _arts := {}        # slot -> {slot, facts, tone, naming, evidence, reroll}
var _eids := {}        # slot -> event id
var _choice := {}      # slot -> 候选标题序号
var _preview := {}     # slot -> {candidates, headline, paragraphs}
var _sel_story := ""
var _edit := ""
var _left: Control
var _page: Control


func _ready() -> void:
	var w = Game.world
	add_child(K.rect(P.DARK_BROWN, Vector2.ZERO, Vector2(640, 360)))
	for y in range(0, 360, 24):
		add_child(K.rect(Color(P.BROWN, 0.35), Vector2(0, y), Vector2(640, 1)))
	_left = Control.new()
	_left.position = Vector2(6, 6)
	_left.size = Vector2(310, 348)
	add_child(_left)
	_page = Control.new()
	_page.position = Vector2(322, 6)
	_page.size = Vector2(312, 348)
	add_child(_page)
	Game.ambience("night_ambience")
	Game.music("piano_3")
	if int(Game.ui.get("layout_week", 0)) == w.week:
		_restore()
	_refresh()


# ------------------------------------------------------------ 状态
func _groups() -> Array:
	var out: Array = []
	for g in Game.world.notebook():
		# 没登过的事；登过但又听到了新料的，可以登续报
		if not g.event.printed or not g.fresh.is_empty():
			out.append(g)
	return out


func _group(eid: String) -> Dictionary:
	for g in _groups():
		if g.event.id == eid:
			return g
	return {}


func _placed(eid: String) -> String:
	for s in _eids:
		if _eids[s] == eid:
			return s
	return ""


func _place(eid: String, slot: String) -> void:
	var w = Game.world
	var g := _group(eid)
	var facts: Array = (g.fresh if g.event.printed else g.facts).duplicate()
	facts.sort_custom(func(a, b): return w.verify_score(a) > w.verify_score(b))
	# 默认只勾坐实到两枚章以上的；一条都没有就只勾最好的那条。没坐实的登不登，让玩家自己选
	var solid: Array = []
	for fid in facts:
		if w.verify_score(fid) >= 2.0:
			solid.append(fid)
	facts = solid.slice(0, 4) if not solid.is_empty() else facts.slice(0, 1)
	var ev := false
	for fid in facts:
		if w.known[fid].evidence:
			ev = true
	_arts[slot] = {"slot": slot, "facts": facts, "tone": "neutral", "naming": "named" if g.event.soft else "alias", "evidence": ev, "reroll": 0}
	_eids[slot] = eid
	_choice[slot] = 0
	_edit = slot
	_sel_story = ""
	Game.sfx("paper_slide")
	Game.track("layout_place", {"slot": slot, "event": g.event.tid})


func _remove(slot: String) -> void:
	_arts.erase(slot)
	_eids.erase(slot)
	_choice.erase(slot)
	_edit = ""


func _ordered() -> Array:
	var out: Array = []
	for s in SLOTS:
		if _arts.has(s):
			out.append(_arts[s])
	return out


func _recompute() -> void:
	_preview.clear()
	var list := _ordered()
	if list.is_empty():
		return
	var res: Array = Game.world.preview_issue(list, _choice)
	for i in list.size():
		_preview[list[i].slot] = res[i]


## 排了一半退出再进来，版面还在
func _save_state() -> void:
	Game.ui.layout_week = Game.world.week
	Game.ui.layout = {"arts": _arts.duplicate(true), "eids": _eids.duplicate(), "choice": _choice.duplicate()}


func _restore() -> void:
	var st: Dictionary = Game.ui.get("layout", {})
	var valid := {}
	for g in _groups():
		valid[g.event.id] = true
	for s in st.get("arts", {}):
		var eid: String = str(st.eids.get(s, ""))
		if not valid.has(eid):
			continue
		var a: Dictionary = st.arts[s]
		a.reroll = int(a.reroll)
		_arts[s] = a
		_eids[s] = eid
		_choice[s] = int(st.choice.get(s, 0))


func _refresh() -> void:
	_recompute()
	_save_state()
	for c in _left.get_children():
		c.queue_free()
	for c in _page.get_children():
		c.queue_free()
	if _edit != "" and _arts.has(_edit):
		_editor(_edit)
	else:
		_edit = ""
		_story_list()
	_newspaper()


# ------------------------------------------------------------ 左边：选题
func _story_list() -> void:
	var w = Game.world
	var sheet := K.paper(Vector2.ZERO, Vector2(310, 348), P.NOTE_PAPER)
	_left.add_child(sheet)
	var t := K.label(Game.t("layout.title"), "serif_black", 14, P.PRINT_INK)
	t.position = Vector2(10, 8)
	sheet.add_child(t)
	var hint := K.para(Game.t("layout.hint"), 290, "pixel", 12, P.WARM_GREY, 0)
	hint.position = Vector2(10, 30)
	sheet.add_child(hint)
	var groups := _groups()
	var sl: Array = K.scroll_list(Vector2(6, 64), Vector2(298, 196), 3)
	sheet.add_child(sl[0])
	if groups.is_empty():
		sl[1].add_child(K.para(Game.t("layout.nothing"), 280, "hand", 11, P.PENCIL))
	for g in groups:
		var e: Dictionary = g.event
		var eid: String = e.id
		var n_ok := 0
		for fid in g.facts:
			if w.is_verified(fid):
				n_ok += 1
		var at := _placed(eid)
		var tag: String = Game.t("layout.tag_followup", {"n": g.fresh.size()}) if e.printed else (Game.t("layout.tag_soft") if e.soft else "")
		var txt := Game.t("layout.story_line", {"name": TE.event_name(w, e, Game.lang), "tag": tag, "n": g.facts.size(), "ok": n_ok, "at": Game.t("layout.placed_at", {"slot": _slot_name(at)}) if at != "" else ""})
		var b := K.row(txt, func():
			if _placed(eid) != "":
				_edit = _placed(eid)
			else:
				_sel_story = eid
			_refresh(), 284, "hand", 11)
		if eid == _sel_story:
			b.add_theme_stylebox_override("normal", K.box(P.LAMP, P.INK, 1, 4))
		elif at != "":
			b.add_theme_stylebox_override("normal", K.box(P.NEWSPRINT_SHADE, P.WARM_GREY, 1, 4))
		sl[1].add_child(b)
	if _sel_story != "":
		var lab := K.label(Game.t("layout.place_into"), "pixel", 12, P.PRINT_INK)
		lab.position = Vector2(10, 270)
		sheet.add_child(lab)
		var hb := HBoxContainer.new()
		hb.position = Vector2(48, 266)
		hb.add_theme_constant_override("separation", 3)
		sheet.add_child(hb)
		for s in SLOTS:
			var slot: String = s
			var b := K.button(_slot_name(s), func(): _place(_sel_story, slot); _refresh())
			b.disabled = _arts.has(s)
			b.tooltip_text = Game.t("layout.hint_" + s)
			hb.add_child(b)
		hb.get_child(0).call_deferred("grab_focus")
	var go := K.button(Game.t("layout.go_press"), _print, 90)
	go.position = Vector2(206, 314)
	sheet.add_child(go)
	var nb := K.button(Game.t("layout.open_notebook"), func(): Game.open_overlay("notebook"), 0)
	nb.position = Vector2(10, 314)
	sheet.add_child(nb)


# ------------------------------------------------------------ 左边：编辑一条
func _editor(slot: String) -> void:
	var w = Game.world
	var a: Dictionary = _arts[slot]
	var g := _group(_eids[slot])
	var e: Dictionary = g.event
	var sheet := K.paper(Vector2.ZERO, Vector2(310, 348), P.NOTE_PAPER)
	_left.add_child(sheet)
	# 只占一行：事件名长（英文常见）就截成省略号，全名放在悬停提示里
	var title := Game.t("layout.editor_title", {"slot": _slot_name(slot), "name": TE.event_name(w, e, Game.lang)})
	var t := K.label(title, "serif_black", 12, P.PRINT_INK)
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.clip_text = true
	t.custom_minimum_size.x = 200
	t.size.x = 200
	t.tooltip_text = title
	t.mouse_filter = Control.MOUSE_FILTER_PASS
	t.position = Vector2(10, 8)
	sheet.add_child(t)
	var back := K.button(Game.t("layout.back"), func(): _edit = ""; _refresh(), 0)
	back.position = Vector2(262, 6)
	sheet.add_child(back)
	var rm := K.button(Game.t("layout.remove"), func(): _remove(slot); _refresh(), 0)
	rm.position = Vector2(220, 6)
	sheet.add_child(rm)
	var sl: Array = K.scroll_list(Vector2(6, 36), Vector2(300, 306), 5)
	sheet.add_child(sl[0])
	var box: VBoxContainer = sl[1]
	# 碎片
	box.add_child(K.label(Game.t("layout.facts"), "pixel", 12, P.STAMP_RED))
	box.add_child(K.para(Game.t("layout.facts_warn"), 280, "pixel", 12, P.WARM_GREY, 0))
	for fid in g.facts:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 3)
		var cb := CheckBox.new()
		cb.button_pressed = fid in a.facts
		var f: String = fid
		cb.toggled.connect(func(on):
			if on and not (f in a.facts) and a.facts.size() < 4:
				a.facts.append(f)
			elif not on and a.facts.size() > 1:
				a.facts.erase(f)
			_fix_evidence(a)
			_refresh())
		hb.add_child(cb)
		hb.add_child(K.stamps(mini(3, int(w.verify_score(fid)))))
		var shaky: bool = w.verify_score(fid) < 2.0
		hb.add_child(K.para((Game.t("layout.unconfirmed") if shaky else "") + TE.fact_note(w, fid, Game.lang), 214, "hand", 10, P.STAMP_RED if shaky else P.PENCIL, 0))
		box.add_child(hb)
	# 语气
	box.add_child(_choice_row("tone", TONES, a.tone, func(v): a.tone = v; _choice[slot] = 0; _refresh(), false))
	# 署名
	box.add_child(_choice_row("naming", NAMINGS, a.naming, func(v): a.naming = v; _choice[slot] = 0; _refresh(), e.soft))
	if e.soft:
		box.add_child(K.para(Game.t("layout.soft_note"), 280, "pixel", 12, P.WARM_GREY, 0))
	# 证据
	var has_ev := false
	for fid in a.facts:
		if w.known[fid].evidence:
			has_ev = true
	var evb := CheckBox.new()
	evb.text = Game.t("layout.evidence")
	evb.disabled = not has_ev
	evb.button_pressed = a.evidence and has_ev
	evb.toggled.connect(func(on): a.evidence = on; _refresh())
	box.add_child(evb)
	box.add_child(K.para(Game.t("layout.evidence_tip") if has_ev else Game.t("layout.evidence_none"), 280, "pixel", 12, P.WARM_GREY, 0))
	# 标题
	box.add_child(K.label(Game.t("layout.headline"), "pixel", 12, P.STAMP_RED))
	var pv: Dictionary = _preview.get(slot, {})
	var cands: Array = pv.get("candidates", [])
	for i in cands.size():
		var idx := i
		var b := K.row(("● " if int(_choice.get(slot, 0)) == i else "○ ") + str(cands[i]), func(): _choice[slot] = idx; Game.sfx("typewriter_key"); _refresh(), 284, "serif", 10)
		if int(_choice.get(slot, 0)) == i:
			b.add_theme_stylebox_override("normal", K.box(P.LAMP, P.INK, 1, 4))
		box.add_child(b)
	var hb2 := HBoxContainer.new()
	hb2.add_theme_constant_override("separation", 4)
	var rr := K.button(Game.t("layout.reroll") if int(a.reroll) == 0 else Game.t("layout.rerolled"), func():
		a.reroll = 1
		_choice[slot] = 0
		Game.sfx("typewriter_bell")
		Game.track("reroll", {"slot": slot})
		_refresh(), 0)
	rr.disabled = int(a.reroll) > 0
	hb2.add_child(rr)
	hb2.add_child(K.button(Game.t("layout.read_full"), func(): _proof(slot), 0))
	box.add_child(hb2)


func _fix_evidence(a: Dictionary) -> void:
	var has := false
	for fid in a.facts:
		if Game.world.known[fid].evidence:
			has = true
	if not has:
		a.evidence = false


## group：tone / naming，文字按 layout.<group>、layout.<group>_<值>、layout.<group>_<值>_tip 取
func _choice_row(group: String, opts: Array, cur: String, cb: Callable, disabled: bool) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 3)
	hb.add_child(K.label(Game.t("layout." + group), "pixel", 12, P.STAMP_RED))
	var tip := ""
	for o in opts:
		var val: String = o
		var key := "layout.%s_%s" % [group, val]
		var b := K.button(Game.t(key), func(): Game.sfx("typewriter_key"); cb.call(val), 44)
		if val == cur:
			b.add_theme_stylebox_override("normal", K.box(P.OCHRE, P.INK, 1, 2))
			b.add_theme_stylebox_override("disabled", K.box(P.OCHRE, P.WARM_GREY, 1, 2))
			tip = Game.t(key + "_tip")
		b.disabled = disabled
		b.tooltip_text = Game.t(key + "_tip")
		hb.add_child(b)
	v.add_child(hb)
	if not disabled:
		v.add_child(K.para(tip, 280, "pixel", 12, P.WARM_GREY, 0))
	return v


func _proof(slot: String) -> void:
	var pv: Dictionary = _preview.get(slot, {})
	Game.track("proof", {"slot": slot})
	Game.open_overlay("proof", {"slot": _slot_name(slot), "headline": pv.get("headline", ""), "paragraphs": pv.get("paragraphs", [])})


func _slot_name(s: String) -> String:
	return Game.t("layout.slot_" + s)


# ------------------------------------------------------------ 右边：报纸
func _newspaper() -> void:
	var w = Game.world
	var sheet := K.paper(Vector2.ZERO, Vector2(312, 348), P.NEWSPRINT)
	_page.add_child(sheet)
	var mast := K.label(Game.paper_title(), "serif_black", 22, P.PRINT_INK)
	mast.size = Vector2(312, 28)
	mast.position = Vector2(0, 6)
	mast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheet.add_child(mast)
	sheet.add_child(K.rect(P.PRINT_INK, Vector2(8, 36), Vector2(296, 1)))
	var date := K.label(Game.t("layout.dateline", {"n": w.week, "season": Game.season_name()}), "serif", 7, P.PRINT_INK)
	date.size = Vector2(312, 10)
	date.position = Vector2(0, 37)
	date.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sheet.add_child(date)
	sheet.add_child(K.rect(P.PRINT_INK, Vector2(8, 47), Vector2(296, 1)))
	sheet.add_child(K.rect(P.PRINT_INK, Vector2(8, 49), Vector2(296, 1)))
	sheet.add_child(K.rect(Color(P.PRINT_INK, 0.6), Vector2(8, 177), Vector2(296, 1)))
	sheet.add_child(K.rect(Color(P.PRINT_INK, 0.6), Vector2(156, 180), Vector2(1, 114)))
	sheet.add_child(K.rect(Color(P.PRINT_INK, 0.6), Vector2(8, 296), Vector2(296, 1)))
	sheet.add_child(K.rect(Color(P.PRINT_INK, 0.6), Vector2(156, 298), Vector2(1, 38)))
	for s in SLOTS:
		_slot_box(sheet, s)
	_ads(sheet, Rect2(160, 299, 144, 38))
	var ed := K.label(Game.t("layout.editor_line", {"name": Game.editor_title()}), "serif", 7, P.PRINT_INK)
	ed.position = Vector2(8, 339)
	ed.size.x = 296
	ed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sheet.add_child(ed)


func _slot_box(sheet: Control, s: String) -> void:
	var r: Rect2 = AREA[s]
	var clip := Control.new()
	clip.position = r.position
	clip.size = r.size
	clip.clip_contents = true
	sheet.add_child(clip)
	var big := s == "head"
	if not _arts.has(s):
		var empty := K.label(Game.t("layout.empty", {"hint": Game.t("layout.hint_" + s)}), "pixel", 12, Color(P.PRINT_INK, 0.35))
		empty.size = r.size
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		clip.add_child(empty)
	else:
		var pv: Dictionary = _preview.get(s, {})
		var hl := K.para(str(pv.get("headline", "")), r.size.x, "serif_black", 14 if big else (10 if s != "small" else 8), P.PRINT_INK, 0)
		if big:
			hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		clip.add_child(hl)
		var hh := int(hl.get_minimum_size().y) + 3
		var indent := Game.t("layout.indent")
		var body := indent + ("\n" + indent).join(K.clean_paras(pv.get("paragraphs", [])))
		if big:
			# 头条正文分两栏
			var col_w := (r.size.x - 8) / 2.0
			var text_l := K.para(body, col_w, "serif", 7, P.PRINT_INK, 0)
			text_l.position = Vector2(0, hh)
			clip.add_child(text_l)
			var lines_per_col := int((r.size.y - hh) / 9.5)
			text_l.max_lines_visible = lines_per_col
			var text_r := K.para(body, col_w, "serif", 7, P.PRINT_INK, 0)
			text_r.position = Vector2(col_w + 8, hh)
			text_r.lines_skipped = lines_per_col
			clip.add_child(text_r)
			clip.add_child(K.rect(Color(P.PRINT_INK, 0.4), Vector2(col_w + 3, hh), Vector2(1, r.size.y - hh)))
		else:
			var text := K.para(body, r.size.x, "serif", 6 if s != "small" else 6, P.PRINT_INK, 0)
			text.position = Vector2(0, hh)
			clip.add_child(text)
	var slot: String = s
	var h := K.hotspot(Rect2(r.position - Vector2(2, 2), r.size + Vector2(4, 4)), Game.t("layout.edit_slot", {"slot": _slot_name(s)}) if _arts.has(s) else _slot_name(s), func():
		if _arts.has(slot):
			_edit = slot
		elif _sel_story != "":
			_place(_sel_story, slot)
		_refresh())
	sheet.add_child(h)


func _ads(sheet: Control, r: Rect2) -> void:
	var w = Game.world
	var act: Array = []
	for rid in w.ads:
		var res: Dictionary = w.residents[rid]
		if w.ads[rid].paused_until <= w.week and res.in_town and res.player_rel.like >= 0.3:
			act.append(rid)
	if act.is_empty():
		var l := K.label(Game.t("layout.ad_vacant"), "serif", 8, Color(P.PRINT_INK, 0.5))
		l.position = r.position + Vector2(40, 14)
		sheet.add_child(l)
		return
	var bw := (r.size.x - (act.size() - 1) * 3) / act.size()
	for i in act.size():
		var rid: String = act[i]
		var bx := Rect2(r.position + Vector2(i * (bw + 3), 0), Vector2(bw, r.size.y))
		var frame := Panel.new()
		frame.position = bx.position
		frame.size = bx.size
		frame.add_theme_stylebox_override("panel", K.box(Color(0, 0, 0, 0), P.PRINT_INK, 1))
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sheet.add_child(frame)
		var txt := K.para(_ad_text(rid), bw - 4, "serif", 6, P.PRINT_INK, 0)
		txt.position = bx.position + Vector2(2, 2)
		txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sheet.add_child(txt)


func _ad_text(rid: String) -> String:
	var w = Game.world
	var r: Dictionary = w.residents[rid]
	match r.occ:
		"owner": return Game.t("layout.ad_owner")
		"grocer": return Game.t("layout.ad_grocer", {"surname": TE.surname(w, rid, Game.lang)})
		"barkeep": return Game.t("layout.ad_barkeep")
	return Game.name_of(rid)


# ------------------------------------------------------------ 付印
func _print() -> void:
	var n := _ordered().size()
	var text := Game.t("layout.confirm_n", {"n": n})
	if n == 0:
		text = Game.t("layout.confirm_empty")
	elif not _arts.has("head"):
		text = Game.t("layout.confirm_no_head")
	Game.open_overlay("confirm", {"text": text, "yes": Game.t("layout.confirm_yes"), "no": Game.t("layout.confirm_no"), "on_yes": func():
		var arts: Array = []
		for a in _ordered():
			arts.append(a.duplicate(true))
		Game.track("print_request", {"n": arts.size(), "articles": arts.map(func(a): return {"slot": a.slot, "tone": a.tone, "naming": a.naming, "evidence": a.evidence, "facts": a.facts.size(), "reroll": a.reroll})})
		Game.fade_to("press", {"articles": arts, "choice": _choice.duplicate()})})
