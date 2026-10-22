## 叠层：一条报道的清样，按读报的字号排。params: {slot, headline, paragraphs}
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")

var params := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(K.rect(Color(P.INK, 0.65), Vector2.ZERO, Vector2(640, 360)))
	var sheet := K.paper(Vector2(100, 14), Vector2(440, 332), P.NEWSPRINT)
	add_child(sheet)
	var tag := K.label(Game.t("proof.tag", {"slot": str(params.get("slot", ""))}), "pixel", 12, P.WARM_GREY)
	tag.position = Vector2(16, 8)
	sheet.add_child(tag)
	var sl: Array = K.scroll_list(Vector2(16, 26), Vector2(414, 270), 6)
	sheet.add_child(sl[0])
	var hl := K.para(str(params.get("headline", "")), 396, "serif_black", 16, P.PRINT_INK, 2)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sl[1].add_child(hl)
	sl[1].add_child(K.rect(P.PRINT_INK, Vector2.ZERO, Vector2(396, 1)))
	for p in K.clean_paras(params.get("paragraphs", [])):
		sl[1].add_child(K.para(Game.t("layout.indent") + str(p), 396, "serif", 10, P.PRINT_INK, 3))
	var ok := K.button(Game.t("proof.close"), func(): Game.close_overlay(), 80)
	ok.position = Vector2(344, 302)
	sheet.add_child(ok)
	ok.call_deferred("grab_focus")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Game.close_overlay()
