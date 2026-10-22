## 周六夜来访：镇民主动上门，求情、威胁、送料、私下交易。不可跳过（策划案三版）。
## 来访名单在进这一屏时向模拟要一次，存进 Game.ui，读档后不会重抽。
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")
const Layers = preload("res://scripts/ui/office_layers.gd")
const Portrait = preload("res://scripts/ui/portrait.gd")
const TE = preload("res://scripts/text/text_engine.gd")


var params := {}
var _i := 0
var _holder: Control


func _ready() -> void:
	var w = Game.world
	if int(Game.ui.get("saturday_week", 0)) < w.week:
		var vs: Array = w.saturday_visitors()
		Game.ui.visitors = vs
		Game.ui.saturday_week = w.week
		Game.ui.deals = {}
		Game.track("visitors", {"n": vs.size(), "kinds": vs.map(func(v): return v.kind)})
		Game.autosave()
	add_child(K.image("res://assets/sprites/bg/office.png"))
	add_child(Layers.new())
	add_child(K.rect(Color(P.SLATE_DARK, 0.35), Vector2.ZERO, Vector2(640, 360)))
	Game.ambience("night_ambience")
	Game.stop_music()
	var head := K.label(Game.t("visitors.head"), "serif_black", 16, P.PAPER)
	head.position = Vector2(12, 8)
	add_child(head)
	_holder = Control.new()
	add_child(_holder)
	_show()


func _show() -> void:
	for c in _holder.get_children():
		c.queue_free()
	var w = Game.world
	var vs: Array = Game.ui.get("visitors", [])
	if vs.is_empty():
		_panel(Game.t("visitors.nobody"), [], "")
		var b := K.button(Game.t("visitors.sleep"), _done, 0)
		b.position = Vector2(440, 318)
		_holder.add_child(b)
		b.call_deferred("grab_focus")
		return
	var v: Dictionary = vs[_i]
	var who: String = str(v.who)
	Game.sfx("door_open", -6.0)
	# 门口站着的人
	if w.residents.has(who):
		var fig := K.image(Portrait.figure(w, who), Vector2(546, 196))
		fig.scale = Vector2(3, 3)
		_holder.add_child(fig)
	# 来送料却没料可送的，就是来道谢的（试玩：标题写「来送料」，内容里没有料）
	var kind_key := "thanks" if str(v.kind) == "tip" and str(v.get("fact", "")) == "" else str(v.kind)
	var kind_s := Game.t("visitors.kind_" + kind_key)
	if kind_s.begins_with("〔"):
		kind_s = Game.t("visitors.kind_other")
	var title := Game.t("visitors.title", {"name": Game.name_of(who), "occ": Game.occ(who) if w.residents.has(who) else "?", "kind": kind_s})
	var gained: Array = []
	if str(v.get("fact", "")) != "":
		gained.append(str(v.fact))
	for f in v.get("facts", []):
		if not (str(f) in gained):
			gained.append(str(f))
	_panel(title, v.lines, who, gained)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.position = Vector2(140, 318)
	_holder.add_child(bar)
	var decided: bool = Game.ui.get("deals", {}).has(str(_i))
	if v.kind == "deal" and not decided:
		var take := K.button(Game.t("visitors.take", {"n": int(v.offer)}), func():
			w.accept_deal(v)
			Game.sfx("coins")
			Game.ui.deals[str(_i)] = true
			Game.track("deal", {"who": who, "offer": int(v.offer), "took": true})
			Game.autosave()
			_next(), 0)
		take.tooltip_text = Game.t("visitors.take_tip")
		bar.add_child(take)
		var refuse := K.button(Game.t("visitors.refuse"), func():
			Game.ui.deals[str(_i)] = false
			Game.track("deal", {"who": who, "offer": int(v.offer), "took": false})
			_next(), 0)
		bar.add_child(refuse)
		refuse.call_deferred("grab_focus")
	else:
		var last: bool = _i >= vs.size() - 1
		var b := K.button(Game.t("visitors.see_out_last") if last else Game.t("visitors.see_out"), _next, 0)
		bar.add_child(b)
		b.call_deferred("grab_focus")
	var cnt := K.label("%d / %d" % [_i + 1, vs.size()], "pixel", 12, P.STONE)
	cnt.position = Vector2(500, 8)
	_holder.add_child(cnt)


func _panel(title: String, lines: Array, who: String, gained: Array = []) -> void:
	var w = Game.world
	var sheet := K.paper(Vector2(120, 36), Vector2(400, 272 if not lines.is_empty() else 70), P.NOTE_PAPER)
	_holder.add_child(sheet)
	var x := 14
	if who != "" and w.residents.has(who):
		var face := K.image(Portrait.face(w, who), Vector2(12, 12))
		face.scale = Vector2(2, 2)
		sheet.add_child(face)
		x = 86
	var t := K.para(title, 400 - x - 14, "serif_black", 12, P.PRINT_INK)
	t.position = Vector2(x, 12)
	sheet.add_child(t)
	var sl: Array = K.scroll_list(Vector2(x, 44), Vector2(400 - x - 8, 220), 6)
	sheet.add_child(sl[0])
	for line in lines:
		sl[1].add_child(K.para(str(line), 400 - x - 24, "hand", 11, P.PENCIL))
	if not gained.is_empty():
		sl[1].add_child(K.label(Game.t("visitors.noted"), "pixel", 12, P.STAMP_RED))
		for fid in gained:
			if w.facts.has(fid):
				sl[1].add_child(K.para("· " + TE.fact_note(w, fid, Game.lang), 400 - x - 30, "hand", 10, P.PENCIL, 0))


func _next() -> void:
	var vs: Array = Game.ui.get("visitors", [])
	if _i < vs.size() - 1:
		_i += 1
		Game.sfx("footsteps_wood", -8.0)
		_show()
	else:
		_done()


func _done() -> void:
	Game.ui.visitors_done_week = Game.world.week
	Game.route()
