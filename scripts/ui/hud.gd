## 顶上一条：哪一周哪一天、行动点、熬夜、现金、本期印数，右边是选题簿、收工、菜单。
## 公信力不在这里显示数字：它只通过来信、广告栏、退订单和周一的账本反映（策划案支柱一）。
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")

signal end_day_requested

var show_end_day := true
var _text: Label
var _end_btn: Button
var _nb_btn: Button


func _ready() -> void:
	position = Vector2.ZERO
	size = Vector2(640, 18)
	add_child(K.rect(Color(P.INK, 0.92), Vector2.ZERO, Vector2(640, 18)))
	add_child(K.rect(P.UMBER, Vector2(0, 18), Vector2(640, 1)))
	_text = K.label("", "pixel", 12, P.PAPER)
	_text.position = Vector2(6, 2)
	add_child(_text)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	add_child(box)
	_nb_btn = _small(Game.t("hud.notebook"), func(): Game.open_overlay("notebook"))
	_nb_btn.tooltip_text = "Tab"
	box.add_child(_nb_btn)
	_end_btn = _small(Game.t("hud.end_day"), func(): end_day_requested.emit())
	box.add_child(_end_btn)
	box.add_child(_small("≡", func(): Game.open_overlay("settings")))
	box.position = Vector2(640 - 3, 1)
	box.resized.connect(func(): box.position.x = 640 - box.size.x - 3)
	refresh()


func _small(text: String, cb: Callable) -> Button:
	var b := K.button(text, cb)
	b.add_theme_stylebox_override("normal", K.box(P.UMBER, P.WARM_GREY, 1, 0))
	b.add_theme_stylebox_override("hover", K.box(P.BROWN, P.LAMP, 1, 0))
	b.add_theme_stylebox_override("pressed", K.box(P.OCHRE, P.LAMP, 1, 0))
	for st in ["normal", "hover", "pressed"]:
		var sb: StyleBoxFlat = b.get_theme_stylebox(st)
		sb.content_margin_left = 5
		sb.content_margin_right = 5
		sb.content_margin_top = 0
		sb.content_margin_bottom = 0
	b.add_theme_color_override("font_color", P.PAPER)
	b.add_theme_color_override("font_hover_color", P.LAMP)
	b.custom_minimum_size.y = 16
	b.focus_mode = Control.FOCUS_NONE
	return b


func refresh() -> void:
	var w = Game.world
	if w == null:
		return
	var day_s: String = Game.t("common.day_short_%d" % clampi(w.day, 1, 7))
	var slot_s: String = Game.slot_name(w.slot) if w.day <= 6 else Game.t("hud.night")
	var act := ""
	for i in 2:
		act += "■" if i < w.actions_left and w.slot <= 1 else "□"
	var nights := ""
	for i in w.MAX_NIGHTS:
		nights += "●" if i < w.nights_used else "○"
	_text.text = Game.t("hud.status", {"week": w.week, "season": Game.season_name(), "day": day_s, "slot": slot_s, "act": act, "nights": nights, "cash": "%.1f" % w.stats.cash, "circ": int(w.stats.circulation)})
	_end_btn.visible = show_end_day and w.day <= 6
	_end_btn.text = Game.t("hud.go_to_bed") if w.slot >= 2 else Game.t("hud.end_day")
	var n: int = w.notebook().size()
	_nb_btn.text = Game.t("hud.notebook_n", {"n": n}) if n > 0 else Game.t("hud.notebook")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		get_viewport().set_input_as_handled()
		if Game.has_overlay():
			Game.close_overlay()
		else:
			Game.open_overlay("notebook")
	elif event.is_action_pressed("ui_cancel") and not Game.has_overlay():
		get_viewport().set_input_as_handled()
		Game.open_overlay("settings")
