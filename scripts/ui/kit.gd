## 界面小零件：标签、按钮、纸片、热区。全部用代码搭，不依赖编辑器。
extends RefCounted

const P = preload("res://scripts/ui/palette.gd")


static func label(text: String, font := "pixel", size := 12, color := P.INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Game.fonts[font])
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 定宽自动换行的段落
static func para(text: String, width: float, font := "hand", size := 10, color := P.INK, line_sep := 2) -> Label:
	var l := label(text, font, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	l.size.x = width
	l.add_theme_constant_override("line_spacing", line_sep)
	return l


static func button(text: String, cb: Callable, min_w := 0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	if min_w > 0:
		b.custom_minimum_size.x = min_w
	b.pressed.connect(func():
		Game.sfx("ui_click")
		cb.call())
	b.mouse_entered.connect(func(): Game.sfx("ui_hover"))
	return b


static func rect(color: Color, pos: Vector2, size: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = pos
	r.size = size
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func image(path_or_tex, pos := Vector2.ZERO) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load(path_or_tex) if path_or_tex is String else path_or_tex
	t.position = pos
	t.stretch_mode = TextureRect.STRETCH_KEEP
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


static func box(bg: Color, border: Color, bw := 1, pad := 6) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_content_margin_all(pad)
	s.anti_aliasing = false
	return s


static func panel(pos: Vector2, size: Vector2, bg := P.PAPER, border := P.INK, bw := 1) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.add_theme_stylebox_override("panel", box(bg, border, bw))
	return p


## 一张纸（选题簿、信、报纸）：纸色底、细边、右下角一点阴影
static func paper(pos: Vector2, size: Vector2, color := P.NOTE_PAPER) -> Control:
	var root := Control.new()
	root.position = pos
	root.size = size
	root.add_child(rect(Color(0, 0, 0, 0.35), Vector2(3, 3), size))
	var p := Panel.new()
	p.size = size
	p.add_theme_stylebox_override("panel", box(color, Color(0, 0, 0, 0.25), 1))
	root.add_child(p)
	return root


static func hotspot(r: Rect2, tip: String, cb: Callable) -> Control:
	var h := preload("res://scripts/ui/hotspot.gd").new()
	h.position = r.position
	h.size = r.size
	h.tip = tip
	h.cb = cb
	return h


## 可滚动的竖列，返回 [ScrollContainer, VBoxContainer]
static func scroll_list(pos: Vector2, size: Vector2, sep := 2) -> Array:
	var sc := ScrollContainer.new()
	sc.position = pos
	sc.size = size
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vb := VBoxContainer.new()
	vb.custom_minimum_size.x = size.x - 10
	vb.add_theme_constant_override("separation", sep)
	sc.add_child(vb)
	return [sc, vb]


## 列表里的一行：点了就回调，像按钮但左对齐、可换行
static func row(text: String, cb: Callable, width: float, font := "pixel", size := 12) -> Button:
	var b := button(text, cb)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.x = width
	if font != "pixel":
		b.add_theme_font_override("font", Game.fonts[font])
		b.add_theme_font_size_override("font_size", size)
	return b


## 文本引擎给的段落里有时带换行或空段：拆开、去空，每段一行
static func clean_paras(paragraphs: Array) -> Array:
	var out: Array = []
	for p in paragraphs:
		for piece in str(p).split("\n"):
			var t := piece.strip_edges()
			if t != "":
				out.append(t)
	return out


## 红色印章：交叉验证的计数（选题簿里同一件事听到一次盖一枚）
static func stamps(n: int, total := 3) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(total * 11, 10)
	for i in total:
		var s := ColorRect.new()
		s.position = Vector2(i * 11, 0)
		s.size = Vector2(9, 9)
		s.color = P.STAMP_RED if i < n else Color(P.STAMP_RED, 0.15)
		s.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.add_child(s)
		if i < n:
			var inner := ColorRect.new()
			inner.position = Vector2(i * 11 + 2, 2)
			inner.size = Vector2(5, 5)
			inner.color = P.NOTE_PAPER
			inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
			c.add_child(inner)
			var dot := ColorRect.new()
			dot.position = Vector2(i * 11 + 3, 3)
			dot.size = Vector2(3, 3)
			dot.color = P.STAMP_RED
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			c.add_child(dot)
	return c
