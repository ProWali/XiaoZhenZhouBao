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
		_: _letter(Game.t("letters.empty"))
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	nav.position = Vector2(150, 322)
	_holder.add_child(nav)
	var prev := K.button(Game.t("letters.prev"), func(): _i -= 1; _show(), 70)
	prev.disabled = _i == 0
	nav.add_child(prev)
	var count := K.label("%d / %d" % [_i + 1, _pages.size()], "pixel", 12, P.PAPER)
	count.custom_minimum_size.x = 60
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nav.add_child(count)
	var last := _i == _pages.size() - 1
	var next := K.button(Game.t("letters.put_down") if last else Game.t("letters.next"), _next, 70)
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
	var title := K.label(Game.t("letters.ledger_title", {"n": int(iss.week)}), "serif_black", 14, P.PRINT_INK)
	title.position = Vector2(16, 10)
	sheet.add_child(title)
	sheet.add_child(K.rect(P.PRINT_INK, Vector2(16, 32), Vector2(348, 1)))
	var y := 40
	var rows := [
		[Game.t("letters.row_sales", {"n": int(round(float(iss.sales) / 0.05))}), "%+.1f" % float(iss.sales)],
		[Game.t("letters.row_retail", {"n": int(iss.get("retail", 0))}), "%+.1f" % (int(iss.get("retail", 0)) * 0.05)],
		[Game.t("letters.row_ads"), "%+.1f" % float(iss.ad_income)],
		[Game.t("letters.row_cost"), "%+.1f" % -float(iss.cost)],
	]
	if float(iss.get("other", 0.0)) != 0.0:
		rows.append([Game.t("letters.row_other"), "%+.1f" % float(iss.other)])
	rows.append([Game.t("letters.row_cash"), Game.t("letters.cash", {"n": "%.1f" % float(w.stats.cash)})])
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
	var circ_line := Game.t("letters.circ_line", {"n": circ_now, "before": int(iss.circ_before)})
	var c := K.label(circ_line, "serif", 10, P.PRINT_INK)
	c.position = Vector2(20, y)
	sheet.add_child(c)
	y += 16
	var cred_line := Game.t("letters.cred_line", {"word": _cred_word(w.stats.credibility), "trend": _trend(float(iss.cred_delta))})
	var cr := K.para(cred_line, 344, "serif", 10, P.PRINT_INK, 0)
	cr.position = Vector2(20, y)
	sheet.add_child(cr)
	y += maxi(22, int(cr.get_minimum_size().y) + 8)
	# 一篇一篇：卖了多少份、怎么登的、镇上信不信、谁有什么反应
	var arts: Array = iss.get("articles", [])
	var cons: Array = iss.get("consequences", [])
	if not arts.is_empty() or not cons.is_empty():
		var h := K.label(Game.t("letters.postman"), "serif_black", 10, P.PRINT_INK)
		h.position = Vector2(20, y)
		sheet.add_child(h)
		y += 16
		var sl: Array = K.scroll_list(Vector2(24, y), Vector2(344, 282 - y), 2)
		sheet.add_child(sl[0])
		var shown := {}
		for a in arts:
			sl[1].add_child(K.para(Game.t("letters.art_head", {"headline": str(a.headline)}), 326, "serif", 10, P.PRINT_INK, 0))
			var how := Game.t("layout.tone_" + str(a.tone)) + "·" + Game.t("layout.naming_" + str(a.naming))
			if bool(a.evidence):
				how += "·" + Game.t("letters.art_evidence")
			sl[1].add_child(K.para(Game.t("letters.art_line", {"n": int(a.retail), "how": how, "cred": _art_cred(a)}), 326, "hand", 11, P.PENCIL, 0))
			for line in a.get("cons", []):
				shown[str(line)] = true
				sl[1].add_child(K.para("· " + str(line), 326, "hand", 11, P.PENCIL, 0))
		for line in cons:
			if not shown.has(str(line)):
				sl[1].add_child(K.para("· " + str(line), 326, "hand", 11, P.PENCIL, 0))


## 这一篇镇上信不信
static func _art_cred(a: Dictionary) -> String:
	if bool(a.get("false", false)):
		return Game.t("letters.art_false")
	var c := float(a.get("cred", 0.0))
	if c > 0.5:
		return Game.t("letters.art_trusted")
	if c < -0.5:
		return Game.t("letters.art_doubted")
	return Game.t("letters.art_flat")


static func _cred_word(c: float) -> String:
	if c < 20: return Game.t("letters.cred_0")
	if c < 35: return Game.t("letters.cred_1")
	if c < 50: return Game.t("letters.cred_2")
	if c < 65: return Game.t("letters.cred_3")
	if c < 80: return Game.t("letters.cred_4")
	return Game.t("letters.cred_5")


static func _trend(d: float) -> String:
	if d >= 3.0: return Game.t("letters.trend_up2")
	if d > 0.4: return Game.t("letters.trend_up1")
	if d <= -3.0: return Game.t("letters.trend_down2")
	if d < -0.4: return Game.t("letters.trend_down1")
	return Game.t("letters.trend_same")
