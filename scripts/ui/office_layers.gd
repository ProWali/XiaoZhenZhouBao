## 编辑室的可变层：碎窗、木板封窗、门缝下的信、窗外人影、撤空的广告栏、桌上的传票、冬天的霜、火烧过的墙。
## 全部从模拟状态读出来，不另存。坐标对的是 assets/sprites/bg/office.png。
extends Control

const P = preload("res://scripts/ui/palette.gd")

const WINDOW := Rect2(22, 14, 56, 208)
const AD_SLOTS := [Rect2(237, 62, 35, 43), Rect2(282, 57, 35, 48), Rect2(326, 65, 35, 43)]
const AD_ORDER := ["owner", "grocer", "barkeep"]
const AD_SHORT := {"owner": "锯木厂", "grocer": "杂货店", "barkeep": "酒馆"}

var letters := 0


func _ready() -> void:
	size = Vector2(640, 360)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w = Game.world
	if w == null:
		return
	var h := 0x5a17
	_draw_ads(w)
	# 冬天：窗玻璃边上结霜
	if w.is_season(w.week) == 4:
		for i in 160:
			h = (h * 1103515245 + 12345) & 0x7fffffff
			var edge: float = float(h % 1000) / 1000.0
			var x := WINDOW.position.x + (edge * 8 if i % 2 == 0 else WINDOW.size.x - edge * 8)
			var y := WINDOW.position.y + float((h >> 10) % int(WINDOW.size.y))
			draw_rect(Rect2(int(x), int(y), 1, 1), P.PAPER)
	# 窗外人影
	var shadows := _shadow_count(w)
	for i in shadows:
		var sx := WINDOW.position.x + 8 + i * 15
		var sy := WINDOW.position.y + 120 + (i % 2) * 6
		draw_rect(Rect2(sx + 2, sy, 6, 7), P.INK)
		draw_rect(Rect2(sx, sy + 7, 10, 22), P.INK)
	# 窗户：这周被砸是碎玻璃，之后三周是木板
	var ww: int = int(w.flags.get("window_week", -99))
	if ww == w.week:
		_draw_cracks()
		for i in 9:
			draw_rect(Rect2(40 + i * 7, 300 + (i * 5) % 11, 2, 1), P.SLATE_LIGHT)
	elif w.week - ww > 0 and w.week - ww <= 3:
		for i in 4:
			var by := WINDOW.position.y + 30 + i * 46
			draw_rect(Rect2(WINDOW.position.x - 4, by, WINDOW.size.x + 8, 9), P.BROWN)
			draw_rect(Rect2(WINDOW.position.x - 4, by + 8, WINDOW.size.x + 8, 1), P.DARK_BROWN)
			draw_rect(Rect2(WINDOW.position.x, by + 4, 1, 1), P.STONE)
			draw_rect(Rect2(WINDOW.position.x + WINDOW.size.x - 1, by + 4, 1, 1), P.STONE)
	# 火烧过：墙上一片片黑
	if int(w.flags.get("burned_until", 0)) > w.week:
		for i in 40:
			h = (h * 1103515245 + 12345) & 0x7fffffff
			var bx := float(h % 640)
			var by := float((h >> 12) % 200)
			draw_rect(Rect2(bx, by, 10 + (h >> 4) % 30, 6 + (h >> 7) % 20), Color(P.INK, 0.55))
	# 桌上的传票
	if not w.lawsuits.is_empty():
		draw_rect(Rect2(200, 194, 30, 20), P.PAPER)
		draw_rect(Rect2(200, 214, 30, 1), P.STONE)
		for i in 4:
			draw_rect(Rect2(204, 198 + i * 3, 18 - (i % 2) * 6, 1), P.WARM_GREY)
		draw_rect(Rect2(221, 205, 6, 6), P.BRICK)
	# 门缝下的信
	for i in mini(letters, 6):
		var lx := 528 + (i * 13) % 50
		var ly := 322 + (i * 7) % 16
		draw_rect(Rect2(lx, ly, 16, 9), P.PAPER)
		draw_rect(Rect2(lx, ly + 9, 16, 1), P.STONE)
		draw_rect(Rect2(lx + 2, ly + 2, 6, 1), P.WARM_GREY)


func _draw_ads(w) -> void:
	var font: Font = Game.fonts.serif
	for i in AD_ORDER.size():
		var rid := ""
		for a in w.ads:
			if w.residents[a].occ == AD_ORDER[i]:
				rid = a
		var r: Rect2 = AD_SLOTS[i]
		var on := false
		if rid != "":
			var res: Dictionary = w.residents[rid]
			on = w.ads[rid].paused_until <= w.week and res.in_town and res.player_rel.like >= 0.3
		if not on:
			# 撤空了：只剩软木和四个钉眼
			draw_rect(r, P.BROWN)
			for c in [Vector2(2, 2), Vector2(r.size.x - 4, 2), Vector2(2, r.size.y - 4), Vector2(r.size.x - 4, r.size.y - 4)]:
				draw_rect(Rect2(r.position + c, Vector2(2, 2)), P.DARK_BROWN)
			continue
		draw_rect(r, P.PAPER)
		draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), P.STONE)
		draw_string(font, r.position + Vector2(3, 11), AD_SHORT[AD_ORDER[i]], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 4, 8, P.INK)
		for k in 5:
			draw_rect(Rect2(r.position.x + 4, r.position.y + 17 + k * 5, r.size.x - 8 - (k % 3) * 5, 1), P.WARM_GREY)


func _draw_cracks() -> void:
	var c := Vector2(48, 96)
	var rays := [Vector2(1, -1.4), Vector2(1.2, 0.3), Vector2(-0.8, 1.2), Vector2(0.4, 1.5), Vector2(-1, -0.6), Vector2(0.2, -1.6)]
	for d in rays:
		var p := c
		for s in 26:
			p += d.normalized() * 1.6 + Vector2(sin(s * 1.7) * 0.4, cos(s * 1.3) * 0.4)
			if not WINDOW.has_point(p):
				break
			draw_rect(Rect2(int(p.x), int(p.y), 1, 1), P.PAPER)
	draw_rect(Rect2(c.x - 3, c.y - 3, 6, 6), P.INK)


## 窗外站几个人：这周有人要来砸窗或者放火，或者刚被重度曝光、脾气又冲的人还在镇上
func _shadow_count(w) -> int:
	var n := 0
	for p in w.pending:
		if p.kind in ["window", "arson"]:
			n += 1
	for rid in w.living_ids():
		var r: Dictionary = w.residents[rid]
		if r.exposed_week >= w.week - 1 and r.bucket == "hot" and r.player_rel.like < 0.2:
			n += 1
	return mini(n, 3)
