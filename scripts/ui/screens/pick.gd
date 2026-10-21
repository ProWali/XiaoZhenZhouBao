## 叠层：从一列里挑一项。params: {title, note, items: [{text, cb, who?, disabled?}]}
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")
const Portrait = preload("res://scripts/ui/portrait.gd")

var params := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(K.rect(Color(P.INK, 0.55), Vector2.ZERO, Vector2(640, 360)))
	var sheet := K.paper(Vector2(120, 26), Vector2(400, 310), P.NOTE_PAPER)
	add_child(sheet)
	var title := K.label(str(params.get("title", "")), "serif_black", 13, P.PRINT_INK)
	title.position = Vector2(14, 10)
	sheet.add_child(title)
	var top := 32
	if str(params.get("note", "")) != "":
		var n := K.para(str(params.note), 370, "pixel", 12, P.WARM_GREY, 0)
		n.position = Vector2(14, 30)
		sheet.add_child(n)
		top = 34 + int(n.get_minimum_size().y)
	var sl: Array = K.scroll_list(Vector2(10, top), Vector2(386, 268 - top), 2)
	sheet.add_child(sl[0])
	var first: Control = null
	for it in params.get("items", []):
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 4)
		if str(it.get("who", "")) != "":
			hb.add_child(K.image(Portrait.face(Game.world, it.who)))
		var cb: Callable = it.cb
		var b := K.row(str(it.text), func():
			Game.close_overlay()
			cb.call(), 340 if str(it.get("who", "")) != "" else 372, str(it.get("font", "pixel")), int(it.get("size", 12)))
		b.disabled = bool(it.get("disabled", false))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.add_child(b)
		sl[1].add_child(hb)
		if first == null and not b.disabled:
			first = b
	var back := K.button("算了", func(): Game.close_overlay(), 70)
	back.position = Vector2(316, 278)
	sheet.add_child(back)
	if first != null:
		first.call_deferred("grab_focus")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Game.close_overlay()
