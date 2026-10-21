## 叠层：一次行动的结果。params: {title, lines: [String], who: rid, gained: [fid], on_close: Callable}
## 新记进选题簿的碎片在下面列出来，盖一枚章。
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")
const Portrait = preload("res://scripts/ui/portrait.gd")
const TE = preload("res://scripts/text/text_engine.gd")

var params := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(K.rect(Color(P.INK, 0.55), Vector2.ZERO, Vector2(640, 360)))
	var w = Game.world
	var sheet := K.paper(Vector2(110, 50), Vector2(420, 260), P.NOTE_PAPER)
	add_child(sheet)
	var x := 16
	var who: String = str(params.get("who", ""))
	if who != "" and w.residents.has(who):
		var face := K.image(Portrait.face(w, who), Vector2(14, 14))
		face.scale = Vector2(2, 2)
		sheet.add_child(face)
		var nm := K.label(w.residents[who].name, "pixel", 12, P.PENCIL)
		nm.position = Vector2(14, 82)
		sheet.add_child(nm)
		var oc := K.label(TE.occ_label(w, who, "zh"), "pixel", 12, P.WARM_GREY)
		oc.position = Vector2(14, 96)
		sheet.add_child(oc)
		x = 92
	var title := K.label(str(params.get("title", "")), "serif_black", 13, P.PRINT_INK)
	title.position = Vector2(x, 12)
	sheet.add_child(title)
	var sl: Array = K.scroll_list(Vector2(x, 34), Vector2(420 - x - 10, 160), 6)
	sheet.add_child(sl[0])
	for line in params.get("lines", []):
		sl[1].add_child(K.para(str(line), 420 - x - 24, "hand", 11, P.PRINT_INK))
	var gained: Array = params.get("gained", [])
	if not gained.is_empty():
		sl[1].add_child(K.rect(P.NOTE_LINE, Vector2.ZERO, Vector2(10, 1)))
		var head := K.label("记进选题簿：", "pixel", 12, P.STAMP_RED)
		sl[1].add_child(head)
		for fid in gained:
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 4)
			hb.add_child(K.stamps(1, 1))
			hb.add_child(K.para(TE.fact_note(w, fid, "zh"), 420 - x - 44, "hand", 10, P.PENCIL))
			sl[1].add_child(hb)
		Game.sfx("stamp")
	var ok := K.button("好", _close, 70)
	ok.position = Vector2(334, 222)
	sheet.add_child(ok)
	ok.call_deferred("grab_focus")


func _close() -> void:
	Game.close_overlay()
	var cb: Callable = params.get("on_close", Callable())
	if cb.is_valid():
		cb.call()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
