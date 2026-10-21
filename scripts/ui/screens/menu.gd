## 主菜单：黄昏的灰河镇，报社窗户亮着。
extends Control

const K = preload("res://scripts/ui/kit.gd")
const P = preload("res://scripts/ui/palette.gd")

var params := {}
var _glow: ColorRect


func _ready() -> void:
	add_child(K.image("res://assets/sprites/bg/menu_town.png"))
	add_child(K.rect(Color(P.INK, 0.25), Vector2.ZERO, Vector2(640, 360)))
	var title := K.label("小镇周报", "serif_black", 44, P.PAPER)
	title.position = Vector2(36, 34)
	add_child(title)
	var sub := K.label("灰河镇 · 一九三五", "serif", 13, P.LAMP)
	sub.position = Vector2(40, 92)
	add_child(sub)
	var box := VBoxContainer.new()
	box.position = Vector2(40, 140)
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	if Game.has_save():
		box.add_child(K.button("接着办报", _continue, 120))
	box.add_child(K.button("新的一局", func(): Game.fade_to("new_game"), 120))
	box.add_child(K.button("设置", func(): Game.open_overlay("settings"), 120))
	box.add_child(K.button("离开", func(): get_tree().quit(), 120))
	if box.get_child_count() > 0:
		box.get_child(0).call_deferred("grab_focus")
	var ver := K.label("%s · 只开放前四周" % Game.VERSION, "pixel", 12, P.STONE)
	ver.position = Vector2(440, 340)
	add_child(ver)
	Game.ambience("night_ambience")
	Game.music("piano_1")


func _continue() -> void:
	if Game.continue_game():
		Game.route()
	else:
		Game.delete_save()
		Game.fade_to("menu")
