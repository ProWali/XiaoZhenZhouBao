## 叠层：周一读门缝下的信，一封一封翻；最后一页是上一期的账本。params: {on_done: Callable}
## 公信力不给数字，账本上只写「镇上怎么看你」和比上周好了还是差了。
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")

var params := {}
var _pages: Array = []   # [{kind: letter|ledger, text}]
var _i := 0
var _holder: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(K.rect(Color(P.INK, 0.6), Vector2.ZERO, Vector2(640, 360)))
	var w = Game.world
	for t in w.render_letters():
		_pages.append({"kind": "letter", "text": t})
	if not Game.ui.get("last_issue", {}).is_empty() and int(Game.ui.last_issue.get("week", 0)) == w.week - 1:
		_pages.append({"kind": "ledger"})
	if _pages.is_empty():
		_pages.append({"kind": "empty"})
	_holder = Control.new()
	add_child(_holder)
	_show()


func _show() -> void:
	for c in _holder.get_children():
		c.queue_free()
	var page: Dictionary = _pages[_i]
	Game.sfx("page_turn")
	match page.kind:
		"letter": _letter(page.text)
		"ledger": _ledger()
		_: _letter("门缝下什么也没有。")
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	nav.position = Vector2(150, 322)
	_holder.add_child(nav)
	var prev := K.button("上一页", func(): _i -= 1; _show(), 70)
	prev.disabled = _i == 0
	nav.add_child(prev)
	var count := K.label("%d / %d" % [_i + 1, _pages.size()], "pixel", 12, P.PAPER)
	count.custom_minimum_size.x = 60
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(count)
	var last := _i == _pages.size() - 1
	var next := K.button("放下" if last else "下一页", _next, 70)
	nav.add_child(next)
	next.call_deferred("grab_focus")


func _next() -> void:
	if _i < _pages.size() - 1:
		_i += 1
		_show()
		return
	Game.close_overlay()
	var cb: Callable = params.get("on_done", Callable())
	if cb.is_valid():
		cb.call()


func _letter(text: String) -> void:
	var sheet := K.paper(Vector2(150, 24), Vector2(340, 290), P.NOTE_PAPER)
	_holder.add_child(sheet)
	var sl: Array = K.scroll_list(Vector2(16, 14), Vector2(316, 266), 0)
	sheet.add_child(sl[0])
	sl[1].add_child(K.para(text, 300, "hand", 12, P.PENCIL, 3))


func _ledger() -> void:
	var w = Game.world
	var iss: Dictionary = Game.ui.last_issue
	var sheet := K.paper(Vector2(130, 18), Vector2(380, 298), P.NEWSPRINT)
	_holder.add_child(sheet)
	var title := K.label("第 %d 期 · 账本" % int(iss.week), "serif_black", 14, P.PRINT_INK)
	title.position = Vector2(16, 10)
	sheet.add_child(title)
	sheet.add_child(K.rect(P.PRINT_INK, Vector2(16, 32), Vector2(348, 1)))
	var y := 40
	var rows := [
		["卖报（%d 份 × 5 分）" % int(round(float(iss.sales) / 0.05)), "%+.1f" % float(iss.sales)],
		["广告", "%+.1f" % float(iss.ad_income)],
		["纸张、油墨、房租", "%+.1f" % -float(iss.cost)],
	]
	if float(iss.get("other", 0.0)) != 0.0:
		rows.append(["别的进出（线人、档案、私下的钱、赔修）", "%+.1f" % float(iss.other)])
	rows.append(["现在抽屉里", "%.1f 元" % float(w.stats.cash)])
	for rw in rows:
		var a := K.label(rw[0], "serif", 10, P.PRINT_INK)
		a.position = Vector2(20, y)
		sheet.add_child(a)
		var b := K.label(rw[1], "serif", 10, P.PRINT_INK)
		b.position = Vector2(280, y)
		b.size.x = 80
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		sheet.add_child(b)
		y += 16
	sheet.add_child(K.rect(Color(P.PRINT_INK, 0.4), Vector2(16, y + 2), Vector2(348, 1)))
	y += 8
	var circ_now := int(w.stats.circulation)
	var circ_line := "下一期印 %d 份（上期 %d）。" % [circ_now, int(iss.circ_before)]
	var c := K.label(circ_line, "serif", 10, P.PRINT_INK)
	c.position = Vector2(20, y)
	sheet.add_child(c)
	y += 16
	var cred_line := "镇上怎么看这份报纸：%s，%s。" % [_cred_word(w.stats.credibility), _trend(float(iss.cred_delta))]
	var cr := K.label(cred_line, "serif", 10, P.PRINT_INK)
	cr.position = Vector2(20, y)
	sheet.add_child(cr)
	y += 22
	var cons: Array = iss.get("consequences", [])
	if not cons.is_empty():
		var h := K.label("邮差送信时顺嘴说了几句：", "serif_black", 10, P.PRINT_INK)
		h.position = Vector2(20, y)
		sheet.add_child(h)
		y += 16
		var sl: Array = K.scroll_list(Vector2(24, y), Vector2(344, 282 - y), 2)
		sheet.add_child(sl[0])
		for line in cons:
			sl[1].add_child(K.para("· " + str(line), 326, "hand", 11, P.PENCIL, 0))


static func _cred_word(c: float) -> String:
	if c < 20: return "没人信了"
	if c < 35: return "有人拿它当笑话"
	if c < 50: return "将信将疑"
	if c < 65: return "说的话有人听"
	if c < 80: return "镇上信得过"
	return "说一不二"


static func _trend(d: float) -> String:
	if d >= 3.0: return "比上周好了不少"
	if d > 0.4: return "比上周好些"
	if d <= -3.0: return "比上周差了一截"
	if d < -0.4: return "比上周差了些"
	return "跟上周差不多"
