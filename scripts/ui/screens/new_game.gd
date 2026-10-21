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
	var head := K.label("新的一局", "serif_black", 18, P.PRINT_INK)
	head.position = Vector2(16, 10)
	sheet.add_child(head)
	var y := 46
	_paper = _field(sheet, "报纸叫什么", "灰河周报", y)
	y += 30
	_editor = _field(sheet, "主编怎么称呼", "", y)
	_editor.placeholder_text = "印在报纸右下角"
	y += 30
	randomize()
	_seed = _field(sheet, "镇子的种子", str(randi_range(1000, 99999)), y)
	_seed.tooltip_text = "同一个种子永远长出同一座镇子"
	y += 34
	var len_l := K.label("局长：试玩版只开放前四周", "pixel", 12, P.WARM_GREY)
	len_l.position = Vector2(16, y)
	sheet.add_child(len_l)
	y += 22
	_ironman = CheckBox.new()
	_ironman.text = "铁人模式：自动存档，说出去的话收不回"
	_ironman.button_pressed = true
	_ironman.position = Vector2(12, y)
	sheet.add_child(_ironman)
	y += 22
	_suicide = CheckBox.new()
	_suicide.text = "允许最重的后果（自杀）出现"
	_suicide.button_pressed = false
	_suicide.position = Vector2(12, y)
	sheet.add_child(_suicide)
	y += 18
	var warn := K.para("默认关闭。打开后，被重度点名的人可能走上绝路。游戏不展示过程，只以讣告和来信出现。", 300, "pixel", 12, P.WARM_GREY, 0)
	warn.position = Vector2(30, y)
	sheet.add_child(warn)
	var go := K.button("开张", _start, 90)
	go.position = Vector2(234, 262)
	sheet.add_child(go)
	var back := K.button("回去", func(): Game.fade_to("menu"), 60)
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
	e.max_length = 12
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
		"paper_name": paper if paper != "" else "灰河周报",
		"player_name": editor if editor != "" else "主编",
		"ironman": _ironman.button_pressed,
		"suicide": _suicide.button_pressed,
	})
	Game.stop_music()
	Game.route()
