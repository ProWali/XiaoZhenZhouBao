## 设置（叠层）：音量、全屏。语言和字号放大留到 M5。
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")

var params := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(K.rect(Color(P.INK, 0.7), Vector2.ZERO, Vector2(640, 360)))
	var sheet := K.paper(Vector2(180, 60), Vector2(280, 240), P.NEWSPRINT)
	add_child(sheet)
	var head := K.label("设置", "serif_black", 18, P.PRINT_INK)
	head.position = Vector2(16, 10)
	sheet.add_child(head)
	var y := 50
	for item in [["master", "总音量"], ["music", "钢琴"], ["sfx", "声音"]]:
		var l := K.label(item[1], "pixel", 12, P.PRINT_INK)
		l.position = Vector2(16, y)
		sheet.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = float(Game.settings[item[0]])
		s.position = Vector2(80, y + 2)
		s.size = Vector2(170, 12)
		var key: String = item[0]
		s.value_changed.connect(func(v): Game.settings[key] = v; Game.save_settings())
		s.drag_ended.connect(func(_c): Game.sfx("typewriter_key"))
		sheet.add_child(s)
		y += 26
	var fs := CheckBox.new()
	fs.text = "全屏（F11）"
	fs.button_pressed = bool(Game.settings.fullscreen)
	fs.position = Vector2(12, y)
	fs.toggled.connect(func(v): Game.settings.fullscreen = v; Game.save_settings())
	sheet.add_child(fs)
	y += 26
	var lang := K.label("语言：简体中文（英文版在做）", "pixel", 12, P.WARM_GREY)
	lang.position = Vector2(16, y)
	sheet.add_child(lang)
	var ok := K.button("好", func(): Game.close_overlay(), 60)
	ok.position = Vector2(204, 200)
	sheet.add_child(ok)
	if Game.world != null:
		var quit := K.button("存档并回主菜单", func():
			Game.autosave()
			Game.world = null
			Game.fade_to("menu"), 0)
		quit.position = Vector2(16, 200)
		sheet.add_child(quit)
	ok.call_deferred("grab_focus")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Game.close_overlay()
