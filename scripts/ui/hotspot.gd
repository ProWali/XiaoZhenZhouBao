## 画面上可点的一块区域：鼠标移上去描一圈虚线框并在旁边显示名字，点了回调。
extends Control

const P = preload("res://scripts/ui/palette.gd")

var tip := ""
var cb: Callable
var enabled := true
var badge := ""      # 角上的小字
var plate := ""      # 底边正中常驻的名牌（地图上的地名和人数）
var _hover := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(func():
		_hover = true
		if enabled:
			Game.sfx("ui_hover")
		queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())
	focus_entered.connect(func(): _hover = true; queue_redraw())
	focus_exited.connect(func(): _hover = false; queue_redraw())


func _gui_input(event: InputEvent) -> void:
	var hit := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		hit = true
	if event.is_action_pressed("ui_accept"):
		hit = true
	if hit and enabled and cb.is_valid():
		accept_event()
		Game.sfx("ui_click")
		cb.call()


func _draw() -> void:
	var font: Font = Game.fonts.pixel
	if plate != "":
		var pw := font.get_string_size(plate, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 6
		var px := clampf((size.x - pw) / 2.0, -position.x + 1, 640 - position.x - pw - 1)
		var py := size.y - 15
		draw_rect(Rect2(px, py, pw, 14), Color(P.INK, 0.85) if enabled else Color(P.INK, 0.5))
		draw_string(font, Vector2(px + 3, py + 11), plate, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.PAPER if enabled else P.WARM_GREY)
	if badge != "":
		var bw := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 6
		draw_rect(Rect2(size.x - bw, -2, bw, 14), P.INK)
		draw_string(font, Vector2(size.x - bw + 3, 9), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, P.LAMP)
	if not _hover:
		return
	var c := P.LAMP if enabled else P.STONE
	# 虚线框
	var step := 4
	for x in range(0, int(size.x), step * 2):
		draw_rect(Rect2(x, 0, mini(step, int(size.x) - x), 1), c)
		draw_rect(Rect2(x, size.y - 1, mini(step, int(size.x) - x), 1), c)
	for y in range(0, int(size.y), step * 2):
		draw_rect(Rect2(0, y, 1, mini(step, int(size.y) - y)), c)
		draw_rect(Rect2(size.x - 1, y, 1, mini(step, int(size.y) - y)), c)
	if tip != "":
		var tw := font.get_string_size(tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 8
		var gp := get_global_rect().position
		var tx := clampf((size.x - tw) / 2.0, -gp.x + 2, 640 - gp.x - tw - 2)
		var ty := -16.0 if gp.y > 20 else size.y + 2
		draw_rect(Rect2(tx, ty, tw, 15), P.INK)
		draw_string(font, Vector2(tx + 4, ty + 11), tip, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, c)
