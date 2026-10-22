## 设置（叠层）：音量、全屏、语言。换语言当场生效：当前这一屏按新语言重建，设置页重新叠上来。
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")

var params := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(K.rect(Color(P.INK, 0.7), Vector2.ZERO, Vector2(640, 360)))
	var sheet := K.paper(Vector2(180, 60), Vector2(280, 240), P.NEWSPRINT)
	add_child(sheet)
	var head := K.label(Game.t("settings.title"), "serif_black", 18, P.PRINT_INK)
	head.position = Vector2(16, 10)
	sheet.add_child(head)
	var y := 50
	for item in [["master", Game.t("settings.master")], ["music", Game.t("settings.music")], ["sfx", Game.t("settings.sfx")]]:
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
	fs.text = Game.t("settings.fullscreen")
	fs.button_pressed = bool(Game.settings.fullscreen)
	fs.position = Vector2(12, y)
	fs.toggled.connect(func(v): Game.settings.fullscreen = v; Game.save_settings())
	sheet.add_child(fs)
	y += 26
	var lang := K.label(Game.t("settings.language"), "pixel", 12, P.PRINT_INK)
	lang.position = Vector2(16, y + 3)
	sheet.add_child(lang)
	var lang_box := HBoxContainer.new()
	lang_box.add_theme_constant_override("separation", 4)
	lang_box.position = Vector2(80, y)
	sheet.add_child(lang_box)
	# 语言名各用各的文字写，不翻译
	for lg in [["zh", "简体中文"], ["en", "English"]]:
		var code: String = lg[0]
		var b := K.button(lg[1], func(): _set_lang(code), 0)
		b.disabled = Game.lang == code
		lang_box.add_child(b)
	var ok := K.button(Game.t("settings.ok"), func(): Game.close_overlay(), 60)
	ok.position = Vector2(204, 200)
	sheet.add_child(ok)
	if Game.world != null:
		var quit := K.button(Game.t("settings.save_quit"), func():
			Game.autosave()
			Game.world = null
			Game.fade_to("menu"), 0)
		quit.position = Vector2(16, 200)
		sheet.add_child(quit)
	ok.call_deferred("grab_focus")


func _set_lang(code: String) -> void:
	Game.set_lang(code)
	Game.reload_screen()
	Game.open_overlay("settings")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		Game.close_overlay()
