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
	var plate := K.label(w.loc_name(_loc), "serif_black", 14, P.PAPER)
	plate.position = Vector2(10, 24)
	add_child(K.rect(Color(P.INK, 0.8), Vector2(4, 22), Vector2(plate.get_minimum_size().x + 12, 22)))
	add_child(plate)
	# 底栏
	add_child(K.rect(Color(P.INK, 0.88), Vector2(0, 334), Vector2(640, 26)))
	_note = K.label("", "pixel", 12, P.PAPER)
	_note.position = Vector2(6, 341)
	add_child(_note)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	bar.alignment = BoxContainer.ALIGNMENT_END
	bar.position = Vector2(336, 337)
	bar.size = Vector2(300, 20)
	add_child(bar)
	var loc_def: Dictionary = T.location_by_id(_loc)
	if loc_def.get("archive", false):
		var ab := K.button("查档案", _archive)
		ab.disabled = not w.can_act_day()
		bar.add_child(ab)
	bar.add_child(K.button("回到街上", func(): Game.fade_to("town_map", {}, 0.2)))
	if people.is_empty():
		_note.text = "这会儿没人。"
	elif not w.can_act_day():
		_note.text = "今天的行动点用完了。"
	else:
		_note.text = "点一个人和他谈谈（花一个行动点）。"


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
		var r: Dictionary = w.residents[f.rid]
		var tip := "%s（%s）" % [r.name, TE.occ_label(w, f.rid, "zh")]
		if Game.lead_from(f.rid) != "":
			tip = "★ " + tip + " · %s让你来找的" % w.res_name(Game.lead_from(f.rid))
		var h := K.hotspot(Rect2(f.pos.x - 2, f.pos.y - 2, 32, 64), tip, _talk.bind(f.rid))
		h.enabled = w.can_act_day()
		add_child(h)


func _talk(rid: String) -> void:
	var w = Game.world
	if not w.can_act_day():
		_note.text = "今天的行动点用完了。"
		return
	var r: Dictionary = w.residents[rid]
	var items: Array = [{"text": "随便聊聊，看%s愿意说什么" % r.name, "cb": _interview.bind(rid, "")}]
	for g in w.notebook():
		var ename: String = TE.event_name(w, g.event, "zh")
		for fid in g.facts:
			items.append({"text": "问「%s」：%s" % [ename, TE.fact_note(w, fid, "zh")], "cb": _interview.bind(rid, fid), "font": "hand", "size": 10})
	var note := "话头从选题簿里挑。问当事人自己的事，对方多半不认，还会记住你在查。问不出来时，对方有时会给你指个人。"
	if Game.lead_from(rid) != "":
		note = "★ %s让你来找%s。说是谁让你来的，对方多半肯开口；随便聊聊就行。" % [w.res_name(Game.lead_from(rid)), r.name]
	if r.avoid_until > w.week:
		note = "%s最近躲着你。" % r.name
	Game.open_overlay("pick", {"title": "和%s（%s）谈什么？" % [r.name, TE.occ_label(w, rid, "zh")], "note": note, "items": items})


func _interview(rid: String, topic: String) -> void:
	var w = Game.world
	var day: int = w.day
	var res: Dictionary = w.act_interview(rid, topic)
	Game.sfx("page_turn")
	Game.show_result("和%s谈" % w.residents[rid].name, res, rid, _after.bind(day))


func _archive() -> void:
	var w = Game.world
	var keeper := ""
	for rid in w.living_ids():
		if w.residents[rid].keeper == _loc:
			keeper = rid
	var text := "翻%s的档案要花一个行动点。" % w.loc_name(_loc)
	var pointed := false
	for g in w.notebook():
		for h in g.hints:
			if h.find(w.loc_name(_loc)) >= 0 and h.find("档案") >= 0:
				pointed = true
	if not pointed:
		text += "选题簿里没有线索指向这里的档案，翻了很可能白翻。"
	if keeper != "":
		var k: Dictionary = w.residents[keeper]
		if k.player_rel.trust >= 0.5:
			text += "%s信得过你，会让你看。" % k.name
		else:
			text += "%s跟你不熟，得塞五块钱。" % k.name
	Game.open_overlay("confirm", {"text": text, "yes": "查", "no": "算了", "on_yes": func():
		var day: int = w.day
		var res: Dictionary = w.act_archive(_loc)
		Game.sfx("paper_slide")
		Game.show_result("%s的档案" % w.loc_name(_loc), res, keeper, _after.bind(day))})


## 一个行动做完：还在同一天白天就留在这里（在场的人可能换了），天黑了就回地图
func _after(day_before: int) -> void:
	var w = Game.world
	if w.day != day_before or w.day > 6:
		Game.route()
	elif w.slot >= 2:
		Game.fade_to("town_map", {}, 0.3)
	else:
		Game.goto("location", {"loc": _loc})
