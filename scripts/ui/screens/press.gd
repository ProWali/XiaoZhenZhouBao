## 印刷夜：一根拉杆，印刷机的声音，不可撤销（策划案九版决策：不露玩家形象，付印只有拉杆和声音）。
## params: {articles, choice}
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")

var params := {}
var _bg: TextureRect
var _note: Label
var _count: Label
var _btn: Button
var _done := false


func _ready() -> void:
	var w = Game.world
	Game.stop_music()
	Game.ambience("")
	_bg = K.image("res://assets/sprites/bg/press_night.png")
	add_child(_bg)
	add_child(K.rect(Color(P.INK, 0.2), Vector2.ZERO, Vector2(640, 360)))
	_note = K.label("第 %d 期。拉下杠杆就印了，印出去的字收不回来。" % w.week, "serif", 12, P.PAPER)
	_note.position = Vector2(16, 14)
	add_child(_note)
	_count = K.label("", "serif_black", 14, P.LAMP)
	_count.position = Vector2(16, 326)
	add_child(_count)
	add_child(K.hotspot(Rect2(470, 40, 140, 120), "拉杆", _pull))
	_btn = K.button("拉下杠杆", _pull, 110)
	_btn.position = Vector2(510, 324)
	add_child(_btn)
	_btn.call_deferred("grab_focus")


func _pull() -> void:
	if _done:
		return
	_done = true
	_btn.disabled = true
	var w = Game.world
	var arts: Array = params.get("articles", [])
	var choice: Dictionary = params.get("choice", {})
	var cash_start := float(Game.ui.get("cash_week_start", 30.0))
	var circ_before: float = w.stats.circulation
	var burned: bool = int(w.flags.get("burned_until", 0)) > w.week
	var week: int = w.week
	var issue: Dictionary = w.print_issue(arts, choice)
	# 记账本：下周一读
	var circ_after: float = float(w.history[-1].circ) if not w.history.is_empty() else w.stats.circulation
	var sales := 0.0 if burned else circ_after * 0.05
	var cost := 10.0 + circ_after * 0.02
	Game.ui.last_issue = {
		"week": week, "circ_before": circ_before, "sales": sales, "ad_income": float(issue.get("ad_income", 0.0)),
		"cost": cost, "other": w.stats.cash - cash_start - float(issue.cash_delta), "cred_delta": float(issue.cred_delta),
		"consequences": issue.consequences.slice(0, 6),
		"headlines": issue.articles.map(func(a): return {"slot": a.slot, "headline": a.headline}),
	}
	Game.ui.cash_week_start = w.stats.cash
	var fronts: Array = Game.ui.get("fronts", [])
	for a in issue.articles:
		if a.slot == "head":
			fronts.append({"week": week, "headline": a.headline})
	Game.ui.fronts = fronts
	Game.track("printed", {"cred_delta": issue.cred_delta, "circ_delta": issue.circ_delta, "cash_delta": issue.cash_delta, "consequences": issue.consequences.size()})
	Game.autosave()
	# 表演
	Game.sfx("lever")
	await get_tree().create_timer(0.5).timeout
	Game.sfx("press_run")
	var total := int(circ_before)
	var tw := create_tween()
	tw.tween_method(func(v): _count.text = "已印 %d / %d 份" % [int(v), total], 0.0, float(total), 5.0)
	var shake := create_tween().set_loops(20)
	shake.tween_property(_bg, "position", Vector2(0, 1), 0.12)
	shake.tween_property(_bg, "position", Vector2(0, 0), 0.13)
	_note.text = ""
	await get_tree().create_timer(6.2).timeout
	_count.text = "印好了。"
	await get_tree().create_timer(1.8).timeout
	_note.text = "报纸天亮前送出去。"
	await get_tree().create_timer(1.6).timeout
	Game.route()
