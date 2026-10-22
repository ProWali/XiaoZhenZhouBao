## 新局设定：报名、主编名、种子、铁人、自杀后果开关。
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")

var params := {}
var _paper: LineEdit
var _editor: LineEdit
var _seed: LineEdit
var _ironman: CheckBox
var _suicide: CheckBox


func _ready() -> void:
	add_child(K.image("res://assets/sprites/bg/menu_town.png"))
	add_child(K.rect(Color(P.INK, 0.6), Vector2.ZERO, Vector2(640, 360)))
	var sheet := K.paper(Vector2(150, 30), Vector2(340, 300), P.NEWSPRINT)
	add_child(sheet)
	var head := K.label(Game.t("new_game.title"), "serif_black", 18, P.PRINT_INK)
	head.position = Vector2(16, 10)
	sheet.add_child(head)
	var y := 46
	_paper = _field(sheet, Game.t("new_game.paper"), Game.t("common.default_paper"), y)
	y += 30
	_editor = _field(sheet, Game.t("new_game.editor"), "", y)
	_editor.placeholder_text = Game.t("new_game.editor_hint")
	y += 30
	randomize()
	_seed = _field(sheet, Game.t("new_game.seed"), str(randi_range(1000, 99999)), y)
	_seed.tooltip_text = Game.t("new_game.seed_tip")
	y += 34
	var len_l := K.label(Game.t("new_game.length"), "pixel", 12, P.WARM_GREY)
	len_l.position = Vector2(16, y)
	sheet.add_child(len_l)
	y += 22
	_ironman = CheckBox.new()
	_ironman.text = Game.t("new_game.ironman")
	_ironman.button_pressed = true
	_ironman.position = Vector2(12, y)
	sheet.add_child(_ironman)
	y += 22
	_suicide = CheckBox.new()
	_suicide.text = Game.t("new_game.suicide")
	_suicide.button_pressed = false
	_suicide.position = Vector2(12, y)
	sheet.add_child(_suicide)
	y += 18
	var warn := K.para(Game.t("new_game.suicide_note"), 300, "pixel", 12, P.WARM_GREY, 0)
	warn.position = Vector2(30, y)
	sheet.add_child(warn)
	var go := K.button(Game.t("new_game.start"), _start, 90)
	go.position = Vector2(234, 262)
	sheet.add_child(go)
	var back := K.button(Game.t("new_game.back"), func(): Game.fade_to("menu"), 60)
	back.position = Vector2(16, 262)
	sheet.add_child(back)
	_paper.call_deferred("grab_focus")


func _field(parent: Control, caption: String, value: String, y: int) -> LineEdit:
	var l := K.label(caption, "pixel", 12, P.PRINT_INK)
	l.position = Vector2(16, y + 3)
	parent.add_child(l)
	var e := LineEdit.new()
	e.text = value
	e.position = Vector2(120, y)
	e.size = Vector2(200, 20)
	e.max_length = 12 if Game.lang == "zh" else 24
	parent.add_child(e)
	return e


func _start() -> void:
	var seed_v: int = int(_seed.text) if _seed.text.strip_edges().is_valid_int() else abs(_seed.text.hash()) % 100000
	var paper := _paper.text.strip_edges()
	var editor := _editor.text.strip_edges()
	if Game.has_save():
		Game.delete_save()
	Game.new_game({
		"seed": seed_v,
		"paper_name": paper if paper != "" else Game.t("common.default_paper"),
		"player_name": editor if editor != "" else Game.t("common.default_editor"),
		"ironman": _ironman.button_pressed,
		"suicide": _suicide.button_pressed,
	})
	Game.stop_music()
	Game.route()
