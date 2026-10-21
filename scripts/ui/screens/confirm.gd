## 叠层：一句话加两个按钮。params: {text, yes, no, on_yes: Callable}
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")

var params := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(K.rect(Color(P.INK, 0.6), Vector2.ZERO, Vector2(640, 360)))
	var sheet := K.paper(Vector2(170, 120), Vector2(300, 110), P.NEWSPRINT)
	add_child(sheet)
	var t := K.para(str(params.get("text", "")), 270, "hand", 11, P.PRINT_INK)
	t.position = Vector2(15, 12)
	sheet.add_child(t)
	var yes := K.button(str(params.get("yes", "好")), func():
		Game.close_overlay()
		var cb: Callable = params.get("on_yes", Callable())
		if cb.is_valid():
			cb.call(), 70)
	yes.position = Vector2(215, 78)
	sheet.add_child(yes)
	var no := K.button(str(params.get("no", "算了")), func(): Game.close_overlay(), 70)
	no.position = Vector2(15, 78)
	sheet.add_child(no)
	no.call_deferred("grab_focus")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Game.close_overlay()
