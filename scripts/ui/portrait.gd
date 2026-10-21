## 居民头像（32×32）和全身小人（14×30）：脸型 × 发型 × 衣着 × 年龄拼出来。
## 只读居民的性别、年龄、职业和编号，用自己的哈希，不碰 world.rng。
extends RefCounted

const P = preload("res://scripts/ui/palette.gd")

static var _faces := {}
static var _figures := {}

const SKINS := [
	[P.PAPER, P.STONE],      # 白
	[P.LAMP, P.OCHRE],       # 晒过
	[P.OCHRE, P.BROWN],      # 黝黑
]
const HAIRS := [P.INK, P.DARK_BROWN, P.BROWN, P.OCHRE, P.UMBER]
const OUTDOOR := ["worker", "farmer", "fisher", "smith", "drifter", "veteran", "foreman"]


static func clear_cache() -> void:
	_faces.clear()
	_figures.clear()


## 一个人的外观参数。同一个 rid 永远一样。
static func look(r: Dictionary) -> Dictionary:
	var h: int = abs(str(r.id).hash())
	var occ: String = r.occ
	var skin_i := 0
	if occ in OUTDOOR:
		skin_i = 1 + (h % 2)
	else:
		skin_i = 0 if h % 5 < 3 else 1
	var age: int = int(r.age)
	var hair: Color = HAIRS[(h >> 3) % HAIRS.size()]
	if age >= 62:
		hair = P.PAPER if skin_i > 0 else P.STONE
	elif age >= 50:
		hair = P.STONE if (h >> 5) % 2 == 0 else P.WARM_GREY
	var coat := P.SLATE
	var trim := P.SLATE_DARK
	var hat := ""
	var extra := ""
	match occ:
		"mayor": coat = P.INK; trim = P.BRICK; hat = "bowler"; extra = "tie"
		"owner": coat = P.UMBER; trim = P.OCHRE; hat = "bowler"; extra = "tie"
		"priest": coat = P.INK; trim = P.PAPER; extra = "collar"
		"foreman": coat = P.BROWN; trim = P.DARK_BROWN; hat = "cap"
		"worker": coat = P.SLATE; trim = P.SLATE_DARK; hat = "cap" if h % 3 != 0 else ""
		"doctor": coat = P.PAPER; trim = P.STONE; extra = "glasses"
		"nurse": coat = P.PAPER; trim = P.SLATE_LIGHT; hat = "nurse"
		"teacher": coat = P.GREEN; trim = P.MOSS; extra = "glasses" if h % 2 == 0 else ""
		"grocer": coat = P.PAPER; trim = P.OCHRE; extra = "apron"
		"postman": coat = P.SLATE; trim = P.OCHRE; hat = "postcap"
		"sheriff": coat = P.BROWN; trim = P.LAMP; hat = "brim"; extra = "star"
		"clerk": coat = P.WARM_GREY; trim = P.UMBER; extra = "glasses"
		"barkeep": coat = P.BRICK_DARK; trim = P.PAPER; extra = "apron"
		"stationmaster": coat = P.SLATE_DARK; trim = P.LAMP; hat = "postcap"
		"widow": coat = P.INK; trim = P.UMBER; hat = "veil" if h % 2 == 0 else ""
		"farmer": coat = P.MOSS if h % 2 == 0 else P.BROWN; trim = P.DARK_BROWN; hat = "straw" if h % 3 != 1 else ""
		"drifter": coat = P.WARM_GREY; trim = P.UMBER; hat = "cap" if h % 2 == 0 else ""; extra = "stubble"
		"newcomer": coat = P.SLATE_LIGHT; trim = P.SLATE; hat = "bowler" if h % 2 == 0 else ""
		"tailor": coat = P.BRICK; trim = P.BRICK_DARK
		"smith": coat = P.DARK_BROWN; trim = P.UMBER; extra = "apron"
		"fisher": coat = P.GREEN; trim = P.SLATE_DARK; hat = "cap"
		"maid": coat = P.UMBER; trim = P.PAPER; hat = "nurse"; extra = "apron"
		"apprentice": coat = P.OCHRE; trim = P.BROWN; hat = "cap" if h % 2 == 0 else ""
		"veteran": coat = P.GREEN; trim = P.OCHRE; hat = "cap"
		"homemaker": coat = [P.BRICK, P.MOSS, P.SLATE, P.OCHRE][(h >> 2) % 4]; trim = P.PAPER
		_: coat = [P.SLATE, P.BROWN, P.MOSS, P.WARM_GREY][(h >> 2) % 4]; trim = P.UMBER
	var female: bool = r.female
	if female and hat == "cap":
		hat = "scarf"
	if female and hat == "straw" and h % 2 == 0:
		hat = "scarf"
	var style: int = (h >> 7) % 3
	var beard: bool = (not female) and age >= 30 and (h >> 9) % 4 == 0
	return {"skin": SKINS[skin_i], "hair": hair, "coat": coat, "trim": trim, "hat": hat, "extra": extra,
		"female": female, "age": age, "style": style, "beard": beard,
		"rx": [6.0, 6.5, 7.5][(h >> 13) % 3], "eye": 13 + (h >> 15) % 2, "mous": (not female) and (not beard) and age >= 25 and (h >> 17) % 4 == 0, "bald": (not female) and age >= 55 and (h >> 11) % 3 == 0}


static func face(world, rid: String) -> Texture2D:
	if _faces.has(rid):
		return _faces[rid]
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if world.residents.has(rid):
		_draw_face(img, look(world.residents[rid]))
	var tex := ImageTexture.create_from_image(img)
	_faces[rid] = tex
	return tex


static func figure(world, rid: String) -> Texture2D:
	if _figures.has(rid):
		return _figures[rid]
	var img := Image.create(14, 30, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	if world.residents.has(rid):
		_draw_figure(img, look(world.residents[rid]))
	var tex := ImageTexture.create_from_image(img)
	_figures[rid] = tex
	return tex


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(maxi(0, y), mini(img.get_height(), y + h)):
		for xx in range(maxi(0, x), mini(img.get_width(), x + w)):
			img.set_pixel(xx, yy, c)


static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, c)


static func _ellipse(img: Image, cx: float, cy: float, rx: float, ry: float, c: Color, y_from := -999, y_to := 999) -> void:
	for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
		if y < y_from or y > y_to:
			continue
		for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
			var dx := (x + 0.5 - cx) / rx
			var dy := (y + 0.5 - cy) / ry
			if dx * dx + dy * dy <= 1.0:
				_px(img, x, y, c)


## 给不透明区域描一圈深色边
static func _outline(img: Image, c: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src := img.duplicate()
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.5:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and src.get_pixel(nx, ny).a > 0.5:
					img.set_pixel(x, y, c)
					break


static func _draw_face(img: Image, L: Dictionary) -> void:
	var skin: Color = L.skin[0]
	var shade: Color = L.skin[1]
	var hair: Color = L.hair
	# 肩膀和衣服
	_ellipse(img, 16, 33, 13, 8, L.coat)
	_rect(img, 14, 22, 4, 4, shade)  # 脖子
	match L.extra:
		"collar":
			_rect(img, 14, 25, 4, 2, P.PAPER)
		"tie":
			_rect(img, 13, 25, 6, 1, P.PAPER)
			_rect(img, 15, 26, 2, 6, L.trim)
		"apron":
			_rect(img, 11, 27, 10, 5, L.trim)
		"star":
			_px(img, 10, 28, P.LAMP); _px(img, 9, 29, P.LAMP); _px(img, 11, 29, P.LAMP); _px(img, 10, 30, P.LAMP)
		_:
			_rect(img, 13, 25, 6, 2, L.trim)
	if L.female and L.style == 2 and L.hat == "":
		# 披下来的长发在肩膀后面
		_rect(img, 9, 12, 3, 13, hair)
		_rect(img, 21, 12, 3, 13, hair)
	# 脸
	_ellipse(img, 16, 14, L.rx, 8.5, skin)
	for y in range(8, 23):
		if img.get_pixel(22, y).a > 0:
			_px(img, 22, y, shade)
	_px(img, 9, 15, skin); _px(img, 23, 15, shade)  # 耳朵
	# 眼睛、眉毛、嘴
	var ey: int = L.eye
	var ex := 1 if L.rx > 7 else 0
	_px(img, 13 - ex, ey, P.INK); _px(img, 19 + ex, ey, P.INK)
	if L.mous:
		_rect(img, 14, 18, 5, 1, L.hair)
	if L.age >= 45:
		_px(img, 12, 16, shade); _px(img, 20, 16, shade)
	_rect(img, 15, 19, 3, 1, shade)
	_px(img, 16, 16, shade); _px(img, 16, 17, shade)
	if L.extra == "glasses":
		for gx in [12, 18]:
			_rect(img, gx, 13, 3, 1, P.UMBER)
			_rect(img, gx, 15, 3, 1, P.UMBER)
			_px(img, gx - 1, 14, P.UMBER); _px(img, gx + 3, 14, P.UMBER)
	if L.beard:
		_rect(img, 12, 18, 9, 3, hair)
		_rect(img, 13, 21, 7, 1, hair)
		_rect(img, 15, 19, 3, 1, P.BRICK_DARK)
	elif L.extra == "stubble":
		for x in range(12, 21, 2):
			_px(img, x, 20, P.WARM_GREY); _px(img, x + 1, 21, P.WARM_GREY)
	# 头发
	if not L.bald:
		if L.female:
			_ellipse(img, 16, 9, 7.5, 5, hair, 3, 10)
			_rect(img, 9, 8, 2, 7, hair)
			_rect(img, 22, 8, 2, 7, hair)
			if L.style == 0:
				_ellipse(img, 16, 3, 3.5, 2.5, hair)  # 发髻
			elif L.style == 1:
				_rect(img, 9, 14, 2, 5, hair); _rect(img, 22, 14, 2, 5, hair)
		else:
			_ellipse(img, 16, 9, 7, 4.5, hair, 3, 9)
			_rect(img, 9, 8, 2, 5, hair)
			_rect(img, 22, 8, 2, 4, hair)
			if L.style == 1:
				_rect(img, 12, 9, 5, 1, hair)
	else:
		_rect(img, 9, 11, 2, 4, hair)
		_rect(img, 22, 11, 2, 4, hair)
	# 帽子
	match L.hat:
		"cap":
			_ellipse(img, 16, 8, 7.5, 4, L.trim, 3, 9)
			_rect(img, 9, 9, 15, 2, L.trim)
			_rect(img, 18, 10, 7, 1, P.UMBER)
		"bowler":
			_ellipse(img, 16, 6, 6, 4.5, P.INK, 1, 8)
			_rect(img, 7, 8, 18, 2, P.INK)
			_rect(img, 10, 7, 12, 1, L.trim)
		"brim":
			_ellipse(img, 16, 6, 6, 4, P.DARK_BROWN, 1, 8)
			_rect(img, 5, 8, 22, 2, P.DARK_BROWN)
		"straw":
			_ellipse(img, 16, 6, 5.5, 3.5, P.LAMP, 2, 8)
			_rect(img, 5, 8, 22, 2, P.OCHRE)
			_rect(img, 11, 7, 10, 1, P.BRICK)
		"postcap":
			_rect(img, 10, 4, 12, 5, L.coat)
			_rect(img, 10, 7, 12, 1, L.trim)
			_rect(img, 15, 9, 9, 1, P.INK)
		"nurse":
			_rect(img, 11, 3, 10, 4, P.PAPER)
			_rect(img, 11, 6, 10, 1, P.STONE)
		"scarf":
			_ellipse(img, 16, 9, 8, 6, L.trim if L.trim != P.PAPER else P.BRICK, 2, 11)
			_rect(img, 8, 10, 2, 8, L.trim if L.trim != P.PAPER else P.BRICK)
			_rect(img, 23, 10, 2, 8, L.trim if L.trim != P.PAPER else P.BRICK)
		"veil":
			_ellipse(img, 16, 9, 8, 6, P.INK, 2, 11)
			_rect(img, 8, 10, 2, 12, P.INK)
			_rect(img, 23, 10, 2, 12, P.INK)
	_outline(img, P.INK)


static func _draw_figure(img: Image, L: Dictionary) -> void:
	var skin: Color = L.skin[0]
	var hair: Color = L.hair
	# 腿
	if L.female:
		_rect(img, 3, 14, 8, 12, L.coat)  # 裙子
		_rect(img, 4, 26, 2, 3, P.UMBER)
		_rect(img, 8, 26, 2, 3, P.UMBER)
	else:
		var legs := P.UMBER if L.coat != P.UMBER else P.INK
		_rect(img, 4, 19, 3, 9, legs)
		_rect(img, 7, 19, 3, 9, legs)
		_rect(img, 3, 28, 4, 1, P.INK)
		_rect(img, 7, 28, 4, 1, P.INK)
	# 身子和胳膊
	_rect(img, 3, 9, 8, 11, L.coat)
	_rect(img, 2, 10, 1, 8, L.coat)
	_rect(img, 11, 10, 1, 8, L.coat)
	_px(img, 2, 18, L.skin[1]); _px(img, 11, 18, L.skin[1])
	match L.extra:
		"apron": _rect(img, 4, 12, 6, 9, L.trim)
		"collar": _rect(img, 6, 9, 2, 1, P.PAPER)
		"tie": _rect(img, 6, 9, 2, 5, L.trim)
		"star": _px(img, 4, 11, P.LAMP)
		_: _rect(img, 6, 9, 2, 1, L.trim)
	# 头
	_rect(img, 4, 2, 6, 7, skin)
	_rect(img, 9, 3, 1, 5, L.skin[1])
	_px(img, 5, 5, P.INK); _px(img, 8, 5, P.INK)
	if not L.bald:
		_rect(img, 4, 1, 6, 2, hair)
		_rect(img, 3, 2, 1, 3 if not L.female else 6, hair)
		_rect(img, 10, 2, 1, 3 if not L.female else 6, hair)
	if L.beard:
		_rect(img, 4, 7, 6, 2, hair)
	match L.hat:
		"cap", "postcap": _rect(img, 3, 0, 8, 2, L.trim); _rect(img, 8, 2, 3, 1, P.UMBER)
		"bowler": _rect(img, 4, 0, 6, 2, P.INK); _rect(img, 2, 2, 10, 1, P.INK)
		"brim": _rect(img, 4, 0, 6, 2, P.DARK_BROWN); _rect(img, 1, 2, 12, 1, P.DARK_BROWN)
		"straw": _rect(img, 4, 0, 6, 2, P.LAMP); _rect(img, 1, 2, 12, 1, P.OCHRE)
		"nurse": _rect(img, 4, 0, 6, 2, P.PAPER)
		"scarf": _rect(img, 3, 0, 8, 3, P.BRICK); _rect(img, 3, 3, 1, 4, P.BRICK); _rect(img, 10, 3, 1, 4, P.BRICK)
		"veil": _rect(img, 3, 0, 8, 3, P.INK); _rect(img, 3, 3, 1, 6, P.INK); _rect(img, 10, 3, 1, 6, P.INK)
	_outline(img, P.INK)
