## 地点内景：单屏固定镜头，在场的人站在前景。点人交谈（先选人，再从选题簿里挑话头），点柜台查档案。
## params: {loc}
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")
const Hud = preload("res://scripts/ui/hud.gd")
const Portrait = preload("res://scripts/ui/portrait.gd")
const TE = preload("res://scripts/text/text_engine.gd")
const T = preload("res://scripts/sim/tables.gd")

const BG := {"farm_a": "loc_farm", "farm_b": "loc_farm"}

var params := {}
var _loc := ""
var _note: Label


func _ready() -> void:
	var w = Game.world
	_loc = str(params.get("loc", "tavern"))
	var bg: String = BG.get(_loc, "loc_" + _loc)
	add_child(K.image("res://assets/sprites/bg/%s.png" % bg))
	if w.slot == 1:
		add_child(K.rect(Color(P.OCHRE, 0.1), Vector2.ZERO, Vector2(640, 360)))
	var people: Array = w.people_at(_loc)
	people.sort()
	_place_people(people)
	var hud := Hud.new()
	hud.end_day_requested.connect(Game.request_end_day)
	add_child(hud)
	# 地名牌
	var plate := K.label(Game.place_title(_loc), "serif_black", 14, P.PAPER)
	plate.position = Vector2(10, 24)
	add_child(K.rect(Color(P.INK, 0.8), Vector2(4, 22), Vector2(plate.get_minimum_size().x + 12, 22)))
	add_child(plate)
	# 底栏
	_note = K.note_bar(self, 334, 26, 0.88, 500)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.position = Vector2(336, 337)
	bar.size = Vector2(300, 20)
	add_child(bar)
	var loc_def: Dictionary = T.location_by_id(_loc)
	if loc_def.get("archive", false):
		var ab := K.button(Game.t("location.archive"), _archive)
		ab.disabled = not w.can_act_day()
		bar.add_child(ab)
	bar.add_child(K.button(Game.t("location.back"), func(): Game.fade_to("town_map", {}, 0.2)))
	if people.is_empty():
		_note.text = Game.t("location.nobody")
	elif not w.can_act_day():
		_note.text = Game.t("location.no_actions")
	else:
		_note.text = Game.t("location.click_person")


func _place_people(people: Array) -> void:
	var w = Game.world
	var n := people.size()
	var per_row := 9
	var figs: Array = []
	for i in n:
		var rid: String = people[i]
		var row := i / per_row
		var in_row := mini(per_row, n - row * per_row)
		var col := i % per_row
		var spacing := 40.0 if in_row > 1 else 0.0
		var x0 := 320.0 - (in_row - 1) * spacing / 2.0
		var x := x0 + col * spacing - 14
		var y := 262.0 - row * 26 + (col % 2) * 4
		figs.append({"rid": rid, "pos": Vector2(x, y), "row": row})
	# 后排先画，前排压在上面；热区最后加，前排的优先接点击
	figs.sort_custom(func(a, b): return a.row > b.row)
	for f in figs:
		var fig := K.image(Portrait.figure(w, f.rid), f.pos)
		fig.scale = Vector2(2, 2)
		add_child(fig)
	for f in figs:
		if Game.lead_from(f.rid) != "":
			var star := K.label("★", "pixel", 12, P.LAMP)
			star.position = f.pos + Vector2(8, -16)
			add_child(star)
	for f in figs:
		var tip := Game.t("location.person_occ", {"name": Game.name_of(f.rid), "occ": Game.occ(f.rid)})
		if Game.lead_from(f.rid) != "":
			tip = Game.t("location.tip_lead", {"tip": tip, "from": Game.name_of(Game.lead_from(f.rid))})
		var h := K.hotspot(Rect2(f.pos.x - 2, f.pos.y - 2, 32, 64), tip, _talk.bind(f.rid))
		h.enabled = w.can_act_day()
		add_child(h)


func _talk(rid: String) -> void:
	var w = Game.world
	if not w.can_act_day():
		_note.text = Game.t("location.no_actions")
		return
	var r: Dictionary = w.residents[rid]
	var items: Array = [{"text": Game.t("location.small_talk", {"name": Game.name_of(rid)}), "cb": _interview.bind(rid, "")}]
	# 还有人能问的事排前面；问完了的放到最后，标出来（试玩：玩家拿登完的事问了两周）
	var open_items: Array = []
	var done_items: Array = []
	for g in w.notebook():
		if g.event.soft:
			continue  # 软新闻人人都知道，拿来当话头问不出东西
		var ename: String = TE.event_name(w, g.event, Game.lang)
		var done: bool = int(g.get("more", 0)) == 0
		for fid in g.facts:
			var text := Game.t("location.ask_about", {"event": ename, "fact": TE.fact_note(w, fid, Game.lang)})
			if done:
				text = Game.t("location.ask_done", {"text": text})
			(done_items if done else open_items).append({"text": text, "cb": _interview.bind(rid, fid), "font": "hand", "size": 10})
	items.append_array(open_items)
	items.append_array(done_items)
	var note := Game.t("location.talk_note")
	if Game.lead_from(rid) != "":
		note = Game.t("location.talk_note_lead", {"from": Game.name_of(Game.lead_from(rid)), "name": Game.name_of(rid)})
	if r.avoid_until > w.week:
		note = Game.t("location.avoiding", {"name": Game.name_of(rid)})
	Game.open_overlay("pick", {"title": Game.t("location.talk_title", {"name": Game.name_of(rid), "occ": Game.occ(rid)}), "note": note, "items": items})


func _interview(rid: String, topic: String) -> void:
	var w = Game.world
	var day: int = w.day
	var res: Dictionary = w.act_interview(rid, topic)
	Game.sfx("page_turn")
	Game.show_result(Game.t("location.talk_result", {"name": Game.name_of(rid)}), res, rid, _after.bind(day))


func _archive() -> void:
	var w = Game.world
	var keeper := ""
	for rid in w.living_ids():
		if w.residents[rid].keeper == _loc:
			keeper = rid
	var text := Game.t("location.archive_cost", {"place": Game.place(_loc)})
	# 和选题簿里「某处的档案里也许有记录」那条提示同一个判断
	var pointed := false
	for g in w.notebook():
		for fid in g.event.facts:
			if w.facts[fid].archive == _loc and not w.known.get(fid, {"evidence": false}).evidence:
				pointed = true
	if not pointed:
		text += Game.t("location.archive_unpointed")
	if keeper != "":
		var k: Dictionary = w.residents[keeper]
		if k.player_rel.trust >= 0.5:
			text += Game.t("location.keeper_trusts", {"name": Game.name_of(keeper)})
		else:
			text += Game.t("location.keeper_bribe", {"name": Game.name_of(keeper)})
	Game.open_overlay("confirm", {"text": text, "yes": Game.t("location.archive_yes"), "no": Game.t("location.archive_no"), "on_yes": func():
		var day: int = w.day
		var res: Dictionary = w.act_archive(_loc)
		Game.sfx("paper_slide")
		Game.show_result(Game.t("location.archive_result", {"place": Game.place(_loc)}), res, keeper, _after.bind(day))})


## 一个行动做完：还在同一天白天就留在这里（在场的人可能换了），天黑了就回地图
func _after(day_before: int) -> void:
	var w = Game.world
	if w.day != day_before or w.day > 6:
		Game.route()
	elif w.slot >= 2:
		Game.fade_to("town_map", {}, 0.3)
	else:
		Game.goto("location", {"loc": _loc})
